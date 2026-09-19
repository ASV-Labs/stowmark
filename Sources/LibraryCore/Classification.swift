import Foundation

enum KindClassifier {
    static func guess(
        url: URL,
        title: String,
        openGraphType: String? = nil,
        captureKind: CaptureKind = .link,
        learned: ContentKind? = nil
    ) -> ContentKind {
        if let learned { return learned }

        let host = URLSafety.domain(for: url)
        let path = url.path.lowercased()
        let hay = "\(host) \(path) \(title)".lowercased()
        let og = openGraphType?.lowercased() ?? ""

        if researchHost(host) || hay.contains("doi.org") || path.contains("/abs/") || path.contains("/pdf/") && researchHost(host) {
            return .research
        }
        if bookHost(host) || path.contains("/dp/") || path.contains("/gp/product") || og.contains("book") {
            return .book
        }
        if socialHost(host) {
            return .social
        }
        if articleHost(host) || path.contains("/wiki/") || og.contains("article") {
            return .article
        }
        if captureKind == .page {
            return .article
        }
        if og.contains("article") {
            return .article
        }
        return .link
    }

    static func isGenericHost(_ domain: String) -> Bool {
        let host = domain.lowercased()
        let generics = [
            "wikipedia.org", "wikimedia.org", "reddit.com", "youtube.com", "youtu.be",
            "amazon.com", "amazon.co.uk", "twitter.com", "x.com", "instagram.com",
            "facebook.com", "github.com", "google.com", "bing.com", "archive.org",
            "tiktok.com", "linkedin.com",
        ]
        return generics.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private static func articleHost(_ host: String) -> Bool {
        suffix(host, [
            "wikipedia.org", "medium.com", "substack.com", "nytimes.com", "washingtonpost.com",
            "theguardian.com", "bbc.com", "bbc.co.uk", "wired.com", "newyorker.com",
            "theatlantic.com", "bloomberg.com", "reuters.com", "apnews.com", "cnn.com",
            "techcrunch.com", "arstechnica.com", "smashingmagazine.com", "css-tricks.com",
            "dev.to", "ghost.io", "hashnode.dev", "theverge.com", "newscientist.com",
        ])
    }

    private static func researchHost(_ host: String) -> Bool {
        suffix(host, [
            "arxiv.org", "doi.org", "nature.com", "sciencedirect.com", "springer.com",
            "wiley.com", "acm.org", "ieee.org", "jstor.org", "ssrn.com", "biorxiv.org",
            "medrxiv.org", "plos.org", "frontiersin.org", "nih.gov", "pubmed.ncbi.nlm.nih.gov",
            "scholar.google.com", "researchgate.net",
        ])
    }

    private static func bookHost(_ host: String) -> Bool {
        suffix(host, ["goodreads.com", "openlibrary.org", "books.google.com", "barnesandnoble.com"])
    }

    private static func socialHost(_ host: String) -> Bool {
        suffix(host, [
            "x.com", "twitter.com", "instagram.com", "reddit.com", "bsky.app",
            "tiktok.com", "facebook.com", "threads.net", "youtube.com", "youtu.be",
        ])
    }

    private static func suffix(_ host: String, _ names: [String]) -> Bool {
        names.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}
