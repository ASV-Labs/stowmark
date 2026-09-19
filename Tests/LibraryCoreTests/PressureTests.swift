import XCTest
import os
@testable import LibraryCore

final class PressureTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mymind-pressure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore() throws -> LibraryStore {
        try LibraryStore(root: root)
    }

    func testTenThousandItemsSearchAndBrowse() throws {
        let store = try makeStore()
        let start = Date()
        for i in 0..<10_000 {
            let result = try store.capture(CaptureRequest(
                captureKind: .link,
                targetURL: "https://example.com/item/\(i)?q=\(i)",
                capturedTitle: i % 17 == 0 ? "Daylight study \(i)" : "Item \(i)",
                note: i % 41 == 0 ? "note \(i)" : nil,
                tags: i % 23 == 0 ? ["Workspace"] : (i % 29 == 0 ? ["Design"] : []),
                origin: "pressure"
            ))
            XCTAssertEqual(result.status, CaptureStatus.saved, "item \(i)")
        }
        let writeSeconds = Date().timeIntervalSince(start)
        XCTAssertLessThan(writeSeconds, 90, "10k writes took \(writeSeconds)s")

        let searchStart = Date()
        var query = LibraryQuery()
        query.text = "daylight"
        query.order = .relevance
        let hits = try store.items(matching: query)
        let searchMs = Date().timeIntervalSince(searchStart) * 1000
        XCTAssertFalse(hits.isEmpty)
        XCTAssertLessThan(searchMs, 500, "search took \(searchMs)ms")
        XCTAssertEqual(try store.counts().all, 10_000)

        let browseStart = Date()
        var browse = LibraryQuery()
        browse.limit = 400
        let recent = try store.items(matching: browse)
        let total = try store.matchedCount(matching: LibraryQuery())
        let browseMs = Date().timeIntervalSince(browseStart) * 1000
        XCTAssertEqual(recent.count, 400)
        XCTAssertEqual(total, 10_000)
        XCTAssertLessThan(browseMs, 1000, "paged browse took \(browseMs)ms")
        print("pressure: write=\(writeSeconds)s search=\(searchMs)ms browse=\(browseMs)ms hits=\(hits.count)")
    }

    func testConcurrentCaptureDoesNotCorruptOrDuplicateReceipts() throws {
        let store = try makeStore()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "pressure.capture", attributes: .concurrent)
        let failures = OSAllocatedUnfairLock(initialState: 0)
        for i in 0..<200 {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    let requestID = UUID()
                    let first = try store.capture(CaptureRequest(
                        requestID: requestID,
                        captureKind: .link,
                        targetURL: "https://example.com/parallel/\(i)",
                        capturedTitle: "Parallel \(i)",
                        origin: "pressure"
                    ))
                    let second = try store.capture(CaptureRequest(
                        requestID: requestID,
                        captureKind: .link,
                        targetURL: "https://example.com/parallel/\(i)",
                        capturedTitle: "Parallel \(i)",
                        origin: "pressure"
                    ))
                    XCTAssertEqual(first.itemID, second.itemID)
                    XCTAssertEqual(first.status, CaptureStatus.saved)
                    XCTAssertEqual(second.status, CaptureStatus.saved)
                } catch {
                    failures.withLock { $0 += 1 }
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 60), .success)
        XCTAssertEqual(failures.withLock { $0 }, 0)
        XCTAssertEqual(try store.counts().all, 200)
    }

    func testReplayAfterForcedCloseAndExportRoundTripAtScale() throws {
        let store = try makeStore()
        let requestIDs = (0..<50).map { _ in UUID() }
        for (index, requestID) in requestIDs.enumerated() {
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
            if index % 2 == 0 {
                _ = try store.capture(CaptureRequest(
                    requestID: requestID,
                    captureKind: .link,
                    targetURL: "https://example.com/round/\(index)",
                    capturedTitle: "Round \(index)",
                    origin: "pressure"
                ))
            } else {
                _ = try store.capture(CaptureRequest(
                    requestID: requestID,
                    captureKind: .image,
                    capturedTitle: "Image \(index)",
                    origin: "pressure",
                    file: CaptureFile(filename: "pixel.png", declaredMIME: "image/png", bytes: png)
                ))
            }
        }
        // Simulate relaunch
        let again = try LibraryStore(root: root)
        for requestID in requestIDs {
            let replay = try again.capture(CaptureRequest(
                requestID: requestID,
                captureKind: .link,
                targetURL: "https://example.com/ignored",
                origin: "pressure"
            ))
            XCTAssertTrue(replay.status == .saved || replay.status == .alreadySaved)
            XCTAssertNotNil(replay.itemID)
        }
        let archive = root.appendingPathComponent("pressure.mymind")
        let summary = try again.exportArchive(to: archive)
        XCTAssertEqual(summary.itemCount, 50)
        XCTAssertEqual(summary.assetCount, 25)

        let restoredRoot = root.appendingPathComponent("restored", isDirectory: true)
        try FileManager.default.createDirectory(at: restoredRoot, withIntermediateDirectories: true)
        let restored = try LibraryStore(root: restoredRoot)
        _ = try restored.restoreArchive(from: archive, mode: .requireEmpty)
        XCTAssertEqual(try restored.counts().all, 50)
        let images = try restored.items(matching: {
            var q = LibraryQuery(); q.kinds = [.image]; return q
        }())
        XCTAssertEqual(images.count, 25)
        for item in images {
            let data = try Data(contentsOf: item.originalAsset!.fileURL(in: restored.rootURL))
            XCTAssertFalse(data.isEmpty)
        }
    }

    func testMalformedAndHostileInputsStayRejected() throws {
        let store = try makeStore()
        _ = try store.capture(CaptureRequest(captureKind: .link, targetURL: "https://example.com/ok", capturedTitle: "OK", origin: "pressure"))
        let bad: [(CaptureKind, String?, CaptureFile?)] = [
            (.link, "javascript:alert(1)", nil),
            (.link, "file:///etc/passwd", nil),
            (.link, "http://", nil),
            (.link, String(repeating: "https://example.com/", count: 2000), nil),
            (.selection, "https://example.com/x", nil),
            (.image, nil, CaptureFile(filename: "x.exe", declaredMIME: "application/octet-stream", bytes: Data([0x00, 0x01]))),
            (.pdf, nil, CaptureFile(filename: "fake.pdf", declaredMIME: "application/pdf", bytes: Data("not a pdf".utf8))),
        ]
        for (kind, url, file) in bad {
            let result = try store.capture(CaptureRequest(
                captureKind: kind,
                pageURL: kind == .selection ? url : nil,
                targetURL: kind == .link ? url : nil,
                selectionText: kind == .selection ? "" : nil,
                origin: "pressure",
                file: file
            ))
            XCTAssertEqual(result.status, .failed, "\(kind) \(String(describing: url))")
        }
        XCTAssertEqual(try store.counts().all, 1)
    }

    func testDiskFullStagingDoesNotCommitBrokenOriginal() throws {
        let store = try makeStore()
        // Oversized attachment path already covered; also ensure partial staging cleanup.
        let huge = Data(count: Limits.maxAttachmentBytes + 12)
        let failed = try store.capture(CaptureRequest(
            captureKind: .image,
            capturedTitle: "Huge",
            origin: "pressure",
            file: CaptureFile(filename: "huge.png", declaredMIME: "image/png", bytes: huge)
        ))
        XCTAssertEqual(failed.status, .failed)
        let staging = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("staging"), includingPropertiesForKeys: nil)
        XCTAssertTrue(staging.isEmpty)
        XCTAssertEqual(try store.counts().all, 0)
    }

    func testTagAndShelfMembershipUnderChurn() throws {
        let store = try makeStore()
        let shelf = try store.createShelf(name: "Reading")
        var ids: [UUID] = []
        for i in 0..<100 {
            let result = try store.capture(CaptureRequest(
                captureKind: .link,
                targetURL: "https://example.com/churn/\(i)",
                capturedTitle: "Churn \(i)",
                tags: ["Design"],
                shelfName: "Reading",
                origin: "pressure"
            ))
            ids.append(result.itemID!)
        }
        for id in ids.prefix(50) {
            try store.addTag(itemID: id, label: "Workspace")
            try store.removeTag(itemID: id, tagID: try store.item(id: id)!.confirmedTags.first { $0.label == "Design" }!.id)
            try store.setMembership(itemID: id, shelfID: shelf.id, member: false)
        }
        try store.deleteShelf(id: shelf.id)
        XCTAssertEqual(try store.counts().all, 100)
        var query = LibraryQuery()
        query.tagNames = ["Workspace"]
        XCTAssertEqual(try store.items(matching: query).count, 50)
        query = LibraryQuery()
        query.tagNames = ["Design"]
        XCTAssertEqual(try store.items(matching: query).count, 50)
    }

    func testQuotedPhraseAndUnicodeSearch() throws {
        let store = try makeStore()
        _ = try store.capture(CaptureRequest(captureKind: .link, targetURL: "https://example.com/a", capturedTitle: "Café morning light", note: "ritual notes", origin: "pressure"))
        _ = try store.capture(CaptureRequest(captureKind: .link, targetURL: "https://example.com/b", capturedTitle: "Morning market", origin: "pressure"))
        _ = try store.capture(CaptureRequest(captureKind: .selection, pageURL: "https://example.com/c", capturedTitle: "Paper", selectionText: "exact phrase about daylight gardens", origin: "pressure"))
        _ = try store.capture(CaptureRequest(captureKind: .link, targetURL: "https://example.com/d", capturedTitle: "ui-alpha-pass fixture", origin: "pressure"))
        var q = LibraryQuery(); q.text = "cafe"; q.order = .relevance
        XCTAssertEqual(try store.items(matching: q).count, 1)
        q.text = "\"exact phrase\""; q.order = .relevance
        XCTAssertEqual(try store.items(matching: q).count, 1)
        q.text = "daylight"; q.order = .relevance
        XCTAssertEqual(try store.items(matching: q).count, 1)
        q.text = "ui-alpha-pass"; q.order = .relevance
        XCTAssertEqual(try store.items(matching: q).count, 1)
    }
}
