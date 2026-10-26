import AppKit
import SwiftUI

enum Branding {
    static let mark: NSImage? = image(named: "mark")
    static let wordmark: NSImage? = image(named: "wordmark")

    private static func image(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

struct IslandView: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            let now = model.track?.isPlaying == true ? timeline.date : Date()
            IslandBody(model: model, now: now)
        }
    }
}

private struct IslandBody: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var look = LookStore.shared
    var now: Date

    private var outline: IslandOutline {
        IslandOutline(structure: look.structure, expanded: model.expanded)
    }
    private var elapsed: Double { model.track?.elapsed(at: now) ?? 0 }
    private var progress: Double {
        guard let duration = model.track?.duration, duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            dragHeader
            if model.expanded {
                expandedBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { glass }
        .clipShape(outline)
        .overlay {
            outline
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.85), look.colors.glassDeep.opacity(0.45), Color.white.opacity(0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: model.expanded)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: model.snapped)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: look.structure)
        .onChange(of: look.transparency) { _, _ in model.onChrome?() }
        .onChange(of: look.fadeWhileWorking) { _, _ in model.onChrome?() }
        .onChange(of: look.pointerInside) { _, _ in model.onChrome?() }
        .onChange(of: look.palette) { _, _ in model.onChrome?() }
        .onChange(of: model.expanded) { _, _ in model.onChrome?() }
    }

    private var dragHeader: some View {
        VStack(spacing: 0) {
            if model.topInset > 0 {
                Color.clear.frame(height: model.topInset).frame(maxWidth: .infinity)
            }
            if model.expanded {
                expandedHeader
            } else if model.track != nil {
                collapsedPlaying
            } else {
                idleMark
            }
        }
        .contentShape(Rectangle())
        .overlay {
            DragHandle(
                onBegin: { model.beginDrag() },
                onDrag: { model.dragChanged(translation: $0) },
                onEnd: { model.endDrag(translation: $0) },
                onHover: { LookStore.shared.setPointer($0) }
            )
        }
    }

    private var collapsedPlaying: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ArtworkView(image: model.artwork, size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(liveLine)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(look.colors.ink)
                        .lineLimit(1)
                    Text(model.track?.collapsedSubtitle ?? "")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(look.colors.inkSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Equalizer(active: model.track?.isPlaying == true)
            }
            ProgressBar(progress: progress)
                .frame(height: 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleMark: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(look.colors.accent)
                .frame(width: 6, height: 6)
            Text("lyriczzz")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(look.colors.inkSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var expandedHeader: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(look.colors.ink.opacity(0.28))
                .frame(width: 38, height: 4)
                .padding(.top, 10)
            if let track = model.track {
                HStack(alignment: .center, spacing: 12) {
                    ArtworkView(image: model.artwork, size: 58)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(look.colors.ink)
                            .lineLimit(2)
                        if !track.subtitle.isEmpty {
                            Text(track.subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(look.colors.inkSoft)
                                .lineLimit(1)
                        }
                        if !track.appName.isEmpty {
                            Text(track.appName.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(1.3)
                                .foregroundStyle(look.colors.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(look.colors.accentSoft.opacity(0.28), in: Capsule())
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(look.colors.inkSoft)
                        .frame(width: 28, height: 28)
                        .background(look.colors.glassDeep.opacity(0.28), in: Circle())
                }
                .padding(.horizontal, 16)
            } else {
                EmptyView()
            }
        }
        .padding(.bottom, model.track == nil ? 0 : 8)
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            if model.track == nil {
                waiting
            } else {
                HStack {
                    Text(clock(elapsed))
                    ProgressBar(progress: progress).frame(height: 3)
                    Text(clock(model.track?.duration ?? 0))
                }
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(look.colors.inkSoft)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

                lyrics
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                controls
                    .padding(.top, 8)
                Text(footer)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(look.colors.inkSoft.opacity(0.7))
                    .padding(.top, 6)
                    .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var waiting: some View {
        VStack(spacing: 6) {
            if let wordmark = Branding.wordmark {
                Image(nsImage: wordmark)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 96)
                    .blendMode(.screen)
            } else if let mark = Branding.mark {
                Image(nsImage: mark)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .blendMode(.screen)
            }
            Text("Play a song in any app.\nIts lyrics will land here.")
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(look.colors.inkSoft)
                .padding(.top, 2)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lyrics: some View {
        let active = model.activeIndex(at: elapsed)
        return Group {
            switch model.lyricsState {
            case .loading:
                status("Finding lyrics…", spinning: true)
            case .missing:
                status("No lyrics for this track yet", spinning: false)
            case .failed:
                status("Can't reach the lyrics service", spinning: false)
            case .instrumental:
                status("Instrumental", spinning: false)
            case .idle:
                status("Lyrics show up with the song", spinning: false)
            case .synced, .approximate, .unsynced:
                LyricsList(lines: model.lines, active: active)
                    .id(model.track?.identity ?? "none")
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            GlassButton(symbol: "backward.fill", size: 15) { model.previousTrack() }
            GlassButton(symbol: model.track?.isPlaying == true ? "pause.fill" : "play.fill", size: 18, prominent: true) {
                model.togglePlay()
            }
            GlassButton(symbol: "forward.fill", size: 15) { model.nextTrack() }
        }
    }

    private var footer: String {
        let songs = look.songsToday == 1 ? "1 song today" : "\(look.songsToday) songs today"
        let hint = "Drag the title to move  ·  \(songs)"
        switch model.lyricsState {
        case .synced: return "\(hint)  ·  Synced"
        case .approximate: return "\(hint)  ·  Approximate timing"
        case .unsynced: return "\(hint)  ·  Lyrics"
        default: return hint
        }
    }

    private var liveLine: String {
        guard let track = model.track else { return "lyriczzz" }
        if let index = model.activeIndex(at: elapsed), model.lines.indices.contains(index) {
            return model.lines[index].text
        }
        return track.title
    }

    private var wash: Double {
        switch look.palette {
        case .clear: return model.expanded ? 0.05 : 0.08
        case .dusk: return model.expanded ? 0.42 : 0.55
        case .cream, .mist: return model.expanded ? 0.18 : 0.28
        }
    }

    private var glass: some View {
        ZStack {
            GlassBackground(material: .underWindowBackground, dark: look.palette == .dusk)
            look.colors.glass.opacity(wash)
            LinearGradient(
                colors: [Color.white.opacity(look.palette == .dusk ? 0.16 : 0.55), Color.white.opacity(0.08), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            LinearGradient(
                colors: [Color.clear, look.colors.glassDeep.opacity(0.22)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    private func status(_ text: String, spinning: Bool) -> some View {
        VStack(spacing: 10) {
            if spinning { ProgressView().controlSize(.small) }
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(look.colors.inkSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clock(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0:00" }
        let total = Int(value.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct LyricsList: View {
    @ObservedObject private var look = LookStore.shared
    var lines: [LyricLine]
    var active: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 28)
                    ForEach(lines) { line in
                        let current = active == line.id
                        Text(line.text)
                            .font(.system(size: (current ? 22 : 16) * look.lyricSize.scale, weight: current ? .semibold : .regular))
                            .foregroundStyle(look.colors.ink.opacity(active == nil ? 0.82 : (current ? 1 : 0.38)))
                            .shadow(color: current ? look.colors.accentSoft.opacity(0.55) : .clear, radius: 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                    Color.clear.frame(height: 36)
                }
                .padding(.horizontal, 22)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.08),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: active) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

private struct ArtworkView: View {
    @ObservedObject private var look = LookStore.shared
    var image: NSImage?
    var size: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let mark = Branding.mark {
                look.colors.glass
                Image(nsImage: mark)
                    .resizable()
                    .scaledToFill()
                    .blendMode(.screen)
            } else {
                LinearGradient(colors: [look.colors.accentSoft, look.colors.glassDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.8), look.colors.glassDeep.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        }
    }
}

private struct ProgressBar: View {
    @ObservedObject private var look = LookStore.shared
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(look.colors.ink.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [look.colors.accentSoft, look.colors.accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, geo.size.width * progress))
            }
        }
    }
}

private struct Equalizer: View {
    @ObservedObject private var look = LookStore.shared
    var active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.09)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { index in
                    let level = active ? abs(sin(time * 4.2 + Double(index) * 0.85)) : 0.15
                    Capsule()
                        .fill(LinearGradient(colors: [look.colors.accentSoft, look.colors.accent], startPoint: .bottom, endPoint: .top))
                        .frame(width: 3, height: 4 + level * 14)
                }
            }
            .frame(width: 20, height: 20)
        }
    }
}

private struct GlassButton: View {
    @ObservedObject private var look = LookStore.shared
    var symbol: String
    var size: CGFloat
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(look.colors.ink)
                .frame(width: prominent ? 52 : 42, height: 38)
                .background(look.colors.glass.opacity(prominent ? 0.55 : 0.28), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
    }
}

private struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var dark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}

private struct IslandOutline: Shape {
    var structure: IslandStructure
    var expanded: Bool

    func path(in rect: CGRect) -> Path {
        if !expanded && structure != .card {
            return Capsule(style: .continuous).path(in: rect)
        }
        let radius: CGFloat
        switch structure {
        case .cylinder:
            radius = min(rect.width, rect.height) * 0.16
        case .compact:
            radius = expanded ? 18 : min(rect.width, rect.height) / 2
        case .card:
            radius = expanded ? 22 : 18
        }
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }
}

private struct DragHandle: NSViewRepresentable {
    var onBegin: () -> Void
    var onDrag: (CGSize) -> Void
    var onEnd: (CGSize) -> Void
    var onHover: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegin: onBegin, onDrag: onDrag, onEnd: onEnd, onHover: onHover)
    }

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {
        context.coordinator.onBegin = onBegin
        context.coordinator.onDrag = onDrag
        context.coordinator.onEnd = onEnd
        context.coordinator.onHover = onHover
        view.coordinator = context.coordinator
    }

    final class Coordinator {
        var onBegin: () -> Void
        var onDrag: (CGSize) -> Void
        var onEnd: (CGSize) -> Void
        var onHover: (Bool) -> Void
        var start: NSPoint?

        init(onBegin: @escaping () -> Void, onDrag: @escaping (CGSize) -> Void, onEnd: @escaping (CGSize) -> Void, onHover: @escaping (Bool) -> Void) {
            self.onBegin = onBegin
            self.onDrag = onDrag
            self.onEnd = onEnd
            self.onHover = onHover
        }
    }

    final class DragView: NSView {
        var coordinator: Coordinator?

        override var isOpaque: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func layout() {
            super.layout()
            updateTrackingAreas()
        }

        override func mouseEntered(with event: NSEvent) {
            NSCursor.openHand.set()
            coordinator?.onHover(true)
        }

        override func mouseExited(with event: NSEvent) {
            NSCursor.arrow.set()
            coordinator?.onHover(false)
        }

        override func mouseDown(with event: NSEvent) {
            coordinator?.start = NSEvent.mouseLocation
            coordinator?.onBegin()
            NSCursor.closedHand.set()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = coordinator?.start else { return }
            let now = NSEvent.mouseLocation
            coordinator?.onDrag(CGSize(width: now.x - start.x, height: now.y - start.y))
        }

        override func mouseUp(with event: NSEvent) {
            let start = coordinator?.start ?? NSEvent.mouseLocation
            let now = NSEvent.mouseLocation
            coordinator?.onEnd(CGSize(width: now.x - start.x, height: now.y - start.y))
            coordinator?.start = nil
            NSCursor.openHand.set()
        }
    }
}

private func hypot(_ width: CGFloat, _ height: CGFloat) -> CGFloat {
    sqrt(width * width + height * height)
}
