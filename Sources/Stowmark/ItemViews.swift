import AppKit
import LibraryCore
import SwiftUI

struct ItemCard: View {
    var item: SavedItem
    var selected: Bool
    var root: URL?
    var size: CardSize
    var onTrash: (() -> Void)? = nil
    var onFavorite: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil
    var onAddPreview: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false
    @State private var thumbnailLoaded = false
    @State private var thumbnailSettled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewZone
                .frame(maxWidth: .infinity)
                .frame(height: size.previewHeight)
                .background(previewBackdrop)
            .clipped()
            .overlay {
                if showsFetchingPreview {
                    Text("Fetching preview…")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary(scheme))
                }
            }
            .overlay(alignment: .bottomLeading) {
                if showsAddPhoto, let onAddPreview {
                    AddPreviewPhotoButton(compact: true, action: onAddPreview)
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(item.kind == .book || item.kind == .research ? .system(.headline, design: .serif) : .headline)
                    .foregroundStyle(Theme.ink(scheme))
                    .lineLimit(2)
                    .help(item.title)
                Text(item.cardContext ?? " ")
                    .font(.callout)
                    .foregroundStyle(item.cardContext == nil ? Color.clear : (item.contextIsNote ? Theme.ink(scheme) : Theme.secondary(scheme)))
                    .lineLimit(2)
                    .help(item.cardContext ?? "Open the card to add a description.")
                Spacer(minLength: 0)
                footer
                tagRow
            }
            .padding(12)
            .padding(.trailing, item.trashedAt == nil && onTrash != nil ? 24 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: size.cardHeight, maxHeight: size.cardHeight, alignment: .top)
        .background(item.kind == .excerpt ? Theme.sidebar(scheme) : Theme.card(scheme), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(selected ? Theme.accent(scheme) : Theme.line(scheme, increased: contrast == .increased), lineWidth: selected ? 2 : 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if item.trashedAt == nil {
                CardQuickActions(
                    favorite: item.favorite,
                    opensFile: item.originalAsset != nil,
                    hovered: hovered,
                    onFavorite: onFavorite,
                    onOpen: onOpen,
                    onTrash: onTrash,
                    inset: 8
                )
            }
        }
        .onHover { hovered = $0 }
        .onPreferenceChange(ThumbnailStatusKey.self) { status in
            thumbnailLoaded = status.loaded
            thumbnailSettled = status.settled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Open preview to read the rest")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var previewZone: some View {
        switch item.kind {
        case .book:
            bookPreview
        case .image:
            photoZone(padding: 8) { imagePlaceholder }
        case .excerpt:
            photoIfPresent { excerptPreview }
        case .document:
            photoIfPresent { documentPreview }
        case .research:
            photoIfPresent { researchPreview }
        case .social:
            photoIfPresent { socialPreview }
        case .article:
            photoZone { articleMasthead }
        case .link:
            photoZone { typographicTile }
        }
    }

    /// Point size of the card preview zone. The cache decodes about 2× this, not the original.
    private var thumbnailPointSize: CGFloat { size.previewHeight }

    private var showsAddPhoto: Bool {
        item.trashedAt == nil && item.lacksPreviewPhoto && onAddPreview != nil
    }

    /// Pending enrichment with nothing to show. A thumbnail that is still decoding does not count as missing.
    @MainActor
    private var showsFetchingPreview: Bool {
        guard item.previewState == .pending, !hasThumbnail else { return false }
        if cardPhotoAsset == nil { return true }
        return thumbnailSettled
    }

    @MainActor
    private var hasThumbnail: Bool {
        if thumbnailLoaded { return true }
        guard let asset = cardPhotoAsset else { return false }
        return ImageCache.shared.peek(
            sha256: asset.sha256,
            minPixel: ImageCache.pixelLimit(forPointSize: thumbnailPointSize)
        ) != nil
    }

    private var cardPhotoAsset: AssetRecord? {
        let preferOriginal = item.kind == .image || item.kind == .book
        if preferOriginal {
            return item.originalAsset ?? item.previewAsset
        }
        return item.previewAsset ?? (item.kind == .image ? item.originalAsset : nil)
    }

    @ViewBuilder
    private func photoIfPresent<Fallback: View>(@ViewBuilder fallback: @escaping () -> Fallback) -> some View {
        if cardPhotoAsset != nil {
            photoZone(fallback: fallback)
        } else {
            fallback()
        }
    }

    @ViewBuilder
    private func photoZone<Fallback: View>(padding: CGFloat = 0, @ViewBuilder fallback: @escaping () -> Fallback) -> some View {
        if let asset = cardPhotoAsset {
            AsyncThumbnail(asset: asset, root: root, maxPointSize: thumbnailPointSize) {
                fallback()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(padding)
        } else {
            fallback()
        }
    }

    private var previewBackdrop: some View {
        Group {
            switch item.kind {
            case .research: Theme.card(scheme)
            case .document, .social: Theme.accentSoft(scheme)
            default: Theme.sidebar(scheme)
            }
        }
    }

    private var bookPreview: some View {
        let coverWidth = size.previewHeight * 0.68
        let coverHeight = size.previewHeight - 16
        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.accent(scheme))
                .frame(width: coverWidth, height: coverHeight)
                .shadow(color: Theme.ink(scheme).opacity(0.16), radius: 8, y: 4)
            if let asset = cardPhotoAsset {
                AsyncThumbnail(asset: asset, root: root, maxPointSize: thumbnailPointSize) {
                    bookCoverTitle(coverWidth: coverWidth, coverHeight: coverHeight)
                }
                .frame(width: coverWidth, height: coverHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                bookCoverTitle(coverWidth: coverWidth, coverHeight: coverHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bookCoverTitle(coverWidth: CGFloat, coverHeight: CGFloat) -> some View {
        Text(item.title)
            .font(.system(.caption, design: .serif))
            .foregroundStyle(Theme.onAccent(scheme))
            .multilineTextAlignment(.leading)
            .lineLimit(5)
            .frame(width: coverWidth - 16, height: coverHeight - 12, alignment: .topLeading)
    }

    private var excerptPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("“")
                .font(.system(.title, design: .serif))
                .foregroundStyle(Theme.accent(scheme))
            Text(item.summary ?? "")
                .font(.system(.callout, design: .serif))
                .foregroundStyle(Theme.ink(scheme))
                .lineLimit(4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var documentPreview: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.card(scheme))
                .offset(x: 6, y: -6)
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.accentSoft(scheme))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "doc")
                        .foregroundStyle(Theme.accent(scheme))
                        .padding(10)
                }
                .overlay(alignment: .bottomLeading) {
                    Text((item.filename ?? "PDF").uppercased())
                        .font(.caption2)
                        .foregroundStyle(Theme.secondary(scheme))
                        .padding(8)
                }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var researchPreview: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Theme.paperRule(scheme))
                .frame(width: 1)
            VStack(alignment: .leading, spacing: 6) {
                Text("Research")
                    .font(.caption)
                    .tracking(1.2)
                    .foregroundStyle(Theme.accent(scheme))
                if let author = item.author, !author.isEmpty {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary(scheme))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var socialPreview: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.wash(item.sourceLabel, scheme))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(String(item.sourceLabel.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(Theme.ink(scheme))
                }
            if let asset = cardPhotoAsset {
                AsyncThumbnail(asset: asset, root: root, maxPointSize: thumbnailPointSize) {
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var articleMasthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.sourceLabel.uppercased())
                    .font(.caption)
                    .tracking(1.1)
                Spacer()
                Text("Article")
                    .font(.caption)
            }
            .foregroundStyle(Theme.secondary(scheme))
            Rectangle()
                .fill(Theme.accent(scheme))
                .frame(height: 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var typographicTile: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Theme.accent(scheme))
                .frame(width: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(item.sourceLabel.prefix(1)).uppercased())
                    .font(.largeTitle)
                    .foregroundStyle(Theme.accent(scheme))
                Text(item.sourceLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary(scheme))
                    .lineLimit(1)
            }
            .padding(12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var imagePlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Theme.card(scheme), lineWidth: 10)
                .padding(14)
            Text("Image")
                .font(.caption)
                .foregroundStyle(Theme.secondary(scheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(item.sourceLabel)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(item.kind.label)
            Text("·")
            Text(retentionLine)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(Theme.secondary(scheme))
    }

    private var tagRow: some View {
        let tags = item.confirmedTags
        return HStack(spacing: 6) {
            ForEach(tags.prefix(2)) { tag in
                Button {
                    NotificationCenter.default.post(name: .filterTag, object: tag.label)
                } label: {
                    Text(tag.label)
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.accentSoft(scheme), in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter by \(tag.label)")
            }
            if tags.count > 2 {
                Text("+\(tags.count - 2)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary(scheme))
                    .accessibilityLabel("\(tags.count - 2) more tags in preview")
            }
            if tags.isEmpty {
                Text(" ")
                    .font(.caption)
            }
        }
        .frame(height: 22)
    }

    private var retentionLine: String {
        if item.retention == .bookmark && item.previewState == .unavailable {
            return "Preview unavailable"
        }
        if item.kind == .book && item.retention == .bookmark {
            return "Book link"
        }
        return item.retention.label
    }

    private var accessibilityText: String {
        var parts = [item.kind.label, item.title, item.sourceLabel, retentionLine]
        let tags = item.confirmedTags.map(\.label)
        if !tags.isEmpty { parts.append(tags.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }
}

struct ItemPreview: View {
    var item: SavedItem
    var model: LibraryModel
    @Environment(\.colorScheme) private var scheme
    @State private var title: String = ""
    @State private var descriptionText: String = ""
    @State private var committedDescription: String = ""
    @State private var note: String = ""
    @State private var committedNote: String = ""
    @State private var tagDraft = ""
    @State private var showDetails = false
    @State private var noteSaveTask: Task<Void, Never>?
    @State private var descriptionSaveTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(item.kind.label)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary(scheme))
                    Spacer()
                    Button("Close") { model.closePreview() }
                }
                object
                Text(item.title)
                    .font(.title2)
                    .foregroundStyle(Theme.ink(scheme))
                    .textSelection(.enabled)
                Text(item.sourceLabel)
                    .font(.callout)
                    .foregroundStyle(Theme.secondary(scheme))
                Text(item.kind == .book && item.retention == .bookmark ? "Book link, not an ebook" : retentionLine)
                    .font(.callout)
                    .foregroundStyle(Theme.accent(scheme))
                if item.previewState == .unavailable && item.retention == .bookmark {
                    Text("The title, tags, and note are still on this Mac.")
                        .font(.callout)
                        .foregroundStyle(Theme.secondary(scheme))
                }
                if item.lacksPreviewPhoto, item.trashedAt == nil {
                    Button("Add preview photo") { model.choosePreviewPhoto(for: item.id) }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 36)
                        .help("Choose a photo for this card’s preview")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary(scheme))
                    ResizableTextBlock(text: $descriptionText, placeholder: "Preview text on the card")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your note")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary(scheme))
                    TextField("A line you’ll recognize later", text: $note, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags")
                        .font(.caption)
                    FlowTags(item: item, model: model)
                    HStack {
                        TextField("Add a tag", text: $tagDraft)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            model.addTag(item.id, tagDraft)
                            tagDraft = ""
                        }
                        .frame(minHeight: 32)
                    }
                }
                HStack(spacing: 8) {
                    Button(item.originalAsset == nil ? "Open original" : "Open saved file") { model.openOriginal(item) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent(scheme))
                        .frame(minHeight: 44)
                    if let link = copyableLink {
                        Button("Copy link") { copyLink(link) }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                            .help("Copy the original link")
                    }
                }
                DisclosureGroup("Edit details", isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Title", text: $title, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.saveTitle(item.id, title) }
                        Picker("Kind", selection: Binding(get: { item.kind }, set: { model.saveKind(item.id, $0) })) {
                            ForEach(ContentKind.allCases) { kind in
                                Text(kind.label).tag(kind)
                            }
                        }
                        Button(item.favorite ? "Unfavorite" : "Favorite") { model.toggleFavorite(item.id) }
                            .frame(minHeight: 36)
                        if item.retention == .bookmark {
                            Button(item.previewState == .pending ? "Refreshing preview…" : "Refresh preview") {
                                model.refreshPreview(item.id)
                            }
                            .disabled(item.previewState == .pending)
                            .frame(minHeight: 36)
                        }
                        if !model.shelves.isEmpty {
                            ForEach(model.shelves) { shelf in
                                Toggle(shelf.name, isOn: Binding(
                                    get: { item.shelves.contains { $0.id == shelf.id } },
                                    set: { model.setMembership(item.id, shelf.id, $0) }
                                ))
                            }
                        }
                        if item.trashedAt != nil {
                            Button("Restore") { model.restoreSelected() }
                                .frame(minHeight: 36)
                        } else {
                            Button("Move to Stowmark Trash") { model.trashSelected() }
                                .foregroundStyle(Theme.danger(scheme))
                                .frame(minHeight: 36)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(18)
        }
        .onAppear {
            adoptFields(from: item, flushPreviousID: nil)
            title = item.title
        }
        .onChange(of: item.id) { oldID, _ in
            adoptFields(from: item, flushPreviousID: oldID)
            title = item.title
        }
        .onChange(of: note) { _, _ in
            scheduleNoteSave()
        }
        .onChange(of: descriptionText) { _, _ in
            scheduleDescriptionSave()
        }
        .onDisappear {
            noteSaveTask?.cancel()
            descriptionSaveTask?.cancel()
            if title != item.title { model.saveTitle(item.id, title) }
            if note != (item.note ?? "") { model.saveNote(item.id, note) }
            if descriptionText != (item.summary ?? "") { model.saveDescription(item.id, descriptionText) }
        }
    }

    private var copyableLink: String? {
        guard let raw = item.originalURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
    }

    @MainActor
    private func copyLink(_ raw: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let url = URL(string: raw) {
            pasteboard.writeObjects([url as NSURL])
        } else {
            pasteboard.setString(raw, forType: .string)
        }
    }

    @MainActor
    private func adoptFields(from item: SavedItem, flushPreviousID: UUID?) {
        noteSaveTask?.cancel()
        descriptionSaveTask?.cancel()
        if let flushPreviousID {
            if note != committedNote { model.saveNote(flushPreviousID, note) }
            if descriptionText != committedDescription { model.saveDescription(flushPreviousID, descriptionText) }
        }
        note = item.note ?? ""
        committedNote = note
        descriptionText = item.summary ?? ""
        committedDescription = descriptionText
    }

    @MainActor
    private func scheduleDescriptionSave() {
        descriptionSaveTask?.cancel()
        let draft = descriptionText
        guard draft != committedDescription else { return }
        let itemID = item.id
        descriptionSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            model.saveDescription(itemID, draft)
            if item.id == itemID {
                committedDescription = draft
            }
        }
    }

    @MainActor
    private func scheduleNoteSave() {
        noteSaveTask?.cancel()
        let draft = note
        guard draft != committedNote else { return }
        let itemID = item.id
        noteSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            model.saveNote(itemID, draft)
            if item.id == itemID {
                committedNote = draft
            }
        }
    }

    @ViewBuilder private var object: some View {
        if let asset = previewImageAsset, let root = model.store?.rootURL {
            AsyncThumbnail(asset: asset, root: root, maxPointSize: 420) {
                objectFallback
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: item.kind == .book ? 4 : Theme.Radius.card))
        } else {
            objectFallback
        }
    }

    private var previewImageAsset: AssetRecord? {
        let candidate = item.kind == .image || item.kind == .book
            ? (item.originalAsset ?? item.previewAsset)
            : (item.previewAsset ?? item.originalAsset)
        guard let candidate else { return nil }
        guard item.kind == .image || item.kind == .book || item.previewAsset != nil else { return nil }
        return candidate
    }

    @ViewBuilder private var objectFallback: some View {
        if item.kind == .book {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.accent(scheme))
                .frame(width: 120, height: 168)
                .overlay {
                    Text(item.title)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(Theme.onAccent(scheme))
                        .padding(10)
                }
        } else if item.kind == .excerpt {
            EmptyView()
        }
    }

    private var retentionLine: String {
        if item.retention == .bookmark && item.previewState == .unavailable {
            return "Link saved, preview unavailable"
        }
        if item.kind == .book && item.retention == .bookmark {
            return "Book link"
        }
        return item.retention.label
    }
}

