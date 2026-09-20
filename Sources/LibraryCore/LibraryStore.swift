import CryptoKit
import Foundation

public struct TagCount: Sendable, Equatable, Hashable, Identifiable {
    public var label: String
    public var count: Int
    public var id: String { label }

    public init(label: String, count: Int) {
        self.label = label
        self.count = count
    }
}

public final class LibraryStore: @unchecked Sendable {
    public let rootURL: URL
    public let databaseURL: URL
    public let usesSharedContainer: Bool
    let db: SQLDatabase
    let lock = NSLock()
    let iso: ISO8601DateFormatter
    var savepointDepth = 0

    public init(root: URL, usesSharedContainer: Bool = false) throws {
        self.rootURL = root
        self.usesSharedContainer = usesSharedContainer
        databaseURL = root.appendingPathComponent("library.sqlite")
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root.appendingPathComponent("assets/originals"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appendingPathComponent("assets/previews"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appendingPathComponent("staging"), withIntermediateDirectories: true)
        db = try SQLDatabase(path: databaseURL.path)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso = formatter
        try migrate()
        try applyCapturedClassification()
        try sweepUnreferencedAssets()
    }

    public static func openLive() throws -> LibraryStore {
        if let override = ProcessInfo.processInfo.environment["MYMIND_ROOT"], !override.isEmpty {
            let root = URL(fileURLWithPath: override, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return try LibraryStore(root: root, usesSharedContainer: false)
        }

        let support = try StorageLocator.appSupportRoot()
        let shared = usableSharedRoot()
        let supportHasDB = LibraryReplica.hasDatabase(at: support)
        let sharedHasDB = shared.map { LibraryReplica.hasDatabase(at: $0) } ?? false

        if supportHasDB, let shared, LibraryReplica.looksEmpty(at: shared) {
            do {
                try LibraryReplica.replicate(from: support, to: shared)
                try? FileManager.default.removeItem(at: StorageLocator.divergedMarker(in: shared))
            } catch {
                // Keep using Application Support; Safari will hand off until a replica exists.
            }
        } else if !supportHasDB, let shared, sharedHasDB {
            do {
                try LibraryReplica.replicate(from: shared, to: support)
            } catch {
                if let opened = try? LibraryStore(root: shared, usesSharedContainer: true) {
                    return opened
                }
            }
        }

        if let shared, LibraryReplica.hasDatabase(at: shared), LibraryReplica.hasDatabase(at: support) {
            let supportPrint = LibraryReplica.fingerprint(at: support)
            let sharedPrint = LibraryReplica.fingerprint(at: shared)
            if let supportPrint, supportPrint == sharedPrint {
                try? FileManager.default.removeItem(at: StorageLocator.divergedMarker(in: shared))
                if let opened = try? LibraryStore(root: shared, usesSharedContainer: true) {
                    return opened
                }
            } else if !LibraryReplica.looksEmpty(at: shared) {
                var absorbed = false
                do {
                    let source = try LibraryStore(root: shared)
                    let destination = try LibraryStore(root: support)
                    _ = try destination.absorbPayloads(from: source)
                    absorbed = true
                } catch {
                    absorbed = false
                }
                if absorbed {
                    do {
                        try LibraryReplica.replicate(from: support, to: shared, replacingExisting: true)
                        try? FileManager.default.removeItem(at: StorageLocator.divergedMarker(in: shared))
                    } catch {
                        try? Data("diverged".utf8).write(to: StorageLocator.divergedMarker(in: shared), options: .atomic)
                    }
                } else {
                    try? Data("diverged".utf8).write(to: StorageLocator.divergedMarker(in: shared), options: .atomic)
                }
            }
        }

        return try LibraryStore(root: support, usesSharedContainer: false)
    }

    public static func openForExtension() throws -> LibraryStore {
        if let override = ProcessInfo.processInfo.environment["MYMIND_ROOT"], !override.isEmpty {
            let root = URL(fileURLWithPath: override, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return try LibraryStore(root: root, usesSharedContainer: false)
        }
        guard let shared = usableSharedRoot() else {
            throw LibraryError.migration("The browser cannot see the shared library on this Mac.")
        }
        if FileManager.default.fileExists(atPath: StorageLocator.divergedMarker(in: shared).path) {
            throw LibraryError.migration("The Mac app and Safari libraries differ. Open Cardfile to finish this save.")
        }
        guard LibraryReplica.hasDatabase(at: shared) else {
            throw LibraryError.migration("The shared library is not ready yet.")
        }
        return try LibraryStore(root: shared, usesSharedContainer: true)
    }

    /// Walks the same steps as `openForExtension` and reports where it stops. Support only.
    public static func extensionOpenDiagnosis() -> [String] {
        var lines: [String] = []
        guard let shared = StorageLocator.sharedRoot() else {
            lines.append("shared container: unavailable")
            return lines
        }
        lines.append("shared container: \(shared.path)")
        lines.append("writable: \(StorageLocator.isWritableDirectory(shared))")
        lines.append("looks like test fixture: \(looksLikeTestFixture(root: shared))")
        lines.append("diverged marker: \(FileManager.default.fileExists(atPath: StorageLocator.divergedMarker(in: shared).path))")
        lines.append("has database: \(LibraryReplica.hasDatabase(at: shared))")
        do {
            let store = try LibraryStore(root: shared, usesSharedContainer: true)
            lines.append("open: succeeded with \((try? store.counts().all).map(String.init) ?? "unknown") items")
        } catch {
            lines.append("open: failed with \(error)")
        }
        return lines
    }

    private static func usableSharedRoot() -> URL? {
        guard let shared = StorageLocator.sharedRoot(), StorageLocator.isWritableDirectory(shared) else { return nil }
        if looksLikeTestFixture(root: shared) { return nil }
        return shared
    }

    static func looksLikeTestFixture(root: URL) -> Bool {
        let path = root.appendingPathComponent("library.sqlite").path
        guard FileManager.default.fileExists(atPath: path), let db = try? SQLDatabase(path: path) else { return false }
        let seeds = (try? db.query("SELECT COUNT(*) AS n FROM items WHERE title LIKE 'Live seed %'").first?.int("n")) ?? 0
        return seeds >= 50
    }

    public static func resetLiveLibrary() throws -> LibraryStore {
        let root = try StorageLocator.appSupportRoot()
        let fm = FileManager.default
        let backup = root.deletingLastPathComponent()
            .appendingPathComponent("Cardfile-reset-backup-\(ISO8601DateFormatter().string(from: Date()))", isDirectory: true)
        if LibraryReplica.hasDatabase(at: root) {
            try? fm.copyItem(at: root, to: backup)
        }
        for name in ["library.sqlite", "library.sqlite-wal", "library.sqlite-shm", "assets", "staging", "handoff"] {
            let url = root.appendingPathComponent(name)
            try? fm.removeItem(at: url)
        }
        return try LibraryStore(root: root, usesSharedContainer: false)
    }

    public func receipt(requestID: UUID) throws -> CaptureResult? {
        try sync { try receiptLocked(requestID) }
    }

    public func savedPayloads() throws -> [CaptureRequest] {
        try sync {
            let rows = try db.query("SELECT payload FROM capture_payloads")
            return rows.compactMap { row in
                row.string("payload").flatMap(CapturePayload.decode)
            }
        }
    }

    /// Replay link and excerpt saves that exist in `source` but not here. File bytes are not stored in the payload.
    public func absorbPayloads(from source: LibraryStore) throws -> Int {
        let payloads = try source.savedPayloads()
        var absorbed = 0
        for request in payloads {
            if try receipt(requestID: request.requestID) != nil { continue }
            let result = try capture(request)
            if result.status == .saved || result.status == .alreadySaved {
                absorbed += 1
            }
        }
        return absorbed
    }

    public func attachPreview(itemID: UUID, data: Data) throws {
        try sync {
            guard data.count <= Limits.maxPreviewBytes else {
                throw LibraryError.tooLarge("That photo is larger than Cardfile can keep as a preview.")
            }
            guard let signature = FileSignature.sniff(data), signature == .png || signature == .jpeg else {
                throw LibraryError.invalidFile("Preview photos need to be a JPEG or PNG.")
            }
            try requireItem(itemID)
            let staged = try stage(data: data, folder: "assets/previews")
            try db.execute("DELETE FROM assets WHERE item_id = ? AND role = 'preview'", [.text(key(itemID))])
            try db.execute(
                "INSERT INTO assets(id, item_id, sha256, relative_path, mime_type, byte_count, role) VALUES(?, ?, ?, ?, ?, ?, 'preview')",
                [.text(staged.id), .text(key(itemID)), .text(staged.hash), .text(staged.relative), .text(signature.mime), .int(Int64(data.count))]
            )
            try db.execute("UPDATE items SET preview_state = 'ready', updated_at = ? WHERE id = ?", [
                .text(stamp(Date())), .text(key(itemID)),
            ])
        }
    }

    public func capture(_ request: CaptureRequest) throws -> CaptureResult {
        try sync { try captureLocked(request) }
    }

    public func undoCapture(requestID: UUID) throws -> CaptureResult {
        try sync { try undoLocked(requestID) }
    }

    public func items(matching query: LibraryQuery) throws -> [SavedItem] {
        try sync { try fetchItems(matching: query) }
    }

    public func matchedCount(matching query: LibraryQuery) throws -> Int {
        try sync { try countItems(matching: query) }
    }

    public func item(id: UUID) throws -> SavedItem? {
        try sync { try hydrate(ids: [key(id)]).first }
    }

    public func shelves() throws -> [Shelf] {
        try sync { try loadShelves() }
    }

    public func counts() throws -> (all: Int, favorites: Int, trash: Int) {
        try sync {
            let all = try db.query("SELECT COUNT(*) AS n FROM items WHERE trashed_at IS NULL").first?.int("n") ?? 0
            let favorites = try db.query("SELECT COUNT(*) AS n FROM items WHERE trashed_at IS NULL AND favorite = 1").first?.int("n") ?? 0
            let trash = try db.query("SELECT COUNT(*) AS n FROM items WHERE trashed_at IS NOT NULL").first?.int("n") ?? 0
            return (all, favorites, trash)
        }
    }

    public func updateTitle(itemID: UUID, title: String) throws {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= Limits.maxTitleCharacters else {
            throw LibraryError.invalidFile("The title needs some text, and it has to stay under 10,000 characters.")
        }
        try sync {
            try requireItem(itemID)
            try db.execute(
                "UPDATE items SET title = ?, title_origin = 'user', updated_at = ? WHERE id = ?",
                [.text(cleaned), .text(stamp(Date())), .text(key(itemID))]
            )
            try writeSearch(id: key(itemID))
        }
    }

    public func updateDescription(itemID: UUID, description: String) throws {
        try sync {
            try requireItem(itemID)
            let cleaned = String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
            try db.execute(
                "UPDATE items SET description = ?, description_origin = ?, updated_at = ? WHERE id = ?",
                [
                    cleaned.isEmpty ? .null : .text(cleaned),
                    cleaned.isEmpty ? .null : .text(FieldOrigin.user.rawValue),
                    .text(stamp(Date())),
                    .text(key(itemID)),
                ]
            )
            try writeSearch(id: key(itemID))
        }
    }

    public func updateNote(itemID: UUID, note: String) throws {
        try sync {
            try requireItem(itemID)
            let cleaned = note.trimmingCharacters(in: .whitespacesAndNewlines)
            try db.execute(
                "UPDATE items SET note = ?, updated_at = ? WHERE id = ?",
                [cleaned.isEmpty ? .null : .text(cleaned), .text(stamp(Date())), .text(key(itemID))]
            )
            try writeSearch(id: key(itemID))
        }
    }

    public func updateKind(itemID: UUID, kind: ContentKind) throws {
        try sync {
            try requireItem(itemID)
            try db.execute(
                "UPDATE items SET kind = ?, kind_origin = 'user', updated_at = ? WHERE id = ?",
                [.text(kind.rawValue), .text(stamp(Date())), .text(key(itemID))]
            )
            if let domain = try hydrate(ids: [key(itemID)]).first?.sourceDomain {
                try rememberKind(domain: domain, kind: kind)
            }
        }
    }

    public func addTag(itemID: UUID, label: String) throws {
        guard let display = TagText.display(for: label), let normalized = TagText.normalize(label) else {
            throw LibraryError.invalidFile("Tags need 1–40 characters.")
        }
        try sync {
            try requireItem(itemID)
            try upsertTag(itemID: key(itemID), display: display, normalized: normalized, status: "confirmed", origin: "user")
            if let domain = try hydrate(ids: [key(itemID)]).first?.sourceDomain {
                try rememberTag(domain: domain, display: display, normalized: normalized)
            }
            try writeSearch(id: key(itemID))
        }
    }

    public func removeTag(itemID: UUID, tagID: UUID) throws {
        try sync {
            try db.execute(
                "UPDATE item_tags SET status = 'rejected', origin = 'user' WHERE item_id = ? AND tag_id = ?",
                [.text(key(itemID)), .text(key(tagID))]
            )
            try writeSearch(id: key(itemID))
        }
    }

    public func confirmTag(itemID: UUID, tagID: UUID) throws {
        try sync {
            try db.execute(
                "UPDATE item_tags SET status = 'confirmed', origin = 'user' WHERE item_id = ? AND tag_id = ?",
                [.text(key(itemID)), .text(key(tagID))]
            )
            if let item = try hydrate(ids: [key(itemID)]).first,
               let tag = item.tags.first(where: { $0.id == tagID }),
               let domain = item.sourceDomain {
                try rememberTag(domain: domain, display: tag.label, normalized: tag.normalized)
            }
            try writeSearch(id: key(itemID))
        }
    }

    public func createShelf(name: String) throws -> Shelf {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 80 else {
            throw LibraryError.invalidFile("A shelf name needs 1–80 characters.")
        }
        return try sync {
            if let existing = try loadShelves().first(where: { $0.name.caseInsensitiveCompare(cleaned) == .orderedSame }) {
                return existing
            }
            let id = uid()
            let order = (try db.query("SELECT COALESCE(MAX(sort_order), 0) AS n FROM shelves").first?.int("n") ?? 0) + 1
            try db.execute(
                "INSERT INTO shelves(id, name, sort_order, created_at) VALUES(?, ?, ?, ?)",
                [.text(id), .text(cleaned), .int(Int64(order)), .text(stamp(Date()))]
            )
            return Shelf(id: UUID(uuidString: id)!, name: cleaned, sortOrder: order, itemCount: 0)
        }
    }

    public func deleteShelf(id: UUID) throws {
        try sync {
            try db.execute("DELETE FROM item_shelves WHERE shelf_id = ?", [.text(key(id))])
            try db.execute("DELETE FROM shelves WHERE id = ?", [.text(key(id))])
        }
    }

    public func renameShelf(id: UUID, name: String) throws {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 80 else {
            throw LibraryError.invalidFile("A shelf name needs 1–80 characters.")
        }
        try sync {
            let shelves = try loadShelves()
            guard shelves.contains(where: { $0.id == id }) else { throw LibraryError.notFound }
            if shelves.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(cleaned) == .orderedSame }) {
                throw LibraryError.invalidFile("A shelf named “\(cleaned)” already exists.")
            }
            try db.execute(
                "UPDATE shelves SET name = ? WHERE id = ?",
                [.text(cleaned), .text(key(id))]
            )
        }
    }

    /// Writes `sort_order` so `orderedIDs` come first. Shelves omitted from the list keep their relative order after those ids.
    public func reorderShelves(_ orderedIDs: [UUID]) throws {
        try sync {
            let existing = try loadShelves()
            var rank: [UUID: Int] = [:]
            var next = 1
            for id in orderedIDs where existing.contains(where: { $0.id == id }) && rank[id] == nil {
                rank[id] = next
                next += 1
            }
            for shelf in existing where rank[shelf.id] == nil {
                rank[shelf.id] = next
                next += 1
            }
            for (id, order) in rank {
                try db.execute(
                    "UPDATE shelves SET sort_order = ? WHERE id = ?",
                    [.int(Int64(order)), .text(key(id))]
                )
            }
        }
    }

    /// Confirmed tags on items that are not in Trash, most used first.
    /// Pass `withCounts: false` to keep the same order with counts zeroed.
    public func allTags(withCounts: Bool = true) throws -> [TagCount] {
        try sync {
            let rows = try db.query("""
            SELECT tags.display_label AS label, COUNT(items.id) AS n
            FROM tags
            JOIN item_tags ON item_tags.tag_id = tags.id AND item_tags.status = 'confirmed'
            JOIN items ON items.id = item_tags.item_id AND items.trashed_at IS NULL
            GROUP BY tags.normalized_name
            ORDER BY n DESC, tags.display_label COLLATE NOCASE ASC
            """)
            return rows.compactMap { row in
                guard let label = row.string("label"), !label.isEmpty else { return nil }
                return TagCount(label: label, count: withCounts ? row.int("n") : 0)
            }
        }
    }

    public func setMembership(itemID: UUID, shelfID: UUID, member: Bool) throws {
        try sync {
            if member {
                try db.execute(
                    "INSERT OR IGNORE INTO item_shelves(item_id, shelf_id) VALUES(?, ?)",
                    [.text(key(itemID)), .text(key(shelfID))]
                )
            } else {
                try db.execute(
                    "DELETE FROM item_shelves WHERE item_id = ? AND shelf_id = ?",
                    [.text(key(itemID)), .text(key(shelfID))]
                )
            }
        }
    }

    public func setFavorite(itemID: UUID, favorite: Bool) throws {
        try sync {
            try db.execute(
                "UPDATE items SET favorite = ?, updated_at = ? WHERE id = ?",
                [.int(favorite ? 1 : 0), .text(stamp(Date())), .text(key(itemID))]
            )
        }
    }

    public func trash(itemID: UUID) throws {
        try sync {
            try db.execute(
                "UPDATE items SET trashed_at = ?, updated_at = ? WHERE id = ?",
                [.text(stamp(Date())), .text(stamp(Date())), .text(key(itemID))]
            )
            try writeSearch(id: key(itemID))
        }
    }

    public func restoreItem(itemID: UUID) throws {
        try sync {
            try db.execute(
                "UPDATE items SET trashed_at = NULL, updated_at = ? WHERE id = ?",
                [.text(stamp(Date())), .text(key(itemID))]
            )
            try writeSearch(id: key(itemID))
        }
    }

    public func trashedItems() throws -> [SavedItem] {
        try sync {
            let rows = try db.query("SELECT id FROM items WHERE trashed_at IS NOT NULL ORDER BY trashed_at DESC")
            return try hydrate(ids: rows.compactMap { $0.string("id") })
        }
    }

    public func emptyTrash() throws {
        try sync {
            let rows = try db.query("SELECT id FROM items WHERE trashed_at IS NOT NULL")
            for id in rows.compactMap({ $0.string("id") }) {
                try hardDelete(id: id)
            }
            try sweepUnreferencedAssets()
        }
    }

    public func purgeExpiredTrash(now: Date = Date()) throws {
        try sync {
            let cutoff = stamp(now.addingTimeInterval(-Double(Limits.trashDays) * 24 * 60 * 60))
            let rows = try db.query("SELECT id FROM items WHERE trashed_at IS NOT NULL AND trashed_at < ?", [.text(cutoff)])
            for id in rows.compactMap({ $0.string("id") }) {
                try hardDelete(id: id)
            }
            if !rows.isEmpty { try sweepUnreferencedAssets() }
        }
    }

    public func clearPreviewCache() throws -> Int {
        try sync {
            let rows = try db.query("SELECT relative_path FROM assets WHERE role = 'preview'")
            try db.execute("DELETE FROM assets WHERE role = 'preview'")
            try db.execute("UPDATE items SET preview_state = 'unavailable' WHERE preview_state = 'ready'")
            var removed = 0
            for path in rows.compactMap({ $0.string("relative_path") }) {
                try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(path))
                removed += 1
            }
            return removed
        }
    }

