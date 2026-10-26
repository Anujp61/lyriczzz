import SwiftUI

enum IslandPalette: String, CaseIterable, Identifiable {
    case cream
    case clear
    case mist
    case dusk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cream: return "Cream"
        case .clear: return "Clear"
        case .mist: return "Mist"
        case .dusk: return "Dusk"
        }
    }
}

enum IslandStructure: String, CaseIterable, Identifiable {
    case cylinder
    case compact
    case card

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cylinder: return "Cylinder"
        case .compact: return "Compact"
        case .card: return "Card"
        }
    }
}

enum LyricSize: String, CaseIterable, Identifiable {
    case small
    case regular
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "S"
        case .regular: return "M"
        case .large: return "L"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.86
        case .regular: return 1
        case .large: return 1.18
        }
    }
}

struct IslandLook {
    var glass: Color
    var glassDeep: Color
    var ink: Color
    var inkSoft: Color
    var accent: Color
    var accentSoft: Color

    static let cream = IslandLook(
        glass: Color(red: 0.99, green: 0.95, blue: 0.88),
        glassDeep: Color(red: 0.86, green: 0.74, blue: 0.58),
        ink: Color(red: 0.33, green: 0.24, blue: 0.16),
        inkSoft: Color(red: 0.46, green: 0.35, blue: 0.24),
        accent: Color(red: 0.72, green: 0.48, blue: 0.26),
        accentSoft: Color(red: 0.90, green: 0.68, blue: 0.40)
    )

    static let clear = IslandLook(
        glass: Color.white,
        glassDeep: Color.white,
        ink: Color(red: 0.20, green: 0.16, blue: 0.12),
        inkSoft: Color(red: 0.28, green: 0.24, blue: 0.20),
        accent: Color(red: 0.45, green: 0.32, blue: 0.18),
        accentSoft: Color(red: 0.72, green: 0.58, blue: 0.40)
    )

    static let mist = IslandLook(
        glass: Color(red: 0.94, green: 0.96, blue: 0.97),
        glassDeep: Color(red: 0.72, green: 0.80, blue: 0.84),
        ink: Color(red: 0.20, green: 0.27, blue: 0.32),
        inkSoft: Color(red: 0.34, green: 0.42, blue: 0.48),
        accent: Color(red: 0.32, green: 0.50, blue: 0.56),
        accentSoft: Color(red: 0.62, green: 0.78, blue: 0.82)
    )

    static let dusk = IslandLook(
        glass: Color(red: 0.14, green: 0.12, blue: 0.11),
        glassDeep: Color(red: 0.08, green: 0.07, blue: 0.06),
        ink: Color(red: 0.97, green: 0.94, blue: 0.88),
        inkSoft: Color(red: 0.82, green: 0.76, blue: 0.68),
        accent: Color(red: 0.90, green: 0.72, blue: 0.48),
        accentSoft: Color(red: 0.70, green: 0.54, blue: 0.36)
    )
}

extension IslandPalette {
    var look: IslandLook {
        switch self {
        case .cream: return .cream
        case .clear: return .clear
        case .mist: return .mist
        case .dusk: return .dusk
        }
    }

    var swatch: Color { look.accentSoft }
}

@MainActor
final class LookStore: ObservableObject {
    static let shared = LookStore()

    @Published var palette: IslandPalette {
        didSet { persist() }
    }
    @Published var structure: IslandStructure {
        didSet {
            persist()
            onStructureChange?()
        }
    }
    @Published var transparency: Double {
        didSet { persist() }
    }
    @Published var fadeWhileWorking: Bool {
        didSet { persist() }
    }
    @Published var hideWhenIdle: Bool {
        didSet {
            persist()
            onIdleBehaviorChange?()
        }
    }
    @Published var openWithSpotify: Bool {
        didSet {
            persist()
            onSpotifyBehaviorChange?()
        }
    }
    @Published var lyricSize: LyricSize {
        didSet { persist() }
    }
    @Published var pointerInside = false
    private(set) var pointerKnown = false
    @Published private(set) var songsToday = 0

    var onStructureChange: (() -> Void)?
    var onIdleBehaviorChange: (() -> Void)?
    var onSpotifyBehaviorChange: (() -> Void)?

    var colors: IslandLook { palette.look }

    private let defaults = UserDefaults.standard

    private init() {
        palette = IslandPalette(rawValue: defaults.string(forKey: "lyriczzz.palette") ?? "") ?? .cream
        structure = IslandStructure(rawValue: defaults.string(forKey: "lyriczzz.structure") ?? "") ?? .cylinder
        let storedTransparency = defaults.object(forKey: "lyriczzz.transparency") as? Double
        transparency = min(1, max(0.45, storedTransparency ?? 0.78))
        fadeWhileWorking = defaults.object(forKey: "lyriczzz.fade") as? Bool ?? true
        hideWhenIdle = defaults.object(forKey: "lyriczzz.hideIdle") as? Bool ?? false
        if defaults.object(forKey: "lyriczzz.spotify") == nil {
            openWithSpotify = true
        } else {
            openWithSpotify = defaults.bool(forKey: "lyriczzz.spotify")
        }
        lyricSize = LyricSize(rawValue: defaults.string(forKey: "lyriczzz.lyricSize") ?? "") ?? .regular
        songsToday = defaults.integer(forKey: Self.dayKey)
    }

    func setPointer(_ inside: Bool) {
        pointerKnown = true
        pointerInside = inside
    }

    func noteNewSong() {
        let key = Self.dayKey
        let count = defaults.integer(forKey: key) + 1
        defaults.set(count, forKey: key)
        songsToday = count
    }

    private func persist() {
        defaults.set(palette.rawValue, forKey: "lyriczzz.palette")
        defaults.set(structure.rawValue, forKey: "lyriczzz.structure")
        defaults.set(transparency, forKey: "lyriczzz.transparency")
        defaults.set(fadeWhileWorking, forKey: "lyriczzz.fade")
        defaults.set(hideWhenIdle, forKey: "lyriczzz.hideIdle")
        defaults.set(openWithSpotify, forKey: "lyriczzz.spotify")
        defaults.set(lyricSize.rawValue, forKey: "lyriczzz.lyricSize")
    }

    private static var dayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "lyriczzz.songs." + formatter.string(from: Date())
    }
}
