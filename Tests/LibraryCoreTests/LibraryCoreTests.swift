import XCTest
@testable import LibraryCore

final class LibraryCoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mymind-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore() throws -> LibraryStore {
        try LibraryStore(root: root)
    }

    func testArticleJourneySurvivesRestartSearchAndRestore() throws {
        let requestID = UUID()
        let first = try makeStore()
        let saved = try first.capture(CaptureRequest(
            requestID: requestID,
            captureKind: .page,
            pageURL: "https://Example.com/articles/Daylight?id=1#top",
            capturedTitle: "Daylight in the studio",
            note: "Keep the north window",
            tags: ["Workspace"],
            origin: "test"
        ))
        XCTAssertEqual(saved.status, .saved)
        XCTAssertEqual(saved.message, "Saved.")
        let replay = try first.capture(CaptureRequest(
            requestID: requestID,
            captureKind: .page,
            pageURL: "https://example.com/articles/Daylight?id=1#top",
            origin: "test"
        ))
        XCTAssertEqual(replay.status, .saved)
        XCTAssertEqual(replay.itemID, saved.itemID)

        let again = try LibraryStore(root: root)
        let found = try again.items(matching: {
            var query = LibraryQuery()
            query.text = "daylight"
            query.tagNames = ["workspace"]
            query.order = .relevance
            return query
        }())
        XCTAssertEqual(found.map(\.id), [saved.itemID])
        XCTAssertEqual(found.first?.note, "Keep the north window")
        guard let url = found.first?.originalURL, let parsed = URL(string: url) else {
            return XCTFail("Missing original URL")
        }
        XCTAssertEqual(parsed.fragment, "top")
        XCTAssertTrue(parsed.query?.contains("id=1") == true)

        let archive = root.appendingPathComponent("library.mymind")
        let summary = try again.exportArchive(to: archive)
        XCTAssertEqual(summary.itemCount, 1)
        let restoredRoot = root.appendingPathComponent("restored", isDirectory: true)
        try FileManager.default.createDirectory(at: restoredRoot, withIntermediateDirectories: true)
        let restored = try LibraryStore(root: restoredRoot)
        let restoredSummary = try restored.restoreArchive(from: archive, mode: .requireEmpty)
        XCTAssertEqual(restoredSummary.itemCount, 1)
        let after = try restored.items(matching: LibraryQuery())
        XCTAssertEqual(after.first?.title, "Daylight in the studio")
        XCTAssertEqual(after.first?.note, "Keep the north window")
        XCTAssertEqual(after.first?.confirmedTags.map(\.label), ["Workspace"])
    }

    func testDistinctExcerptsAndConservativeURLMatch() throws {
        let store = try makeStore()
        let page = "https://example.com/story?id=a"
        _ = try store.capture(CaptureRequest(captureKind: .page, pageURL: page, capturedTitle: "Story", origin: "test"))
        let first = try store.capture(CaptureRequest(captureKind: .selection, pageURL: page, capturedTitle: "Story", selectionText: "First passage.", origin: "test"))
        let second = try store.capture(CaptureRequest(captureKind: .selection, pageURL: page, capturedTitle: "Story", selectionText: "Second passage — “quoted”.", origin: "test"))
        XCTAssertEqual(first.status, .saved)
        XCTAssertEqual(second.status, .saved)
        XCTAssertNotEqual(first.itemID, second.itemID)
        let signed = try store.capture(CaptureRequest(captureKind: .link, targetURL: "https://example.com/story?id=b", capturedTitle: "Other", origin: "test"))
        XCTAssertEqual(signed.status, .saved)
        XCTAssertEqual(try store.counts().all, 4)
        let items = try store.items(matching: LibraryQuery())
        XCTAssertEqual(items.first { $0.id == second.itemID }?.summary, "Second passage — “quoted”.")
    }

    func testRejectsUnsafeInputAndKeepsLibraryOnFileFailure() throws {
        let store = try makeStore()
        let kept = try store.capture(CaptureRequest(captureKind: .link, targetURL: "https://example.com/keep", capturedTitle: "Keep", origin: "test"))
        XCTAssertEqual(try store.capture(CaptureRequest(captureKind: .link, targetURL: "javascript:alert(1)", origin: "test")).status, .failed)
        XCTAssertEqual(try store.capture(CaptureRequest(captureKind: .link, targetURL: "file:///etc/passwd", origin: "test")).status, .failed)
        let huge = CaptureFile(filename: "big.png", declaredMIME: "image/png", bytes: Data(count: Limits.maxAttachmentBytes + 1))
        let failed = try store.capture(CaptureRequest(captureKind: .image, origin: "test", file: huge))
        XCTAssertEqual(failed.status, .failed)
        XCTAssertTrue(failed.message.contains("100 MB"))
        XCTAssertEqual(try store.item(id: kept.itemID!)?.title, "Keep")
    }

    func testPrivateHostIsStoredButNotFetched() throws {
        XCTAssertTrue(URLSafety.isBlockedFetchTarget(URL(string: "http://127.0.0.1/admin")!))
        XCTAssertTrue(URLSafety.isBlockedFetchTarget(URL(string: "http://10.1.2.3/")!))
        XCTAssertTrue(URLSafety.isBlockedFetchTarget(URL(string: "http://192.168.1.9/")!))
        XCTAssertTrue(URLSafety.isPrivateIPString("172.16.4.4"))
        XCTAssertFalse(URLSafety.isPrivateIPString("8.8.8.8"))
        XCTAssertFalse(URLSafety.isBlockedFetchTarget(URL(string: "https://example.com/post")!))
        let store = try makeStore()
        let saved = try store.capture(CaptureRequest(captureKind: .link, targetURL: "http://127.0.0.1/notes", capturedTitle: "Local", origin: "test"))
        XCTAssertEqual(saved.status, .saved)
        XCTAssertEqual(try store.item(id: saved.itemID!)?.previewState, .unavailable)
        XCTAssertTrue(try store.pendingEnrichmentJobs().isEmpty)
    }

    func testCopiedFileSurvivesSourceDeletionAndCacheClear() throws {
        let store = try makeStore()
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let source = root.appendingPathComponent("source.png")
        try png.write(to: source)
        let saved = try store.capture(CaptureRequest(
            captureKind: .image,
            capturedTitle: "Swatch",
            origin: "test",
            file: CaptureFile(filename: "source.png", declaredMIME: "image/png", bytes: png)
        ))
        try FileManager.default.removeItem(at: source)
        let item = try store.item(id: saved.itemID!)
        let stored = try Data(contentsOf: item!.originalAsset!.fileURL(in: store.rootURL))
        XCTAssertEqual(stored, png)
        XCTAssertEqual(item?.retention, .copiedImage)
        _ = try store.clearPreviewCache()
        XCTAssertEqual(try Data(contentsOf: item!.originalAsset!.fileURL(in: store.rootURL)), png)
    }

    func testShelfRemovalAndTrashDoNotDestroyTheWrongRecords() throws {
        let store = try makeStore()
        let shelf = try store.createShelf(name: "Reading")
        let saved = try store.capture(CaptureRequest(captureKind: .link, targetURL: "https://example.com/book", capturedTitle: "Book link", shelfName: "Reading", origin: "test"))
        try store.deleteShelf(id: shelf.id)
        XCTAssertEqual(try store.item(id: saved.itemID!)?.title, "Book link")
        XCTAssertTrue(try store.shelves().isEmpty)
        try store.trash(itemID: saved.itemID!)
        var query = LibraryQuery()
        query.text = "Book"
        query.order = .relevance
        XCTAssertTrue(try store.items(matching: query).isEmpty)
        try store.restoreItem(itemID: saved.itemID!)
        XCTAssertEqual(try store.items(matching: query).count, 1)
    }

    func testUserTitleWinsOverEnrichmentAndSearchFindsCafe() throws {
        let store = try makeStore()
        let saved = try store.capture(CaptureRequest(captureKind: .page, pageURL: "https://example.com/cafe", capturedTitle: "Café notes", origin: "test"))
        try store.updateTitle(itemID: saved.itemID!, title: "My title")
        try store.completeEnrichment(
            itemID: saved.itemID!,
            metadata: PageMetadata(title: "Replaced", description: "A design study", author: "Ada", imageURL: nil, openGraphType: "article"),
            preview: nil,
            previewFailed: true
        )
        let item = try store.item(id: saved.itemID!)
        XCTAssertEqual(item?.title, "My title")
        XCTAssertEqual(item?.summary, "A design study")
        XCTAssertEqual(item?.author, "Ada")
        XCTAssertTrue(item?.suggestedTags.contains { $0.label == "Design" } == true)
        var query = LibraryQuery()
        query.text = "cafe"
        query.order = .relevance
        XCTAssertEqual(try store.items(matching: query).first?.id, saved.itemID)
    }

    func testBookmarkImportPreviewsBeforeCommit() throws {
        let store = try makeStore()
        _ = try store.capture(CaptureRequest(captureKind: .link, targetURL: "https://example.com/known", capturedTitle: "Known", origin: "test"))
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
        <DT><H3>Recipes</H3>
        <DL><p>
        <DT><A HREF="https://example.com/known">Known</A>
        <DT><A HREF="https://example.com/new">New recipe</A>
        <DT><A HREF="javascript:void(0)">Bad</A>
        </DL><p>
        </DL>
        """.data(using: .utf8)!
        let plan = try store.planBookmarkImport(html)
        XCTAssertEqual(plan.readyCount, 1)
        XCTAssertEqual(plan.duplicateCount, 1)
        XCTAssertEqual(plan.unsupportedCount, 1)
        XCTAssertEqual(try store.counts().all, 1)
        let commit = try store.commitBookmarkImport(plan, createShelves: true)
        XCTAssertEqual(commit.saved, 1)
        XCTAssertEqual(try store.counts().all, 2)
        XCTAssertEqual(try store.shelves().map(\.name), ["Recipes"])
    }

    func testZeroResultsDoNotDeleteItems() throws {
        let store = try makeStore()
        _ = try store.capture(CaptureRequest(captureKind: .link, targetURL: "https://example.com/a", capturedTitle: "Alpha", tags: ["Design"], origin: "test"))
        var query = LibraryQuery()
        query.text = "missing"
        query.tagNames = ["Design"]
        query.order = .relevance
        XCTAssertTrue(try store.items(matching: query).isEmpty)
        XCTAssertEqual(try store.counts().all, 1)
    }

    func testRestoreRefusesNonEmptyLibrary() throws {
        let store = try makeStore()
        _ = try store.capture(CaptureRequest(captureKind: .link, targetURL: "https://example.com/a", capturedTitle: "Alpha", origin: "test"))
        let archive = root.appendingPathComponent("one.mymind")
        _ = try store.exportArchive(to: archive)
        _ = try store.capture(CaptureRequest(captureKind: .link, targetURL: "https://example.com/b", capturedTitle: "Beta", origin: "test"))
        XCTAssertThrowsError(try store.restoreArchive(from: archive, mode: .requireEmpty)) { error in
            XCTAssertEqual(error as? LibraryError, .libraryNotEmpty)
        }
        XCTAssertEqual(try store.counts().all, 2)
    }

    func testWikipediaBecomesArticleAndCoffeeIsSuggested() throws {
        let store = try makeStore()
        let saved = try store.capture(CaptureRequest(
            captureKind: .link,
            targetURL: "https://en.wikipedia.org/wiki/Espresso",
            capturedTitle: "Espresso",
            origin: "test"
        ))
        let item = try store.item(id: saved.itemID!)
        XCTAssertEqual(item?.kind, .article)
        XCTAssertTrue(item?.suggestedTags.contains { $0.label == "Coffee" } == true)
        let arxiv = try store.capture(CaptureRequest(
            captureKind: .link,
            targetURL: "https://arxiv.org/abs/2303.11366",
            capturedTitle: "A paper",
            origin: "test"
        ))
        XCTAssertEqual(try store.item(id: arxiv.itemID!)?.kind, .research)
    }

    func testUserKindAndTagsAreRememberedForTheNextSave() throws {
        let store = try makeStore()
        let first = try store.capture(CaptureRequest(
            captureKind: .link,
            targetURL: "https://example.com/one",
            capturedTitle: "One",
            origin: "test"
        ))
        try store.updateKind(itemID: first.itemID!, kind: .article)
        try store.addTag(itemID: first.itemID!, label: "Workspace")
        let second = try store.capture(CaptureRequest(
            captureKind: .link,
            targetURL: "https://example.com/two",
            capturedTitle: "Two",
            origin: "test"
        ))
        let item = try store.item(id: second.itemID!)
        XCTAssertEqual(item?.kind, .article)
        XCTAssertTrue(item?.suggestedTags.contains { $0.label == "Workspace" } == true)
    }

    func testPageMetadataReadsOgTagsAndRejectsChallengePages() {
        let html = """
        <html><head>
        <meta content="Learn to code" property="og:title">
        <meta property="og:description" content="Practice with real exercises.">
        <meta property="og:image" content="/og.png">
        </head></html>
        """
        let parsed = PageMetadataParser.parse(html: html, baseURL: URL(string: "https://exercism.org/")!)
        XCTAssertEqual(parsed.title, "Learn to code")
        XCTAssertEqual(parsed.description, "Practice with real exercises.")
        XCTAssertEqual(parsed.imageURL?.absoluteString, "https://exercism.org/og.png")
        XCTAssertTrue(ChallengePage.isChallenge("<title>Just a moment...</title><div class=\"cf-browser-verification\">"))
        XCTAssertTrue(ChallengePage.isChallengeTitle("Just a moment..."))
        XCTAssertFalse(ChallengePage.isChallengeTitle("Exercism"))
    }

    func testVerifiedReplicaDoesNotOverwriteALibraryWithItems() throws {
        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let destRoot = root.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
        let source = try LibraryStore(root: sourceRoot)
        let dest = try LibraryStore(root: destRoot)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let saved = try source.capture(CaptureRequest(
            captureKind: .image,
            capturedTitle: "Swatch",
            origin: "test",
            file: CaptureFile(filename: "swatch.png", declaredMIME: "image/png", bytes: png)
        ))
        XCTAssertEqual(saved.status, .saved)
        _ = try dest.capture(CaptureRequest(captureKind: .link, targetURL: "https://example.com/keep-me", capturedTitle: "Keep me", origin: "test"))

        XCTAssertThrowsError(try LibraryReplica.replicate(from: sourceRoot, to: destRoot)) { error in
            XCTAssertEqual(error as? LibraryError, .migration("The other library already has items, so it was left untouched."))
        }
        XCTAssertEqual(try dest.item(id: try dest.items(matching: LibraryQuery()).first!.id)?.title, "Keep me")
        XCTAssertEqual(try dest.counts().all, 1)
    }

    func testVerifiedReplicaCopiesItemsAndOriginals() throws {
        let sourceRoot = root.appendingPathComponent("source2", isDirectory: true)
        let destRoot = root.appendingPathComponent("empty-dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
        let source = try LibraryStore(root: sourceRoot)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let saved = try source.capture(CaptureRequest(
            captureKind: .image,
            capturedTitle: "Replica swatch",
            origin: "test",
            file: CaptureFile(filename: "swatch.png", declaredMIME: "image/png", bytes: png)
        ))
        try LibraryReplica.replicate(from: sourceRoot, to: destRoot)
        let copied = try LibraryStore(root: destRoot)
        XCTAssertEqual(try copied.counts().all, 1)
        let item = try copied.item(id: saved.itemID!)
        XCTAssertEqual(item?.title, "Replica swatch")
        XCTAssertEqual(try Data(contentsOf: item!.originalAsset!.fileURL(in: destRoot)), png)
        XCTAssertEqual(LibraryReplica.fingerprint(at: sourceRoot), LibraryReplica.fingerprint(at: destRoot))
    }

    func testReceiptReplayAndHandshakeStayPendingUntilSaved() throws {
        let store = try makeStore()
        let requestID = UUID()
        XCTAssertNil(try store.receipt(requestID: requestID))
        let pending = CaptureHandshake.pending(requestID: requestID)
        XCTAssertEqual(pending.status, .pending)
        CaptureHandshake.write(pending, requestID: requestID, roots: [root])
        XCTAssertEqual(CaptureHandshake.read(requestID: requestID, roots: [root])?.status, .pending)
        let saved = try store.capture(CaptureRequest(
            requestID: requestID,
            captureKind: .link,
            targetURL: "https://example.com/handoff",
            capturedTitle: "Handoff",
            origin: "safari"
        ))
        XCTAssertEqual(saved.status, .saved)
        XCTAssertEqual(try store.receipt(requestID: requestID)?.status, .saved)
        XCTAssertEqual(try store.receipt(requestID: requestID)?.itemID, saved.itemID)
    }

    func testSafariSaveWhileClosedIsAbsorbedIntoTheAppLibrary() throws {
        let support = root.appendingPathComponent("support", isDirectory: true)
        let shared = root.appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        let app = try LibraryStore(root: support)
        _ = try app.capture(CaptureRequest(captureKind: .link, targetURL: "https://example.com/already", capturedTitle: "Already here", origin: "test"))
        try LibraryReplica.replicate(from: support, to: shared)
        let safari = try LibraryStore(root: shared)
        let saved = try safari.capture(CaptureRequest(
            captureKind: .page,
            pageURL: "https://example.com/from-safari",
            capturedTitle: "Saved while closed",
            origin: "safari"
        ))
        XCTAssertEqual(saved.status, .saved)
        let absorbed = try app.absorbPayloads(from: safari)
        XCTAssertEqual(absorbed, 1)
        XCTAssertEqual(try app.counts().all, 2)
        let found = try app.items(matching: {
            var query = LibraryQuery()
            query.text = "while closed"
            query.order = .relevance
            return query
        }())
        XCTAssertEqual(found.first?.title, "Saved while closed")
        XCTAssertEqual(try app.absorbPayloads(from: safari), 0)
    }

    func testRenameReorderAndTagCountsSurviveRelaunch() throws {
        let store = try makeStore()
        let reading = try store.createShelf(name: "Reading")
        let later = try store.createShelf(name: "Later")
        try store.renameShelf(id: reading.id, name: "Now reading")
        XCTAssertThrowsError(try store.renameShelf(id: later.id, name: "now reading")) { error in
            guard let libraryError = error as? LibraryError, case .invalidFile = libraryError else {
                return XCTFail("Expected a duplicate-name error, got \(error)")
            }
        }
        XCTAssertThrowsError(try store.renameShelf(id: reading.id, name: " "))
        try store.reorderShelves([later.id, reading.id])

        let kept = try store.capture(CaptureRequest(
            captureKind: .link,
            targetURL: "https://example.com/kept",
            capturedTitle: "Kept",
            tags: ["Design"],
            origin: "test"
        ))
        XCTAssertEqual(kept.status, .saved)
        let discarded = try store.capture(CaptureRequest(
            captureKind: .link,
            targetURL: "https://example.com/discarded",
            capturedTitle: "Discarded",
            tags: ["Design", "Quiet"],
            origin: "test"
        ))
        try store.trash(itemID: discarded.itemID!)

        let reopened = try LibraryStore(root: root)
        XCTAssertEqual(try reopened.shelves().map(\.name), ["Later", "Now reading"])
        let counts = try reopened.allTags(withCounts: true)
        XCTAssertEqual(counts.map(\.label), ["Design"])
        XCTAssertEqual(counts.first?.count, 1)
        let unlabeled = try reopened.allTags(withCounts: false)
        XCTAssertEqual(unlabeled.map(\.label), ["Design"])
        XCTAssertEqual(unlabeled.first?.count, 0)
    }
}
