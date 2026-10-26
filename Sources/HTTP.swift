import Foundation

enum HTTP {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Lyriczzz/1.0 (macOS)"]
        return URLSession(configuration: configuration)
    }()

    static func data(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    static func isImage(_ data: Data) -> Bool {
        guard data.count > 8 else { return false }
        let bytes = [UInt8](data.prefix(8))
        if bytes[0] == 0xFF && bytes[1] == 0xD8 { return true }
        if bytes[0] == 0x89 && bytes[1] == 0x50 { return true }
        if bytes[0] == 0x47 && bytes[1] == 0x49 { return true }
        return false
    }
}
