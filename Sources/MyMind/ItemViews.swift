import AppKit
import LibraryCore
import SwiftUI

struct ItemCard: View {
    var item: SavedItem
    var selected: Bool
    var root: URL?
    var size: CardSize
    var onTrash: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewZone
                .frame(maxWidth: .infinity)
                .frame(height: size.previewHeight)
                .background(previewBackdrop)
                .clipped()
                .overlay {
                    if item.previewState == .pending, photo == nil {
                        Text("Fetching preview…")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary(scheme))
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
                    .help(item.cardContext ?? "Open preview to read the rest.")
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
            if item.trashedAt == nil, let onTrash {
                CardTrashButton(action: onTrash)
                    .padding(8)
            }
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
            if let fittedPhoto { fittedPhoto } else { imagePlaceholder }
        case .excerpt:
            excerptPreview
        case .document:
            documentPreview
        case .research:
            researchPreview
        case .social:
            socialPreview
        case .article:
            if let fittedPhoto { fittedPhoto } else { articleMasthead }
        case .link:
            if let fittedPhoto { fittedPhoto } else { typographicTile }
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

    @ViewBuilder
    private var fittedPhoto: some View? {
        if let photo {
            photo
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(item.kind == .image ? 8 : 0)
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
            if let photo {
                photo
                    .resizable()
                    .scaledToFit()
                    .frame(width: coverWidth, height: coverHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text(item.title)
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(Theme.onAccent(scheme))
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
                    .frame(width: coverWidth - 16, height: coverHeight - 12, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let fittedPhoto { fittedPhoto } else { Spacer(minLength: 0) }
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

    private var photo: Image? {
        guard let root else { return nil }
        let preferOriginal = item.kind == .image || item.kind == .book
        let asset = preferOriginal
            ? (item.originalAsset ?? item.previewAsset)
            : (item.previewAsset ?? (item.kind == .image ? item.originalAsset : nil))
        guard let asset, let image = NSImage(contentsOf: asset.fileURL(in: root)) else { return nil }
        return Image(nsImage: image)
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
    @State private var note: String = ""
    @State private var tagDraft = ""
    @State private var showDetails = false

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
                if item.kind == .excerpt {
                    Text(item.summary ?? "")
                        .font(.system(.body, design: .serif))
                        .textSelection(.enabled)
                } else if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(Theme.secondary(scheme))
                        .textSelection(.enabled)
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
                Button(item.originalAsset == nil ? "Open original" : "Open saved file") { model.openOriginal(item) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent(scheme))
                    .frame(minHeight: 44)
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
                            Button("Move to My Mind Trash") { model.trashSelected() }
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
            title = item.title
            note = item.note ?? ""
        }
        .onChange(of: item.id) { _, _ in
            title = item.title
            note = item.note ?? ""
        }
        .onDisappear {
            if title != item.title { model.saveTitle(item.id, title) }
            if note != (item.note ?? "") { model.saveNote(item.id, note) }
        }
    }

    @ViewBuilder private var object: some View {
        if let root = model.store?.rootURL,
           let asset = item.kind == .image || item.kind == .book
            ? (item.originalAsset ?? item.previewAsset)
            : (item.previewAsset ?? item.originalAsset),
           let image = NSImage(contentsOf: asset.fileURL(in: root)),
           item.kind == .image || item.kind == .book || item.previewAsset != nil {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: item.kind == .book ? 4 : Theme.Radius.card))
        } else if item.kind == .book {
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
    static let filterTag = Notification.Name("MyMind.filterTag")
}

struct CoverTile: View {
    var item: SavedItem
    var selected: Bool
    var root: URL?
    var size: CGFloat
    var onTrash: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(Theme.sidebar(scheme))
                if let image = coverImage {
                    image
                        .resizable()
                        .scaledToFit()
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
            .overlay(alignment: .bottomTrailing) {
                if item.trashedAt == nil, let onTrash {
                    CardTrashButton(action: onTrash)
                        .padding(6)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.kind.label), \(item.title), \(item.keptLabel)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var coverImage: Image? {
        guard let root else { return nil }
        let asset = item.kind == .image || item.kind == .book
            ? (item.originalAsset ?? item.previewAsset)
            : item.previewAsset
        guard let asset, let image = NSImage(contentsOf: asset.fileURL(in: root)) else { return nil }
        return Image(nsImage: image)
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
        .help("Move to My Mind Trash")
        .accessibilityLabel("Move to My Mind Trash")
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
