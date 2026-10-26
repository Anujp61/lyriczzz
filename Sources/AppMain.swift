import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let shared = AppDelegate()

    private var model: PlayerModel?
    private var windowController: IslandWindowController?
    private var statusItem: NSStatusItem?
    private var lyricsItem: NSMenuItem?
    private var visibilityItem: NSMenuItem?
    private var spotifyObserver: NSObjectProtocol?

    private var wokeFromSpotify: Bool {
        CommandLine.arguments.contains("--spotify-wake")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let anchor = DisplayAnchor.preferred() else {
            print("LYRICZZZ no displays")
            return
        }
        let model = PlayerModel(anchor: anchor)
        let windowController = IslandWindowController(model: model)
        self.model = model
        self.windowController = windowController
        let look = LookStore.shared
        look.onSpotifyBehaviorChange = {
            SpotifyWake.apply(enabled: LookStore.shared.openWithSpotify)
        }
        look.onIdleBehaviorChange = { [weak self] in
            self?.windowController?.notePlayback(hasTrack: self?.model?.track != nil)
        }
        model.onPresence = { [weak self] hasTrack in
            self?.windowController?.notePlayback(hasTrack: hasTrack)
        }
        model.onNewSong = { [weak self] in
            self?.windowController?.revealForSpotify()
        }
        SpotifyWake.apply(enabled: look.openWithSpotify)
        installMenus()
        watchSpotify()
        windowController.show()
        model.start()
        if wokeFromSpotify {
            print("LYRICZZZ woke with Spotify")
        } else {
            OptionsPanel.shared.show()
        }
        print("LYRICZZZ ready notch=\(anchor.hasNotch) height=\(anchor.notchHeight) width=\(anchor.notchWidth)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.save()
        SpotifyWake.rememberSpotifyQuit()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.show()
        OptionsPanel.shared.show()
        return false
    }

    func menuWillOpen(_ menu: NSMenu) {
        let visible = windowController?.panel.isVisible ?? false
        lyricsItem?.title = (model?.expanded == true && visible) ? "Hide Lyrics" : "Show Lyrics"
        visibilityItem?.title = visible ? "Hide Island" : "Show Island"
    }

    @objc private func toggleLyrics(_ sender: Any?) {
        windowController?.show()
        guard let model else { return }
        model.setExpanded(!model.expanded)
    }

    @objc private func toggleIsland(_ sender: Any?) {
        windowController?.toggleHidden()
    }

    @objc private func snap(_ sender: Any?) {
        model?.snapToCamera()
        windowController?.show()
    }

    @objc private func showOptions(_ sender: Any?) {
        OptionsPanel.shared.show()
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "lyriczzz"
        alert.informativeText = "Lyrics for whatever is playing, floating on the camera bar.\n\nClick the island to open lyrics. Drag it anywhere. Drop it back on the camera bar and it snaps home."
        if let mark = Branding.mark { alert.icon = mark }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func installMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = NSMenuItem(title: "About lyriczzz", action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        let lookItem = NSMenuItem(title: "Look & Feel…", action: #selector(showOptions(_:)), keyEquivalent: ",")
        lookItem.target = self
        appMenu.addItem(lookItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit lyriczzz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main

        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "lyriczzz") {
            image.isTemplate = true
            status.button?.image = image
        }
        status.button?.toolTip = "lyriczzz"
        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "lyriczzz", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let lyrics = NSMenuItem(title: "Show Lyrics", action: #selector(toggleLyrics(_:)), keyEquivalent: "l")
        lyrics.target = self
        lyricsItem = lyrics
        menu.addItem(lyrics)

        let visibility = NSMenuItem(title: "Hide Island", action: #selector(toggleIsland(_:)), keyEquivalent: "h")
        visibility.target = self
        visibilityItem = visibility
        menu.addItem(visibility)

        let snapItem = NSMenuItem(title: "Snap to Camera Bar", action: #selector(snap(_:)), keyEquivalent: "0")
        snapItem.target = self
        menu.addItem(snapItem)
        let options = NSMenuItem(title: "Look & Feel…", action: #selector(showOptions(_:)), keyEquivalent: "")
        options.target = self
        menu.addItem(options)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit lyriczzz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
        statusItem = status
    }

    private func watchSpotify() {
        spotifyObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard running?.bundleIdentifier == "com.spotify.client" else { return }
            MainActor.assumeIsolated {
                AppDelegate.shared.windowController?.revealForSpotify()
                print("LYRICZZZ Spotify opened")
            }
        }
    }
}

@main
enum AppMain {
    static func main() {
        MainActor.assumeIsolated {
            freopen("/tmp/lyriczzz-run.log", "w", stdout)
            freopen("/tmp/lyriczzz-run.log", "a", stderr)
            setbuf(stdout, nil)
            let app = NSApplication.shared
            app.delegate = AppDelegate.shared
            app.setActivationPolicy(.regular)
            app.run()
        }
    }
}
