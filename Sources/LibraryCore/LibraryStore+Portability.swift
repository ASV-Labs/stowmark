import CryptoKit
import Foundation

public struct ImportCommit: Sendable, Equatable {
    public var saved: Int
    public var skipped: Int
    public var failed: Int
}

extension LibraryStore {
    public func exportArchive(to url: URL) throws -> ArchiveSummary {
        try sync {
            let items = try db.query("SELECT * FROM items")
            let tags = try db.query("SELECT * FROM tags")
            let itemTags = try db.query("SELECT * FROM item_tags")
            let shelves = try db.query("SELECT * FROM shelves")
            let memberships = try db.query("SELECT * FROM item_shelves")
            let assets = try db.query("SELECT * FROM assets WHERE role = 'original'")
            let receipts = try db.query("SELECT * FROM capture_receipts")
            let manifest = ArchiveManifest(
                schemaVersion: 1,
                exportedAt: stamp(Date()),
                items: items.map(ArchiveItem.init),
                tags: tags.map(ArchiveTag.init),
                itemTags: itemTags.map(ArchiveItemTag.init),
                shelves: shelves.map(ArchiveShelf.init),
                memberships: memberships.map(ArchiveMembership.init),
                assets: assets.map(ArchiveAsset.init),
                receipts: receipts.map(ArchiveReceipt.init)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var entries = [ZipArchive.Entry(name: "manifest.json", data: try encoder.encode(manifest))]
            for asset in manifest.assets {
                let data = try Data(contentsOf: rootURL.appendingPathComponent(asset.relativePath))
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard hash == asset.sha256 else {
                    throw LibraryError.archive("Refused to export \(asset.relativePath) because its checksum changed.")
                }
                entries.append(ZipArchive.Entry(name: "assets/\(asset.id)", data: data))
            }
            try ZipArchive.write(entries, to: url)
            return ArchiveSummary(itemCount: manifest.items.count, assetCount: manifest.assets.count)
        }
    }

    public func restoreArchive(from url: URL, mode: RestoreMode) throws -> ArchiveSummary {
        let entries = try ZipArchive.read(from: url)
        guard let manifestData = entries.first(where: { $0.name == "manifest.json" })?.data else {
            throw LibraryError.archive("That archive has no manifest.")
        }
        let manifest = try JSONDecoder().decode(ArchiveManifest.self, from: manifestData)
        guard manifest.schemaVersion == 1 else { throw LibraryError.unsupportedSchema }
        var files: [String: Data] = [:]
        for asset in manifest.assets {
            guard let data = entries.first(where: { $0.name == "assets/\(asset.id)" })?.data else {
                throw LibraryError.archive("The archive is missing a copied file for \(asset.id).")
            }
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard hash == asset.sha256, data.count == asset.byteCount else {
                throw LibraryError.archive("A copied file in the archive does not match its checksum.")
            }
            files[asset.id] = data
        }
        return try sync {
            let existing = try db.query("SELECT COUNT(*) AS n FROM items").first?.int("n") ?? 0
            if existing > 0 && mode == .requireEmpty { throw LibraryError.libraryNotEmpty }
            for (id, data) in files {
                guard let asset = manifest.assets.first(where: { $0.id == id }) else { continue }
                let destination = rootURL.appendingPathComponent(asset.relativePath)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
            }
            try transaction {
                if mode == .replace {
                    try db.execute("DELETE FROM item_tags")
                    try db.execute("DELETE FROM item_shelves")
                    try db.execute("DELETE FROM assets")
                    try db.execute("DELETE FROM enrichment_jobs")
                    try db.execute("DELETE FROM capture_receipts")
                    try db.execute("DELETE FROM search_documents")
                    try db.execute("DELETE FROM items")
                    try db.execute("DELETE FROM tags")
                    try db.execute("DELETE FROM shelves")
                }
                for tag in manifest.tags {
                    try db.execute("INSERT OR REPLACE INTO tags(id, normalized_name, display_label) VALUES(?, ?, ?)", [
                        .text(tag.id), .text(tag.normalizedName), .text(tag.displayLabel),
                    ])
                }
                for shelf in manifest.shelves {
                    try db.execute("INSERT OR REPLACE INTO shelves(id, name, sort_order, created_at) VALUES(?, ?, ?, ?)", [
                        .text(shelf.id), .text(shelf.name), .int(Int64(shelf.sortOrder)), .text(shelf.createdAt),
                    ])
                }
                for item in manifest.items {
                    try db.execute("""
                    INSERT OR REPLACE INTO items(id, kind, kind_origin, retention_state, original_url, match_key, title, title_origin,
                        description, description_origin, note, author, filename, source_domain, favorite, preview_state, trashed_at, created_at, updated_at)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [
                        .text(item.id), .text(item.kind), .text(item.kindOrigin), .text(item.retentionState),
                        item.originalURL.map(SQLBind.text) ?? .null, item.matchKey.map(SQLBind.text) ?? .null,
                        .text(item.title), .text(item.titleOrigin), item.description.map(SQLBind.text) ?? .null,
                        item.descriptionOrigin.map(SQLBind.text) ?? .null, item.note.map(SQLBind.text) ?? .null,
                        item.author.map(SQLBind.text) ?? .null, item.filename.map(SQLBind.text) ?? .null,
                        item.sourceDomain.map(SQLBind.text) ?? .null, .int(Int64(item.favorite)), .text(item.previewState),
                        item.trashedAt.map(SQLBind.text) ?? .null, .text(item.createdAt), .text(item.updatedAt),
                    ])
                }
                for link in manifest.itemTags {
                    try db.execute("INSERT OR REPLACE INTO item_tags(item_id, tag_id, origin, status) VALUES(?, ?, ?, ?)", [
                        .text(link.itemID), .text(link.tagID), .text(link.origin), .text(link.status),
                    ])
                }
                for membership in manifest.memberships {
                    try db.execute("INSERT OR REPLACE INTO item_shelves(item_id, shelf_id) VALUES(?, ?)", [
                        .text(membership.itemID), .text(membership.shelfID),
                    ])
                }
                for asset in manifest.assets {
                    try db.execute("""
                    INSERT OR REPLACE INTO assets(id, item_id, sha256, relative_path, mime_type, byte_count, role)
                    VALUES(?, ?, ?, ?, ?, ?, 'original')
                    """, [
                        .text(asset.id), .text(asset.itemID), .text(asset.sha256), .text(asset.relativePath),
                        asset.mimeType.map(SQLBind.text) ?? .null, .int(Int64(asset.byteCount)),
                    ])
                }
                for receipt in manifest.receipts {
                    try db.execute("""
                    INSERT OR REPLACE INTO capture_receipts(request_id, schema_version, origin, item_id, status, retention_state, created_at)
                    VALUES(?, ?, ?, ?, ?, ?, ?)
                    """, [
                        .text(receipt.requestID), .int(Int64(receipt.schemaVersion)), .text(receipt.origin),
                        receipt.itemID.map(SQLBind.text) ?? .null, .text(receipt.status),
                        receipt.retentionState.map(SQLBind.text) ?? .null, .text(receipt.createdAt),
                    ])
                }
                try db.execute("DELETE FROM search_documents")
            }
            let ids = try db.query("SELECT id FROM items WHERE trashed_at IS NULL").compactMap { $0.string("id") }
            for id in ids { try writeSearch(id: id) }
            try sweepUnreferencedAssets()
            return ArchiveSummary(itemCount: manifest.items.count, assetCount: manifest.assets.count)
        }
    }

    public func planBookmarkImport(_ data: Data) throws -> BookmarkImportPlan {
        let parsed = BookmarkHTML.parse(data)
        return try sync {
            var entries: [BookmarkEntry] = []
            for entry in parsed {
                let disposition: BookmarkDisposition
                if case .failure = URLSafety.captureURL(from: entry.url) {
                    disposition = .unsupported
                } else if case .success(let url) = URLSafety.captureURL(from: entry.url) {
                    let match = URLSafety.matchKey(for: url)
                    let existing = try db.query(
                        "SELECT id FROM items WHERE match_key = ? AND trashed_at IS NULL AND retention_state != 'savedExcerpt' LIMIT 1",
                        [.text(match)]
                    )
                    disposition = existing.isEmpty ? .ready : .duplicate
                } else {
                    disposition = .unsupported
                }
                entries.append(BookmarkEntry(url: entry.url, title: entry.title, folder: entry.folder, disposition: disposition))
            }
            let folders = Array(Set(entries.compactMap(\.folder))).sorted()
            return BookmarkImportPlan(
                entries: entries,
                folders: folders,
                readyCount: entries.filter { $0.disposition == .ready }.count,
                duplicateCount: entries.filter { $0.disposition == .duplicate }.count,
                unsupportedCount: entries.filter { $0.disposition == .unsupported }.count
            )
        }
    }

    public func commitBookmarkImport(_ plan: BookmarkImportPlan, createShelves: Bool) throws -> ImportCommit {
        var saved = 0
        var skipped = 0
        var failed = 0
        for entry in plan.entries where entry.disposition == .ready {
            let request = CaptureRequest(
                captureKind: .link,
                targetURL: entry.url,
                capturedTitle: entry.title,
                shelfName: createShelves ? entry.folder : nil,
                origin: "bookmark-import"
            )
            let result = try capture(request)
            switch result.status {
            case .saved: saved += 1
            case .alreadySaved: skipped += 1
            case .failed, .undone, .pending: failed += 1
            }
        }
        skipped += plan.entries.filter { $0.disposition == .duplicate }.count
        return ImportCommit(saved: saved, skipped: skipped, failed: failed)
    }
}

private struct ArchiveManifest: Codable {
    var schemaVersion: Int
    var exportedAt: String
    var items: [ArchiveItem]
    var tags: [ArchiveTag]
    var itemTags: [ArchiveItemTag]
    var shelves: [ArchiveShelf]
    var memberships: [ArchiveMembership]
    var assets: [ArchiveAsset]
    var receipts: [ArchiveReceipt]
}

private struct ArchiveItem: Codable {
    var id, kind, kindOrigin, retentionState, title, titleOrigin, previewState, createdAt, updatedAt: String
    var originalURL, matchKey, description, descriptionOrigin, note, author, filename, sourceDomain, trashedAt: String?
    var favorite: Int
    init(_ row: SQLRow) {
        id = row.string("id") ?? ""
        kind = row.string("kind") ?? "link"
        kindOrigin = row.string("kind_origin") ?? "captured"
        retentionState = row.string("retention_state") ?? "bookmark"
        title = row.string("title") ?? "Untitled"
        titleOrigin = row.string("title_origin") ?? "captured"
        previewState = row.string("preview_state") ?? "none"
        createdAt = row.string("created_at") ?? ""
        updatedAt = row.string("updated_at") ?? ""
        originalURL = row.string("original_url")
        matchKey = row.string("match_key")
        description = row.string("description")
        descriptionOrigin = row.string("description_origin")
        note = row.string("note")
        author = row.string("author")
        filename = row.string("filename")
        sourceDomain = row.string("source_domain")
        trashedAt = row.string("trashed_at")
        favorite = row.int("favorite")
    }
}

private struct ArchiveTag: Codable {
    var id, normalizedName, displayLabel: String
    init(_ row: SQLRow) {
        id = row.string("id") ?? ""
        normalizedName = row.string("normalized_name") ?? ""
        displayLabel = row.string("display_label") ?? ""
    }
}

private struct ArchiveItemTag: Codable {
    var itemID, tagID, origin, status: String
    init(_ row: SQLRow) {
        itemID = row.string("item_id") ?? ""
        tagID = row.string("tag_id") ?? ""
        origin = row.string("origin") ?? "user"
        status = row.string("status") ?? "confirmed"
    }
}

private struct ArchiveShelf: Codable {
    var id, name, createdAt: String
    var sortOrder: Int
    init(_ row: SQLRow) {
        id = row.string("id") ?? ""
        name = row.string("name") ?? ""
        createdAt = row.string("created_at") ?? ""
        sortOrder = row.int("sort_order")
    }
}

private struct ArchiveMembership: Codable {
    var itemID, shelfID: String
    init(_ row: SQLRow) {
        itemID = row.string("item_id") ?? ""
        shelfID = row.string("shelf_id") ?? ""
    }
}

private struct ArchiveAsset: Codable {
    var id, itemID, sha256, relativePath: String
    var mimeType: String?
    var byteCount: Int
    init(_ row: SQLRow) {
        id = row.string("id") ?? ""
        itemID = row.string("item_id") ?? ""
        sha256 = row.string("sha256") ?? ""
        relativePath = row.string("relative_path") ?? ""
        mimeType = row.string("mime_type")
        byteCount = row.int("byte_count")
    }
}

private struct ArchiveReceipt: Codable {
    var requestID, origin, status, createdAt: String
    var schemaVersion: Int
    var itemID, retentionState: String?
    init(_ row: SQLRow) {
        requestID = row.string("request_id") ?? ""
        origin = row.string("origin") ?? ""
        status = row.string("status") ?? ""
        createdAt = row.string("created_at") ?? ""
        schemaVersion = row.int("schema_version")
        itemID = row.string("item_id")
        retentionState = row.string("retention_state")
    }
}
