import Foundation

struct NowPlayingSnapshot: Decodable {
    var empty: Bool = true
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var elapsed: Double?
    var rate: Double?
    var timestamp: Double?
    var appName: String?
    var bundleID: String?
    var error: String?
}

enum NowPlayingScript {
    static func fetch() -> NowPlayingSnapshot? {
        guard let script = Bundle.main.url(forResource: "now-playing", withExtension: "js") else {
            print("LYRICZZZ missing now-playing.js")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", script.path]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            print("LYRICZZZ osascript \(error.localizedDescription)")
            return nil
        }

        if finished.wait(timeout: .now() + 4) == .timedOut {
            process.terminate()
            print("LYRICZZZ osascript timed out")
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8),
              let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              let json = String(text[start...end]).data(using: .utf8) else {
            let err = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print("LYRICZZZ empty now-playing output \(err)")
            return nil
        }

        do {
            let snapshot = try JSONDecoder().decode(NowPlayingSnapshot.self, from: json)
            if let error = snapshot.error, !error.isEmpty {
                print("LYRICZZZ now-playing \(error)")
            }
            return snapshot
        } catch {
            print("LYRICZZZ decode \(error.localizedDescription)")
            return nil
        }
    }
}
