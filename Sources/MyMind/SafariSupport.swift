import Foundation
import LibraryCore
import SafariServices

enum SafariSupport {
    static let extensionIdentifier = "com.charlesbonetti.mymind.extension"
    /// Same file the extension reads from the App Group handoff folder.
    static let toolbarSettingsFile = "capture-settings.json"

    struct ToolbarSettings: Codable, Equatable {
        var safariToolbarClickSaves: Bool
    }

    static func openExtensionPreferences() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionIdentifier) { _ in }
    }

    static var toolbarClickSavesImmediately: Bool {
        readToolbarSettings()?.safariToolbarClickSaves ?? false
    }

    static func setToolbarClickSavesImmediately(_ enabled: Bool) {
        writeToolbarSettings(ToolbarSettings(safariToolbarClickSaves: enabled))
        SFSafariApplication.dispatchMessage(
            withName: "capture-settings",
            toExtensionWithIdentifier: extensionIdentifier,
            userInfo: ["safariToolbarClickSaves": enabled]
        ) { _ in }
    }

    static func extensionStateLabel() async -> String {
        guard NSClassFromString("SFSafariExtensionManager") != nil else { return "Not found" }
        return await withCheckedContinuation { continuation in
            SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionIdentifier) { state, error in
                let label: String
                if error == nil, let state {
                    label = state.isEnabled ? "On" : "Off"
                } else {
                    label = "Not found"
                }
                continuation.resume(returning: label)
            }
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
