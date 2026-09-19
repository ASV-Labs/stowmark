import CryptoKit
import Foundation

extension LibraryStore {
    func captureLocked(_ request: CaptureRequest) throws -> CaptureResult {
        guard request.schemaVersion == 1 else {
            return .failed("Not saved. This capture came from an unsupported version.")
        }
        if let existing = try db.query(
            "SELECT * FROM capture_receipts WHERE request_id = ?",
            [.text(key(request.requestID))]
        ).first {
            return try replay(existing)
        }
        return try transaction { try insertCapture(request) }
    }

    func undoLocked(_ requestID: UUID) throws -> CaptureResult {
        guard let receipt = try db.query(
            "SELECT * FROM capture_receipts WHERE request_id = ?",
            [.text(key(requestID))]
        ).first else {
            return .failed("Nothing to undo. That save was not found.")
        }
        let status = CaptureStatus(rawValue: receipt.string("status") ?? "") ?? .failed
        if status == .alreadySaved {
            return CaptureResult(
                status: .alreadySaved,
                itemID: receipt.string("item_id").flatMap(UUID.init(uuidString:)),
                retention: receipt.string("retention_state").flatMap(RetentionState.init(rawValue:)),
                warnings: [],
                message: "That item was already in your library, so undo left it in place."
            )
        }
        guard status == .saved, let itemID = receipt.string("item_id") else {
            return .failed("Nothing to undo.")
        }
        try db.execute("UPDATE items SET trashed_at = ?, updated_at = ? WHERE id = ?", [
            .text(stamp(Date())), .text(stamp(Date())), .text(itemID),
        ])
        try db.execute("UPDATE capture_receipts SET status = 'undone' WHERE request_id = ?", [.text(key(requestID))])
        try writeSearch(id: itemID)
        return CaptureResult(status: .undone, itemID: UUID(uuidString: itemID), retention: nil, warnings: [], message: "Save undone. It is in Trash if you need it back.")
    }

    func receiptLocked(_ requestID: UUID) throws -> CaptureResult? {
        guard let row = try db.query(
            "SELECT * FROM capture_receipts WHERE request_id = ?",
            [.text(key(requestID))]
        ).first else { return nil }
        return try replay(row)
    }

    private func insertCapture(_ request: CaptureRequest) throws -> CaptureResult {
        switch request.captureKind {
        case .page, .link:
            return try insertLink(request)
        case .selection:
            return try insertExcerpt(request)
        case .image, .pdf:
            return try insertFile(request)
        }
    }

    private func insertLink(_ request: CaptureRequest) throws -> CaptureResult {
        let parsed = URLSafety.captureURL(from: request.targetURL ?? request.pageURL)
        guard case .success(let url) = parsed else {
            return parsed.failureResult
        }
        let match = URLSafety.matchKey(for: url)
        if let existing = try db.query(
            "SELECT id, retention_state FROM items WHERE match_key = ? AND trashed_at IS NULL AND retention_state != 'savedExcerpt' LIMIT 1",
            [.text(match)]
        ).first, let id = existing.string("id") {
            let retention = RetentionState(rawValue: existing.string("retention_state") ?? "") ?? .bookmark
            try writeReceipt(request, itemID: id, status: .alreadySaved, retention: retention)
            try assignShelf(request.shelfName, itemID: id)
            return CaptureResult(status: .alreadySaved, itemID: UUID(uuidString: id), retention: retention, warnings: [], message: "Already in your library.")
        }
        let id = uid()
        let now = stamp(Date())
        let title = clippedTitle(request.capturedTitle, fallback: URLSafety.domain(for: url))
        let domain = URLSafety.domain(for: url)
        let kind = KindClassifier.guess(
            url: url,
            title: title,
            captureKind: request.captureKind,
            learned: try learnedKind(for: domain)
        )
        let blocked = URLSafety.isBlockedFetchTarget(url)
        let preview: PreviewState = blocked ? .unavailable : .pending
        try db.execute("""
        INSERT INTO items(id, kind, kind_origin, retention_state, original_url, match_key, title, title_origin,
            description, description_origin, note, author, filename, source_domain, favorite, preview_state, trashed_at, created_at, updated_at)
        VALUES(?, ?, 'captured', 'bookmark', ?, ?, ?, 'captured', NULL, NULL, ?, NULL, NULL, ?, 0, ?, NULL, ?, ?)
        """, [
            .text(id),
            .text(kind.rawValue),
            .text(url.absoluteString),
            .text(match),
            .text(title),
            request.note.flatMap(emptyToNil).map(SQLBind.text) ?? .null,
            .text(domain),
            .text(preview.rawValue),
            .text(now),
            .text(now),
        ])
        try applyUserTags(request.tags, itemID: id, domain: domain)
        try suggest(title: title, description: nil, excerpt: nil, itemID: id, domain: domain)
        try assignShelf(request.shelfName, itemID: id)
        if !blocked {
            try db.execute(
                "INSERT INTO enrichment_jobs(id, item_id, job_type, attempts, status) VALUES(?, ?, 'metadata', 0, 'pending')",
                [.text(uid()), .text(id)]
            )
        }
        try writeReceipt(request, itemID: id, status: .saved, retention: .bookmark)
        try writeSearch(id: id)
        return CaptureResult(status: .saved, itemID: UUID(uuidString: id), retention: .bookmark, warnings: blocked ? ["preview_unavailable"] : [], message: "Saved.")
    }

