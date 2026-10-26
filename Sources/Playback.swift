import Foundation

enum MediaCommand: Int {
    case play = 0
    case pause = 1
    case toggle = 2
    case next = 4
    case previous = 5
}

enum Playback {
    static func send(_ command: MediaCommand) {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/playback-helper")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            print("LYRICZZZ playback helper missing")
            return
        }
        let process = Process()
        process.executableURL = url
        process.arguments = [String(command.rawValue)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            print("LYRICZZZ playback \(error.localizedDescription)")
        }
    }
}