    public func storageUsage() throws -> StorageUsage {
        try sync {
            let originals = try db.query("SELECT COALESCE(SUM(byte_count), 0) AS n FROM assets WHERE role = 'original'").first?.int("n") ?? 0
            let previews = try db.query("SELECT COALESCE(SUM(byte_count), 0) AS n FROM assets WHERE role = 'preview'").first?.int("n") ?? 0
            let items = try db.query("SELECT COUNT(*) AS n FROM items WHERE trashed_at IS NULL").first?.int("n") ?? 0
            return StorageUsage(originalBytes: originals, previewBytes: previews, itemCount: items)
        }
    }

    public func boolSetting(_ key: String, default defaultValue: Bool) throws -> Bool {
        try sync {
            guard let raw = try db.query("SELECT value FROM settings WHERE key = ?", [.text(key)]).first?.string("value") else {
                return defaultValue
            }
            return raw == "1"
        }
    }

    public func setBoolSetting(_ key: String, _ value: Bool) throws {
        try sync {
            try db.execute(
                "INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [.text(key), .text(value ? "1" : "0")]
            )
        }
    }

    public func requeueMissingPreviews() throws -> Int {
        try sync {
            let rows = try db.query("""
            SELECT id FROM items
            WHERE trashed_at IS NULL AND retention_state = 'bookmark'
              AND preview_state IN ('unavailable', 'pending')
            """)
            var queued = 0
            for id in rows.compactMap({ $0.string("id") }) {
                let existing = try db.query(
                    "SELECT id, status FROM enrichment_jobs WHERE item_id = ? ORDER BY rowid DESC LIMIT 1",
                    [.text(id)]
                ).first
                if let jobID = existing?.string("id") {
                    try db.execute(
                        "UPDATE enrichment_jobs SET status = 'pending', attempts = 0, error_class = NULL WHERE id = ?",
                        [.text(jobID)]
                    )
                } else {
                    try db.execute(
                        "INSERT INTO enrichment_jobs(id, item_id, job_type, attempts, status) VALUES(?, ?, 'metadata', 0, 'pending')",
                        [.text(uid()), .text(id)]
                    )
                }
                try db.execute("UPDATE items SET preview_state = 'pending' WHERE id = ? AND preview_state = 'unavailable'", [.text(id)])
                queued += 1
            }
            return queued
        }
    }