extension Notification.Name {
    static let filterTag = Notification.Name("Stowmark.filterTag")
    static let openStowmarkSettings = Notification.Name("Stowmark.openSettings")
}

struct CoverTile: View {
    var item: SavedItem
    var selected: Bool
    var root: URL?
    var size: CGFloat
    var onTrash: (() -> Void)? = nil
    var onFavorite: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil
    var onAddPreview: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(Theme.sidebar(scheme))
                if let asset = coverAsset {
                    AsyncThumbnail(asset: asset, root: root, maxPointSize: size) {
                        typographicCover
                    }
                    .frame(maxWidth: size, maxHeight: size)
                    .padding(item.kind == .book ? 10 : 0)
                } else {
                    typographicCover
                }
                if selected {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption)
                            .lineLimit(2)
                        Text(item.keptLabel)
                            .font(.caption2)
                    }
                    .foregroundStyle(Theme.ink(scheme))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(selected ? Theme.accent(scheme) : Theme.line(scheme, increased: contrast == .increased), lineWidth: selected ? 2 : 1)
            )
            .overlay(alignment: .topLeading) {
                if item.trashedAt == nil, item.lacksPreviewPhoto, let onAddPreview {
                    AddPreviewPhotoButton(compact: true, action: onAddPreview)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if item.trashedAt == nil {
                    CardQuickActions(
                        favorite: item.favorite,
                        opensFile: item.originalAsset != nil,
                        hovered: hovered,
                        onFavorite: onFavorite,
                        onOpen: onOpen,
                        onTrash: onTrash,
                        inset: 6
                    )
                }
            }
            if !selected {
                Text(item.title)
                    .font(.caption)
                    .foregroundStyle(Theme.ink(scheme))
                    .lineLimit(2)
                    .frame(width: size, alignment: .leading)
            }
        }
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.kind.label), \(item.title), \(item.keptLabel)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var coverAsset: AssetRecord? {
        if item.kind == .image || item.kind == .book {
            return item.originalAsset ?? item.previewAsset
        }
        return item.previewAsset
    }

    private var typographicCover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(item.sourceLabel.prefix(1)).uppercased())
                .font(.largeTitle)
                .foregroundStyle(Theme.accent(scheme))
            Text(item.sourceLabel)
                .font(.caption)
                .foregroundStyle(Theme.secondary(scheme))
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(item.kind.label)
                .font(.caption2)
                .foregroundStyle(Theme.secondary(scheme))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.wash(item.sourceLabel, scheme))
    }
}

