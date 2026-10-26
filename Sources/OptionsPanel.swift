import AppKit
import SwiftUI

extension Notification.Name {
    static let lyriczzzShowOptions = Notification.Name("lyriczzz.showOptions")
}

@MainActor
final class OptionsPanel {
    static let shared = OptionsPanel()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let host = NSHostingView(rootView: OptionsView(look: LookStore.shared) { [weak self] in
                self?.panel?.orderOut(nil)
            })
            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 640),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "lyriczzz"
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.appearance = NSAppearance(named: .aqua)
            window.backgroundColor = NSColor(calibratedRed: 0.99, green: 0.96, blue: 0.92, alpha: 1)
            host.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            window.center()
            panel = window
        }
        panel?.center()
        panel?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct OptionsView: View {
    @ObservedObject var look: LookStore
    var onDone: () -> Void

    private var ink: Color { Color(red: 0.28, green: 0.20, blue: 0.14) }
    private var inkSoft: Color { Color(red: 0.45, green: 0.34, blue: 0.24) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("lyriczzz")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                Text("A light player you can see through while you work.")
                    .font(.system(size: 12))
                    .foregroundStyle(inkSoft)
            }

            option("Color") {
                HStack(spacing: 10) {
                    ForEach(IslandPalette.allCases) { palette in
                        Button {
                            look.palette = palette
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(palette.swatch)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        Circle().strokeBorder(ink.opacity(look.palette == palette ? 0.85 : 0.2), lineWidth: look.palette == palette ? 2 : 1)
                                    }
                                Text(palette.title)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(ink)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            option("See-through") {
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $look.transparency, in: 0.45...1)
                        .tint(Color(red: 0.72, green: 0.48, blue: 0.26))
                    Text(look.transparency > 0.9 ? "Mostly glass" : "More tint, still light")
                        .font(.system(size: 11))
                        .foregroundStyle(inkSoft)
                }
            }

            option("Shape") {
                Picker("Shape", selection: $look.structure) {
                    ForEach(IslandStructure.allCases) { structure in
                        Text(structure.title).tag(structure)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            option("Lyrics") {
                Picker("Lyrics", selection: $look.lyricSize) {
                    ForEach(LyricSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Fade while you work", isOn: $look.fadeWhileWorking)
                Toggle("Hide when the music stops", isOn: $look.hideWhenIdle)
                Toggle("Open when Spotify opens", isOn: $look.openWithSpotify)
            }
            .font(.system(size: 13))
            .foregroundStyle(ink)
            .tint(Color(red: 0.72, green: 0.48, blue: 0.26))
            .toggleStyle(.switch)

            Text(look.openWithSpotify
                 ? "A tiny check runs every 12 seconds and only starts lyriczzz if Spotify is open and lyriczzz is not."
                 : "Spotify will not start lyriczzz on its own.")
                .font(.system(size: 11))
                .foregroundStyle(inkSoft)

            HStack {
                Text(look.songsToday == 1 ? "1 song with you today" : "\(look.songsToday) songs with you today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ink)
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.55, green: 0.36, blue: 0.18))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 420, alignment: .topLeading)
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .background(Color(red: 0.99, green: 0.96, blue: 0.92))
    }

    private func option<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.45, green: 0.34, blue: 0.24))
            content()
        }
    }
}
