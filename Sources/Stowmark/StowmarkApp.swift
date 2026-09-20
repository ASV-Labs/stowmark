@preconcurrency import AppKit
import SwiftUI

/// One library model for the window, Services, and Dock drops.
/// Created before the first service request so a cold launch can save.
@MainActor
enum AppModel {
    static let shared = LibraryModel()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppModel.shared
        NSApp.servicesProvider = ServicesProvider.shared
        NSUpdateDynamicServices()
        MenuBarController.shared.install()
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        OpenedFileRouter.route(filenames)
        application.reply(toOpenOrPrint: .success)
    }
}

@MainActor
enum OpenedFileRouter {
    static func route(_ filenames: [String]) {
        let model = AppModel.shared
        NSApp.activate()
        var files: [URL] = []
        for name in filenames {
            if let url = URL(string: name), let scheme = url.scheme?.lowercased() {
                switch scheme {
                case "stowmark", "cardfile", "mymind":
                    model.handleIncomingURL(url)
                    continue
                case "http", "https":
                    if let wrapped = saveURL(for: url) {
                        model.handleIncomingURL(wrapped)
                    }
                    continue
                case "file":
                    files.append(url)
                    continue
                default:
                    break
                }
            }
            files.append(URL(fileURLWithPath: name))
        }
        if !files.isEmpty {
            model.importDropped(files)
        }
    }

    /// `handleIncomingURL` accepts `stowmark://` (and legacy `cardfile://` / `mymind://`).
    /// Wrap a web address so Dock links use that path and never `Data(contentsOf:)` on a remote URL.
    private static func saveURL(for web: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "stowmark"
        components.host = "save"
        components.queryItems = [URLQueryItem(name: "url", value: web.absoluteString)]
        return components.url
    }
}

@main
struct StowmarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            LibraryShell(model: model)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(model.appearance.colorScheme)
        }
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: ["stowmark", "cardfile", "mymind"])
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Save") { model.focusCapture() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Save from Clipboard") { model.captureFromClipboard() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Import Bookmarks…") { model.requestImport() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                Button("Focus Search") { model.focusSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Open Selected") { model.openSelected() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Move Selected to Stowmark Trash") { model.trashSelected() }
                    .keyboardShortcut(.delete, modifiers: .command)
                Button("Undo Last Save") { model.undoLastCapture() }
                    .keyboardShortcut("z", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Settings…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("View") {
                ForEach(ViewMode.allCases) { mode in
                    Button(mode.label) { model.setViewMode(mode) }
                }
            }
        }

        Settings {
            SettingsView(model: model)
                .preferredColorScheme(model.appearance.colorScheme)
        }
    }
}