private struct ResizableTextBlock: View {
    @Binding var text: String
    var placeholder: String
    @Environment(\.colorScheme) private var scheme
    @State private var height: CGFloat = 132
    @State private var dragOrigin: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .foregroundStyle(Theme.ink(scheme))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(Theme.secondary(scheme).opacity(0.72))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            resizeGrip
        }
        .background(Theme.sidebar(scheme), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line(scheme, increased: false)))
    }

    private var resizeGrip: some View {
        HStack {
            Spacer()
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(Theme.secondary(scheme))
                .frame(width: 44, height: 16)
                .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, minHeight: 18)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragOrigin == nil { dragOrigin = height }
                    let base = dragOrigin ?? height
                    height = min(420, max(96, base + value.translation.height))
                }
                .onEnded { _ in dragOrigin = nil }
        )
        .help("Drag to resize the description")
        .accessibilityLabel("Resize description")
        .accessibilityHint("Drag up or down to change the height")
    }
}

private struct AddPreviewPhotoButton: View {
    var compact: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(compact ? "Add photo" : "Add preview photo", systemImage: "photo.badge.plus")
                .font(.caption)
                .padding(.horizontal, compact ? 8 : 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Choose a photo for this card’s preview")
        .accessibilityLabel("Add preview photo")
    }
}

