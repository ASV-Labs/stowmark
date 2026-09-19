import SwiftUI

@main
struct MyMindApp: App {
    @State private var model = LibraryModel()

    var body: some Scene {
        WindowGroup {
            LibraryShell(model: model)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(model.appearance.colorScheme)
        }
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: ["mymind"])
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
                Button("Move Selected to Trash") { model.trashSelected() }
                    .keyboardShortcut(.delete, modifiers: .command)
                Button("Undo Last Save") { model.undoLastCapture() }
                    .keyboardShortcut("z", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button("My Mind Settings…") { model.openSettings() }
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
