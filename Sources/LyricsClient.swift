import Foundation

enum LyricsState: Equatable, Sendable {
    case idle
    case loading
    case instrumental
    case missing
    case failed
    case synced
    case approximate
    case unsynced
}

struct LyricLine: Identifiable, Equatable, Sendable {
    var id: Int
    var time: Double
    var text: String
}

struct LyricPayload: Sendable {
    var lines: [LyricLine]
    var state: LyricsState
}

actor LyricsClient {
    static let shared = LyricsClient()
    private var cache: [String: LyricPayload] = [:]

    func lyrics(for track: Track) async -> LyricPayload {
        if let cached = cache[track.identity] { return cached }
        let payload = await load(track)
        if payload.state != .failed {
            cache[track.identity] = payload
        }
        return payload
    }

    private func load(_ track: Track) async -> LyricPayload {
        if let payload = await fetch(track) { return payload }
        try? await Task.sleep(nanoseconds: 500_000_000)
        return await fetch(track) ?? LyricPayload(lines: [], state: .failed)
    }

    private func fetch(_ track: Track) async -> LyricPayload? {
        if let record = await exact(track) { return payload(from: record, track: track) }
        if let record = await search(track) { return payload(from: record, track: track) }
        return nil
    }

    private func exact(_ track: Track) async -> LRCRecord? {
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist)
        ]
        if !track.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: track.album)) }
        if track.duration >= 1 {
            items.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))))
        }
        if let record = await record(path: "/api/get", items: items) { return record }
        if track.duration >= 1 {
            return await record(path: "/api/get", items: Array(items.dropLast()))
        }
        return nil
    }

    private func search(_ track: Track) async -> LRCRecord? {
        let items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist)
        ]
        guard let url = endpoint("/api/search", items: items),
              let data = await HTTP.data(from: url),
              let records = try? JSONDecoder().decode([LRCRecord].self, from: data) else { return nil }
        let best = records.max { score($0, track: track) < score($1, track: track) }
        guard let best, score(best, track: track) >= 5 else { return nil }
        return best
    }

    private func record(path: String, items: [URLQueryItem]) async -> LRCRecord? {
        guard let url = endpoint(path, items: items), let data = await HTTP.data(from: url) else { return nil }
        return try? JSONDecoder().decode(LRCRecord.self, from: data)
    }

    private func endpoint(_ path: String, items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: "https://lrclib.net" + path)
        components?.queryItems = items.filter { !($0.value ?? "").isEmpty }
        return components?.url
    }

    private func score(_ record: LRCRecord, track: Track) -> Int {
        let wantTitle = TextMatch.normalize(track.title)
        let gotTitle = TextMatch.normalize(record.trackName ?? "")
        let wantArtist = TextMatch.normalize(track.artist)
        let gotArtist = TextMatch.normalize(record.artistName ?? "")
        var value = 0
        if !wantTitle.isEmpty, gotTitle == wantTitle || gotTitle.contains(wantTitle) || wantTitle.contains(gotTitle) {
            value += 5
        }
        if let word = wantArtist.split(separator: " ").first, gotArtist.contains(word) {
            value += 3
        }
        if let duration = record.duration, track.duration > 0 {
            let delta = abs(duration - track.duration)
            if delta <= 2 { value += 4 } else if delta <= 8 { value += 1 }
        }
        return value
    }

    private func payload(from record: LRCRecord, track: Track) -> LyricPayload {
        if record.instrumental == true { return LyricPayload(lines: [], state: .instrumental) }
        let synced = LyricParser.synced(record.syncedLyrics ?? "")
        if !synced.isEmpty { return LyricPayload(lines: synced, state: .synced) }
        let plain = LyricParser.plain(record.plainLyrics ?? "", duration: track.duration)
        if plain.isEmpty { return LyricPayload(lines: [], state: .missing) }
        if track.duration > 1 { return LyricPayload(lines: plain, state: .approximate) }
        return LyricPayload(lines: plain, state: .unsynced)
    }
}

struct LRCRecord: Decodable, Sendable {
    var trackName: String?
    var artistName: String?
    var duration: Double?
    var instrumental: Bool?
    var plainLyrics: String?
    var syncedLyrics: String?
}

enum LyricParser {
    private static let stamps: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
    }()

    static func synced(_ raw: String) -> [LyricLine] {
        var items: [(Double, String)] = []
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).replacingOccurrences(of: "\u{feff}", with: "")
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            let matches = stamps.matches(in: line, range: range)
            guard let last = matches.last else { continue }
            var times: [Double] = []
            for match in matches {
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: match.range(at: 2))) ?? 0
                times.append(minutes * 60 + seconds)
            }
            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for time in times { items.append((time, text)) }
        }
        items.sort { $0.0 < $1.0 }
        return items.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    static func plain(_ raw: String, duration: Double) -> [LyricLine] {
        let rows = raw
            .replacingOccurrences(of: "\u{feff}", with: "")
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !rows.isEmpty else { return [] }
        let slot = duration > 1 ? duration / Double(rows.count) : 0
        return rows.enumerated().map { LyricLine(id: $0.offset, time: slot * Double($0.offset), text: $0.element) }
    }
}

enum TextMatch {
    static func normalize(_ value: String) -> String {
        let mapped = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    static func titlesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalize(lhs)
        let right = normalize(rhs)
        if left.isEmpty || right.isEmpty { return false }
        if left.contains(right) || right.contains(left) { return true }
        let leftWords = Set(left.split(separator: " ").map(String.init))
        let rightWords = Set(right.split(separator: " ").map(String.init))
        let overlap = leftWords.intersection(rightWords).count
        return overlap >= 2 && overlap * 2 >= min(leftWords.count, rightWords.count)
    }

    static func artistsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalize(lhs)
        let right = normalize(rhs)
        if left.isEmpty || right.isEmpty { return false }
        if left.contains(right) || right.contains(left) { return true }
        let leftWord = left.split(separator: " ").first.map(String.init) ?? ""
        let rightWord = right.split(separator: " ").first.map(String.init) ?? ""
        return !leftWord.isEmpty && (right.contains(leftWord) || left.contains(rightWord))
    }
}
