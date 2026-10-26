import Darwin
import Foundation

enum SpotifyWake {
    private static let label = "com.lyriczzz.wake"

    static func apply(enabled: Bool) {
        let agents = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plistURL = agents.appendingPathComponent("\(label).plist")
        let domain = "gui/\(getuid())"
        bootout(domain: domain)
        guard enabled else {
            try? FileManager.default.removeItem(at: plistURL)
            return
        }
        do {
            try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
            let app = Bundle.main.bundleURL.path
            let stamp = "\"$HOME/Library/Application Support/lyriczzz/spotify-pid\""
            let command = "pid=$(pgrep -x Spotify | head -1); stamp=$(cat \(stamp) 2>/dev/null || true); if [ -n \"$pid\" ] && [ \"$pid\" != \"$stamp\" ] && ! pgrep -xq Lyriczzz; then open -g \(shellQuote(app)) --args --spotify-wake; fi"
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/bin/bash", "-c", command],
                "StartInterval": 12,
                "RunAtLoad": true,
                "ProcessType": "Background"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            bootstrap(domain: domain, plist: plistURL)
        } catch {
            print("LYRICZZZ spotify wake \(error.localizedDescription)")
        }
    }

    private static func bootstrap(domain: String, plist: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootstrap", domain, plist.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private static func bootout(domain: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "\(domain)/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    static func rememberSpotifyQuit() {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/lyriczzz", isDirectory: true)
        let url = folder.appendingPathComponent("spotify-pid")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "Spotify"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let pid = String(data: data, encoding: .utf8)?
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
        try? Data(pid.utf8).write(to: url, options: .atomic)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
