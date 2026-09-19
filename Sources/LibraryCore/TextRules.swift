import Foundation

enum TagSuggestions {
    private static let rules: [(label: String, words: [String])] = [
        ("Coffee", ["coffee", "espresso", "latte", "cappuccino", "cafe", "café"]),
        ("Tea", ["tea", "matcha", "chai"]),
        ("Cooking", ["recipe", "cooking", "bake", "baking", "kitchen"]),
        ("Food", ["restaurant", "cuisine", "dinner", "cookbook"]),
        ("Design", ["design", "layout", "typography", "typeface", "branding"]),
        ("Gardening", ["garden", "gardening", "plant", "soil", "pruning"]),
        ("Rituals", ["ritual", "rituals"]),
        ("Travel", ["travel", "itinerary", "flight", "hotel"]),
        ("Papers", ["doi", "journal", "abstract", "arxiv"]),
        ("Photography", ["photograph", "photography", "camera", "lens"]),
        ("Architecture", ["architecture", "interior", "furniture"]),
        ("Programming", ["programming", "software", "swift", "python", "code"]),
        ("Science", ["science", "physics", "chemistry", "biology"]),
        ("Art", ["painting", "museum", "gallery", "sculpture"]),
        ("Music", ["music", "album", "song", "concert"]),
        ("Film", ["film", "cinema", "movie"]),
        ("Health", ["health", "nutrition", "medical"]),
    ]

    static func suggest(title: String, description: String?, excerpt: String?, extras: [String] = []) -> [String] {
        let hay = [title, description ?? "", excerpt ?? ""].joined(separator: " ").lowercased()
        let tokens = Set(hay.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        var hits: [String] = []
        func add(_ label: String) {
            guard hits.count < 3, !hits.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) else { return }
            hits.append(label)
        }
        for extra in extras { add(extra) }
        for rule in rules where rule.words.contains(where: { tokens.contains($0) }) {
            add(rule.label)
        }
        return hits
    }
}

enum TagText {
    static func normalize(_ raw: String) -> String? {
        let collapsed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split { $0.isWhitespace }.joined(separator: " ")
        guard !collapsed.isEmpty, collapsed.count <= 40 else { return nil }
        return collapsed.lowercased()
    }

    static func display(for raw: String) -> String? {
        let collapsed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split { $0.isWhitespace }.joined(separator: " ")
        guard !collapsed.isEmpty, collapsed.count <= 40 else { return nil }
        return collapsed
    }
}

