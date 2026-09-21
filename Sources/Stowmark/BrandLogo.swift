import AppKit
import SwiftUI

/// Horizontal icon + wordmark. Picks the light or dark PNG from the app bundle.
struct BrandLogo: View {
    @Environment(\.colorScheme) private var scheme
    var height: CGFloat = 28

    var body: some View {
        Group {
            if let image = nsImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: height)
                    .accessibilityLabel("Stowmark")
            } else {
                Text("Stowmark")
                    .font(.title2)
                    .foregroundStyle(Theme.ink(scheme))
            }
        }
    }

    private var nsImage: NSImage? {
        let name = scheme == .dark ? "BrandLogoDark" : "BrandLogoLight"
        if let image = NSImage(named: name) { return image }
        // Packaged app Resources, or the source tree during `swift run`.
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name).png"),
            Bundle.main.bundleURL.appendingPathComponent("\(name).png"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("App/Resources/\(name).png"),
        ]
        for url in candidates {
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }
}
