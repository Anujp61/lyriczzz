import AppKit

struct DisplayAnchor {
    let screen: NSScreen
    let hasNotch: Bool
    let notchHeight: CGFloat
    let notchWidth: CGFloat

    init(screen: NSScreen) {
        self.screen = screen
        let inset = screen.safeAreaInsets.top
        hasNotch = inset > 0.5
        notchHeight = hasNotch ? inset : 0
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        if hasNotch, left > 0 || right > 0 {
            notchWidth = max(140, screen.frame.width - left - right)
        } else {
            notchWidth = 188
        }
    }

    static func preferred() -> DisplayAnchor? {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.safeAreaInsets.top > 0.5 }) ?? NSScreen.main ?? screens.first else {
            return nil
        }
        return DisplayAnchor(screen: screen)
    }
}

enum IslandMetrics {
    static let playingLip: CGFloat = 68
    static let idleLip: CGFloat = 40
    static let expandedBody: CGFloat = 548
    static let expandedWidth: CGFloat = 430

    static func size(snapped: Bool, expanded: Bool, hasTrack: Bool, anchor: DisplayAnchor, structure: IslandStructure) -> NSSize {
        switch structure {
        case .compact:
            if expanded { return NSSize(width: 360, height: 460) }
            if hasTrack { return NSSize(width: 280, height: 48) }
            return NSSize(width: 168, height: 36)
        case .card:
            if expanded { return NSSize(width: 440, height: 520) }
            if hasTrack { return NSSize(width: 400, height: 86) }
            return NSSize(width: 240, height: 52)
        case .cylinder:
            if expanded { return NSSize(width: expandedWidth, height: expandedBody) }
            if hasTrack {
                let width = min(max(anchor.notchWidth + 188, 386), anchor.screen.frame.width - 48)
                return NSSize(width: width, height: playingLip)
            }
            return NSSize(width: 220, height: idleLip)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        guard displayID != 0 else { return nil }
        return screens.first { $0.displayID == displayID }
    }
}
