import AppKit
import LibraryCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: LibraryModel
    @Environment(\.colorScheme) private var scheme
    @State private var status: String?

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
                    Toggle("Confirm before moving to My Mind Trash", isOn: Binding(
                        get: { model.confirmTrash },
                        set: { model.setConfirmTrash($0) }
                    ))
                    Toggle("Remember the last shelf when relaunching", isOn: Binding(
                        get: { model.rememberLastPlace },
                        set: { model.setRememberLastPlace($0) }
                    ))
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
                        status = "In Safari, turn on My Mind. Saving a page writes the same local library, including when this window is closed."
                    }
                    Text(model.usesSharedContainer
                         ? "Safari and My Mind are sharing one library on this Mac."
                         : "Safari will open My Mind to finish a save until the shared library folder is available.")
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
        }
        .frame(width: 560, height: 520)
    }

    private func byteString(_ value: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(value))
    }

    private func exportLibrary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "mymind")!]
        panel.nameFieldStringValue = "MyMind-library.mymind"
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
        panel.allowedContentTypes = [.init(filenameExtension: "mymind")!, .zip]
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
