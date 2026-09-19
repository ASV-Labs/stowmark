import AppKit
import Darwin
import LibraryCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum LibraryPlace: Hashable {
    case all
    case favorites
    case trash
    case shelf(UUID)
}

enum DateWindow: String, CaseIterable, Identifiable {
    case any, week, month
    var id: String { rawValue }
    var label: String {
        switch self {
        case .any: "Any time"
        case .week: "Past 7 days"
        case .month: "Past 30 days"
        }
    }
}

enum SearchScope: String, CaseIterable, Identifiable {
    case currentPlace, allItems
    var id: String { rawValue }
}

@MainActor
@Observable
final class LibraryModel {
    private(set) var store: LibraryStore?
    private(set) var items: [SavedItem] = []
    private(set) var matchedCount = 0
    private(set) var shelves: [Shelf] = []
    private(set) var allCount = 0
    private(set) var favoriteCount = 0
    private(set) var trashCount = 0
    static let displayPageSize = 400
    var startupError: String?
    var place: LibraryPlace = .all
    var queryText = ""
    var tagFilters: [String] = []
    var kindFilters: Set<ContentKind> = []
    var domainFilter: String?
    var dateWindow: DateWindow = .any
    var scope: SearchScope = .currentPlace
    var listOrder: ResultOrder = .relevance
    var selectedItemID: UUID?
    var previewItemID: UUID?
    var viewMode: ViewMode = .cards
    var cardSize: CardSize = .medium
    var captureDraft = ""
    var captureMessage: String?
    var captureFailed = false
    var isSaving = false
    var importPlan: BookmarkImportPlan?
    var createShelvesOnImport = true
    var searchFocusToken = 0
    var captureFocusToken = 0
    var importToken = 0
    var usesSharedContainer = false
    var fetchPreviews = true
    var appearance: AppearancePref = .system
    var openPreviewOnSelect = false
    var confirmTrash = true
    var showCaptureBar = true
    var rememberLastPlace = true
    var defaultSortRaw: String = ResultOrder.recent.rawValue
    private var lastRequestID: UUID?
    private var watchSource: DispatchSourceFileSystemObject?
    private var watchFD: Int32 = -1
    private var reloadScheduled = false
    private var searchGeneration = 0

    var defaultSort: ResultOrder {
        get { ResultOrder(rawValue: defaultSortRaw) ?? .recent }
        set { defaultSortRaw = newValue.rawValue }
    }

    var isFiltering: Bool {
        !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !tagFilters.isEmpty
            || !kindFilters.isEmpty
            || domainFilter != nil
            || dateWindow != .any
    }

    var placeTitle: String {
        if isFiltering {
            return scope == .allItems ? "Searching entire library" : "Searching \(currentPlaceName)"
        }
        return currentPlaceName
    }

    var currentPlaceName: String {
        switch place {
        case .all: return "All items"
        case .favorites: return "Favorites"
        case .trash: return "Trash"
        case .shelf(let id):
            return shelves.first { $0.id == id }?.name ?? "This shelf"
        }
    }

    var scopeCurrentLabel: String {
        switch place {
        case .all: return "All items"
        case .favorites: return "Favorites"
        case .trash: return "Trash"
        case .shelf: return "This shelf"
        }
    }

