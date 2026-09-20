import Foundation

/// One definition of the browser extension protocol, shared by the Safari app extension and the
/// Chrome native messaging host, so the same message produces the same status in both browsers.
///
/// Nothing here reports `saved` on its own. A save is only `saved` or `already_saved` when
/// `LibraryStore.capture` says so. When the shared library cannot be opened, the reply is
/// `pending` and the app is asked to finish the save through `mymind://save`.
public struct CaptureMessageRouter: Sendable {
    /// Recorded on each item so the library can tell Safari saves from Chrome saves.
    public let origin: String
    private let openURL: @Sendable (URL) -> Void

    public init(origin: String, openURL: @escaping @Sendable (URL) -> Void) {
        self.origin = origin
        self.openURL = openURL
    }

    public func respond(to message: [String: Any]) -> [String: Any] {
        let action = message["action"] as? String ?? "savePage"
        let requestID = UUID(uuidString: message["requestId"] as? String ?? "") ?? UUID()

        if action == "getSettings" {
            return ["safariToolbarClickSaves": Self.toolbarClickSavesImmediately()]
        }

        if action == "openApp" {
            open("mymind://open")
            return ["status": "opened", "message": "Opening My Mind."]
        }

        if action == "receipt" {
            return encode(lookupReceipt(requestID: requestID), requestID: requestID)
        }

        do {
            let store = try LibraryStore.openForExtension()
            if action == "undo" {
                let result = try store.undoCapture(requestID: requestID)
                CaptureHandshake.write(result, requestID: requestID)
                return encode(result, requestID: requestID)
            }

            if action == "saveImage" {
                let result = try captureImage(message, requestID: requestID, store: store)
                CaptureHandshake.write(result, requestID: requestID)
                return encode(result, requestID: requestID)
            }

            let pageURL = message["pageURL"] as? String
            let selection = message["selection"] as? String
            let request = CaptureRequest(
                requestID: requestID,
                captureKind: (selection?.isEmpty == false) ? .selection : .page,
                pageURL: pageURL,
                targetURL: pageURL,
                capturedTitle: message["title"] as? String,
                selectionText: selection,
                note: message["note"] as? String,
                tags: message["tags"] as? [String] ?? [],
                shelfName: message["shelf"] as? String,
                origin: origin
            )
            let result = try store.capture(request)
            CaptureHandshake.write(result, requestID: requestID)
            return encode(result, requestID: requestID)
        } catch {
            if action == "undo" {
                return encode(.failed("Nothing to undo until My Mind confirms the save."), requestID: requestID)
            }
            if let pageURL = message["pageURL"] as? String, !pageURL.isEmpty {
                openSaveURL(
                    requestID: requestID,
                    pageURL: pageURL,
                    title: message["title"] as? String,
                    selection: message["selection"] as? String,
                    note: message["note"] as? String,
                    shelf: message["shelf"] as? String,
                    tags: message["tags"] as? [String] ?? []
                )
                let pending = CaptureHandshake.pending(requestID: requestID)
                CaptureHandshake.write(pending, requestID: requestID)
                return encode(pending, requestID: requestID)
            }
            return encode(.failed("Not saved. Open My Mind once so the browser can share the library."), requestID: requestID)
        }
    }

    private func captureImage(_ message: [String: Any], requestID: UUID, store: LibraryStore) throws -> CaptureResult {
        guard let encoded = message["bytes"] as? String, let data = Data(base64Encoded: encoded), !data.isEmpty else {
            return .failed("Not saved. The image could not be read.")
        }
        let filename = (message["filename"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "image"
        let request = CaptureRequest(
            requestID: requestID,
            captureKind: .image,
            pageURL: message["pageURL"] as? String,
            capturedTitle: message["title"] as? String ?? filename,
            origin: origin,
            file: CaptureFile(filename: filename, declaredMIME: nil, bytes: data)
        )
        return try store.capture(request)
    }

    private func lookupReceipt(requestID: UUID) -> CaptureResult {
        if let store = try? LibraryStore.openForExtension(),
           let result = try? store.receipt(requestID: requestID) {
            return result
        }
        if let handshake = CaptureHandshake.read(requestID: requestID), handshake.status != .pending {
            return handshake
        }
        return CaptureHandshake.pending(requestID: requestID)
    }

    private func open(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        openURL(url)
    }

    private func openSaveURL(
        requestID: UUID,
        pageURL: String,
        title: String?,
        selection: String?,
        note: String?,
        shelf: String?,
        tags: [String]
    ) {
        var parts = [
            URLQueryItem(name: "url", value: pageURL),
            URLQueryItem(name: "requestId", value: requestID.uuidString),
        ]
        if let title, !title.isEmpty {
            parts.append(URLQueryItem(name: "title", value: title))
        }
        if let selection, !selection.isEmpty {
            parts.append(URLQueryItem(name: "text", value: selection))
        }
        if let note, !note.isEmpty {
            parts.append(URLQueryItem(name: "note", value: note))
        }
        if let shelf, !shelf.isEmpty {
            parts.append(URLQueryItem(name: "shelf", value: shelf))
        }
        if !tags.isEmpty {
            parts.append(URLQueryItem(name: "tags", value: tags.joined(separator: ",")))
        }
        var components = URLComponents(string: "mymind://save")
        components?.queryItems = parts
        if let url = components?.url {
            openURL(url)
        }
    }

    /// `handoff/capture-settings.json`, the same shape the app writes.
    static func toolbarClickSavesImmediately() -> Bool {
        struct ToolbarSettings: Decodable {
            var safariToolbarClickSaves: Bool
        }
        var roots: [URL] = []
        if let shared = StorageLocator.sharedRoot() { roots.append(shared) }
        if let support = try? StorageLocator.appSupportRoot() { roots.append(support) }
        let decoder = JSONDecoder()
        for root in roots {
            let url = StorageLocator.handoffDirectory(in: root).appendingPathComponent("capture-settings.json")
            guard let data = try? Data(contentsOf: url),
                  let settings = try? decoder.decode(ToolbarSettings.self, from: data) else { continue }
            return settings.safariToolbarClickSaves
        }
        return false
    }

    private func encode(_ result: CaptureResult, requestID: UUID) -> [String: Any] {
        var payload: [String: Any] = [
            "status": result.status.rawValue,
            "message": result.message,
            "warnings": result.warnings,
            "requestId": requestID.uuidString,
        ]
        if let itemID = result.itemID {
            payload["itemId"] = itemID.uuidString
        }
        if let retention = result.retention {
            payload["retention"] = retention.rawValue
        }
        return payload
    }
}
