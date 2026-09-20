import Foundation

/// Installs the native messaging host that lets Chromium browsers save into the same local library
/// Safari uses. Chrome only looks for hosts inside its own support folder, so one small JSON file
/// has to be written per browser. Nothing here touches the library itself.
public enum ChromeSupport {
    public static let hostName = "com.charlesbonetti.stowmark.extension"
    /// Pinned by the `key` field in ChromeExtension/manifest.json, so an unpacked build keeps one ID.
    public static let pinnedExtensionID = "jeojfcmnpaachoikepjbbglnnilhbjgi"
    /// Filled in after the Chrome Web Store assigns an ID on first upload.
    private static let storeIDKey = "chromeStoreExtensionID"

    public struct Browser: Identifiable, Sendable {
        public var id: String { name }
        public var name: String
        /// Relative to the real home directory, not the sandbox container.
        public var relativeSupportPath: String

        public var hostsDirectory: URL {
            realHome.appendingPathComponent(relativeSupportPath, isDirectory: true)
                .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
        }

        public var manifestURL: URL {
            hostsDirectory.appendingPathComponent("\(ChromeSupport.hostName).json", isDirectory: false)
        }

        /// The browser's profile folder exists once it has been run at least once.
        public var isPresent: Bool {
            FileManager.default.fileExists(
                atPath: realHome.appendingPathComponent(relativeSupportPath, isDirectory: true).path
            )
        }

        public var isInstalled: Bool {
            FileManager.default.fileExists(atPath: manifestURL.path)
        }
    }

    public static let browsers: [Browser] = [
        Browser(name: "Chrome", relativeSupportPath: "Library/Application Support/Google/Chrome"),
        Browser(name: "Chrome Beta", relativeSupportPath: "Library/Application Support/Google/Chrome Beta"),
        Browser(name: "Chrome Canary", relativeSupportPath: "Library/Application Support/Google/Chrome Canary"),
        Browser(name: "Chromium", relativeSupportPath: "Library/Application Support/Chromium"),
        Browser(name: "Brave", relativeSupportPath: "Library/Application Support/BraveSoftware/Brave-Browser"),
        Browser(name: "Edge", relativeSupportPath: "Library/Application Support/Microsoft Edge"),
        Browser(name: "Vivaldi", relativeSupportPath: "Library/Application Support/Vivaldi"),
        Browser(name: "Arc", relativeSupportPath: "Library/Application Support/Arc/User Data"),
    ]

    /// The sandbox rewrites `NSHomeDirectory()` to the container, but the temporary exception in
    /// Stowmark.entitlements is relative to the account's real home.
    private static var realHome: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    public static var storeExtensionID: String {
        get { UserDefaults.standard.string(forKey: storeIDKey) ?? "" }
        set {
            let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            UserDefaults.standard.set(cleaned, forKey: storeIDKey)
        }
    }

    /// Chrome matches the caller against this list, so an unknown extension cannot reach the library.
    public static var allowedOrigins: [String] {
        var ids = [pinnedExtensionID]
        let store = storeExtensionID
        if !store.isEmpty, store != pinnedExtensionID { ids.append(store) }
        return ids.map { "chrome-extension://\($0)/" }
    }

    /// The helper ships inside the app bundle, so the path follows the app wherever it is installed.
    /// It is a background-only bundle because a sandboxed process needs a bundle identity.
    /// `Bundle.main` is the app for the app itself and a helper directory for the bundled tool, so
    /// the enclosing `.app` is found by walking up.
    public static var hostExecutable: URL? {
        let relative = "Contents/Helpers/StowmarkChromeHost.app/Contents/MacOS/StowmarkChromeHost"
        var candidates: [URL] = []
        var base = Bundle.main.bundleURL
        while base.path != "/" {
            if base.pathExtension == "app" {
                candidates.append(base.appendingPathComponent(relative, isDirectory: false))
            }
            base = base.deletingLastPathComponent()
        }
        if let confirmed = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return confirmed
        }
        // A sandboxed helper cannot read the app bundle that contains it, so fall back to the
        // outermost enclosing app without checking. Chrome reports a bad path clearly enough.
        return candidates.last
    }

    public struct InstallReport: Sendable {
        public var installed: [String] = []
        public var failed: [String: String] = [:]
        public var skipped: [String] = []

        public var summary: String {
            if installed.isEmpty && failed.isEmpty {
                return "No Chromium browser was found on this Mac. Install Chrome, then try again."
            }
            var parts: [String] = []
            if !installed.isEmpty {
                parts.append("Chrome capture installed for \(installed.joined(separator: ", ")).")
            }
            if !failed.isEmpty {
                let detail = failed.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "; ")
                parts.append("Not installed for \(detail)")
            }
            return parts.joined(separator: " ")
        }
    }

    /// Writes the host manifest for every Chromium browser that has been run on this Mac.
    public static func install() -> InstallReport {
        var report = InstallReport()
        guard let executable = hostExecutable else {
            report.failed["Stowmark"] = "the bundled host is missing, so this copy of the app cannot serve Chrome"
            return report
        }
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Stowmark capture host",
            "path": executable.path,
            "type": "stdio",
            "allowed_origins": allowedOrigins,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) else {
            report.failed["Stowmark"] = "the host manifest could not be written"
            return report
        }
        for browser in browsers {
            guard browser.isPresent else {
                report.skipped.append(browser.name)
                continue
            }
            do {
                try FileManager.default.createDirectory(at: browser.hostsDirectory, withIntermediateDirectories: true)
                try data.write(to: browser.manifestURL, options: .atomic)
                report.installed.append(browser.name)
            } catch {
                report.failed[browser.name] = error.localizedDescription
            }
        }
        return report
    }

    public static func remove() -> InstallReport {
        var report = InstallReport()
        for browser in browsers where browser.isInstalled {
            do {
                try FileManager.default.removeItem(at: browser.manifestURL)
                report.installed.append(browser.name)
            } catch {
                report.failed[browser.name] = error.localizedDescription
            }
        }
        return report
    }

    /// Browsers that have been run here, with whether the host is in place for each.
    public static func presentBrowsers() -> [(name: String, installed: Bool)] {
        browsers.filter(\.isPresent).map { ($0.name, $0.isInstalled) }
    }

    public static var storeListingURL: URL? {
        let id = storeExtensionID
        guard !id.isEmpty else { return nil }
        return URL(string: "https://chromewebstore.google.com/detail/\(id)")
    }
}