    var captureDestination: String {
        if case .shelf(let id) = place, let name = shelves.first(where: { $0.id == id })?.name {
            return "Also adds to \(name)"
        }
        return "Saves to All items"
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: "viewMode") {
            switch raw {
            case ViewMode.table.rawValue, "list": viewMode = .table
            case ViewMode.covers.rawValue: viewMode = .covers
            default: viewMode = .cards
            }
        }
        if let raw = UserDefaults.standard.string(forKey: "cardSize"),
           let size = CardSize(rawValue: raw) {
            cardSize = size
        }
        if let raw = UserDefaults.standard.string(forKey: "appearance"),
           let stored = AppearancePref(rawValue: raw) {
            appearance = stored
        }
        openPreviewOnSelect = UserDefaults.standard.bool(forKey: "openPreviewOnSelect")
        if UserDefaults.standard.object(forKey: "confirmTrash") != nil {
            confirmTrash = UserDefaults.standard.bool(forKey: "confirmTrash")
        }
        if UserDefaults.standard.object(forKey: "showCaptureBar") != nil {
            showCaptureBar = UserDefaults.standard.bool(forKey: "showCaptureBar")
        }
        if UserDefaults.standard.object(forKey: "rememberLastPlace") != nil {
            rememberLastPlace = UserDefaults.standard.bool(forKey: "rememberLastPlace")
        }
        if let raw = UserDefaults.standard.string(forKey: "defaultSort"),
           let sort = ResultOrder(rawValue: raw) {
            defaultSort = sort
            listOrder = sort == .relevance ? .recent : sort
        }
        bootstrap()
    }

    func bootstrap() {
        do {
            let opened = try LibraryStore.openLive()
            store = opened
            startupError = nil
            usesSharedContainer = opened.usesSharedContainer
            fetchPreviews = try opened.boolSetting("fetch_remote_previews", default: true)
            try opened.purgeExpiredTrash()
            _ = try opened.requeueMissingPreviews()
            reload()
            watchDatabase()
            Task { await enrichPending() }
        } catch {
            store = nil
            if let libraryError = error as? LibraryError {
                startupError = libraryError.description
            } else {
                startupError = error.localizedDescription
            }
        }
    }

    func createFreshLibrary() {
        do {
            let opened = try LibraryStore.resetLiveLibrary()
            store = opened
            startupError = nil
            usesSharedContainer = false
            fetchPreviews = true
            items = []
            matchedCount = 0
            shelves = []
            allCount = 0
            favoriteCount = 0
            trashCount = 0
            watchDatabase()
            captureFailed = false
            captureMessage = "New library ready."
        } catch {
            if let libraryError = error as? LibraryError {
                startupError = libraryError.description
            } else {
                startupError = error.localizedDescription
            }
        }
    }

    func reload() {
        guard let store else { return }
        do {
            var query = currentQuery()
            matchedCount = try store.matchedCount(matching: query)
            query.limit = Self.displayPageSize
            items = try store.items(matching: query)
            shelves = try store.shelves()
            let counts = try store.counts()
            allCount = counts.all
            favoriteCount = counts.favorites
            trashCount = counts.trash
            if let selectedItemID, !items.contains(where: { $0.id == selectedItemID }) {
                self.selectedItemID = items.first?.id
            }
            if let previewItemID, try store.item(id: previewItemID) == nil {
                self.previewItemID = nil
            }
        } catch {
            captureFailed = true
            captureMessage = error.localizedDescription
        }
    }

    func scheduleSearch() {
        searchGeneration += 1
        let generation = searchGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard generation == searchGeneration else { return }
            reload()
        }
    }

    func focusSearch() { searchFocusToken += 1 }
    func focusCapture() { captureFocusToken += 1 }
    func requestImport() { importToken += 1 }

    func setViewMode(_ mode: ViewMode) {
        viewMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "viewMode")
    }

    func setCardSize(_ size: CardSize) {
        cardSize = size
        UserDefaults.standard.set(size.rawValue, forKey: "cardSize")
    }

    func toggleView() {
        let next: ViewMode
        switch viewMode {
        case .cards: next = .table
        case .table: next = .covers
        case .covers: next = .cards
        }
        setViewMode(next)
    }

    func setAppearance(_ value: AppearancePref) {
        appearance = value
        UserDefaults.standard.set(value.rawValue, forKey: "appearance")
    }

    func setOpenPreviewOnSelect(_ value: Bool) {
        openPreviewOnSelect = value
        UserDefaults.standard.set(value, forKey: "openPreviewOnSelect")
    }

    func setConfirmTrash(_ value: Bool) {
        confirmTrash = value
        UserDefaults.standard.set(value, forKey: "confirmTrash")
    }

    func setShowCaptureBar(_ value: Bool) {
        showCaptureBar = value
        UserDefaults.standard.set(value, forKey: "showCaptureBar")
    }

    func setRememberLastPlace(_ value: Bool) {
        rememberLastPlace = value
        UserDefaults.standard.set(value, forKey: "rememberLastPlace")
    }

    func setDefaultSort(_ value: ResultOrder) {
        defaultSort = value
        UserDefaults.standard.set(value.rawValue, forKey: "defaultSort")
        if !isFiltering {
            listOrder = value == .relevance ? .recent : value
            reload()
        }
    }

    func choose(_ place: LibraryPlace) {
        self.place = place
        scope = .currentPlace
        reload()
    }

    func addTagFilter(_ label: String) {
        let cleaned = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              !tagFilters.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }) else { return }
        tagFilters.append(cleaned)
        reload()
    }

    func setKindFilter(_ kind: ContentKind?) {
        if let kind {
            kindFilters = [kind]
        } else {
            kindFilters = []
        }
        reload()
    }

    func filterDomain(_ domain: String) {
        domainFilter = domain
        reload()
    }

    func clearQuery() {
        queryText = ""
        reload()
    }

    func clearFilters() {
        tagFilters = []
        kindFilters = []
        domainFilter = nil
        dateWindow = .any
        scope = .currentPlace
        reload()
    }

    func select(_ id: UUID?) {
        selectedItemID = id
    }

    func openPreview() {
        previewItemID = selectedItemID
    }

    func closePreview() {
        previewItemID = nil
    }

    func loadMore() {
        guard let store, items.count < matchedCount else { return }
        do {
            var query = currentQuery()
            query.limit = Self.displayPageSize
            query.offset = items.count
            let more = try store.items(matching: query)
            let existing = Set(items.map(\.id))
            items.append(contentsOf: more.filter { !existing.contains($0.id) })
        } catch {
            showFailure(error.localizedDescription)
        }
    }

    func setListOrder(_ order: ResultOrder) {
        listOrder = order
        reload()
    }

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedItemID } ?? 0
        let next = min(max(0, current + delta), items.count - 1)
        selectedItemID = items[next].id
    }

    func captureDraftLink() {
        let raw = Self.normalizedWebAddress(captureDraft)
        guard !raw.isEmpty else { return }
        captureLink(raw, origin: "paste", clearDraftOnSuccess: true)
    }

    func captureLink(
        _ raw: String,
        origin: String,
        capturedTitle: String? = nil,
        clearDraftOnSuccess: Bool = false,
        requestID: UUID = UUID(),
        note: String? = nil,
        tags: [String] = [],
        shelfName: String? = nil
    ) {
        guard let store else { return }
        let address = Self.normalizedWebAddress(raw)
        lastRequestID = requestID
        var assignedShelf = shelfName
        if assignedShelf == nil, case .shelf(let id) = place, place != .trash {
            assignedShelf = shelves.first { $0.id == id }?.name
        }
        let request = CaptureRequest(
            requestID: requestID,
            captureKind: .link,
            targetURL: address,
            capturedTitle: capturedTitle,
            note: note,
            tags: tags,
            shelfName: assignedShelf,
            origin: origin
        )
        runCapture(request, store: store, clearDraftOnSuccess: clearDraftOnSuccess ? captureDraft : nil)
    }

    func captureExcerpt(
        pageURL: String,
        title: String?,
        text: String,
        origin: String,
        requestID: UUID = UUID(),
        note: String? = nil,
        tags: [String] = [],
        shelfName: String? = nil
    ) {
        guard let store else { return }
        let request = CaptureRequest(
            requestID: requestID,
            captureKind: .selection,
            pageURL: Self.normalizedWebAddress(pageURL),
            capturedTitle: title,
            selectionText: text,
            note: note,
            tags: tags,
            shelfName: shelfName,
            origin: origin
        )
        runCapture(request, store: store)
    }

    func captureFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let files = urls.filter { $0.isFileURL }
            if !files.isEmpty {
                importDropped(files)
                return
            }
            if let web = urls.first(where: { $0.scheme == "http" || $0.scheme == "https" }) {
                captureLink(web.absoluteString, origin: "clipboard")
                return
            }
        }
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            captureImageData(png, filename: "Clipboard.png", origin: "clipboard")
            return
        }
        if let raw = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string) {
            let first = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
            let address = Self.normalizedWebAddress(first)
            if address.lowercased().hasPrefix("http://") || address.lowercased().hasPrefix("https://") {
                captureLink(address, origin: "clipboard")
                return
            }
        }
        showFailure("Clipboard does not have a web link or image to save.")
        focusCapture()
    }

    func openSafariExtensionSettings() {
        SafariSupport.openExtensionPreferences()
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "mymind" else { return }
        let host = url.host?.lowercased() ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        if host == "open" || host.isEmpty {
            return
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let page = value("url") ?? value("page")
        let title = value("title")
        let text = value("text") ?? value("selection")
        let note = value("note")
        let shelf = value("shelf")
        let tags = (value("tags") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let requestID = value("requestId").flatMap(UUID.init(uuidString:)) ?? UUID()
        guard let page, !page.isEmpty else { return }
        if let text, !text.isEmpty {
            captureExcerpt(pageURL: page, title: title, text: text, origin: "safari", requestID: requestID, note: note, tags: tags, shelfName: shelf)
        } else {
            captureLink(page, origin: "safari", capturedTitle: title, requestID: requestID, note: note, tags: tags, shelfName: shelf)
        }
    }

    func importDropped(_ urls: [URL]) {
        for url in urls {
            importFile(url)
        }
    }

    func importFile(_ url: URL) {
        guard let store else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        if ext == "html" || ext == "htm" {
            guard let data = try? Data(contentsOf: url) else {
                showFailure("Not saved. That bookmark file could not be read.")
                return
            }
            do {
                importPlan = try store.planBookmarkImport(data)
            } catch {
                showFailure(error.localizedDescription)
            }
            return
        }
        if ext == "webloc", let data = try? Data(contentsOf: url), let link = WeblocParser.url(in: data) {
            captureLink(link.absoluteString, origin: "webloc")
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            showFailure("Not saved. That file could not be read.")
            return
        }
        let kind: CaptureKind = ext == "pdf" || FileSignaturePeek.isPDF(data) ? .pdf : .image
        let request = CaptureRequest(
            captureKind: kind,
            capturedTitle: url.deletingPathExtension().lastPathComponent,
            origin: "drop",
            file: CaptureFile(filename: url.lastPathComponent, declaredMIME: nil, bytes: data)
        )
        runCapture(request, store: store)
    }

    func captureImageData(_ data: Data, filename: String, origin: String) {
        guard let store else { return }
        let request = CaptureRequest(
            captureKind: .image,
            capturedTitle: filename,
            origin: origin,
            file: CaptureFile(filename: filename, declaredMIME: "image/png", bytes: data)
        )
        runCapture(request, store: store)
    }

    func commitImport() {
        guard let store, let plan = importPlan else { return }
        do {
            let result = try store.commitBookmarkImport(plan, createShelves: createShelvesOnImport)
            importPlan = nil
            captureFailed = result.failed > 0 && result.saved == 0
            captureMessage = "Imported \(result.saved). Skipped \(result.skipped). Failed \(result.failed)."
            reload()
            Task { await enrichPending() }
        } catch {
            showFailure(error.localizedDescription)
        }
    }

    func openOriginal(_ item: SavedItem) {
        if let asset = item.originalAsset {
            NSWorkspace.shared.open(asset.fileURL(in: store?.rootURL ?? URL(fileURLWithPath: "/")))
            return
        }
        guard let raw = item.originalURL, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    func openSelected() {
        guard let id = selectedItemID ?? previewItemID, let item = items.first(where: { $0.id == id }) ?? (try? store?.item(id: id)) else { return }
        openOriginal(item)
    }

    func trashSelected() {
        guard let id = selectedItemID ?? previewItemID else { return }
        trashItem(id)
    }

    func trashItem(_ id: UUID) {
        guard let store else { return }
        if confirmTrash {
            let alert = NSAlert()
            alert.messageText = "Move to Trash?"
            alert.informativeText = "You can restore it from Trash for \(Limits.trashDays) days."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            try store.trash(itemID: id)
        } catch {
            showFailure(error.localizedDescription)
            return
        }
        if selectedItemID == id { selectedItemID = nil }
        if previewItemID == id { previewItemID = nil }
        reload()
    }

    func restoreSelected() {
        guard let store, let id = selectedItemID ?? previewItemID else { return }
        do {
            try store.restoreItem(itemID: id)
        } catch {
            showFailure(error.localizedDescription)
            return
        }
        reload()
    }

    func toggleFavorite(_ id: UUID) {
        guard let store, let item = try? store.item(id: id) else { return }
        try? store.setFavorite(itemID: id, favorite: !item.favorite)
        reload()
    }

    func saveTitle(_ id: UUID, _ title: String) {
        try? store?.updateTitle(itemID: id, title: title)
        reload()
    }

    func saveNote(_ id: UUID, _ note: String) {
        try? store?.updateNote(itemID: id, note: note)
        reload()
    }

    func saveKind(_ id: UUID, _ kind: ContentKind) {
        try? store?.updateKind(itemID: id, kind: kind)
        reload()
    }

    func addTag(_ id: UUID, _ label: String) {
        try? store?.addTag(itemID: id, label: label)
        reload()
    }

    func removeTag(_ id: UUID, _ tagID: UUID) {
        try? store?.removeTag(itemID: id, tagID: tagID)
        reload()
    }

    func confirmTag(_ id: UUID, _ tagID: UUID) {
        try? store?.confirmTag(itemID: id, tagID: tagID)
        reload()
    }

    func createShelf(name: String) {
        guard let shelf = try? store?.createShelf(name: name) else { return }
        place = .shelf(shelf.id)
        reload()
    }

    func setMembership(_ itemID: UUID, _ shelfID: UUID, _ member: Bool) {
        try? store?.setMembership(itemID: itemID, shelfID: shelfID, member: member)
        reload()
    }

    func deleteShelf(_ id: UUID) {
        try? store?.deleteShelf(id: id)
        if case .shelf(let current) = place, current == id { place = .all }
        reload()
    }

    func setFetchPreviews(_ enabled: Bool) {
        fetchPreviews = enabled
        try? store?.setBoolSetting("fetch_remote_previews", enabled)
    }

    func clearCache() {
        _ = try? store?.clearPreviewCache()
        reload()
    }

    func emptyTrash() {
        try? store?.emptyTrash()
        if place == .trash { selectedItemID = nil; previewItemID = nil }
        reload()
    }

    func exportArchive(to url: URL) throws {
        _ = try store?.exportArchive(to: url)
    }

    func restoreArchive(from url: URL, replace: Bool) throws {
        _ = try store?.restoreArchive(from: url, mode: replace ? .replace : .requireEmpty)
        reload()
    }

    func undoLastCapture() {
        guard let store, let lastRequestID else { return }
        if let result = try? store.undoCapture(requestID: lastRequestID) {
            captureFailed = false
            captureMessage = result.message
            reload()
        }
    }

    func refreshPreview(_ id: UUID) {
        try? store?.refreshPreview(itemID: id)
        reload()
        Task { await enrichPending() }
    }

    func enrichPending() async {
        guard let store else { return }
        let images = (try? store.boolSetting("fetch_remote_previews", default: true)) ?? true
        var processed = 0
        while processed < 24 {
            let jobs = (try? store.pendingEnrichmentJobs()) ?? []
            if jobs.isEmpty { break }
        for job in jobs {
            guard let item = try? store.item(id: job.itemID),
                  let raw = item.originalURL,
                  let url = URL(string: raw) else {
                try? store.failEnrichment(jobID: job.id, errorClass: "missing")
                continue
            }
            if !images {
                try? store.completeEnrichment(
                    itemID: item.id,
                    metadata: PageMetadata(title: nil, description: nil, author: nil, imageURL: nil, openGraphType: nil),
                    preview: nil,
                    previewFailed: true
                )
                continue
            }
            let blocked = URLSafety.isBlockedFetchTarget(url)
            if blocked {
                try? store.completeEnrichment(itemID: item.id, metadata: PageMetadata(title: nil, description: nil, author: nil, imageURL: nil, openGraphType: nil), preview: nil, previewFailed: true)
                continue
            }
            do {
                let preview = await SitePreview.fetch(url: url)
                let failed = preview.image == nil && preview.metadata.title == nil && preview.metadata.description == nil
                try store.completeEnrichment(
                    itemID: item.id,
                    metadata: preview.metadata,
                    preview: preview.image,
                    previewFailed: failed
                )
            } catch {
                try? store.failEnrichment(jobID: job.id, errorClass: "network")
            }
            }
            processed += jobs.count
        }
        reload()
    }

    static func normalizedWebAddress(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        if trimmed.contains(" ") || trimmed.contains("\n") || trimmed.isEmpty {
            return trimmed
        }
        if trimmed.contains("."), !trimmed.contains("/") || trimmed.contains(".") {
            let host = trimmed.split(separator: "/").first.map(String.init) ?? trimmed
            if host.contains(".") {
                return "https://\(trimmed)"
            }
        }
        return trimmed
    }

    static let safariPageBookmarklet =
        "javascript:void(location.href='mymind://save?url='+encodeURIComponent(location.href)+'&title='+encodeURIComponent(document.title))"

    static let safariExcerptBookmarklet =
        "javascript:void(location.href='mymind://save?url='+encodeURIComponent(location.href)+'&title='+encodeURIComponent(document.title)+'&text='+encodeURIComponent(window.getSelection().toString()))"

    private func runCapture(_ request: CaptureRequest, store: LibraryStore, clearDraftOnSuccess: String? = nil) {
        isSaving = true
        captureMessage = "Saving…"
        captureFailed = false
        lastRequestID = request.requestID
        let result: CaptureResult
        do {
            result = try store.capture(request)
        } catch {
            isSaving = false
            showFailure(error.localizedDescription)
            CaptureHandshake.write(.failed(error.localizedDescription), requestID: request.requestID)
            return
        }
        isSaving = false
        captureFailed = result.status == .failed
        captureMessage = result.message
        CaptureHandshake.write(result, requestID: request.requestID)
        if result.status != .failed, let clearDraftOnSuccess {
            if captureDraft.trimmingCharacters(in: .whitespacesAndNewlines) == clearDraftOnSuccess.trimmingCharacters(in: .whitespacesAndNewlines) {
                captureDraft = ""
            }
        }
        if let id = result.itemID {
            selectedItemID = id
            if place == .trash { place = .all }
        }
        reload()
        if result.status == .saved {
            Task { await enrichPending() }
        }
    }

    private func showFailure(_ message: String) {
        captureFailed = true
        captureMessage = message
    }

    private func currentQuery() -> LibraryQuery {
        var query = LibraryQuery()
        query.text = queryText
        query.tagNames = tagFilters
        query.kinds = Array(kindFilters)
        query.domain = domainFilter
        switch dateWindow {
        case .any: break
        case .week: query.createdAfter = Date().addingTimeInterval(-7 * 86_400)
        case .month: query.createdAfter = Date().addingTimeInterval(-30 * 86_400)
        }
        switch listOrder {
        case .title, .source, .kind, .tags, .kept, .recent:
            query.order = listOrder
        case .relevance:
            query.order = isFiltering ? .relevance : (defaultSort == .title || defaultSort == .source ? defaultSort : .recent)
        }
        let constrainToPlace = !isFiltering || scope == .currentPlace
        if constrainToPlace {
            switch place {
            case .all: break
            case .favorites: query.favoritesOnly = true
            case .trash:
                query.trashedOnly = true
                query.includeTrashed = true
            case .shelf(let id): query.shelfID = id
            }
        }
        return query
    }

    private func watchDatabase() {
        watchSource?.cancel()
        watchSource = nil
        if watchFD >= 0 {
            close(watchFD)
            watchFD = -1
        }
        guard let store else { return }
        watchFD = open(store.databaseURL.path, O_EVTONLY)
        guard watchFD >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: watchFD, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if self.reloadScheduled { return }
            self.reloadScheduled = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                self.reloadScheduled = false
                self.reload()
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.watchFD, fd >= 0 {
                close(fd)
                self?.watchFD = -1
            }
        }
        source.resume()
        watchSource = source
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case cards, table, covers
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cards: "Cards"
        case .table: "Rows & Columns"
        case .covers: "Covers"
        }
    }
    var symbol: String {
        switch self {
        case .cards: "rectangle.grid.2x2"
        case .table: "list.bullet.rectangle"
        case .covers: "square.grid.3x3"
        }
    }
    var blurb: String {
        switch self {
        case .cards: "Equal cards in a grid — the default visual library"
        case .table: "dense rows for scanning titles, sources, and kinds"
        case .covers: "equal preview tiles for fast visual recognition"
        }
    }
}

enum CardSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var label: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }
    var cardHeight: CGFloat {
        switch self {
        case .small: 252
        case .medium: 300
        case .large: 348
        }
    }
    var previewHeight: CGFloat {
        switch self {
        case .small: 108
        case .medium: 132
        case .large: 160
        }
    }
    var cardMinWidth: CGFloat {
        switch self {
        case .small: 180
        case .medium: 220
        case .large: 260
        }
    }
    var coverSize: CGFloat {
        switch self {
        case .small: 110
        case .medium: 140
        case .large: 180
        }
    }
}

enum AppearancePref: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

enum FileSignaturePeek {
    static func isPDF(_ data: Data) -> Bool {
        data.starts(with: [0x25, 0x50, 0x44, 0x46])
    }
}