    public func refreshPreview(itemID: UUID) throws {
        try sync {
            try requireItem(itemID)
            try db.execute("DELETE FROM assets WHERE item_id = ? AND role = 'preview'", [.text(key(itemID))])
            try db.execute("UPDATE items SET preview_state = 'pending' WHERE id = ?", [.text(key(itemID))])
            let existing = try db.query(
                "SELECT id FROM enrichment_jobs WHERE item_id = ? AND status = 'pending'",
                [.text(key(itemID))]
            )
            if existing.isEmpty {
                try db.execute(
                    "INSERT INTO enrichment_jobs(id, item_id, job_type, attempts, status) VALUES(?, ?, 'metadata', 0, 'pending')",
                    [.text(uid()), .text(key(itemID))]
                )
            }
        }
    }

    public func pendingEnrichmentJobs() throws -> [EnrichmentJob] {
        try sync {
            try db.query(
                "SELECT id, item_id, attempts FROM enrichment_jobs WHERE status = 'pending' ORDER BY rowid ASC LIMIT 8"
            ).compactMap { row in
                guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
                      let itemID = row.string("item_id").flatMap(UUID.init(uuidString:)) else { return nil }
                return EnrichmentJob(id: id, itemID: itemID, attempts: row.int("attempts"))
            }
        }
    }

