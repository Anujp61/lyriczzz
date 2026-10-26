import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

@MainActor
final class IslandWindowController {
    let model: PlayerModel
    let panel: IslandPanel
    private var screenObserver: NSObjectProtocol?
    private var userHid = false

    init(model: PlayerModel) {
        self.model = model
        panel = IslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure()
        let hosting = ClearHostingView(rootView: IslandView(model: model))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        model.panel = panel
        model.onLayoutChange = { [weak self] in
            self?.relayout(animated: true)
        }
        model.onChrome = { [weak self] in
            self?.applyChrome()
        }
        LookStore.shared.onStructureChange = { [weak self] in
            self?.relayout(animated: true)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refreshAnchorKeepingSnap() }
        }
    }

    func show() {
        relayout(animated: false)
        applyChrome()
        panel.orderFrontRegardless()
    }

    func notePlayback(hasTrack: Bool) {
        if LookStore.shared.hideWhenIdle && !hasTrack {
            panel.orderOut(nil)
            return
        }
        if hasTrack { userHid = false }
        if userHid { return }
        show()
    }

    func revealForSpotify() {
        userHid = false
        show()
    }

    func toggleHidden() {
        if panel.isVisible {
            userHid = true
            panel.orderOut(nil)
        } else {
            userHid = false
            show()
        }
    }

    private func applyChrome() {
        let look = LookStore.shared
        panel.appearance = NSAppearance(named: look.palette == .dusk ? .darkAqua : .aqua)
        var alpha = look.transparency
        if look.fadeWhileWorking && look.pointerKnown && !look.pointerInside && !model.expanded {
            alpha *= 0.42
        }
        let next = CGFloat(min(1, max(0.2, alpha)))
        guard abs(panel.alphaValue - next) > 0.01 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            panel.animator().alphaValue = next
        }
    }

    private func configure() {
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.title = "lyriczzz"
        panel.identifier = NSUserInterfaceItemIdentifier("lyriczzz.island")
        panel.appearance = NSAppearance(named: .aqua)
        panel.animationBehavior = .none
    }

    private func relayout(animated: Bool) {
        guard !model.isDragging else { return }
        let frame = model.targetFrame()
        let current = panel.frame
        let same = abs(current.origin.x - frame.origin.x) < 0.5
            && abs(current.origin.y - frame.origin.y) < 0.5
            && abs(current.width - frame.width) < 0.5
            && abs(current.height - frame.height) < 0.5
        guard !same else { return }
        print(String(format: "LYRICZZZ frame %.0f %.0f %.0f %.0f expanded=%d snapped=%d", frame.origin.x, frame.origin.y, frame.width, frame.height, model.expanded ? 1 : 0, model.snapped ? 1 : 0))
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.38
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.85, 0.2, 1)
            panel.animator().setFrame(frame, display: true)
        }
    }
}
