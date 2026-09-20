import AppKit
import LibraryCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Compact share sheet. "Saved" is shown only after `LibraryStore.capture` returns `.saved` or `.alreadySaved`.
@objc(ShareViewController)
final class ShareViewController: NSViewController {
    private let model = ShareDraft()
    private var dismissTask: Task<Void, Never>?
    private var didStart = false

    override func loadView() {
        let size = NSSize(width: 360, height: 460)
        preferredContentSize = size
        let host = NSHostingView(rootView: ShareForm(
            model: model,
            onSave: { [weak self] in self?.save() },
            onCancel: { [weak self] in self?.cancel() }
        ))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        view = host
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Save to Stowmark"
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didStart else { return }
        didStart = true
        Task { @MainActor in
            await loadShare()
        }
    }

    private func loadShare() async {
        model.phase = .loading
        model.statusText = "Reading…"
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let intake = await ShareIntake.load(items: items)
        model.apply(intake)
        model.shelfNames = ShareIntake.shelfNames()
    }

    private func save() {
        guard model.canSave else { return }
        model.phase = .saving
        model.statusText = "Saving…"

        let requests = makeRequests()
        let store: LibraryStore
        do {
            store = try LibraryStore.openForExtension()
        } catch {
            handoff(requestID: requests.first?.requestID ?? UUID())
            return
        }

        var results: [CaptureResult] = []
        for request in requests {
            do {
                let result = try store.capture(request)
                CaptureHandshake.write(result, requestID: request.requestID)
                results.append(result)
            } catch {
                results.append(.failed("Not saved. \(error.localizedDescription)"))
            }
        }
        let summary = ShareStatus.summarize(results)
        model.statusText = summary.text
        if summary.allConfirmed {
            model.phase = .finished
            scheduleDismiss()
        } else if summary.anyConfirmed {
            // A retry would insert the files again. Leave the sheet open so the failure can be read.
            model.phase = .finished
        } else {
            model.phase = .failed
        }
    }

    private func cancel() {
        dismissTask?.cancel()
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        extensionContext?.cancelRequest(withError: error)
    }

    private func handoff(requestID: UUID) {
        let fields = handoffFields()
        let tags = ShareText.tags(model.tags)
        var components = URLComponents()
        components.scheme = "stowmark"
        components.host = "save"
        components.queryItems = [
            URLQueryItem(name: "url", value: fields.url),
            URLQueryItem(name: "title", value: ShareText.optional(model.title) ?? ""),
            URLQueryItem(name: "text", value: fields.text ?? ""),
            URLQueryItem(name: "note", value: ShareText.optional(model.note) ?? ""),
            URLQueryItem(name: "shelf", value: ShareText.optional(model.shelf) ?? ""),
            URLQueryItem(name: "tags", value: tags.joined(separator: ",")),
            URLQueryItem(name: "requestId", value: requestID.uuidString),
        ]
        let pending = CaptureHandshake.pending(requestID: requestID)
        CaptureHandshake.write(pending, requestID: requestID)
        if let url = components.url {
            openHost(url)
        }
        model.phase = .handingOff
        model.statusText = "Opening Stowmark to finish…"
        scheduleDismiss()
    }

    private func handoffFields() -> (url: String, text: String?) {
        guard let first = model.items.first else { return ("", nil) }
        switch first {
        case .bookmark(let url, _):
            return (url, nil)
        case .excerpt(let text, let pageURL):
            return (pageURL ?? "", text)
        case .file:
            return ("", nil)
        }
    }

