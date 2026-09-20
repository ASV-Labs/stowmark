import AppKit
import LibraryCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: LibraryModel
    @Environment(\.colorScheme) private var scheme
    @State private var status: String?
    @State private var safariExtensionState = "Checking…"
    @State private var toolbarClickSaves = SafariSupport.toolbarClickSavesImmediately
    @State private var chromeBrowsers: [(name: String, installed: Bool)] = []
    @State private var chromeStoreID = ChromeSupport.storeExtensionID

    var body: some View {
        TabView {
            Form {
                Section("Layout") {
                    Picker("Library layout", selection: Binding(
                        get: { model.viewMode },
                        set: { model.setViewMode($0) }
                    )) {
                        ForEach(ViewMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    Text(model.viewMode.blurb)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary(scheme))

                    if model.viewMode != .table {
                        Picker("Card size", selection: Binding(
                            get: { model.cardSize },
                            set: { model.setCardSize($0) }
                        )) {
                            ForEach(CardSize.allCases) { size in
                                Text(size.label).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Cards and covers stay equal within the size you pick.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary(scheme))
                    }
                }

                Section("Appearance") {
                    Picker("Appearance", selection: Binding(
                        get: { model.appearance },
                        set: { model.setAppearance($0) }
                    )) {
                        ForEach(AppearancePref.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Light is the paper library. Dark is the night list. System follows the Mac.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary(scheme))
                }

                Section("Behavior") {
                    Picker("Default sort", selection: Binding(
                        get: { model.defaultSort },
                        set: { model.setDefaultSort($0) }
                    )) {
                        Text("Recently saved").tag(ResultOrder.recent)
                        Text("Title").tag(ResultOrder.title)
                        Text("Source").tag(ResultOrder.source)
                    }
                    Toggle("Show capture bar", isOn: Binding(
                        get: { model.showCaptureBar },
                        set: { model.setShowCaptureBar($0) }
                    ))
                    Toggle("Open preview on second click", isOn: Binding(
                        get: { model.openPreviewOnSelect },
                        set: { model.setOpenPreviewOnSelect($0) }
                    ))
                    Toggle("Confirm before moving to Stowmark Trash", isOn: Binding(
                        get: { model.confirmTrash },
                        set: { model.setConfirmTrash($0) }
                    ))
                    Toggle("Remember the last shelf when relaunching", isOn: Binding(
                        get: { model.rememberLastPlace },
                        set: { model.setRememberLastPlace($0) }
                    ))
                    Toggle("Show menu bar capture", isOn: Binding(
                        get: { UserDefaults.standard.object(forKey: "menuBarCaptureEnabled") as? Bool ?? true },
                        set: { MenuBarController.shared.setEnabled($0) }
                    ))
                    Text("Save from the clipboard without bringing the library window forward.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary(scheme))
                }
            }
            .formStyle(.grouped)
            .padding()
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Safari") {
                    Text("Safari capture is part of the product. Paste, drop, and clipboard still work if you skip it.")
                        .font(.callout)
                        .foregroundStyle(Theme.secondary(scheme))
                    Button("Open Safari Extensions…") {
                        model.openSafariExtensionSettings()
                        status = "In Safari, turn on Stowmark. Saving a page writes the same local library, including when this window is closed."
                    }
                    Text(model.usesSharedContainer
                         ? "Safari and Stowmark are sharing one library on this Mac."
                         : "Safari will open Stowmark to finish a save until the shared library folder is available.")
                        .font(.callout)
                }
                Section("Previews") {
                    Toggle("Fetch remote previews for saved links", isOn: Binding(
                        get: { model.fetchPreviews },
                        set: { model.setFetchPreviews($0) }
                    ))
                    Text("Off skips page, DuckDuckGo, and favicon requests. On still never fetches private or loopback addresses.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary(scheme))
                    Button("Clear preview cache") {
                        model.clearCache()
                        status = "Preview cache cleared. Copied originals were left alone."
                    }
                }
                Section("Trash") {
                    Text("Items stay in Trash for \(Limits.trashDays) days. \(model.trashCount) items are in Trash now.")
                        .font(.callout)
                    Button("Empty Trash") {
                        model.emptyTrash()
                        status = "Trash emptied."
                    }
                }
                Section("Export and restore") {
                    Button("Export library…") { exportLibrary() }
                    Button("Restore into empty library…") { restoreLibrary(replace: false) }
                    Button("Replace this library from archive…") { confirmReplace() }
                    Text("Viewing and exporting never require a purchase. Device loss still means loss if you have not exported.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary(scheme))
                }
                Section("Diagnostics") {
                    LabeledContent("Items") { Text("\(model.allCount)") }
                    LabeledContent("Shared container") { Text(model.usesSharedContainer ? "Yes" : "No") }
                    if let usage = try? model.store?.storageUsage() {
                        LabeledContent("Copied originals") { Text(byteString(usage.originalBytes)) }
                        LabeledContent("Preview cache") { Text(byteString(usage.previewBytes)) }
                    }
                    if let status {
                        Text(status)
                            .font(.callout)
                            .foregroundStyle(Theme.accent(scheme))
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
            .tabItem { Label("Library", systemImage: "books.vertical") }

            Form {
                Section("Safari") {
                    LabeledContent("Extension") {
                        Text(safariExtensionState)
                    }
                    Button("Turn on Stowmark in Safari…") {
                        model.openSafariExtensionSettings()
                    }
                    .help("Opens Safari's extension settings with Stowmark selected")
                    Toggle("Safari toolbar click saves immediately", isOn: $toolbarClickSaves)
                        .onChange(of: toolbarClickSaves) { _, enabled in
                            SafariSupport.setToolbarClickSavesImmediately(enabled)
                        }
                    Text("On, the toolbar button saves the page. Off, it opens the popup. Right-click menus stay.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary(scheme))
                }
                Section("Bookmarklets") {
                    Text("Save this page")
                        .font(.callout)
                    Text(LibraryModel.safariPageBookmarklet)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Text("Save the selection")
                        .font(.callout)
                    Text(LibraryModel.safariExcerptBookmarklet)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Section("Chrome, Arc, Brave, and Edge") {
                    if chromeBrowsers.isEmpty {
                        Text("No Chromium browser has been run on this Mac yet.")
                            .font(.callout)
                            .foregroundStyle(Theme.secondary(scheme))
                    } else {
                        ForEach(chromeBrowsers, id: \.name) { browser in
                            LabeledContent(browser.name) {
                                Text(browser.installed ? "Ready" : "Not installed")
                                    .foregroundStyle(browser.installed ? Theme.accent(scheme) : Theme.secondary(scheme))
                            }
                        }
                    }
                    HStack {
                        Button("Install Chrome capture") { installChromeHost() }
                        if chromeBrowsers.contains(where: \.installed) {
                            Button("Remove") { removeChromeHost() }
                        }
                    }
                    Text("This installs the helper that lets the extension save without opening Stowmark. The extension itself is installed from the Chrome Web Store. The helper records where this copy of Stowmark lives, so run it again if you move the app.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary(scheme))
                    if let listing = ChromeSupport.storeListingURL {
                        Link("Install the extension for Chrome", destination: listing)
                    } else {
                        Text("Add the Web Store ID below once the listing is published, and a one-click install link appears here.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary(scheme))
                    }
                    TextField("Web Store extension ID", text: $chromeStoreID)
                        .onSubmit { saveChromeStoreID() }
                    Text("Until then, load ChromeExtension in Chrome with developer mode. That build always has the ID \(ChromeSupport.pinnedExtensionID), which this Mac already trusts.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary(scheme))
                }
                Section("Any other app") {
                    Text("Share and the Services menu save from any Mac app, and stowmark://save works from a bookmarklet (cardfile:// and mymind:// still accepted).")
                        .font(.callout)
                        .foregroundStyle(Theme.secondary(scheme))
                }
            }
            .formStyle(.grouped)
            .padding()
            .task {
                safariExtensionState = await SafariSupport.extensionStateLabel()
                chromeBrowsers = ChromeSupport.presentBrowsers()
            }
            .tabItem { Label("Capture", systemImage: "tray.and.arrow.down") }
        }
        .frame(width: 560, height: 640)
    }

    private func installChromeHost() {
        let report = ChromeSupport.install()
        chromeBrowsers = ChromeSupport.presentBrowsers()
        status = report.summary
    }

    private func removeChromeHost() {
        let report = ChromeSupport.remove()
        chromeBrowsers = ChromeSupport.presentBrowsers()
        status = report.installed.isEmpty
            ? "Chrome capture was not installed."
            : "Chrome capture removed for \(report.installed.joined(separator: ", "))."
    }

    private func saveChromeStoreID() {
        ChromeSupport.storeExtensionID = chromeStoreID
        chromeStoreID = ChromeSupport.storeExtensionID
        // Existing manifests still list the old IDs until they are written again.
        if chromeBrowsers.contains(where: \.installed) {
            installChromeHost()
        }
    }

    private func byteString(_ value: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(value))
    }

    private func exportLibrary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "stowmark")!]
        panel.nameFieldStringValue = "Stowmark-library.stowmark"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportArchive(to: url)
            status = "Library exported."
        } catch {
            status = error.localizedDescription
        }
    }

    private func confirmReplace() {
        let alert = NSAlert()
        alert.messageText = "Replace this library?"
        alert.informativeText = "Export a backup first. Replace overwrites every item on this Mac with the archive."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Choose Archive…")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        restoreLibrary(replace: true)
    }

    private func restoreLibrary(replace: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "stowmark")!,
            .init(filenameExtension: "cardfile")!,
            .init(filenameExtension: "mymind")!,
            .zip,
        ]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.restoreArchive(from: url, replace: replace)
            status = "Library restored."
        } catch {
            status = error.localizedDescription
        }
    }
}
