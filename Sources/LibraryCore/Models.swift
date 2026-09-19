import Foundation

public enum ContentKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case article, image, research, book, social, excerpt, document, link
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .article: "Article"
        case .image: "Image"
        case .research: "Research"
        case .book: "Book"
        case .social: "Social post"
        case .excerpt: "Excerpt"
        case .document: "Document"
        case .link: "Link"
        }
    }
}

public enum RetentionState: String, Codable, Sendable {
    case bookmark
    case copiedImage
    case copiedPDF
    case savedExcerpt

    public var label: String {
        switch self {
        case .bookmark: "Bookmark"
        case .copiedImage: "Image copied"
        case .copiedPDF: "PDF copied"
        case .savedExcerpt: "Excerpt saved"
        }
    }
}

public enum PreviewState: String, Codable, Sendable {
    case pending, ready, unavailable, none
}

public enum FieldOrigin: String, Codable, Sendable {
    case captured, user, publisher, metadata
}

public enum CaptureKind: String, Codable, Sendable {
    case page, link, selection, image, pdf
}

public enum CaptureStatus: String, Codable, Sendable {
    case saved
    case alreadySaved = "already_saved"
    case failed
    case undone
    case pending
}

public struct ItemTag: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var label: String
    public var normalized: String
    public var status: String
    public var origin: String
    public var isSuggestion: Bool { status == "suggested" }
}

public struct Shelf: Identifiable, Sendable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var sortOrder: Int
    public var itemCount: Int
}

public struct AssetRecord: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var role: String
    public var relativePath: String
    public var mimeType: String?
    public var byteCount: Int
    public var sha256: String

    public func fileURL(in root: URL) -> URL {
        root.appendingPathComponent(relativePath, isDirectory: false)
    }
}

public struct SavedItem: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var kind: ContentKind
    public var kindOrigin: FieldOrigin
    public var retention: RetentionState
    public var originalURL: String?
    public var title: String
    public var titleOrigin: FieldOrigin
    public var summary: String?
    public var summaryOrigin: FieldOrigin?
    public var note: String?
    public var author: String?
    public var filename: String?
    public var sourceDomain: String?
    public var favorite: Bool
    public var previewState: PreviewState
    public var trashedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: [ItemTag]
    public var shelves: [Shelf]
    public var assets: [AssetRecord]

    public var confirmedTags: [ItemTag] { tags.filter { $0.status == "confirmed" } }
    public var suggestedTags: [ItemTag] { tags.filter { $0.status == "suggested" } }

    public var originalAsset: AssetRecord? { assets.first { $0.role == "original" } }
    public var previewAsset: AssetRecord? { assets.first { $0.role == "preview" } }

    public var sourceLabel: String {
        if let sourceDomain, !sourceDomain.isEmpty { return sourceDomain }
        if let filename, !filename.isEmpty { return filename }
        return "On this Mac"
    }

    /// The line under the title. A description wins, so editing preview text changes the card. A note fills in only when there is no description.
    public var cardContext: String? {
        if let summary, !summary.isEmpty { return summary }
        if let note, !note.isEmpty { return note }
        return nil
    }

    public var contextIsNote: Bool {
        if let summary, !summary.isEmpty { return false }
        if let note, !note.isEmpty { return true }
        return false
    }

    /// True when the card preview zone has nothing to show as a picture.
    public var lacksPreviewPhoto: Bool {
        switch kind {
        case .image, .book:
            return originalAsset == nil && previewAsset == nil
        default:
            return previewAsset == nil
        }
    }

    public var tagsLabel: String {
        confirmedTags.map(\.label).joined(separator: ", ")
    }

    public var keptLabel: String {
        if kind == .book && retention == .bookmark { return "Book link" }
        return retention.label
    }

    public var kindLabel: String { kind.label }
}

public struct CaptureFile: Sendable {
    public var filename: String
    public var declaredMIME: String?
    public var bytes: Data
    public init(filename: String, declaredMIME: String?, bytes: Data) {
        self.filename = filename
        self.declaredMIME = declaredMIME
        self.bytes = bytes
    }
}

