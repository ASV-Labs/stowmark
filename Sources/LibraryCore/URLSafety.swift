import Darwin
import Foundation

public enum URLSafety {
    public static func captureURL(from raw: String?) -> Result<URL, LibraryError> {
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .failure(.unsafeURL("Not saved. Paste a full web address."))
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .failure(.unsafeURL("Not saved. Only web links can be kept, not files or scripts."))
        }
        guard let host = url.host, !host.isEmpty else {
            return .failure(.unsafeURL("Not saved. That link has no site name."))
        }
        if raw.count > 16_384 {
            return .failure(.unsafeURL("Not saved. That link is too long to keep."))
        }
        return .success(url)
    }

    public static func matchKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if (components.scheme == "http" && components.port == 80)
            || (components.scheme == "https" && components.port == 443) {
            components.port = nil
        }
        return components.string ?? url.absoluteString
    }

    public static func domain(for url: URL) -> String {
        var host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    public static func isBlockedFetchTarget(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" else { return true }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return true }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
        if host.contains(":") {
            return isPrivateIPString(host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")))
        }
        if isIPLiteral(host) { return isPrivateIPString(host) }
        return false
    }

    public static func resolvesToBlockedAddress(_ url: URL) -> Bool {
        if isBlockedFetchTarget(url) { return true }
        guard let host = url.host else { return true }
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var info: UnsafeMutablePointer<addrinfo>?
        let code = getaddrinfo(host, nil, &hints, &info)
        // Fail open on DNS errors so the URLSession stack can still fetch public sites
        // from the sandbox. Host literals and .local names are already blocked above.
        guard code == 0, let info else { return false }
        defer { freeaddrinfo(info) }
        var cursor: UnsafeMutablePointer<addrinfo>? = info
        while let node = cursor {
            if let address = node.pointee.ai_addr, isPrivateSockAddr(address) {
                return true
            }
            cursor = node.pointee.ai_next
        }
        return false
    }

    public static func isPrivateIPString(_ host: String) -> Bool {
        if host == "::1" || host == "0:0:0:0:0:0:0:1" { return true }
        let lowered = host.lowercased()
        if lowered.hasPrefix("fe80:") || lowered.hasPrefix("fc") && lowered.contains(":") || lowered.hasPrefix("fd") && lowered.contains(":") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        if parts[0] == 10 || parts[0] == 127 || parts[0] == 0 { return true }
        if parts[0] == 169 && parts[1] == 254 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 100 && (64...127).contains(parts[1]) { return true }
        return false
    }

    private static func isIPLiteral(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        if parts.count == 4 && parts.allSatisfy({ Int($0) != nil }) { return true }
        return host.contains(":")
    }

    private static func isPrivateSockAddr(_ address: UnsafeMutablePointer<sockaddr>) -> Bool {
        if address.pointee.sa_family == sa_family_t(AF_INET) {
            let raw = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let host = UInt32(bigEndian: raw)
            let a = Int((host >> 24) & 0xFF)
            let b = Int((host >> 16) & 0xFF)
            return isPrivateIPString("\(a).\(b).0.1") || (a == 127) || (a == 10) || (a == 0)
        }
        if address.pointee.sa_family == sa_family_t(AF_INET6) {
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            var copy = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
            guard inet_ntop(AF_INET6, &copy, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return true }
            return isPrivateIPString(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        return true
    }
}

enum FileSignature {
    case jpeg, png, heic, pdf

    var mime: String {
        switch self {
        case .jpeg: "image/jpeg"
        case .png: "image/png"
        case .heic: "image/heic"
        case .pdf: "application/pdf"
        }
    }

    var retention: RetentionState {
        self == .pdf ? .copiedPDF : .copiedImage
    }

    var kind: ContentKind {
        self == .pdf ? .document : .image
    }

    static func sniff(_ data: Data) -> FileSignature? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { return .pdf }
        guard data.count >= 12 else { return nil }
        let brand = Data(data[4..<12])
        if let text = String(data: brand, encoding: .ascii), text.hasPrefix("ftyp") {
            let mark = text.lowercased()
            if mark.contains("heic") || mark.contains("heif") || mark.contains("mif1") || mark.contains("heix") {
                return .heic
            }
        }
        return nil
    }
}

public enum WeblocParser {
    public static func url(in data: Data) -> URL? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let raw = object["URL"] as? String else { return nil }
        return URL(string: raw)
    }
}