    private func openHost(_ url: URL) {
        if let context = extensionContext {
            context.open(url) { accepted in
                guard !accepted else { return }
                Task { @MainActor in
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func makeRequests() -> [CaptureRequest] {
        let edited = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = ShareText.optional(model.note)
        let shelf = ShareText.optional(model.shelf)
        let tags = ShareText.tags(model.tags)
        let many = model.items.count > 1
        return model.items.map { item in
            let title = Self.requestTitle(edited: edited, item: item, many: many)
            switch item {
            case .bookmark(let url, let kind):
                return CaptureRequest(
                    requestID: UUID(),
                    captureKind: kind,
                    pageURL: url,
                    targetURL: url,
                    capturedTitle: title,
                    note: note,
                    tags: tags,
                    shelfName: shelf,
                    origin: "share"
                )
            case .file(let kind, let filename, let mime, let bytes, let pageURL):
                return CaptureRequest(
                    requestID: UUID(),
                    captureKind: kind,
                    pageURL: pageURL,
                    capturedTitle: title,
                    note: note,
                    tags: tags,
                    shelfName: shelf,
                    origin: "share",
                    file: CaptureFile(filename: filename, declaredMIME: mime, bytes: bytes)
                )
            case .excerpt(let text, let pageURL):
                return CaptureRequest(
                    requestID: UUID(),
                    captureKind: .selection,
                    pageURL: pageURL,
                    targetURL: pageURL,
                    capturedTitle: title,
                    selectionText: text,
                    note: note,
                    tags: tags,
                    shelfName: shelf,
                    origin: "share"
                )
            }
        }
    }

    private static func requestTitle(edited: String, item: PlannedItem, many: Bool) -> String {
        switch item {
        case .bookmark:
            return edited
        case .file(_, let filename, _, _, _):
            if edited.isEmpty { return filename }
            return many ? "\(edited) — \(filename)" : edited
        case .excerpt:
            return edited
        }
    }
}

struct ShareForm: View {
    @Bindable var model: ShareDraft
    var onSave: () -> Void
    var onCancel: () -> Void
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Save to Stowmark")
                .font(.headline)
            if !model.detail.isEmpty {
                Text(model.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            TextField("Title", text: $model.title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onSubmit(onSave)
                .disabled(fieldsLocked)
            HStack(spacing: 8) {
                TextField("Shelf", text: $model.shelf, prompt: Text("Optional"))
                    .textFieldStyle(.roundedBorder)
                    .disabled(fieldsLocked)
                if !model.shelfNames.isEmpty {
                    Menu("Shelves") {
                        Button("No shelf") { model.shelf = "" }
                        Divider()
                        ForEach(model.shelfNames, id: \.self) { name in
                            Button(name) { model.shelf = name }
                        }
                    }
                    .fixedSize()
                    .disabled(fieldsLocked)
                }
            }
            TextField("Tags", text: $model.tags, prompt: Text("Optional, comma separated"))
                .textFieldStyle(.roundedBorder)
                .disabled(fieldsLocked)
            TextField("Note", text: $model.note, prompt: Text("Optional"), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .disabled(fieldsLocked)
            if !model.retentionText.isEmpty {
                Text(model.retentionText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !model.statusText.isEmpty {
                Text(model.statusText)
                    .font(.callout)
                    .foregroundStyle(model.statusText.hasPrefix("Not saved") ? Color.red : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .frame(minHeight: 44)
                    .disabled(model.phase == .saving || model.phase == .finished || model.phase == .handingOff)
                Spacer()
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .frame(minWidth: 88, minHeight: 44)
                    .disabled(!model.canSave)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { titleFocused = true }
    }

    private var fieldsLocked: Bool {
        model.phase == .loading || model.phase == .saving || model.phase == .finished || model.phase == .handingOff
    }
}

enum SharePhase: Equatable {
    case loading
    case ready
    case saving
    case finished
    case handingOff
    case failed
}

@MainActor
@Observable
final class ShareDraft {
    var title = ""
    var shelf = ""
    var tags = ""
    var note = ""
    var detail = ""
    var retentionText = ""
    var statusText = ""
    var shelfNames: [String] = []
    var phase: SharePhase = .loading
    var items: [PlannedItem] = []

    var canSave: Bool {
        !items.isEmpty && (phase == .ready || phase == .failed)
    }

    func apply(_ intake: Intake) {
        title = intake.title
        detail = intake.detail
        retentionText = intake.retention
        items = intake.items
        if items.isEmpty {
            phase = .failed
            statusText = intake.problem ?? "Not saved. Nothing was shared."
        } else {
            phase = .ready
            statusText = ""
        }
    }
}

enum PlannedItem: Sendable {
    case bookmark(url: String, kind: CaptureKind)
    case file(kind: CaptureKind, filename: String, mime: String?, bytes: Data, pageURL: String?)
    case excerpt(text: String, pageURL: String?)

    var retentionLabel: String {
        switch self {
        case .bookmark:
            RetentionState.bookmark.label
        case .file(let kind, _, _, _, _):
            kind == .pdf ? RetentionState.copiedPDF.label : RetentionState.copiedImage.label
        case .excerpt:
            RetentionState.savedExcerpt.label
        }
    }
}

struct Intake: Sendable {
    var title: String
    var detail: String
    var retention: String
    var items: [PlannedItem]
    var problem: String?
}

/// Decides bookmark vs copied file vs excerpt before the user presses Save.
@MainActor
enum ShareIntake {
    static func load(items: [NSExtensionItem]) async -> Intake {
        var collected = Collected()
        collected.suggestedTitle = items
            .compactMap { $0.attributedTitle?.string }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        let providers = items.flatMap { $0.attachments ?? [] }
        for provider in providers.prefix(20) {
            let piece = await piece(from: provider)
            collected.webs.append(contentsOf: piece.webs)
            collected.texts.append(contentsOf: piece.texts)
            for file in piece.files where collected.files.count < 10 {
                collected.files.append(file)
            }
            collected.skippedUnsupported += piece.skippedUnsupported
            collected.skippedTooLarge += piece.skippedTooLarge
        }

        if collected.texts.isEmpty {
            let bodies = items.compactMap { $0.attributedContentText?.string }
            collected.texts.append(contentsOf: bodies)
        }
        return plan(collected)
    }

    static func shelfNames() -> [String] {
        guard let store = try? LibraryStore.openForExtension() else { return [] }
        return (try? store.shelves().map(\.name).filter { !$0.isEmpty }) ?? []
    }

    /// A page share often lists `public.url` before a preview image. File and image shares list the bytes first.
    private static func prefersFile(_ provider: NSItemProvider) -> Bool {
        let types = provider.registeredTypeIdentifiers
        func isFileish(_ identifier: String) -> Bool {
            if identifier == "public.heif" || identifier == "com.adobe.pdf" || identifier == "com.apple.web-internet-location" {
                return true
            }
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .fileURL) || type.conforms(to: .image) || type.conforms(to: .pdf)
        }
        guard let fileIndex = types.firstIndex(where: isFileish) else { return false }
        if let urlIndex = types.firstIndex(of: UTType.url.identifier) {
            return fileIndex < urlIndex
        }
        return true
    }

    private static func piece(from provider: NSItemProvider) async -> Piece {
        var piece = Piece()
        var filename = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if filename?.isEmpty == true { filename = nil }
        var fileBytes: Data?
        var fileIsWebloc = false
        var sawTooLarge = false
        let wantsBytes = prefersFile(provider)

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(provider, UTType.fileURL.identifier) {
            if url.isFileURL {
                filename = filename ?? url.lastPathComponent
                fileIsWebloc = url.pathExtension.lowercased() == "webloc"
                if wantsBytes {
                    switch readFile(at: url) {
                    case .data(let data):
                        fileBytes = data
                    case .tooLarge:
                        sawTooLarge = true
                    case .unreadable:
                        break
                    }
                }
            } else if let web = httpURL(url.absoluteString) {
                piece.webs.append(WebHit(url: web, source: .page))
            }
        }

        if !piece.webs.contains(where: { $0.source == .page }),
           provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(provider, UTType.url.identifier),
           !url.isFileURL,
           let web = httpURL(url.absoluteString) {
            piece.webs.append(WebHit(url: web, source: .page))
        }

        if wantsBytes, fileBytes == nil, !sawTooLarge,
           let loaded = await loadOriginal(provider, suggested: filename) {
            fileBytes = loaded.data
            filename = loaded.filename
        }

        if wantsBytes, sawTooLarge, fileBytes == nil {
            piece.skippedTooLarge += 1
        } else if let fileBytes {
            switch classify(bytes: fileBytes, filename: filename ?? "Shared", isWebloc: fileIsWebloc) {
            case .bookmark(let url):
                piece.webs.append(WebHit(url: url, source: .webloc))
            case .stored(let file):
                piece.files.append(file)
            case .tooLarge:
                piece.skippedTooLarge += 1
            case .unsupported:
                piece.skippedUnsupported += 1
            }
        } else if wantsBytes {
            piece.skippedUnsupported += 1
        }

        if let text = await loadText(provider) {
            piece.texts.append(text)
        }
        return piece
    }

    private static func plan(_ collected: Collected) -> Intake {
        var webs = deduped(collected.webs)
        var prose: [String] = []
        var rejected: String?
        for raw in collected.texts {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let url = singleHTTP(text) {
                if !webs.contains(where: { sameURL($0.url, url) }) {
                    webs.append(WebHit(url: url, source: .link))
                }
                continue
            }
            if !text.contains(where: \.isNewline), text.contains("://"),
               case .failure(let error) = URLSafety.captureURL(from: text) {
                rejected = error.localizedDescription
                continue
            }
            if webs.contains(where: { sameURL($0.url, text) }) { continue }
            if !prose.contains(text) { prose.append(text) }
        }

        let pageURL = webs.first(where: { $0.source == .page })?.url ?? webs.first?.url
        var items: [PlannedItem] = []
        if !collected.files.isEmpty {
            items = collected.files.map { file in
                PlannedItem.file(kind: file.kind, filename: file.filename, mime: file.mime, bytes: file.bytes, pageURL: pageURL)
            }
        } else if let pageURL, !prose.isEmpty {
            items = [.excerpt(text: joined(prose), pageURL: pageURL)]
        } else if !prose.isEmpty {
            items = [.excerpt(text: joined(prose), pageURL: nil)]
        } else if let web = webs.first(where: { $0.source == .page }) ?? webs.first {
            let kind: CaptureKind = web.source == .page ? .page : .link
            items = [.bookmark(url: web.url, kind: kind)]
        }

        let title = suggestedTitle(collected.suggestedTitle, items: items)
        let detail = detailLine(items: items, skippedUnsupported: collected.skippedUnsupported, skippedTooLarge: collected.skippedTooLarge)
        let retention = retentionLine(items.map(\.retentionLabel))
        let problem = items.isEmpty ? problemLine(rejected: rejected, collected: collected) : nil
        return Intake(title: title, detail: detail, retention: retention, items: items, problem: problem)
    }

    private static func suggestedTitle(_ raw: String?, items: [PlannedItem]) -> String {
        if let raw {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, singleHTTP(trimmed) == nil { return trimmed }
        }
        switch items.first {
        case .bookmark(let url, _):
            return hostTitle(url)
        case .file(_, let filename, _, _, _):
            let stem = (filename as NSString).deletingPathExtension
            return stem.isEmpty ? filename : stem
        case .excerpt(let text, _):
            return snippet(text, limit: 80)
        case nil:
            return ""
        }
    }

    private static func detailLine(items: [PlannedItem], skippedUnsupported: Int, skippedTooLarge: Int) -> String {
        let primary: String
        switch items.count {
        case 0:
            primary = ""
        case 1:
            switch items[0] {
            case .bookmark(let url, _):
                primary = url
            case .file(_, let filename, _, _, let pageURL):
                primary = pageURL ?? filename
            case .excerpt(let text, _):
                primary = snippet(text, limit: 180)
            }
        default:
            primary = items.map { item in
                switch item {
                case .bookmark(let url, _): url
                case .file(_, let filename, _, _, _): filename
                case .excerpt(let text, _): snippet(text, limit: 60)
                }
            }.joined(separator: ", ")
        }
        var notes: [String] = []
        if skippedUnsupported > 0 {
            notes.append("Skipped \(skippedUnsupported) file\(skippedUnsupported == 1 ? "" : "s") Stowmark cannot copy.")
        }
        if skippedTooLarge > 0 {
            notes.append("Skipped \(skippedTooLarge) file\(skippedTooLarge == 1 ? "" : "s") over 100 MB.")
        }
        return ([primary] + notes).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func problemLine(rejected: String?, collected: Collected) -> String {
        if let rejected { return rejected }
        if collected.skippedTooLarge > 0 && collected.skippedUnsupported == 0 && collected.files.isEmpty {
            return "Not saved. That file is over the 100 MB limit."
        }
        if collected.skippedUnsupported > 0 {
            return "Not saved. Stowmark can copy JPEG, PNG, HEIC, and PDF files."
        }
        return "Not saved. Nothing was shared."
    }

    private static func retentionLine(_ labels: [String]) -> String {
        let order = [
            RetentionState.bookmark.label,
            RetentionState.copiedImage.label,
            RetentionState.copiedPDF.label,
            RetentionState.savedExcerpt.label,
        ]
        let unique = order.filter { labels.contains($0) }
        guard !unique.isEmpty else { return "" }
        return "Will keep: \(unique.joined(separator: " · "))"
    }

    static func hostTitle(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        let domain = URLSafety.domain(for: url)
        return domain.isEmpty ? urlString : domain
    }

    static func snippet(_ text: String, limit: Int) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
        if oneLine.count <= limit { return oneLine }
        return String(oneLine.prefix(limit)) + "…"
    }

    private static func joined(_ prose: [String]) -> String {
        let text = prose.joined(separator: "\n\n")
        if text.count <= Limits.maxExcerptCharacters { return text }
        return String(text.prefix(Limits.maxExcerptCharacters + 1))
    }

    private static func deduped(_ webs: [WebHit]) -> [WebHit] {
        var unique: [WebHit] = []
        for hit in webs where !unique.contains(where: { sameURL($0.url, hit.url) }) {
            unique.append(hit)
        }
        return unique
    }

    private static func sameURL(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        guard case .success(let left) = URLSafety.captureURL(from: lhs),
              case .success(let right) = URLSafety.captureURL(from: rhs) else { return false }
        return URLSafety.matchKey(for: left) == URLSafety.matchKey(for: right)
    }

    private static func httpURL(_ raw: String) -> String? {
        guard case .success(let url) = URLSafety.captureURL(from: raw) else { return nil }
        return url.absoluteString
    }

    private static func singleHTTP(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return nil }
        return httpURL(trimmed)
    }

    private static func loadOriginal(_ provider: NSItemProvider, suggested: String?) async -> (data: Data, filename: String)? {
        let originals: [(String, String)] = [
            (UTType.pdf.identifier, "pdf"),
            (UTType.jpeg.identifier, "jpg"),
            (UTType.png.identifier, "png"),
            (UTType.heic.identifier, "heic"),
            ("public.heif", "heif"),
        ]
        for (identifier, ext) in originals where provider.hasItemConformingToTypeIdentifier(identifier) {
            if let data = await loadData(provider, identifier), !data.isEmpty {
                return (data, named(suggested, ext: ext))
            }
        }
        let convertible = [UTType.tiff.identifier, UTType.gif.identifier, UTType.bmp.identifier, UTType.image.identifier]
        for identifier in convertible where provider.hasItemConformingToTypeIdentifier(identifier) {
            if let data = await loadData(provider, identifier), !data.isEmpty {
                return (data, named(suggested, ext: "png"))
            }
        }
        return nil
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        let types = [UTType.utf8PlainText.identifier, UTType.plainText.identifier]
        for identifier in types where provider.hasItemConformingToTypeIdentifier(identifier) {
            if let text = await loadString(provider, identifier) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.rtf.identifier),
           let data = await loadData(provider, UTType.rtf.identifier),
           let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            let trimmed = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func classify(bytes: Data, filename: String, isWebloc: Bool) -> Classified {
        if bytes.count > Limits.maxAttachmentBytes { return .tooLarge }
        if isWebloc || filename.lowercased().hasSuffix(".webloc"),
           let found = WeblocParser.url(in: bytes),
           let web = httpURL(found.absoluteString) {
            return .bookmark(web)
        }
        if let sniff = sniff(bytes) {
            return .stored(StoredFile(
                filename: named(filename, ext: sniff.ext),
                mime: sniff.mime,
                bytes: bytes,
                kind: sniff.kind
            ))
        }
        if let png = pngData(from: bytes) {
            return .stored(StoredFile(
                filename: named(filename, ext: "png"),
                mime: "image/png",
                bytes: png,
                kind: .image
            ))
        }
        return .unsupported
    }

    /// Keep in step with `FileSignature.sniff` so the preview matches what the library will store.
    private static func sniff(_ data: Data) -> Sniff? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { return .pdf }
        guard data.count >= 12 else { return nil }
        let brand = Data(data[4..<12])
        if let text = String(data: brand, encoding: .ascii), text.hasPrefix("ftyp") {
            let mark = text.lowercased()
            if mark.contains("heic") || mark.contains("heif") || mark.contains("mif1") || mark.contains("heix") {
                return .heic
            }
        }
        return nil
    }

    private static func pngData(from data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]),
              !png.isEmpty else { return nil }
        return png
    }

    private static func named(_ filename: String?, ext: String) -> String {
        let raw = filename?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ns = (raw.isEmpty ? "Shared" : raw) as NSString
        let stem = ns.pathExtension.isEmpty ? ns.lastPathComponent : ns.deletingPathExtension
        let root = stem.isEmpty ? "Shared" : stem
        return "\(root).\(ext)"
    }

    private static func readFile(at url: URL) -> FileRead {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > Limits.maxAttachmentBytes {
            return .tooLarge
        }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return .unreadable }
        if data.count > Limits.maxAttachmentBytes { return .tooLarge }
        return .data(data)
    }

    private static func loadURL(_ provider: NSItemProvider, _ identifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            let box = ResumeBox<URL?>()
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                box.resume(continuation, returning: ShareItem.url(from: item))
            }
        }
    }

    private static func loadData(_ provider: NSItemProvider, _ identifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            let box = ResumeBox<Data?>()
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                box.resume(continuation, returning: data)
            }
        }
    }

    private static func loadString(_ provider: NSItemProvider, _ identifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            let box = ResumeBox<String?>()
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                box.resume(continuation, returning: ShareItem.string(from: item))
            }
        }
    }
}