public struct CapturePayload: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var requestID: String
    public var captureKind: String
    public var pageURL: String?
    public var targetURL: String?
    public var capturedTitle: String?
    public var selectionText: String?
    public var note: String?
    public var tags: [String]
    public var shelfName: String?
    public var origin: String

    public init(_ request: CaptureRequest) {
        schemaVersion = request.schemaVersion
        requestID = request.requestID.uuidString
        captureKind = request.captureKind.rawValue
        pageURL = request.pageURL
        targetURL = request.targetURL
        capturedTitle = request.capturedTitle
        selectionText = request.selectionText
        note = request.note
        tags = request.tags
        shelfName = request.shelfName
        origin = request.origin
    }

    public func request() -> CaptureRequest? {
        guard let id = UUID(uuidString: requestID), let kind = CaptureKind(rawValue: captureKind) else { return nil }
        return CaptureRequest(
            schemaVersion: schemaVersion,
            requestID: id,
            captureKind: kind,
            pageURL: pageURL,
            targetURL: targetURL,
            capturedTitle: capturedTitle,
            selectionText: selectionText,
            note: note,
            tags: tags,
            shelfName: shelfName,
            origin: origin
        )
    }

    public static func decode(_ json: String) -> CaptureRequest? {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(CapturePayload.self, from: data) else { return nil }
        return payload.request()
    }
}

public struct CaptureRequest: Sendable {
    public var schemaVersion: Int
    public var requestID: UUID
    public var captureKind: CaptureKind
    public var pageURL: String?
    public var targetURL: String?
    public var capturedTitle: String?
    public var selectionText: String?
    public var note: String?
    public var tags: [String]
    public var shelfName: String?
    public var origin: String
    public var file: CaptureFile?

    public init(
        schemaVersion: Int = 1,
        requestID: UUID = UUID(),
        captureKind: CaptureKind,
        pageURL: String? = nil,
        targetURL: String? = nil,
        capturedTitle: String? = nil,
        selectionText: String? = nil,
        note: String? = nil,
        tags: [String] = [],
        shelfName: String? = nil,
        origin: String,
        file: CaptureFile? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.captureKind = captureKind
        self.pageURL = pageURL
        self.targetURL = targetURL
        self.capturedTitle = capturedTitle
        self.selectionText = selectionText
        self.note = note
        self.tags = tags
        self.shelfName = shelfName
        self.origin = origin
        self.file = file
    }
}

public struct CaptureResult: Sendable, Equatable {
    public var status: CaptureStatus
    public var itemID: UUID?
    public var retention: RetentionState?
    public var warnings: [String]
    public var message: String

    public static func failed(_ message: String) -> CaptureResult {
        CaptureResult(status: .failed, itemID: nil, retention: nil, warnings: [], message: message)
    }
}

public struct LibraryQuery: Sendable {
    public var text: String = ""
    public var kinds: [ContentKind] = []
    public var tagNames: [String] = []
    public var shelfID: UUID?
    public var favoritesOnly: Bool = false
    public var domain: String?
    public var createdAfter: Date?
    public var includeTrashed: Bool = false
    public var trashedOnly: Bool = false
    public var order: ResultOrder = .recent
    public var limit: Int? = nil
    public var offset: Int? = nil

    public init() {}
}

public enum ResultOrder: String, Sendable, Hashable {
    case recent, relevance, title, source, kind, tags, kept
}

public struct EnrichmentJob: Sendable, Equatable {
    public var id: UUID
    public var itemID: UUID
    public var attempts: Int
}

public struct PageMetadata: Sendable, Equatable {
    public var title: String?
    public var description: String?
    public var author: String?
    public var imageURL: URL?
    public var openGraphType: String?

    public init(title: String?, description: String?, author: String?, imageURL: URL?, openGraphType: String?) {
        self.title = title
        self.description = description
        self.author = author
        self.imageURL = imageURL
        self.openGraphType = openGraphType
    }
}

public struct StorageUsage: Sendable, Equatable {
    public var originalBytes: Int
    public var previewBytes: Int
    public var itemCount: Int
}

public struct BookmarkEntry: Sendable, Equatable, Identifiable {
    public var id: String { url + "|" + (folder ?? "") }
    public var url: String
    public var title: String
    public var folder: String?
    public var disposition: BookmarkDisposition
}

public enum BookmarkDisposition: String, Sendable {
    case ready, duplicate, unsupported
}

public struct BookmarkImportPlan: Sendable, Equatable {
    public var entries: [BookmarkEntry]
    public var folders: [String]
    public var readyCount: Int
    public var duplicateCount: Int
    public var unsupportedCount: Int
}

public struct ArchiveSummary: Sendable, Equatable {
    public var itemCount: Int
    public var assetCount: Int
}

public enum RestoreMode: Sendable {
    case requireEmpty
    case replace
}

public enum LibraryError: Error, LocalizedError, CustomStringConvertible, Equatable {
    case database(String)
    case unsafeURL(String)
    case tooLarge(String)
    case invalidFile(String)
    case notFound
    case archive(String)
    case libraryNotEmpty
    case unsupportedSchema
    case migration(String)

