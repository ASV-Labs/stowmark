import Foundation
import LibraryCore

enum PageFetch {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15 Stowmark/1.0",
            "Accept": "text/html,application/xhtml+xml,image/jpeg,image/png,image/webp;q=0.8,*/*;q=0.5",
        ]
        return URLSession(configuration: configuration)
    }()

    static func string(from url: URL) async throws -> String {
        let data = try await data(from: url, limit: 1_000_000)
        return String(decoding: data, as: UTF8.self)
    }

    static func data(from url: URL, limit: Int, referer: URL? = nil) async throws -> Data {
        if URLSafety.isBlockedFetchTarget(url) || URLSafety.resolvesToBlockedAddress(url) {
            throw URLError(.noPermissionsToReadFile)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
            request.setValue("image/jpeg,image/png,image/webp,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if let final = http.url, URLSafety.isBlockedFetchTarget(final) || URLSafety.resolvesToBlockedAddress(final) {
            throw URLError(.noPermissionsToReadFile)
        }
        if http.expectedContentLength > Int64(limit) {
            throw URLError(.dataLengthExceedsMaximum)
        }
        var data = Data()
        data.reserveCapacity(min(limit, 65_536))
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit {
                throw URLError(.dataLengthExceedsMaximum)
            }
        }
        return data
    }
}
