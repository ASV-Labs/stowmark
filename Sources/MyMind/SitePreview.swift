import AppKit
import Foundation
import LibraryCore
import LinkPresentation
import UniformTypeIdentifiers
import WebKit

enum SitePreview {
    struct Result {
        var metadata: PageMetadata
        var image: Data?
    }

    static func fetch(url: URL) async -> Result {
        var metadata = PageMetadata(title: nil, description: nil, author: nil, imageURL: nil, openGraphType: nil)
        var image: Data?

        if let link = try? await appleLinkPreview(url) {
            if !ChallengePage.isChallengeTitle(link.title) {
                metadata.title = link.title
            }
            image = link.image
        }

        var html: String?
        do {
            let fetched = try await PageFetch.string(from: url)
            if ChallengePage.isChallenge(fetched) {
                html = try? await WebPageHTML.load(url)
            } else {
                html = fetched
            }
        } catch {
            html = try? await WebPageHTML.load(url)
        }

        if let html, !ChallengePage.isChallenge(html) {
            let parsed = PageMetadataParser.parse(html: html, baseURL: url)
            if metadata.title == nil { metadata.title = parsed.title }
            if metadata.description == nil { metadata.description = parsed.description }
            if metadata.author == nil { metadata.author = parsed.author }
            if metadata.openGraphType == nil { metadata.openGraphType = parsed.openGraphType }
            metadata.imageURL = parsed.imageURL
            if image == nil, let imageURL = parsed.imageURL, !URLSafety.isBlockedFetchTarget(imageURL) {
                if let bytes = try? await PageFetch.data(from: imageURL, limit: Limits.maxPreviewBytes, referer: url) {
                    image = Thumbnail.makePreview(from: bytes)
                }
            }
            if image == nil {
                image = await firstIcon(in: html, baseURL: url)
            }
        }

        if image == nil {
            image = await firstIcon(in: "", baseURL: url)
        }

        if metadata.title == nil || metadata.description == nil || image == nil {
            if let fallback = await searchCard(for: url) {
                if metadata.title == nil { metadata.title = fallback.title }
                if metadata.description == nil { metadata.description = fallback.description }
                if image == nil { image = fallback.image }
            }
        }

        if image == nil {
            image = await siteIcon(for: url)
        }

        return Result(metadata: metadata, image: image)
    }

    private struct LinkBits {
        var title: String?
        var image: Data?
    }

    private static func appleLinkPreview(_ url: URL) async throws -> LinkBits {
        let provider = LPMetadataProvider()
        provider.timeout = 12
        let meta = try await provider.startFetchingMetadata(for: url)
        var bits = LinkBits(title: meta.title, image: nil)
        if let item = meta.imageProvider, let data = await ImageProviderData.load(item) {
            bits.image = Thumbnail.makePreview(from: data)
        } else if let item = meta.iconProvider, let data = await ImageProviderData.load(item) {
            bits.image = Thumbnail.makePreview(from: data)
        }
        return bits
    }

    private struct SearchCard {
        var title: String?
        var description: String?
        var image: Data?
    }

    private static func searchCard(for url: URL) async -> SearchCard? {
        let host = URLSafety.domain(for: url)
        let name = host.split(separator: ".").first.map(String.init) ?? host
        guard let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let api = URL(string: "https://api.duckduckgo.com/?q=\(query)&format=json&no_html=1&skip_disambig=1"),
              let data = try? await PageFetch.data(from: api, limit: 400_000),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let heading = json["Heading"] as? String
        let abstract = json["AbstractText"] as? String
        let official = (json["OfficialWebsite"] as? String ?? "").lowercased()
        let source = (json["AbstractURL"] as? String ?? "").lowercased()
        let related = official.contains(host) || source.contains(host) || (heading?.lowercased() == name.lowercased())
        guard related, let heading, !heading.isEmpty else { return nil }
        var card = SearchCard(title: heading, description: abstract, image: nil)
        if let path = json["Image"] as? String, !path.isEmpty {
            let imageURL = path.hasPrefix("http") ? URL(string: path) : URL(string: "https://duckduckgo.com\(path)")
            if let imageURL, let bytes = try? await PageFetch.data(from: imageURL, limit: Limits.maxPreviewBytes) {
                card.image = Thumbnail.makePreview(from: bytes)
            }
        }
        return card
    }