    public var description: String {
        switch self {
        case .database(let detail): "The library database hit a problem: \(detail)"
        case .unsafeURL(let detail): detail
        case .tooLarge(let detail): detail
        case .invalidFile(let detail): detail
        case .notFound: "That item is no longer in the library."
        case .archive(let detail): detail
        case .libraryNotEmpty: "This library already has items. Restore only replaces it when you confirm that choice."
        case .unsupportedSchema: "This archive was written by a newer version of My Mind."
        case .migration(let detail): detail
        }
    }

    public var errorDescription: String? { description }
}

public enum Limits {
    public static let maxAttachmentBytes = 100 * 1024 * 1024
    public static let maxPreviewBytes = 20 * 1024 * 1024
    public static let maxExcerptCharacters = 50_000
    public static let maxTitleCharacters = 10_000
    public static let trashDays = 30
}

public enum StorageLocator {
    public static let appGroupID = "group.com.charlesbonetti.mymind"

    /// Sandboxed Application Support — primary library home for the Mac app.
    public static func appSupportRoot() throws -> URL {
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyMind", isDirectory: true)
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    /// Shared container for a future Safari extension. May be unavailable under Developer ID
    /// until the App Group is fully provisioned — never require it to launch.
    public static func sharedRoot() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    public static func appRoot() throws -> URL {
        try appSupportRoot()
    }

    public static func isWritableDirectory(_ url: URL) -> Bool {
        let probe = url.appendingPathComponent(".mymind-write-probe-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("ok".utf8).write(to: probe, options: .atomic)
            try FileManager.default.removeItem(at: probe)
            return true
        } catch {
            try? FileManager.default.removeItem(at: probe)
            return false
        }
    }

    public static func copyLibrary(from source: URL, to destination: URL) throws {
        try LibraryReplica.replicate(from: source, to: destination)
    }

    public static func divergedMarker(in root: URL) -> URL {
        root.appendingPathComponent(".mymind-diverged")
    }

    public static func handoffDirectory(in root: URL) -> URL {
        root.appendingPathComponent("handoff", isDirectory: true)
    }
}

public enum LibraryReplica {
    public static func hasDatabase(at root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("library.sqlite").path)
    }

    public static func itemCount(at root: URL) -> Int? {
        let path = root.appendingPathComponent("library.sqlite").path
        guard FileManager.default.fileExists(atPath: path), let db = try? SQLDatabase(path: path) else { return nil }
        return try? db.query("SELECT COUNT(*) AS n FROM items").first?.int("n")
    }

    public static func fingerprint(at root: URL) -> String? {
        let path = root.appendingPathComponent("library.sqlite").path
        guard FileManager.default.fileExists(atPath: path), let db = try? SQLDatabase(path: path) else { return nil }
        let count = (try? db.query("SELECT COUNT(*) AS n FROM items").first?.int("n")) ?? 0
        let latest = (try? db.query("SELECT MAX(updated_at) AS t FROM items").first?.string("t")) ?? ""
        let firstID = (try? db.query("SELECT id FROM items ORDER BY created_at ASC, id ASC LIMIT 1").first?.string("id")) ?? ""
        return "\(count)|\(latest)|\(firstID)"
    }

    public static func looksEmpty(at root: URL) -> Bool {
        guard hasDatabase(at: root) else { return true }
        return (itemCount(at: root) ?? 0) == 0
    }

