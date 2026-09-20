import Foundation
import LibraryCore
import SafariServices

enum SafariSupport {
    static let extensionIdentifier = "com.charlesbonetti.stowmark.extension"
    /// Same file the extension reads from the App Group handoff folder.
    static let toolbarSettingsFile = "capture-settings.json"

    struct ToolbarSettings: Codable, Equatable {
        var safariToolbarClickSaves: Bool
    }

    /// Every Safari reply below uses the async form. Safari answers on an XPC queue, and the
    /// completion-handler form makes the reply block actor-isolated, which traps on current macOS.
    static func openExtensionPreferences() {
        Task { try? await SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionIdentifier) }
    }

    static var toolbarClickSavesImmediately: Bool {
        readToolbarSettings()?.safariToolbarClickSaves ?? false
    }

    static func setToolbarClickSavesImmediately(_ enabled: Bool) {
        writeToolbarSettings(ToolbarSettings(safariToolbarClickSaves: enabled))
        Task {
            try? await SFSafariApplication.dispatchMessage(
                withName: "capture-settings",
                toExtensionWithIdentifier: extensionIdentifier,
                userInfo: ["safariToolbarClickSaves": enabled]
            )
        }
    }

    static func extensionStateLabel() async -> String {
        guard NSClassFromString("SFSafariExtensionManager") != nil else { return "Not found" }
        do {
            let state = try await SFSafariExtensionManager.stateOfSafariExtension(withIdentifier: extensionIdentifier)
            return state.isEnabled ? "On" : "Off"
        } catch {
            return "Not found"
        }
    }

    private static func roots() -> [URL] {
        var roots: [URL] = []
        if let shared = StorageLocator.sharedRoot() { roots.append(shared) }
        if let support = try? StorageLocator.appSupportRoot() { roots.append(support) }
        return roots
    }

    private static func readToolbarSettings() -> ToolbarSettings? {
        let decoder = JSONDecoder()
        for root in roots() {
            let url = StorageLocator.handoffDirectory(in: root).appendingPathComponent(toolbarSettingsFile)
            guard let data = try? Data(contentsOf: url),
                  let settings = try? decoder.decode(ToolbarSettings.self, from: data) else { continue }
            return settings
        }
        return nil
    }

    private static func writeToolbarSettings(_ settings: ToolbarSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        for root in roots() {
            let folder = StorageLocator.handoffDirectory(in: root)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(toolbarSettingsFile)
            try? data.write(to: url, options: .atomic)
        }
    }
}