    private func insertExcerpt(_ request: CaptureRequest) throws -> CaptureResult {
        let text = request.selectionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return .failed("Not saved. Select some text first.") }
        guard text.count <= Limits.maxExcerptCharacters else {
            return .failed("Not saved. That excerpt is over \(Limits.maxExcerptCharacters) characters.")
        }
        let parsed = URLSafety.captureURL(from: request.pageURL ?? request.targetURL)
        guard case .success(let url) = parsed else { return parsed.failureResult }
        let match = URLSafety.matchKey(for: url)
        if let existing = try db.query(
            "SELECT id FROM items WHERE match_key = ? AND retention_state = 'savedExcerpt' AND description = ? AND trashed_at IS NULL LIMIT 1",
            [.text(match), .text(text)]
        ).first, let id = existing.string("id") {
            try writeReceipt(request, itemID: id, status: .alreadySaved, retention: .savedExcerpt)
            return CaptureResult(status: .alreadySaved, itemID: UUID(uuidString: id), retention: .savedExcerpt, warnings: [], message: "Already in your library.")
        }
        let id = uid()
        let now = stamp(Date())
        let title = clippedTitle(request.capturedTitle, fallback: URLSafety.domain(for: url))
        try db.execute("""
        INSERT INTO items(id, kind, kind_origin, retention_state, original_url, match_key, title, title_origin,
            description, description_origin, note, author, filename, source_domain, favorite, preview_state, trashed_at, created_at, updated_at)
        VALUES(?, 'excerpt', 'captured', 'savedExcerpt', ?, ?, ?, 'captured', ?, 'captured', ?, NULL, NULL, ?, 0, 'none', NULL, ?, ?)
        """, [
            .text(id), .text(url.absoluteString), .text(match), .text(title), .text(text),
            request.note.flatMap(emptyToNil).map(SQLBind.text) ?? .null,
            .text(URLSafety.domain(for: url)), .text(now), .text(now),
        ])
        try applyUserTags(request.tags, itemID: id, domain: URLSafety.domain(for: url))
        try suggest(title: title, description: nil, excerpt: text, itemID: id, domain: URLSafety.domain(for: url))
        try assignShelf(request.shelfName, itemID: id)
        try writeReceipt(request, itemID: id, status: .saved, retention: .savedExcerpt)
        try writeSearch(id: id)
        return CaptureResult(status: .saved, itemID: UUID(uuidString: id), retention: .savedExcerpt, warnings: [], message: "Excerpt saved.")
    }

    private func insertFile(_ request: CaptureRequest) throws -> CaptureResult {
        guard let file = request.file else { return .failed("Not saved. No file was included.") }
        guard file.bytes.count <= Limits.maxAttachmentBytes else {
            return .failed("Not saved. That file is over the 100 MB limit.")
        }
        guard let signature = FileSignature.sniff(file.bytes) else {
            return .failed("Not saved. My Mind can copy JPEG, PNG, HEIC, and PDF files.")
        }
        let staged = try stage(data: file.bytes, folder: "assets/originals")
        let id = uid()
        let now = stamp(Date())
        let filename = (file.filename as NSString).lastPathComponent
        let title = clippedTitle(request.capturedTitle, fallback: filename)
        try db.execute("""
        INSERT INTO items(id, kind, kind_origin, retention_state, original_url, match_key, title, title_origin,
            description, description_origin, note, author, filename, source_domain, favorite, preview_state, trashed_at, created_at, updated_at)
        VALUES(?, ?, 'captured', ?, NULL, ?, ?, 'captured', NULL, NULL, ?, NULL, ?, NULL, 0, 'none', NULL, ?, ?)
        """, [
            .text(id), .text(signature.kind.rawValue), .text(signature.retention.rawValue), .text(staged.hash),
            .text(title), request.note.flatMap(emptyToNil).map(SQLBind.text) ?? .null, .text(filename), .text(now), .text(now),
        ])
        try db.execute(
            "INSERT INTO assets(id, item_id, sha256, relative_path, mime_type, byte_count, role) VALUES(?, ?, ?, ?, ?, ?, 'original')",
            [.text(staged.id), .text(id), .text(staged.hash), .text(staged.relative), .text(signature.mime), .int(Int64(file.bytes.count))]
        )
        try applyUserTags(request.tags, itemID: id)
        try suggest(title: title, description: nil, excerpt: nil, itemID: id)
        try assignShelf(request.shelfName, itemID: id)
        try writeReceipt(request, itemID: id, status: .saved, retention: signature.retention)
        try writeSearch(id: id)
        let message = signature == .pdf ? "PDF copied." : "Image copied."
        return CaptureResult(status: .saved, itemID: UUID(uuidString: id), retention: signature.retention, warnings: [], message: message)
    }

    func fetchItems(matching query: LibraryQuery) throws -> [SavedItem] {
        let ids = try matchingIDs(for: query, applyLimit: true)
        return try hydrate(ids: ids)
    }

    func countItems(matching query: LibraryQuery) throws -> Int {
        let (filterSQL, filterBinds) = filters(for: query)
        if let fts = SearchText.ftsQuery(from: query.text) {
            do {
                let rows = try db.query("""
                SELECT COUNT(*) AS n FROM search_documents
                JOIN items ON items.id = search_documents.item_id
                WHERE search_documents MATCH ? \(filterSQL)
                """, [.text(fts)] + filterBinds)
                return rows.first?.int("n") ?? 0
            } catch {
                return 0
            }
        }
        let rows = try db.query("SELECT COUNT(*) AS n FROM items WHERE 1 = 1 \(filterSQL)", filterBinds)
        return rows.first?.int("n") ?? 0
    }

    private func matchingIDs(for query: LibraryQuery, applyLimit: Bool) throws -> [String] {
        let (filterSQL, filterBinds) = filters(for: query)
        let fts = SearchText.ftsQuery(from: query.text)
        let limitSQL: String
        if applyLimit, let limit = query.limit, limit > 0 {
            let offset = max(0, query.offset ?? 0)
            limitSQL = " LIMIT \(limit) OFFSET \(offset)"
        } else {
            limitSQL = ""
        }
        if let fts {
            do {
                return try matchingIDs(fts: fts, filterSQL: filterSQL, filterBinds: filterBinds, order: query.order, limitSQL: limitSQL)
            } catch {
                // Malformed MATCH strings must not crash browsing; treat as zero hits.
                return []
            }
        }
        let orderSQL: String
        switch query.order {
        case .title: orderSQL = "ORDER BY items.title COLLATE NOCASE ASC"
        case .source: orderSQL = "ORDER BY items.source_domain COLLATE NOCASE ASC, items.created_at DESC"
        case .kind: orderSQL = "ORDER BY items.kind COLLATE NOCASE ASC, items.created_at DESC"
        case .tags: orderSQL = """
            ORDER BY (
                SELECT MIN(tags.normalized_name) FROM item_tags
                JOIN tags ON tags.id = item_tags.tag_id
                WHERE item_tags.item_id = items.id AND item_tags.status = 'confirmed'
            ) COLLATE NOCASE ASC, items.created_at DESC
            """
        case .kept: orderSQL = "ORDER BY items.retention_state COLLATE NOCASE ASC, items.created_at DESC"
        case .recent, .relevance: orderSQL = "ORDER BY items.created_at DESC"
        }
        let rows = try db.query("SELECT id FROM items WHERE 1 = 1 \(filterSQL) \(orderSQL)\(limitSQL)", filterBinds)
        return rows.compactMap { $0.string("id") }
    }

    private func matchingIDs(fts: String, filterSQL: String, filterBinds: [SQLBind], order: ResultOrder, limitSQL: String) throws -> [String] {
        let orderSQL: String
        switch order {
        case .title: orderSQL = "ORDER BY items.title COLLATE NOCASE ASC"
        case .source: orderSQL = "ORDER BY items.source_domain COLLATE NOCASE ASC"
        case .kind: orderSQL = "ORDER BY items.kind COLLATE NOCASE ASC, items.created_at DESC"
        case .tags: orderSQL = """
            ORDER BY (
                SELECT MIN(tags.normalized_name) FROM item_tags
                JOIN tags ON tags.id = item_tags.tag_id
                WHERE item_tags.item_id = items.id AND item_tags.status = 'confirmed'
            ) COLLATE NOCASE ASC, items.created_at DESC
            """
        case .kept: orderSQL = "ORDER BY items.retention_state COLLATE NOCASE ASC, items.created_at DESC"
        case .recent: orderSQL = "ORDER BY items.created_at DESC"
        case .relevance: orderSQL = "ORDER BY bm25(search_documents), items.created_at DESC"
        }
        let rows = try db.query("""
        SELECT items.id AS id FROM search_documents
        JOIN items ON items.id = search_documents.item_id
        WHERE search_documents MATCH ? \(filterSQL) \(orderSQL)\(limitSQL)
        """, [.text(fts)] + filterBinds)
        return rows.compactMap { $0.string("id") }
    }

    private func filters(for query: LibraryQuery) -> (String, [SQLBind]) {
        var sql = ""
        var binds: [SQLBind] = []
        if query.trashedOnly {
            sql += " AND items.trashed_at IS NOT NULL"
        } else if !query.includeTrashed {
            sql += " AND items.trashed_at IS NULL"
        }
        if !query.kinds.isEmpty {
            sql += " AND items.kind IN (\(query.kinds.map { _ in "?" }.joined(separator: ",")))"
            binds += query.kinds.map { .text($0.rawValue) }
        }
        if let shelfID = query.shelfID {
            sql += " AND EXISTS (SELECT 1 FROM item_shelves WHERE item_id = items.id AND shelf_id = ?)"
            binds.append(.text(key(shelfID)))
        }
        if query.favoritesOnly { sql += " AND items.favorite = 1" }
        if let domain = query.domain {
            sql += " AND items.source_domain = ?"
            binds.append(.text(domain))
        }
        if let createdAfter = query.createdAfter {
            sql += " AND items.created_at >= ?"
            binds.append(.text(stamp(createdAfter)))
        }
        let names = query.tagNames.compactMap(TagText.normalize)
        if !names.isEmpty {
            sql += """
             AND (
               SELECT COUNT(DISTINCT tags.normalized_name) FROM item_tags
               JOIN tags ON tags.id = item_tags.tag_id
               WHERE item_tags.item_id = items.id AND item_tags.status = 'confirmed'
                 AND tags.normalized_name IN (\(names.map { _ in "?" }.joined(separator: ",")))
             ) = \(names.count)
            """
            binds += names.map { SQLBind.text($0) }
        }
        return (sql, binds)
    }

    func hydrate(ids: [String]) throws -> [SavedItem] {
        guard !ids.isEmpty else { return [] }
        var built: [String: SavedItem] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 400).map({ Array(ids[$0..<min($0 + 400, ids.count)]) }) {
            let marks = chunk.map { _ in "?" }.joined(separator: ",")
            let binds = chunk.map { SQLBind.text($0) }
            for row in try db.query("SELECT * FROM items WHERE id IN (\(marks))", binds) {
                if let item = makeItem(row) { built[key(item.id)] = item }
            }
            let tags = try db.query("""
            SELECT item_tags.item_id, item_tags.tag_id, item_tags.origin, item_tags.status, tags.display_label, tags.normalized_name
            FROM item_tags JOIN tags ON tags.id = item_tags.tag_id
            WHERE item_tags.item_id IN (\(marks)) AND item_tags.status != 'rejected'
            """, binds)
            for row in tags {
                guard let itemID = row.string("item_id"), var item = built[itemID],
                      let tagID = row.string("tag_id").flatMap(UUID.init(uuidString:)) else { continue }
                item.tags.append(ItemTag(
                    id: tagID,
                    label: row.string("display_label") ?? "",
                    normalized: row.string("normalized_name") ?? "",
                    status: row.string("status") ?? "confirmed",
                    origin: row.string("origin") ?? "user"
                ))
                built[itemID] = item
            }
            let shelves = try db.query("""
            SELECT item_shelves.item_id, shelves.id, shelves.name, shelves.sort_order
            FROM item_shelves JOIN shelves ON shelves.id = item_shelves.shelf_id
            WHERE item_shelves.item_id IN (\(marks))
            """, binds)
            for row in shelves {
                guard let itemID = row.string("item_id"), var item = built[itemID],
                      let shelfID = row.string("id").flatMap(UUID.init(uuidString:)) else { continue }
                item.shelves.append(Shelf(id: shelfID, name: row.string("name") ?? "", sortOrder: row.int("sort_order"), itemCount: 0))
                built[itemID] = item
            }
            let assets = try db.query("SELECT * FROM assets WHERE item_id IN (\(marks))", binds)
            for row in assets {
                guard let itemID = row.string("item_id"), var item = built[itemID],
                      let assetID = row.string("id").flatMap(UUID.init(uuidString:)) else { continue }
                item.assets.append(AssetRecord(
                    id: assetID,
                    role: row.string("role") ?? "original",
                    relativePath: row.string("relative_path") ?? "",
                    mimeType: row.string("mime_type"),
                    byteCount: row.int("byte_count"),
                    sha256: row.string("sha256") ?? ""
                ))
                built[itemID] = item
            }
        }
        return ids.compactMap { built[$0] }
    }

    private func makeItem(_ row: SQLRow) -> SavedItem? {
        guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
              let kind = row.string("kind").flatMap(ContentKind.init(rawValue:)),
              let retention = row.string("retention_state").flatMap(RetentionState.init(rawValue:)),
              let title = row.string("title"),
              let created = parseDate(row.string("created_at")),
              let updated = parseDate(row.string("updated_at")) else { return nil }
        return SavedItem(
            id: id,
            kind: kind,
            kindOrigin: FieldOrigin(rawValue: row.string("kind_origin") ?? "") ?? .captured,
            retention: retention,
            originalURL: row.string("original_url"),
            title: title,
            titleOrigin: FieldOrigin(rawValue: row.string("title_origin") ?? "") ?? .captured,
            summary: row.string("description"),
            summaryOrigin: row.string("description_origin").flatMap(FieldOrigin.init(rawValue:)),
            note: row.string("note"),
            author: row.string("author"),
            filename: row.string("filename"),
            sourceDomain: row.string("source_domain"),
            favorite: row.int("favorite") == 1,
            previewState: PreviewState(rawValue: row.string("preview_state") ?? "") ?? .none,
            trashedAt: parseDate(row.string("trashed_at")),
            createdAt: created,
            updatedAt: updated,
            tags: [],
            shelves: [],
            assets: []
        )
    }

    func writeSearch(id: String) throws {
        try db.execute("DELETE FROM search_documents WHERE item_id = ?", [.text(id)])
        guard let item = try hydrate(ids: [id]).first, item.trashedAt == nil else { return }
        try db.execute("""
        INSERT INTO search_documents(title, url, domain, description, filename, note, tags, author, excerpt, item_id)
        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            .text(item.title),
            .text(item.originalURL ?? ""),
            .text(item.sourceDomain ?? ""),
            .text(item.kind == .excerpt ? "" : (item.summary ?? "")),
            .text(item.filename ?? ""),
            .text(item.note ?? ""),
            .text(item.confirmedTags.map(\.label).joined(separator: " ")),
            .text(item.author ?? ""),
            .text(item.kind == .excerpt ? (item.summary ?? "") : ""),
            .text(id),
        ])
    }

    func loadShelves() throws -> [Shelf] {
        try db.query("""
        SELECT shelves.id, shelves.name, shelves.sort_order, COUNT(items.id) AS n
        FROM shelves
        LEFT JOIN item_shelves ON item_shelves.shelf_id = shelves.id
        LEFT JOIN items ON items.id = item_shelves.item_id AND items.trashed_at IS NULL
        GROUP BY shelves.id
        ORDER BY shelves.sort_order ASC
        """).compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)) else { return nil }
            return Shelf(id: id, name: row.string("name") ?? "", sortOrder: row.int("sort_order"), itemCount: row.int("n"))
        }
    }

    private func replay(_ row: SQLRow) throws -> CaptureResult {
        let status = CaptureStatus(rawValue: row.string("status") ?? "") ?? .failed
        let itemID = row.string("item_id").flatMap(UUID.init(uuidString:))
        let retention = row.string("retention_state").flatMap(RetentionState.init(rawValue:))
        if status == .saved || status == .alreadySaved {
            if let itemID, try hydrate(ids: [key(itemID)]).isEmpty {
                return .failed("Not saved. That earlier save was deleted.")
            }
        }
        let message: String
        switch status {
        case .saved: message = retention == .savedExcerpt ? "Excerpt saved." : retention == .copiedImage ? "Image copied." : retention == .copiedPDF ? "PDF copied." : "Saved."
        case .alreadySaved: message = "Already in your library."
        case .undone: message = "That save was undone."
        case .failed: message = "Not saved, retry needed."
        case .pending: message = "Waiting for My Mind to finish saving."
        }
        return CaptureResult(status: status, itemID: itemID, retention: retention, warnings: [], message: message)
    }

    private func writeReceipt(_ request: CaptureRequest, itemID: String, status: CaptureStatus, retention: RetentionState) throws {
        try db.execute("""
        INSERT INTO capture_receipts(request_id, schema_version, origin, item_id, status, retention_state, created_at)
        VALUES(?, ?, ?, ?, ?, ?, ?)
        """, [
            .text(key(request.requestID)), .int(Int64(request.schemaVersion)), .text(request.origin),
            .text(itemID), .text(status.rawValue), .text(retention.rawValue), .text(stamp(Date())),
        ])
        if request.file == nil, let data = try? JSONEncoder().encode(CapturePayload(request)), let json = String(data: data, encoding: .utf8) {
            try db.execute(
                "INSERT OR REPLACE INTO capture_payloads(request_id, payload) VALUES(?, ?)",
                [.text(key(request.requestID)), .text(json)]
            )
        }
    }

    private func applyUserTags(_ labels: [String], itemID: String, domain: String? = nil) throws {
        for label in labels {
            guard let display = TagText.display(for: label), let normalized = TagText.normalize(label) else { continue }
            try upsertTag(itemID: itemID, display: display, normalized: normalized, status: "confirmed", origin: "user")
            if let domain {
                try rememberTag(domain: domain, display: display, normalized: normalized)
            }
        }
    }

    func suggest(title: String, description: String?, excerpt: String?, itemID: String, domain: String? = nil) throws {
        let extras = try rememberedSuggestions(title: title, domain: domain)
        for label in TagSuggestions.suggest(title: title, description: description, excerpt: excerpt, extras: extras) {
            guard let display = TagText.display(for: label), let normalized = TagText.normalize(label) else { continue }
            try upsertTag(itemID: itemID, display: display, normalized: normalized, status: "suggested", origin: "suggestion", onlyIfMissing: true)
        }
    }

    func upsertTag(itemID: String, display: String, normalized: String, status: String, origin: String, onlyIfMissing: Bool = false) throws {
        let existing = try db.query("SELECT id FROM tags WHERE normalized_name = ?", [.text(normalized)]).first?.string("id")
        let tagID = existing ?? uid()
        if existing == nil {
            try db.execute("INSERT INTO tags(id, normalized_name, display_label) VALUES(?, ?, ?)", [.text(tagID), .text(normalized), .text(display)])
        }
        let link = try db.query("SELECT status FROM item_tags WHERE item_id = ? AND tag_id = ?", [.text(itemID), .text(tagID)]).first
        if link != nil {
            if onlyIfMissing { return }
            if link?.string("status") == "rejected" && status == "suggested" { return }
            try db.execute("UPDATE item_tags SET status = ?, origin = ? WHERE item_id = ? AND tag_id = ?", [
                .text(status), .text(origin), .text(itemID), .text(tagID),
            ])
        } else {
            try db.execute("INSERT INTO item_tags(item_id, tag_id, origin, status) VALUES(?, ?, ?, ?)", [
                .text(itemID), .text(tagID), .text(origin), .text(status),
            ])
        }
    }

    private func assignShelf(_ name: String?, itemID: String) throws {
        guard let cleaned = name?.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty else { return }
        let shelf = try createShelfUnlocked(name: cleaned)
        try db.execute("INSERT OR IGNORE INTO item_shelves(item_id, shelf_id) VALUES(?, ?)", [.text(itemID), .text(key(shelf.id))])
    }

    private func createShelfUnlocked(name: String) throws -> Shelf {
        if let existing = try loadShelves().first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let id = uid()
        let order = (try db.query("SELECT COALESCE(MAX(sort_order), 0) AS n FROM shelves").first?.int("n") ?? 0) + 1
        try db.execute("INSERT INTO shelves(id, name, sort_order, created_at) VALUES(?, ?, ?, ?)", [
            .text(id), .text(name), .int(Int64(order)), .text(stamp(Date())),
        ])
        return Shelf(id: UUID(uuidString: id)!, name: name, sortOrder: order, itemCount: 0)
    }

    func stage(data: Data, folder: String) throws -> (id: String, relative: String, hash: String) {
        let id = uid()
        let relative = "\(folder)/\(id)"
        let staging = rootURL.appendingPathComponent("staging/\(id)")
        try data.write(to: staging, options: .atomic)
        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        try FileManager.default.moveItem(at: staging, to: rootURL.appendingPathComponent(relative))
        return (id, relative, hash)
    }

    func hardDelete(id: String) throws {
        try db.execute("DELETE FROM item_tags WHERE item_id = ?", [.text(id)])
        try db.execute("DELETE FROM item_shelves WHERE item_id = ?", [.text(id)])
        try db.execute("DELETE FROM assets WHERE item_id = ?", [.text(id)])
        try db.execute("DELETE FROM enrichment_jobs WHERE item_id = ?", [.text(id)])
        try db.execute("DELETE FROM search_documents WHERE item_id = ?", [.text(id)])
        try db.execute("DELETE FROM items WHERE id = ?", [.text(id)])
    }

    func requireItem(_ id: UUID) throws {
        let rows = try db.query("SELECT id FROM items WHERE id = ?", [.text(key(id))])
        if rows.isEmpty { throw LibraryError.notFound }
    }

    func sweepUnreferencedAssets() throws {
        let keep = Set(try db.query("SELECT relative_path FROM assets").compactMap { $0.string("relative_path") })
        let fileManager = FileManager.default
        for folder in ["assets/originals", "assets/previews"] {
            let directory = rootURL.appendingPathComponent(folder)
            let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where !keep.contains("\(folder)/\(file.lastPathComponent)") {
                try? fileManager.removeItem(at: file)
            }
        }
        let staging = rootURL.appendingPathComponent("staging")
        for file in (try? fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? [] {
            try? fileManager.removeItem(at: file)
        }
    }

    private func clippedTitle(_ raw: String?, fallback: String) -> String {
        let cleaned = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chosen = cleaned.isEmpty ? fallback : cleaned
        if chosen.isEmpty { return "Untitled" }
        return String(chosen.prefix(Limits.maxTitleCharacters))
    }

    private func emptyToNil(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

private extension Result where Success == URL, Failure == LibraryError {
    var failureResult: CaptureResult {
        if case .failure(let error) = self { return .failed(error.description) }
        return .failed("Not saved.")
    }
}