private struct Collected {
    var suggestedTitle: String?
    var webs: [WebHit] = []
    var texts: [String] = []
    var files: [StoredFile] = []
    var skippedUnsupported = 0
    var skippedTooLarge = 0
}

private struct Piece {
    var webs: [WebHit] = []
    var texts: [String] = []
    var files: [StoredFile] = []
    var skippedUnsupported = 0
    var skippedTooLarge = 0
}

private struct WebHit: Equatable {
    enum Source: Equatable { case page, link, webloc }
    var url: String
    var source: Source
}

private struct StoredFile: Sendable {
    var filename: String
    var mime: String?
    var bytes: Data
    var kind: CaptureKind
}

private enum Classified {
    case bookmark(String)
    case stored(StoredFile)
    case tooLarge
    case unsupported
}

private enum FileRead {
    case data(Data)
    case tooLarge
    case unreadable
}

private enum Sniff {
    case jpeg, png, heic, pdf

    var ext: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .pdf: "pdf"
        }
    }

    var mime: String {
        switch self {
        case .jpeg: "image/jpeg"
        case .png: "image/png"
        case .heic: "image/heic"
        case .pdf: "application/pdf"
        }
    }

    var kind: CaptureKind { self == .pdf ? .pdf : .image }
}

enum ShareText {
    static func optional(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func tags(_ raw: String) -> [String] {
        raw.split { $0 == "," || $0 == ";" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum ShareStatus {
    static func summarize(_ results: [CaptureResult]) -> (text: String, allConfirmed: Bool, anyConfirmed: Bool) {
        guard !results.isEmpty else {
            return ("Not saved. Nothing was shared.", false, false)
        }
        var lines: [String] = []
        var confirmed = 0
        for result in results {
            switch result.status {
            case .saved, .alreadySaved:
                confirmed += 1
                if !lines.contains(result.message) { lines.append(result.message) }
            default:
                let message = (result.message == "Saved" || result.message == "Saved.") ? "Not saved." : result.message
                if !lines.contains(message) { lines.append(message) }
            }
        }
        let text = lines.joined(separator: "\n")
        return (text, confirmed == results.count, confirmed > 0)
    }
}

private enum ShareItem {
    static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let text = item as? String {
            return URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let text = item as? NSString {
            return URL(string: (text as String).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let data = item as? Data {
            if let url = URL(dataRepresentation: data, relativeTo: nil) { return url }
            if let text = String(data: data, encoding: .utf8) {
                return URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return nil
    }

    static func string(from item: NSSecureCoding?) -> String? {
        if let text = item as? String { return text }
        if let text = item as? NSString { return text as String }
        if let attributed = item as? NSAttributedString { return attributed.string }
        if let data = item as? Data {
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
        }
        return nil
    }
}

private final class ResumeBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ continuation: CheckedContinuation<T, Never>, returning value: T) {
        lock.lock()
        let shouldResume = !resumed
        resumed = true
        lock.unlock()
        if shouldResume {
            continuation.resume(returning: value)
        }
    }
}
