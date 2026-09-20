import AppKit
import Foundation
import LibraryCore

/// Chrome native messaging host for Stowmark.
///
/// Chrome frames every message as a 4-byte native-endian length followed by UTF-8 JSON, on stdin
/// and stdout. Nothing else may reach stdout, or Chrome drops the connection. The messages
/// themselves are the same ones the Safari extension sends, so `CaptureMessageRouter` decides what
/// counts as saved.
///
/// Chrome passes the calling extension's origin as the first argument. The host manifest's
/// `allowed_origins` is what actually restricts callers, so the argument is only read for logging.
enum ChromeHost {
    static func main() {
        // Chrome only ever passes an origin, so a flag is unambiguous. Diagnostics go to stderr,
        // which Chrome logs and which can never corrupt the framed protocol on stdout.
        if CommandLine.arguments.contains("--diagnose") {
            diagnose()
            return
        }
        let router = CaptureMessageRouter(origin: "chrome") { url in
            NSWorkspace.shared.open(url)
        }
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput

        // `sendNativeMessage` delivers one message then closes. `connectNative` keeps the pipe open.
        while let message = readMessage(from: input) {
            let reply = router.respond(to: message)
            guard write(reply, to: output) else { break }
        }
    }

    private static func diagnose() {
        func say(_ line: String) { FileHandle.standardError.write(Data("\(line)\n".utf8)) }
        say("group id: \(StorageLocator.appGroupID)")
        for line in LibraryStore.extensionOpenDiagnosis() {
            say("  \(line)")
        }
        do {
            let store = try LibraryStore.openForExtension()
            say("save target: \(store.rootURL.path)")
        } catch {
            say("save target: unavailable, so saves hand off to the app (\(error))")
        }
    }

    private static func readMessage(from handle: FileHandle) -> [String: Any]? {
        guard let header = readExactly(4, from: handle) else { return nil }
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        // A wild length means a desynchronized pipe. Stop instead of allocating on a bad number.
        guard length > 0, length <= 64 * 1024 * 1024 else { return nil }
        guard let body = readExactly(Int(length), from: handle) else { return nil }
        guard let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return parsed
    }

    /// stdin is a pipe, so one read can return fewer bytes than asked for.
    private static func readExactly(_ count: Int, from handle: FileHandle) -> Data? {
        var collected = Data()
        while collected.count < count {
            guard let chunk = try? handle.read(upToCount: count - collected.count), !chunk.isEmpty else {
                return nil
            }
            collected.append(chunk)
        }
        return collected
    }

    private static func write(_ reply: [String: Any], to handle: FileHandle) -> Bool {
        guard let body = try? JSONSerialization.data(withJSONObject: reply) else { return false }
        var length = UInt32(body.count)
        var framed = Data(bytes: &length, count: 4)
        framed.append(body)
        do {
            try handle.write(contentsOf: framed)
            return true
        } catch {
            return false
        }
    }
}

ChromeHost.main()