    /// Snapshot `from` into `to` with SQLite backup + asset copy. Never deletes `from`.
    /// Refuses to overwrite a destination that already has items unless `replacingExisting` is set,
    /// in which case the destination is backed up and restored if verification fails.
    public static func replicate(from source: URL, to destination: URL, replacingExisting: Bool = false) throws {
        let fm = FileManager.default
        guard hasDatabase(at: source) else {
            throw LibraryError.migration("There is no library to copy.")
        }
        if hasDatabase(at: destination), !looksEmpty(at: destination), !replacingExisting {
            throw LibraryError.migration("The other library already has items, so it was left untouched.")
        }

        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent("mymind-replica-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var backupRoot: URL?
        do {
            let sourceDB = try SQLDatabase(path: source.appendingPathComponent("library.sqlite").path)
            let snapshot = staging.appendingPathComponent("library.sqlite")
            try sourceDB.backup(to: snapshot.path)
            for name in ["assets", "staging"] {
                let src = source.appendingPathComponent(name)
                let dst = staging.appendingPathComponent(name)
                guard fm.fileExists(atPath: src.path) else { continue }
                try fm.copyItem(at: src, to: dst)
            }
            try verify(source: source, replica: staging)

            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            if hasDatabase(at: destination) || fm.fileExists(atPath: destination.appendingPathComponent("assets").path) {
                let stamped = destination.deletingLastPathComponent()
                    .appendingPathComponent("MyMind-backup-\(ISO8601DateFormatter().string(from: Date()))", isDirectory: true)
                try fm.copyItem(at: destination, to: stamped)
                backupRoot = stamped
            }
            for name in ["library.sqlite", "library.sqlite-wal", "library.sqlite-shm", "assets", "staging"] {
                let dst = destination.appendingPathComponent(name)
                if fm.fileExists(atPath: dst.path) {
                    try fm.removeItem(at: dst)
                }
            }
            for name in ["library.sqlite", "assets", "staging"] {
                let src = staging.appendingPathComponent(name)
                guard fm.fileExists(atPath: src.path) else { continue }
                try fm.copyItem(at: src, to: destination.appendingPathComponent(name))
            }
            try verify(source: source, replica: destination)
            try? fm.removeItem(at: staging)
        } catch {
            try? fm.removeItem(at: staging)
            if let backupRoot {
                restore(from: backupRoot, to: destination)
            }
            throw error
        }
    }

    private static func verify(source: URL, replica: URL) throws {
        guard let sourceCount = itemCount(at: source), let replicaCount = itemCount(at: replica), sourceCount == replicaCount else {
            throw LibraryError.migration("The copied library did not match the original item count.")
        }
        let originals = source.appendingPathComponent("assets/originals", isDirectory: true)
        let replicaOriginals = replica.appendingPathComponent("assets/originals", isDirectory: true)
        guard FileManager.default.fileExists(atPath: originals.path) else { return }
        guard let enumerator = FileManager.default.enumerator(at: originals, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        let basePath = originals.standardizedFileURL.path
        while let url = enumerator.nextObject() as? URL {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isFile else { continue }
            let full = url.standardizedFileURL.path
            let relative = full.hasPrefix(basePath)
                ? String(full.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : url.lastPathComponent
            let copy = replicaOriginals.appendingPathComponent(relative)
            if !FileManager.default.fileExists(atPath: copy.path) {
                throw LibraryError.migration("A copied original file is missing after the library snapshot.")
            }
        }
    }

    private static func restore(from backup: URL, to destination: URL) {
        let fm = FileManager.default
        for name in ["library.sqlite", "library.sqlite-wal", "library.sqlite-shm", "assets", "staging"] {
            let dst = destination.appendingPathComponent(name)
            try? fm.removeItem(at: dst)
            let src = backup.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }
    }
}

public enum CaptureHandshake {
    public struct Record: Codable, Sendable, Equatable {
        public var requestID: String
        public var status: String
        public var message: String
        public var itemID: String?
        public var retention: String?
    }

    public static func write(_ result: CaptureResult, requestID: UUID, roots: [URL]? = nil) {
        let record = Record(
            requestID: requestID.uuidString,
            status: result.status.rawValue,
            message: result.message,
            itemID: result.itemID?.uuidString,
            retention: result.retention?.rawValue
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        let targets = roots ?? defaultRoots()
        for root in targets {
            let folder = StorageLocator.handoffDirectory(in: root)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("\(requestID.uuidString).json")
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func read(requestID: UUID, roots: [URL]? = nil) -> CaptureResult? {
        let targets = roots ?? defaultRoots()
        for root in targets {
            let url = StorageLocator.handoffDirectory(in: root).appendingPathComponent("\(requestID.uuidString).json")
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(Record.self, from: data),
                  let status = CaptureStatus(rawValue: record.status) else { continue }
            return CaptureResult(
                status: status,
                itemID: record.itemID.flatMap(UUID.init(uuidString:)),
                retention: record.retention.flatMap(RetentionState.init(rawValue:)),
                warnings: [],
                message: record.message
            )
        }
        return nil
    }

    public static func pending(requestID: UUID, message: String = "Waiting for My Mind to finish saving.") -> CaptureResult {
        CaptureResult(status: .pending, itemID: nil, retention: nil, warnings: [], message: message)
    }

    private static func defaultRoots() -> [URL] {
        var roots: [URL] = []
        if let shared = StorageLocator.sharedRoot() { roots.append(shared) }
        if let support = try? StorageLocator.appSupportRoot() { roots.append(support) }
        return roots
    }
}
