import Foundation

/// Lightweight offline article extraction — keeps title + main text, strips chrome.
public enum ArticleCleaner {
    /// Returns a small self-contained HTML document suitable for WKWebView offline reading.
    public static func cleanedDocument(from html: String, title: String?, baseURL: URL) -> String? {
        guard let body = extractMainText(from: html), body.count >= 280 else { return nil }
        let heading = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? baseURL.host
            ?? "Saved article"
        let paragraphs = body
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(120)
            .map { "<p>\(escape($0))</p>" }
            .joined(separator: "\n")
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <base href="\(escape(baseURL.absoluteString))">
        <style>
          body{font:18px/1.55 -apple-system,BlinkMacSystemFont,sans-serif;margin:24px;max-width:42rem;color:#1c1c1c;background:#f7f4ef}
          h1{font-size:1.6rem;line-height:1.25;margin:0 0 1rem}
          p{margin:0 0 0.9rem}
          .source{color:#666;font-size:0.85rem;margin-bottom:1.25rem}
        </style></head><body>
        <h1>\(escape(heading))</h1>
        <p class="source">\(escape(baseURL.host ?? baseURL.absoluteString)) · saved in Stowmark</p>
        \(paragraphs)
        </body></html>
        """
    }

    private static func extractMainText(from html: String) -> String? {
        var work = html
        let stripBlocks = [
            #"(?is)<script\b[^>]*>.*?</script>"#,
            #"(?is)<style\b[^>]*>.*?</style>"#,
            #"(?is)<noscript\b[^>]*>.*?</noscript>"#,
            #"(?is)<nav\b[^>]*>.*?</nav>"#,
            #"(?is)<footer\b[^>]*>.*?</footer>"#,
            #"(?is)<header\b[^>]*>.*?</header>"#,
            #"(?is)<!--.*?-->"#,
        ]
        for pattern in stripBlocks {
            work = work.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        if let article = firstMatch(pattern: #"(?is)<article\b[^>]*>(.*?)</article>"#, in: work)
            ?? firstMatch(pattern: #"(?is)<main\b[^>]*>(.*?)</main>"#, in: work) {
            work = article
        }
        work = work.replacingOccurrences(of: #"(?is)<br\s*/?>"#, with: "\n", options: .regularExpression)
        work = work.replacingOccurrences(of: #"(?is)</p\s*>"#, with: "\n", options: .regularExpression)
        work = work.replacingOccurrences(of: #"(?is)</(div|h[1-6]|li|tr)\s*>"#, with: "\n", options: .regularExpression)
        work = work.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
        work = work
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        let lines = work
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 40 }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let body = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[body])
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
