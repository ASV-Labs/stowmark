@preconcurrency import AppKit

/// Services menu target. The selector must stay `saveSelection:userData:error:`
/// so Launch Services can start the app and deliver the pasteboard.
final class ServicesProvider: NSObject {
    static let shared = ServicesProvider()

    @objc(saveSelection:userData:error:)
    func saveSelection(
        _ pasteboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        _ = userData
        let input = ServicePasteboard.read(pasteboard)
        let failure: String? = if Thread.isMainThread {
            MainActor.assumeIsolated { ServiceCapture.perform(input) }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated { ServiceCapture.perform(input) }
            }
        }
        if let failure {
            errorPointer.pointee = failure as NSString
        }
    }
}

struct ServicePasteboard: Sendable {
    var text: String?
    var pageURL: String?

    static func read(_ pasteboard: NSPasteboard) -> ServicePasteboard {
        let textType = NSPasteboard.PasteboardType("public.utf8-plain-text")
        let raw = pasteboard.string(forType: textType) ?? pasteboard.string(forType: .string)
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ServicePasteboard(
            text: (text?.isEmpty == false) ? text : nil,
            pageURL: pageURL(on: pasteboard)
        )
    }

    private static func pageURL(on pasteboard: NSPasteboard) -> String? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let match = urls.first(where: isWeb) {
            return match.absoluteString
        }
        if let raw = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: NSPasteboard.PasteboardType("public.url")),
           let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           isWeb(url) {
            return url.absoluteString
        }
        return nil
    }

    private static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        return true
    }
}

@MainActor
enum ServiceCapture {
    static func perform(_ input: ServicePasteboard) -> String? {
        let model = AppModel.shared
        NSApp.activate()
        guard model.store != nil else {
            return fail(model, "Not saved.")
        }
        if let text = input.text, let link = webAddress(text) {
            model.captureLink(link, origin: "service")
            return model.captureFailed ? model.captureMessage : nil
        }
        if let text = input.text, let page = input.pageURL {
            model.captureExcerpt(pageURL: page, title: nil, text: text, origin: "service")
            return model.captureFailed ? model.captureMessage : nil
        }
        if input.text == nil, let page = input.pageURL {
            model.captureLink(page, origin: "service")
            return model.captureFailed ? model.captureMessage : nil
        }
        if input.text == nil {
            return fail(model, "Not saved. Select some text first.")
        }
        return fail(model, "Not saved. Drop text from a web page so the source is kept, or drop the page link.")
    }

    /// A selection is a link only when the whole string is already http(s).
    /// Do not invent a scheme or a source page.
    private static func webAddress(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url.absoluteString
    }

    private static func fail(_ model: LibraryModel, _ message: String) -> String {
        model.captureFailed = true
        model.captureMessage = message
        return message
    }
}