enum SearchText {
    static func ftsQuery(from raw: String) -> String? {
        var phrases: [String] = []
        var plain = ""
        var quoting = false
        var phrase = ""
        for character in raw {
            if character == "\"" {
                if quoting {
                    let cleaned = sanitizePhrase(phrase)
                    if !cleaned.isEmpty { phrases.append("\"\(cleaned)\"") }
                    phrase = ""
                }
                quoting.toggle()
            } else if quoting {
                phrase.append(character)
            } else {
                plain.append(character)
            }
        }
        if quoting {
            let cleaned = sanitizePhrase(phrase)
            if !cleaned.isEmpty { phrases.append("\"\(cleaned)\"") }
        }
        let tokens = plain.split { $0.isWhitespace || $0 == "-" || $0 == "_" }.map(String.init).compactMap { token -> String? in
            let cleaned = sanitize(token)
            guard !cleaned.isEmpty else { return nil }
            return "\(cleaned)*"
        }
        let parts = phrases + tokens
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    private static func sanitize(_ raw: String) -> String {
        raw.filter { character in
            character.isLetter || character.isNumber || character == "'"
        }
    }

    private static func sanitizePhrase(_ raw: String) -> String {
        raw.split { !$0.isLetter && !$0.isNumber && $0 != "'" }
            .map(String.init)
            .map(sanitize)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum BookmarkHTML {
    static func parse(_ data: Data) -> [(url: String, title: String, folder: String?)] {
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return []
        }
        var folderStack: [String] = []
        var entries: [(url: String, title: String, folder: String?)] = []
        let lines = html.components(separatedBy: .newlines)
        for line in lines {
            let folded = line.lowercased()
            if folded.contains("<h3"), let name = inner(line, tag: "h3") {
                folderStack.append(decode(name))
            }
            if folded.contains("</dl>"), !folderStack.isEmpty {
                folderStack.removeLast()
            }
            guard folded.contains("<a "), folded.contains("href") else { continue }
            guard let href = attribute(line, name: "href") else { continue }
            let title = inner(line, tag: "a").map(decode) ?? URL(string: href)?.host ?? href
            entries.append((href, title, folderStack.last))
        }
        return entries
    }

    private static func inner(_ line: String, tag: String) -> String? {
        let pattern = "<\(tag)\\b[^>]*>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let hit = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[hit])
    }

    private static func attribute(_ line: String, name: String) -> String? {
        let pattern = "\(name)\\s*=\\s*([\"'])(.*?)\\1"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range), match.numberOfRanges > 2,
              let value = Range(match.range(at: 2), in: line) else { return nil }
        return String(line[value])
    }

    private static func decode(_ raw: String) -> String {
        raw.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ChallengePage {
    public static func isChallenge(_ html: String) -> Bool {
        let text = html.lowercased()
        if isChallengeTitle(plainTitle(html)) { return true }
        return text.contains("cf-browser-verification")
            || text.contains("cf-mitigated")
            || text.contains("challenge-platform")
            || text.contains("checking your browser")
            || text.contains("enable javascript and cookies")
            || text.contains("cdn-cgi/challenge")
    }

    public static func isChallengeTitle(_ title: String?) -> Bool {
        guard let title else { return false }
        let lowered = title.lowercased()
        return lowered.contains("just a moment")
            || lowered.contains("human verification")
            || lowered.contains("attention required")
            || lowered.contains("checking your browser")
            || lowered == "security check"
    }

    private static func plainTitle(_ html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range), match.numberOfRanges > 1,
              let hit = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[hit])
    }
}

public enum PageMetadataParser {
    public static func parse(html: String, baseURL: URL) -> PageMetadata {
        let capped = String(html.prefix(1_000_000))
        let rawTitle = meta(capped, key: "property", value: "og:title")
            ?? meta(capped, key: "name", value: "twitter:title")
            ?? plain(first(capped, pattern: "<title[^>]*>(.*?)</title>"))
        let title = ChallengePage.isChallengeTitle(rawTitle) ? nil : rawTitle
        let description = meta(capped, key: "property", value: "og:description")
            ?? meta(capped, key: "name", value: "twitter:description")
            ?? meta(capped, key: "name", value: "description")
        let author = meta(capped, key: "name", value: "author")
        let imageRaw = meta(capped, key: "property", value: "og:image")
            ?? meta(capped, key: "property", value: "og:image:url")
            ?? meta(capped, key: "name", value: "twitter:image")
        let type = meta(capped, key: "property", value: "og:type")
        let imageURL = imageRaw.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        return PageMetadata(title: title, description: description, author: author, imageURL: imageURL, openGraphType: type)
    }

    private static func meta(_ html: String, key: String, value: String) -> String? {
        let quoted = NSRegularExpression.escapedPattern(for: value)
        let after = "<meta[^>]*\(key)\\s*=\\s*[\"']\(quoted)[\"'][^>]*content\\s*=\\s*[\"'](.*?)[\"']"
        let before = "<meta[^>]*content\\s*=\\s*[\"'](.*?)[\"'][^>]*\(key)\\s*=\\s*[\"']\(quoted)[\"']"
        return plain(first(html, pattern: after)) ?? plain(first(html, pattern: before))
    }

    private static func first(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let hit = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[hit])
    }

    private static func plain(_ raw: String?) -> String? {
        guard var text = raw else { return nil }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        let collapsed = text.split { $0.isWhitespace }.joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}
