import AppKit
import Foundation
import LibraryCore
import SafariServices

@objc(SafariWebExtensionHandler)
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any] else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        let response = handle(message)
        let reply = NSExtensionItem()
        reply.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [reply], completionHandler: nil)
    }

    private func handle(_ message: [String: Any]) -> [String: Any] {
        let action = message["action"] as? String ?? "savePage"
        let requestID = UUID(uuidString: message["requestId"] as? String ?? "") ?? UUID()

        if action == "openApp" {
            openApp()
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

            let pageURL = message["pageURL"] as? String
            let title = message["title"] as? String
            let note = message["note"] as? String
            let shelf = message["shelf"] as? String
            let tags = message["tags"] as? [String] ?? []
            let selection = message["selection"] as? String
            let kind: CaptureKind = (selection?.isEmpty == false) ? .selection : .page
            let request = CaptureRequest(
                requestID: requestID,
                captureKind: kind,
                pageURL: pageURL,
                targetURL: pageURL,
                capturedTitle: title,
                selectionText: selection,
                note: note,
                tags: tags,
                shelfName: shelf,
                origin: "safari"
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
            return encode(.failed("Not saved. Open My Mind once so Safari can share the library."), requestID: requestID)
        }
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

    private func openApp() {
        if let url = URL(string: "mymind://open") {
            NSWorkspace.shared.open(url)
        }
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
            NSWorkspace.shared.open(url)
        }
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