    public func completeEnrichment(itemID: UUID, metadata: PageMetadata, preview: Data?, previewFailed: Bool) throws {
        try sync {
            guard let item = try hydrate(ids: [key(itemID)]).first else { return }
            if item.titleOrigin != .user, let title = metadata.title, !title.isEmpty, title.count <= Limits.maxTitleCharacters {
                try db.execute(
                    "UPDATE items SET title = ?, title_origin = 'metadata', updated_at = ? WHERE id = ?",
                    [.text(title), .text(stamp(Date())), .text(key(itemID))]
                )
            }
            if item.summaryOrigin != .user, let description = metadata.description, !description.isEmpty {
                try db.execute(
                    "UPDATE items SET description = ?, description_origin = 'publisher', updated_at = ? WHERE id = ?",
                    [.text(String(description.prefix(2_000))), .text(stamp(Date())), .text(key(itemID))]
                )
            }
            if item.author == nil, let author = metadata.author, !author.isEmpty {
                try db.execute("UPDATE items SET author = ? WHERE id = ?", [.text(String(author.prefix(200))), .text(key(itemID))])
            }
            if item.kindOrigin != .user, let url = item.originalURL.flatMap(URL.init(string:)) {
                let learned = try learnedKind(for: item.sourceDomain)
                let guessed = KindClassifier.guess(
                    url: url,
                    title: metadata.title ?? item.title,
                    openGraphType: metadata.openGraphType,
                    captureKind: item.kind == .article ? .page : .link,
                    learned: learned
                )
                if guessed != item.kind, !(guessed == .link && item.kind != .link) {
                    try db.execute(
                        "UPDATE items SET kind = ?, kind_origin = 'metadata' WHERE id = ?",
                        [.text(guessed.rawValue), .text(key(itemID))]
                    )
                }
            }
            let fresh = try hydrate(ids: [key(itemID)]).first
            let extras = try rememberedSuggestions(title: fresh?.title ?? item.title, domain: item.sourceDomain)
            for label in TagSuggestions.suggest(
                title: fresh?.title ?? item.title,
                description: metadata.description,
                excerpt: item.kind == .excerpt ? item.summary : nil,
                extras: extras
            ) {
                guard let display = TagText.display(for: label), let normalized = TagText.normalize(label) else { continue }
                try upsertTag(itemID: key(itemID), display: display, normalized: normalized, status: "suggested", origin: "suggestion", onlyIfMissing: true)
            }
            if item.previewAsset == nil, let preview, preview.count <= Limits.maxPreviewBytes,
               let signature = FileSignature.sniff(preview), signature == .png || signature == .jpeg {
                let staged = try stage(data: preview, folder: "assets/previews")
                try db.execute("DELETE FROM assets WHERE item_id = ? AND role = 'preview'", [.text(key(itemID))])
                try db.execute(
                    "INSERT INTO assets(id, item_id, sha256, relative_path, mime_type, byte_count, role) VALUES(?, ?, ?, ?, ?, ?, 'preview')",
                    [.text(staged.id), .text(key(itemID)), .text(staged.hash), .text(staged.relative), .text(signature.mime), .int(Int64(preview.count))]
                )
                try db.execute("UPDATE items SET preview_state = 'ready' WHERE id = ?", [.text(key(itemID))])
            } else if previewFailed || item.previewState == .pending {
                try db.execute("UPDATE items SET preview_state = 'unavailable' WHERE id = ? AND preview_state = 'pending'", [.text(key(itemID))])
            }
            try db.execute("UPDATE enrichment_jobs SET status = 'done', error_class = NULL WHERE item_id = ? AND status = 'pending'", [.text(key(itemID))])
            try writeSearch(id: key(itemID))
        }
    }

