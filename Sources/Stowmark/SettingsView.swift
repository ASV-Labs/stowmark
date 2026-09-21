import AppKit
import LibraryCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: LibraryModel
    @Environment(\.colorScheme) private var scheme
    @State private var status: String?
    @AppStorage("stowmark.settingsTab") private var selectedTab = SettingsTab.general.rawValue

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general
        case library
        case capture
        case help

        var id: String { rawValue }

        var label: String {
            switch self {
            case .general: "General"
            case .library: "Library"
            case .capture: "Capture"
            case .help: "Help"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .library: "books.vertical"
            case .capture: "tray.and.arrow.down"
            case .help: "questionmark.circle"
            }
        }
    }

    var body: some View {
        TabView(selection: Binding(
            get: { SettingsTab(rawValue: selectedTab) ?? .general },
            set: { selectedTab = $0.rawValue }
        )) {
            generalTab
                .tabItem { Label(SettingsTab.general.label, systemImage: SettingsTab.general.symbol) }
                .tag(SettingsTab.general)

            libraryTab
                .tabItem { Label(SettingsTab.library.label, systemImage: SettingsTab.library.symbol) }
                .tag(SettingsTab.library)

            captureTab
                .tabItem { Label(SettingsTab.capture.label, systemImage: SettingsTab.capture.symbol) }
                .tag(SettingsTab.capture)

            helpTab
                .tabItem { Label(SettingsTab.help.label, systemImage: SettingsTab.help.symbol) }
                .tag(SettingsTab.help)
        }
        .frame(width: 560, height: 640)
        .onReceive(NotificationCenter.default.publisher(for: .openStowmarkHelp)) { _ in
            selectedTab = SettingsTab.help.rawValue
        }
    }

    private var generalTab: some View {
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
                Toggle("Watch clipboard for links and images", isOn: Binding(
                    get: { model.clipboardWatcherEnabled },
                    set: { model.clipboardWatcherEnabled = $0 }
                ))
                Text("When on, Stowmark saves a new pasteboard URL or image automatically. Plain text is ignored.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary(scheme))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var libraryTab: some View {
        Form {
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
    }

    private var captureTab: some View {
        Form {
            Section {
                Text("Browser extensions are not ready in this alpha. Use paste, drop, Share, Services, or the menu bar instead.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondary(scheme))
                LabeledContent("Safari") {
                    Text("Coming soon")
                        .foregroundStyle(Theme.secondary(scheme))
                }
                LabeledContent("Chrome") {
                    Text("Coming soon")
                        .foregroundStyle(Theme.secondary(scheme))
                }
                LabeledContent("Arc, Brave, and Edge") {
                    Text("Coming soon")
                        .foregroundStyle(Theme.secondary(scheme))
                }
            } header: {
                Text("Browser extensions")
            } footer: {
                Text("Share from Safari or Chrome still saves into the same local library today.")
            }

            Section("Works today") {
                Text("Paste a link into the capture bar, drop a file, use ⇧⌘V / the menu bar icon, Share to Stowmark, or Services → Save to Stowmark.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondary(scheme))
                Text("stowmark://save works from a bookmarklet.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary(scheme))
            }

            Section("Bookmarklets (optional)") {
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
        }
        .formStyle(.grouped)
        .padding()
    }

    private var helpTab: some View {
        UserGuideView()
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