private struct CardQuickActions: View {
    var favorite: Bool
    var opensFile: Bool
    var hovered: Bool
    var onFavorite: (() -> Void)?
    var onOpen: (() -> Void)?
    var onTrash: (() -> Void)?
    var inset: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            quickButton(
                systemName: favorite ? "star.fill" : "star",
                help: favorite ? "Unfavorite" : "Favorite",
                label: favorite ? "Unfavorite" : "Favorite",
                enabled: onFavorite != nil,
                action: { onFavorite?() }
            )
            quickButton(
                systemName: "arrow.up.right.square",
                help: opensFile ? "Open saved file" : "Open original",
                label: opensFile ? "Open saved file" : "Open original",
                enabled: onOpen != nil,
                action: { onOpen?() }
            )
            if let onTrash {
                CardTrashButton(action: onTrash)
            }
        }
        .padding(inset)
    }

    private func quickButton(systemName: String, help: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption)
                .foregroundStyle(Theme.secondary(scheme).opacity(enabled ? 1 : 0.35))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .opacity(hovered ? 1 : 0)
        .allowsHitTesting(hovered)
        .help(help)
        .accessibilityLabel(label)
    }
}

private struct CardTrashButton: View {
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.caption)
                .foregroundStyle(Theme.secondary(scheme))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Move to Stowmark Trash")
        .accessibilityLabel("Move to Stowmark Trash")
        .accessibilityHint("Removes this item from the library. It does not use the Mac Trash.")
    }
}

private struct FlowTags: View {
    var item: SavedItem
    var model: LibraryModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(item.confirmedTags) { tag in
                HStack {
                    Button(tag.label) {
                        NotificationCenter.default.post(name: .filterTag, object: tag.label)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button("Remove") { model.removeTag(item.id, tag.id) }
                }
                .font(.callout)
            }
            ForEach(item.suggestedTags) { tag in
                HStack {
                    Text("Suggested: \(tag.label)")
                        .foregroundStyle(Theme.secondary(scheme))
                    Spacer()
                    Button("Keep") { model.confirmTag(item.id, tag.id) }
                    Button("Not this") { model.removeTag(item.id, tag.id) }
                }
                .font(.callout)
            }
        }
    }
}