    public func failEnrichment(jobID: UUID, errorClass: String) throws {
        try sync {
            let rows = try db.query("SELECT item_id, attempts FROM enrichment_jobs WHERE id = ?", [.text(key(jobID))])
            guard let row = rows.first, let itemID = row.string("item_id") else { return }
            let attempts = row.int("attempts") + 1
            if attempts >= 3 {
                try db.execute(
                    "UPDATE enrichment_jobs SET status = 'failed', attempts = ?, error_class = ? WHERE id = ?",
                    [.int(Int64(attempts)), .text(errorClass), .text(key(jobID))]
                )
                try db.execute("UPDATE items SET preview_state = 'unavailable' WHERE id = ? AND preview_state = 'pending'", [.text(itemID)])
            } else {
                try db.execute(
                    "UPDATE enrichment_jobs SET attempts = ?, error_class = ? WHERE id = ?",
                    [.int(Int64(attempts)), .text(errorClass), .text(key(jobID))]
                )
            }
        }
    }

    func sync<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        savepointDepth += 1
        let name = "sp\(savepointDepth)"
        try db.execute("SAVEPOINT \(name);")
        do {
            let value = try body()
            try db.execute("RELEASE \(name);")
            savepointDepth -= 1
            return value
        } catch {
            try? db.execute("ROLLBACK TO \(name);")
            try? db.execute("RELEASE \(name);")
            savepointDepth -= 1
            throw error
        }
    }

    func stamp(_ date: Date) -> String { iso.string(from: date) }
    func parseDate(_ raw: String?) -> Date? { raw.flatMap { iso.date(from: $0) } }
    func uid() -> String { UUID().uuidString.lowercased() }
    func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    func learnedKind(for domain: String?) throws -> ContentKind? {
        guard let domain, !domain.isEmpty else { return nil }
        guard let raw = try db.query("SELECT kind FROM learned_kinds WHERE domain = ?", [.text(domain)]).first?.string("kind") else {
            return nil
        }
        return ContentKind(rawValue: raw)
    }

    func applyCapturedClassification() throws {
        let rows = try db.query("""
        SELECT id, original_url, title, kind, kind_origin, source_domain, description
        FROM items WHERE trashed_at IS NULL AND kind_origin != 'user'
        """)
        for row in rows {
            guard let id = row.string("id"),
                  let url = row.string("original_url").flatMap(URL.init(string:)) else { continue }
            let title = row.string("title") ?? ""
            let learned = try learnedKind(for: row.string("source_domain"))
            let current = ContentKind(rawValue: row.string("kind") ?? "link") ?? .link
            let guessed = KindClassifier.guess(url: url, title: title, learned: learned)
            if guessed != current, !(guessed == .link && current != .link) {
                try db.execute(
                    "UPDATE items SET kind = ?, kind_origin = 'metadata' WHERE id = ?",
                    [.text(guessed.rawValue), .text(id)]
                )
            }
            try suggest(
                title: title,
                description: row.string("description"),
                excerpt: guessed == .excerpt ? row.string("description") : nil,
                itemID: id,
                domain: row.string("source_domain")
            )
        }
    }

    func rememberKind(domain: String, kind: ContentKind) throws {
        try db.execute(
            "INSERT INTO learned_kinds(domain, kind, updated_at) VALUES(?, ?, ?) ON CONFLICT(domain) DO UPDATE SET kind = excluded.kind, updated_at = excluded.updated_at",
            [.text(domain), .text(kind.rawValue), .text(stamp(Date()))]
        )
    }

    func rememberTag(domain: String, display: String, normalized: String) throws {
        guard !KindClassifier.isGenericHost(domain) else { return }
        try db.execute("""
        INSERT INTO learned_tags(domain, normalized_name, display_label, uses) VALUES(?, ?, ?, 1)
        ON CONFLICT(domain, normalized_name) DO UPDATE SET uses = uses + 1, display_label = excluded.display_label
        """, [.text(domain), .text(normalized), .text(display)])
    }

    func rememberedSuggestions(title: String, domain: String?) throws -> [String] {
        var labels: [String] = []
        if let domain, !KindClassifier.isGenericHost(domain) {
            let rows = try db.query(
                "SELECT display_label FROM learned_tags WHERE domain = ? ORDER BY uses DESC LIMIT 3",
                [.text(domain)]
            )
            labels.append(contentsOf: rows.compactMap { $0.string("display_label") })
        }
        let hasConfirmed = try db.query("SELECT 1 AS n FROM item_tags WHERE status = 'confirmed' LIMIT 1")
        guard !hasConfirmed.isEmpty else { return labels }
        let tokens = title.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { token in
            token.count >= 4 && !["wikipedia", "https", "http", "www", "html", "article"].contains(token)
        }
        if !tokens.isEmpty {
            var sql = """
            SELECT tags.display_label AS label, COUNT(*) AS n
            FROM items
            JOIN item_tags ON item_tags.item_id = items.id AND item_tags.status = 'confirmed'
            JOIN tags ON tags.id = item_tags.tag_id
            WHERE items.trashed_at IS NULL AND (
            """
            sql += tokens.map { _ in "lower(items.title) LIKE ?" }.joined(separator: " OR ")
            sql += ") GROUP BY tags.normalized_name ORDER BY n DESC LIMIT 3"
            let binds = tokens.map { SQLBind.text("%\($0)%") }
            for row in try db.query(sql, binds) {
                if let label = row.string("label") { labels.append(label) }
            }
        }
        return labels
    }

    func migrate() throws {
        let version = try db.userVersion
        if version < 1 {
        try db.execute("""
        CREATE TABLE items (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            kind_origin TEXT NOT NULL,
            retention_state TEXT NOT NULL,
            original_url TEXT,
            match_key TEXT,
            title TEXT NOT NULL,
            title_origin TEXT NOT NULL,
            description TEXT,
            description_origin TEXT,
            note TEXT,
            author TEXT,
            filename TEXT,
            source_domain TEXT,
            favorite INTEGER NOT NULL DEFAULT 0,
            preview_state TEXT NOT NULL,
            trashed_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE tags (
            id TEXT PRIMARY KEY,
            normalized_name TEXT NOT NULL UNIQUE,
            display_label TEXT NOT NULL
        );
        CREATE TABLE item_tags (
            item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
            origin TEXT NOT NULL,
            status TEXT NOT NULL,
            PRIMARY KEY(item_id, tag_id)
        );
        CREATE TABLE shelves (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            created_at TEXT NOT NULL
        );
        CREATE TABLE item_shelves (
            item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            shelf_id TEXT NOT NULL REFERENCES shelves(id) ON DELETE CASCADE,
            PRIMARY KEY(item_id, shelf_id)
        );
        CREATE TABLE assets (
            id TEXT PRIMARY KEY,
            item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            sha256 TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            mime_type TEXT,
            byte_count INTEGER NOT NULL,
            role TEXT NOT NULL
        );
        CREATE TABLE capture_receipts (
            request_id TEXT PRIMARY KEY,
            schema_version INTEGER NOT NULL,
            origin TEXT NOT NULL,
            item_id TEXT,
            status TEXT NOT NULL,
            retention_state TEXT,
            created_at TEXT NOT NULL
        );
        CREATE TABLE enrichment_jobs (
            id TEXT PRIMARY KEY,
            item_id TEXT NOT NULL,
            job_type TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL,
            error_class TEXT
        );
        CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE VIRTUAL TABLE search_documents USING fts5(
            title, url, domain, description, filename, note, tags, author, excerpt,
            item_id UNINDEXED,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        CREATE INDEX idx_items_match ON items(match_key);
        CREATE INDEX idx_items_trashed ON items(trashed_at);
        """)
            try db.setUserVersion(1)
        }
        if try db.userVersion < 2 {
            try db.execute("""
            CREATE TABLE IF NOT EXISTS learned_kinds (
                domain TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS learned_tags (
                domain TEXT NOT NULL,
                normalized_name TEXT NOT NULL,
                display_label TEXT NOT NULL,
                uses INTEGER NOT NULL DEFAULT 1,
                PRIMARY KEY(domain, normalized_name)
            );
            """)
            try db.setUserVersion(2)
        }
        if try db.userVersion < 3 {
            try db.execute("""
            CREATE TABLE IF NOT EXISTS capture_payloads (
                request_id TEXT PRIMARY KEY,
                payload TEXT NOT NULL
            );
            """)
            try db.setUserVersion(3)
        }
    }
}
