import Foundation
import LibraryCore

@main
struct CardfileTool {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard let command = args.first else {
                printUsage()
                exit(2)
            }

            // These run before the library is opened, because they are about browser wiring.
            switch command {
            case "chrome-install":
                let report = ChromeSupport.install()
                print(report.summary)
                if let host = ChromeSupport.hostExecutable { print("host=\(host.path)") }
                print("origins=\(ChromeSupport.allowedOrigins.joined(separator: " "))")
                exit(report.failed.isEmpty ? 0 : 1)
            case "chrome-status":
                print("bundle=\(Bundle.main.bundleURL.path)")
                print("host=\(ChromeSupport.hostExecutable?.path ?? "missing")")
                for browser in ChromeSupport.presentBrowsers() {
                    print("\(browser.name)\t\(browser.installed ? "ready" : "not installed")")
                }
                for line in LibraryStore.extensionOpenDiagnosis() { print(line) }
                exit(0)
            case "chrome-remove":
                let report = ChromeSupport.remove()
                print(report.installed.isEmpty ? "nothing to remove" : "removed for \(report.installed.joined(separator: ", "))")
                exit(report.failed.isEmpty ? 0 : 1)
            default:
                break
            }

            let store = try LibraryStore.openLive()
            switch command {
            case "status":
                let counts = try store.counts()
                print("items=\(counts.all) favorites=\(counts.favorites) trash=\(counts.trash) shared=\(store.usesSharedContainer) root=\(store.rootURL.path)")
            case "save":
                guard args.count >= 2 else { printUsage(); exit(2) }
                let url = args[1]
                let title = args.count >= 3 ? args[2] : nil
                let result = try store.capture(CaptureRequest(
                    captureKind: .page,
                    pageURL: url,
                    targetURL: url,
                    capturedTitle: title,
                    origin: "cli"
                ))
                print("\(result.status.rawValue)\t\(result.message)\t\(result.itemID?.uuidString ?? "-")")
                exit(result.status == .failed ? 1 : 0)
            case "search":
                let text = args.dropFirst().joined(separator: " ")
                var query = LibraryQuery()
                query.text = text
                query.order = .relevance
                query.limit = 50
                let items = try store.items(matching: query)
                let total = try store.matchedCount(matching: query)
                print("matched=\(total) showing=\(items.count)")
                for item in items {
                    print("\(item.id.uuidString)\t\(item.kind.rawValue)\t\(item.title)\t\(item.sourceLabel)")
                }
            case "seed":
                let count = Int(args.dropFirst().first ?? "100") ?? 100
                let start = Date()
                for i in 0..<count {
                    _ = try store.capture(CaptureRequest(
                        captureKind: .link,
                        targetURL: "https://example.com/seed/\(UUID().uuidString)/\(i)",
                        capturedTitle: i % 11 == 0 ? "Alpha seed \(i)" : "Seed item \(i)",
                        tags: i % 7 == 0 ? ["Workspace"] : [],
                        origin: "cli-seed"
                    ))
                }
                print("seeded=\(count) seconds=\(String(format: "%.2f", Date().timeIntervalSince(start)))")
            case "export":
                guard args.count >= 2 else { printUsage(); exit(2) }
                let url = URL(fileURLWithPath: args[1])
                let summary = try store.exportArchive(to: url)
                print("exported items=\(summary.itemCount) assets=\(summary.assetCount) path=\(url.path)")
            case "pressure":
                try await runPressure(store: store)
            default:
                printUsage()
                exit(2)
            }
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func runPressure(store: LibraryStore) async throws {
        var failures: [String] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if ok {
                print("PASS \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            } else {
                print("FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
                failures.append(name)
            }
        }

        let stamp = UUID().uuidString.lowercased()
        let requestID = UUID()
        let saved = try store.capture(CaptureRequest(
            requestID: requestID,
            captureKind: .page,
            pageURL: "https://example.com/pressure-live/\(stamp)",
            capturedTitle: "Pressure live article \(stamp)",
            note: "alpha note",
            tags: ["Workspace"],
            origin: "pressure-live"
        ))
        check("save", saved.status == .saved, saved.message)

        let replay = try store.capture(CaptureRequest(
            requestID: requestID,
            captureKind: .page,
            pageURL: "https://example.com/pressure-live/\(stamp)",
            origin: "pressure-live"
        ))
        check("idempotent-replay", replay.itemID == saved.itemID && replay.status == .saved)

        var query = LibraryQuery()
        query.text = stamp
        query.tagNames = ["Workspace"]
        query.order = .relevance
        let hits = try store.items(matching: query)
        check("search", hits.contains { $0.id == saved.itemID })

        let hostile = try store.capture(CaptureRequest(
            captureKind: .link,
            targetURL: "javascript:alert(1)",
            origin: "pressure-live"
        ))
        check("reject-javascript", hostile.status == .failed)

        let privateHost = try store.capture(CaptureRequest(
            captureKind: .link,
            targetURL: "http://127.0.0.1/secret/\(stamp)",
            capturedTitle: "Loopback \(stamp)",
            origin: "pressure-live"
        ))
        check("private-bookmark", privateHost.status == .saved)
        if let id = privateHost.itemID, let item = try store.item(id: id) {
            check("private-no-fetch", item.previewState == .unavailable)
        } else {
            check("private-no-fetch", false, "missing item")
        }

        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("cardfile-pressure-\(UUID().uuidString).cardfile")
        let summary = try store.exportArchive(to: archive)
        check("export", summary.itemCount >= 1, "items=\(summary.itemCount)")

        let seedCount = 500
        let seedStart = Date()
        for i in 0..<seedCount {
            _ = try store.capture(CaptureRequest(
                captureKind: .link,
                targetURL: "https://example.com/live-seed/\(UUID().uuidString)",
                capturedTitle: "Live seed \(i)",
                origin: "pressure-live"
            ))
        }
        let seedSeconds = Date().timeIntervalSince(seedStart)
        check("seed-500", seedSeconds < 20, String(format: "%.2fs", seedSeconds))

        var page = LibraryQuery()
        page.limit = 400
        let pageStart = Date()
        let pageItems = try store.items(matching: page)
        let pageMs = Date().timeIntervalSince(pageStart) * 1000
        check("paged-browse", pageItems.count == 400 && pageMs < 1000, String(format: "%.1fms", pageMs))

        if failures.isEmpty {
            print("PRESSURE OK")
            exit(0)
        } else {
            print("PRESSURE FAILED: \(failures.joined(separator: ", "))")
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        CardfileTool status|save <url> [title]|search <query>|seed [count]|export <path>|pressure
        CardfileTool chrome-install|chrome-status|chrome-remove
        """)
    }
}