    private static func siteIcon(for url: URL) async -> Data? {
        let host = URLSafety.domain(for: url)
        let candidates = [
            URL(string: "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://\(host)&size=128"),
            URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico"),
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if let bytes = try? await PageFetch.data(from: candidate, limit: Limits.maxPreviewBytes),
               let image = Thumbnail.makePreview(from: bytes) {
                return image
            }
        }
        return nil
    }

    private static func firstIcon(in html: String, baseURL: URL) async -> Data? {
        var candidates: [URL] = []
        if let href = linkHref(html, rel: "apple-touch-icon") ?? linkHref(html, rel: "apple-touch-icon-precomposed") ?? linkHref(html, rel: "icon"),
           let url = URL(string: href, relativeTo: baseURL)?.absoluteURL {
            candidates.append(url)
        }
        if let host = baseURL.host {
            let root = "\(baseURL.scheme ?? "https")://\(host)"
            candidates.append(contentsOf: [
                URL(string: "\(root)/apple-touch-icon.png"),
                URL(string: "\(root)/apple-touch-icon-precomposed.png"),
                URL(string: "\(root)/favicon.ico"),
            ].compactMap { $0 })
        }
        for url in candidates where !URLSafety.isBlockedFetchTarget(url) {
            if let bytes = try? await PageFetch.data(from: url, limit: Limits.maxPreviewBytes, referer: baseURL),
               let image = Thumbnail.makePreview(from: bytes) {
                return image
            }
        }
        return nil
    }

    private static func linkHref(_ html: String, rel: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: rel)
        let after = "<link[^>]*rel\\s*=\\s*[\"'][^\"']*\(escaped)[^\"']*[\"'][^>]*href\\s*=\\s*[\"']([^\"']+)[\"']"
        let before = "<link[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*rel\\s*=\\s*[\"'][^\"']*\(escaped)[^\"']*[\"']"
        return first(html, after) ?? first(html, before)
    }

    private static func first(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let hit = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[hit])
    }
}

enum ImageProviderData {
    static func load(_ provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                    let data = (object as? NSImage).flatMap { image -> Data? in
                        guard let tiff = image.tiffRepresentation,
                              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
                        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
                            ?? bitmap.representation(using: .png, properties: [:])
                    }
                    continuation.resume(returning: data)
                }
                return
            }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

@MainActor
final class WebPageHTML: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<String, Error>?
    private var webView: WKWebView?
    private var window: NSWindow?
    private var timeout: Task<Void, Never>?
    private var poll: Task<Void, Never>?
    private var settled = false

    static func load(_ url: URL) async throws -> String {
        let loader = WebPageHTML()
        return try await loader.start(url)
    }

    private func start(_ url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768))
            view.navigationDelegate = self
            let window = NSWindow(
                contentRect: NSRect(x: -2500, y: 80, width: 1024, height: 768),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.alphaValue = 0.01
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            self.window = window
            self.webView = view
            timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(16))
                await self?.capture(failIfChallenge: true)
            }
            view.load(URLRequest(url: url, timeoutInterval: 15))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        poll?.cancel()
        poll = Task { @MainActor [weak self] in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(400))
                if Task.isCancelled { return }
                if await self?.capture(failIfChallenge: false) == true { return }
            }
            await self?.capture(failIfChallenge: true)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    @discardableResult
    private func capture(failIfChallenge: Bool) async -> Bool {
        guard !settled, let webView else { return false }
        let html = (try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String) ?? ""
        if html.isEmpty { return false }
        if ChallengePage.isChallenge(html) {
            if failIfChallenge {
                finish(.failure(URLError(.cannotParseResponse)))
                return true
            }
            return false
        }
        finish(.success(html))
        return true
    }

    private func finish(_ result: Result<String, Error>) {
        guard !settled else { return }
        settled = true
        timeout?.cancel()
        poll?.cancel()
        continuation?.resume(with: result)
        continuation = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        webView = nil
    }
}
