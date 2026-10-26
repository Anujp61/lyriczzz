import AppKit
import Combine

struct Track: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsed: Double
    var rate: Double
    var sampledAt: Date
    var appName: String
    var bundleID: String

    var identity: String { "\(title)\n\(artist)\n\(album)" }
    var isPlaying: Bool { rate > 0.05 }

    func elapsed(at date: Date) -> Double {
        let value = elapsed + date.timeIntervalSince(sampledAt) * rate
        guard value.isFinite else { return 0 }
        if duration > 0 { return min(max(0, value), duration) }
        return max(0, value)
    }

    var subtitle: String {
        [artist, album].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var collapsedSubtitle: String {
        [artist, appName].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct Placement: Codable {
    var snapped: Bool
    var midX: Double
    var topY: Double
    var displayID: UInt32
}

@MainActor
final class PlayerModel: ObservableObject {
    @Published var track: Track?
    @Published var artwork: NSImage?
    @Published var lines: [LyricLine] = []
    @Published var lyricsState: LyricsState = .idle
    @Published var expanded = false
    @Published var snapped = true
    @Published var anchor: DisplayAnchor

    weak var panel: NSPanel?
    var onLayoutChange: (() -> Void)?
    var onPresence: ((Bool) -> Void)?
    var onNewSong: (() -> Void)?
    var onChrome: (() -> Void)?

    private(set) var isDragging = false
    private var dragOrigin: NSPoint?
    private var savedMidX: CGFloat
    private var savedTopY: CGFloat
    private var misses = 0
    private var pollTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var holdPlaybackUntil = Date.distantPast
    private var lastLoggedIdentity = ""

    static let placementKey = "lyriczzz.placement.v1"

    var topInset: CGFloat { 0 }

    init(anchor: DisplayAnchor) {
        self.anchor = anchor
        savedMidX = anchor.screen.frame.midX
        savedTopY = anchor.screen.frame.maxY
        loadPlacement()
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                await pollOnce()
                let pause: UInt64 = track == nil ? 3_000_000_000 : 1_200_000_000
                try? await Task.sleep(nanoseconds: pause)
            }
        }
    }

    func setExpanded(_ value: Bool) {
        expanded = value
        onLayoutChange?()
    }

    func snapToCamera() {
        if let preferred = DisplayAnchor.preferred() { anchor = preferred }
        snapped = true
        save()
        onLayoutChange?()
    }

    func beginDrag() {
        dragOrigin = panel?.frame.origin
    }

    func dragChanged(translation: CGSize) {
        guard let panel, let dragOrigin else { return }
        guard hypot(translation.width, translation.height) > 6 else { return }
        isDragging = true
        panel.setFrameOrigin(NSPoint(
            x: dragOrigin.x + translation.width,
            y: dragOrigin.y + translation.height
        ))
    }

    func endDrag(translation: CGSize) {
        let dragged = hypot(translation.width, translation.height) > 6
        isDragging = false
        dragOrigin = nil
        guard let panel else { return }
        if !dragged {
            expanded.toggle()
            onLayoutChange?()
            return
        }
        if let screen = snapScreen(for: panel.frame) {
            snapped = true
            anchor = DisplayAnchor(screen: screen)
        } else {
            snapped = false
            let point = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
            if let screen = screenContaining(point) {
                anchor = DisplayAnchor(screen: screen)
            }
            let size = IslandMetrics.size(snapped: false, expanded: expanded, hasTrack: track != nil, anchor: anchor, structure: LookStore.shared.structure)
            savedMidX = panel.frame.midX
            savedTopY = panel.frame.minY + size.height
        }
        save()
        onLayoutChange?()
    }

    func togglePlay() {
        guard var current = track else { return }
        Playback.send(.toggle)
        let now = Date()
        current.elapsed = current.elapsed(at: now)
        current.sampledAt = now
        current.rate = current.isPlaying ? 0 : 1
        track = current
        holdPlaybackUntil = now.addingTimeInterval(0.9)
        refreshSoon()
    }

    func nextTrack() {
        Playback.send(.next)
        holdPlaybackUntil = .distantPast
        refreshSoon()
    }

    func previousTrack() {
        Playback.send(.previous)
        holdPlaybackUntil = .distantPast
        refreshSoon()
    }

    func activeIndex(at elapsed: Double) -> Int? {
        guard lyricsState == .synced || lyricsState == .approximate, !lines.isEmpty else { return nil }
        if lines[0].time > elapsed + 0.08 { return nil }
        var best = 0
        for (index, line) in lines.enumerated() where line.time <= elapsed + 0.08 {
            best = index
        }
        return best
    }

    func targetFrame() -> NSRect {
        let size = IslandMetrics.size(snapped: snapped, expanded: expanded, hasTrack: track != nil, anchor: anchor, structure: LookStore.shared.structure)
        if snapped {
            let top = anchor.hasNotch
                ? anchor.screen.frame.maxY - anchor.notchHeight - 8
                : anchor.screen.visibleFrame.maxY - 6
            return NSRect(
                x: anchor.screen.frame.midX - size.width / 2,
                y: top - size.height,
                width: size.width,
                height: size.height
            )
        }
        let screen = screenContaining(NSPoint(x: savedMidX, y: savedTopY - 1)) ?? anchor.screen
        var x = savedMidX - size.width / 2
        var y = savedTopY - size.height
        let minX = screen.visibleFrame.minX + 8
        let maxX = screen.visibleFrame.maxX - size.width - 8
        if maxX >= minX { x = min(max(x, minX), maxX) }
        y = min(max(y, screen.visibleFrame.minY + 8), screen.frame.maxY - size.height)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    func refreshAnchorKeepingSnap() {
        if snapped {
            if let screen = NSScreen.screen(for: anchor.screen.displayID) {
                anchor = DisplayAnchor(screen: screen)
            } else if let preferred = DisplayAnchor.preferred() {
                anchor = preferred
            }
        }
        onLayoutChange?()
    }

    func save() {
        let placement = Placement(
            snapped: snapped,
            midX: savedMidX,
            topY: savedTopY,
            displayID: anchor.screen.displayID
        )
        if let data = try? JSONEncoder().encode(placement) {
            UserDefaults.standard.set(data, forKey: Self.placementKey)
        }
    }

    private func loadPlacement() {
        guard let data = UserDefaults.standard.data(forKey: Self.placementKey),
              let saved = try? JSONDecoder().decode(Placement.self, from: data) else { return }
        snapped = saved.snapped
        savedMidX = saved.midX
        savedTopY = saved.topY
        if let screen = NSScreen.screen(for: saved.displayID) {
            anchor = DisplayAnchor(screen: screen)
        }
    }

    private func pollOnce() async {
        let snapshot = await Task.detached(priority: .userInitiated) { NowPlayingScript.fetch() }.value
        apply(snapshot)
    }

    private func refreshSoon() {
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            await pollOnce()
        }
    }

    private func apply(_ snapshot: NowPlayingSnapshot?) {
        guard let snapshot, let updated = makeTrack(snapshot) else {
            misses += 1
            if misses >= 3 { clearTrack() }
            return
        }
        misses = 0
        let previous = track
        var next = updated
        if Date() < holdPlaybackUntil, let previous, previous.identity == updated.identity {
            let now = Date()
            next.rate = previous.rate
            next.elapsed = previous.elapsed(at: now)
            next.sampledAt = now
        }
        let identityChanged = previous?.identity != next.identity
        track = next
        if previous == nil {
            onLayoutChange?()
            onPresence?(true)
        }
        guard identityChanged else { return }
        LookStore.shared.noteNewSong()
        onNewSong?()
        artwork = nil
        lines = []
        lyricsState = .loading
        if lastLoggedIdentity != next.identity {
            lastLoggedIdentity = next.identity
            print("LYRICZZZ playing \(next.title) — \(next.artist) via \(next.appName)")
        }
        loadLyrics(for: next)
        loadArtwork(for: next)
    }

    private func clearTrack() {
        guard track != nil else { return }
        track = nil
        artwork = nil
        lines = []
        lyricsState = .idle
        misses = 0
        onLayoutChange?()
        onPresence?(false)
    }

    private func makeTrack(_ snapshot: NowPlayingSnapshot) -> Track? {
        guard !snapshot.empty,
              let title = snapshot.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        let timestamp = snapshot.timestamp ?? 0
        let sampled = timestamp > 1_000_000_000 ? Date(timeIntervalSince1970: timestamp) : Date()
        return Track(
            title: title,
            artist: snapshot.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            album: snapshot.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            duration: max(0, snapshot.duration ?? 0),
            elapsed: max(0, snapshot.elapsed ?? 0),
            rate: snapshot.rate ?? 0,
            sampledAt: sampled,
            appName: snapshot.appName ?? "",
            bundleID: snapshot.bundleID ?? ""
        )
    }

    private func loadLyrics(for track: Track) {
        lyricsTask?.cancel()
        let identity = track.identity
        lyricsTask = Task {
            let payload = await LyricsClient.shared.lyrics(for: track)
            guard !Task.isCancelled, self.track?.identity == identity else { return }
            lines = payload.lines
            lyricsState = payload.state
            print("LYRICZZZ lyrics \(payload.state) \(payload.lines.count)")
        }
    }

    private func loadArtwork(for track: Track) {
        artworkTask?.cancel()
        let identity = track.identity
        artworkTask = Task {
            let web = Task { await ArtworkClient.shared.webData(for: track) }
            let exact = Task { await ArtworkClient.shared.exactData(for: track) }
            if let data = await web.value, self.track?.identity == identity, let image = NSImage(data: data) {
                artwork = image
            }
            if let data = await exact.value, self.track?.identity == identity, let image = NSImage(data: data) {
                artwork = image
            }
        }
    }

    private func snapScreen(for frame: NSRect) -> NSScreen? {
        for screen in NSScreen.screens {
            let display = DisplayAnchor(screen: screen)
            let edge = display.hasNotch ? screen.frame.maxY : screen.visibleFrame.maxY
            let nearTop = abs(frame.maxY - edge) < 64 || abs(frame.maxY - screen.frame.maxY) < 36
            let nearCenter = abs(frame.midX - screen.frame.midX) < 220
            if nearTop && nearCenter { return screen }
        }
        return nil
    }

    private func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.insetBy(dx: -8, dy: -8).contains(point)
        }
    }
}
