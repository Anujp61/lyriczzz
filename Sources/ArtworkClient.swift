import Foundation

actor ArtworkClient {
    static let shared = ArtworkClient()

    func webData(for track: Track) async -> Data? {
        for country in ["in", "us"] {
            if let url = await itunesURL(for: track, country: country),
               let data = await HTTP.data(from: url), HTTP.isImage(data) {
                return data
            }
        }
        if let url = await deezerURL(for: track),
           let data = await HTTP.data(from: url), HTTP.isImage(data) {
            return data
        }
        return nil
    }

    func exactData(for track: Track) async -> Data? {
        guard track.bundleID == "com.spotify.client" || track.bundleID == "com.apple.Music" else { return nil }
        let bundleID = track.bundleID
        let raw = await Task.detached { artworkScriptResult(bundleID: bundleID) }.value
        guard let raw, let url = URL(string: raw) else { return nil }
        if url.isFileURL {
            let data = try? Data(contentsOf: url)
            return data.flatMap { HTTP.isImage($0) ? $0 : nil }
        }
        guard let data = await HTTP.data(from: url), HTTP.isImage(data) else { return nil }
        return data
    }

    private func itunesURL(for track: Track, country: String) async -> URL? {
        let term = [track.artist, track.title].filter { !$0.isEmpty }.joined(separator: " ")
        guard var components = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "country", value: country)
        ]
        guard let url = components.url, let data = await HTTP.data(from: url) else { return nil }
        guard let response = try? JSONDecoder().decode(ITunesResponse.self, from: data) else { return nil }
        let match = response.results.first {
            TextMatch.titlesMatch($0.trackName ?? "", track.title)
                && TextMatch.artistsMatch($0.artistName ?? "", track.artist)
        } ?? response.results.first { TextMatch.titlesMatch($0.trackName ?? "", track.title) }
        guard let artwork = match?.artworkUrl100 else { return nil }
        let large = artwork
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            .replacingOccurrences(of: "100x100", with: "600x600")
        return URL(string: large)
    }

    private func deezerURL(for track: Track) async -> URL? {
        let query = [track.artist, track.title].filter { !$0.isEmpty }.joined(separator: " ")
        guard var components = URLComponents(string: "https://api.deezer.com/search") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "6")]
        guard let url = components.url, let data = await HTTP.data(from: url) else { return nil }
        guard let response = try? JSONDecoder().decode(DeezerResponse.self, from: data) else { return nil }
        let match = response.data.first {
            TextMatch.titlesMatch($0.title ?? "", track.title)
                && TextMatch.artistsMatch($0.artist?.name ?? "", track.artist)
        } ?? response.data.first { TextMatch.titlesMatch($0.title ?? "", track.title) }
        let cover = match?.album?.cover_xl ?? match?.album?.cover_big
        return cover.flatMap(URL.init(string:))
    }
}

private struct ITunesResponse: Decodable {
    struct Item: Decodable {
        var trackName: String?
        var artistName: String?
        var artworkUrl100: String?
    }
    var results: [Item]
}

private struct DeezerResponse: Decodable {
    struct Item: Decodable {
        struct Artist: Decodable { var name: String? }
        struct Album: Decodable {
            var cover_xl: String?
            var cover_big: String?
        }
        var title: String?
        var artist: Artist?
        var album: Album?
    }
    var data: [Item]
}

private func artworkScriptResult(bundleID: String) -> String? {
    let application: String
    switch bundleID {
    case "com.spotify.client": application = "Spotify"
    case "com.apple.Music": application = "Music"
    default: return nil
    }
    let source = """
    if application "\(application)" is running then
      tell application "\(application)"
        try
          return artwork url of current track
        end try
      end tell
    end if
    """
    return runAppleScript(source, timeout: 4)
}

private func runAppleScript(_ source: String, timeout: TimeInterval) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", source]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    guard (try? process.run()) != nil else { return nil }
    if finished.wait(timeout: .now() + timeout) == .timedOut {
        process.terminate()
        return nil
    }
    guard process.terminationStatus == 0 else { return nil }
    let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let text, text.hasPrefix("http") || text.hasPrefix("file:") else { return nil }
    return text
}
