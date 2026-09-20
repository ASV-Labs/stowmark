import AppIntents
import Foundation
import LibraryCore

struct SaveToStowmarkIntent: AppIntent {
    static let title: LocalizedStringResource = "Save to Stowmark"
    static let description = IntentDescription("Save a web link into Stowmark on this Mac.")
    static let openAppWhenRun = true

    @Parameter(title: "URL")
    var url: URL

    @Parameter(title: "Shelf")
    var shelf: String?

    @Parameter(title: "Tags")
    var tags: [String]?

    @Parameter(title: "Note")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$url) to Stowmark") {
            \.$shelf
            \.$tags
            \.$note
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let shelfName = shelf?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteText = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = CaptureRequest(
            captureKind: .link,
            targetURL: url.absoluteString,
            note: (noteText?.isEmpty == false) ? noteText : nil,
            tags: (tags ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            shelfName: (shelfName?.isEmpty == false) ? shelfName : nil,
            origin: "shortcut"
        )
        let store = try LibraryStore.openLive()
        let result = try store.capture(request)
        await MainActor.run {
            let model = AppModel.shared
            model.reload()
            model.captureFailed = result.status == .failed
            model.captureMessage = result.message
            if let id = result.itemID, result.status != .failed {
                model.selectedItemID = id
                if model.place == .trash { model.place = .all }
            }
        }
        guard result.status == .saved || result.status == .alreadySaved else {
            throw NSError(
                domain: "com.charlesbonetti.stowmark",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: result.message]
            )
        }
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}

struct StowmarkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveToStowmarkIntent(),
            phrases: [
                "Save to \(.applicationName)",
            ],
            shortTitle: "Save to Stowmark",
            systemImageName: "bookmark"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}
