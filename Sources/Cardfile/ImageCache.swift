import AppKit
import ImageIO
import LibraryCore
import SwiftUI

/// Memory cache of downsampled thumbnails.
///
/// Card bodies used to call `NSImage(contentsOf:)` on every refresh, which read full originals on the main thread and made scrolling stutter. Decoding happens off the main actor, capped at about 2× the preview zone, so recognition stays sharp without holding the library's originals in RAM.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    /// Cost ceiling for decoded thumbnails (not source bytes). The count cap stops a flood of tiny images from outrunning the byte limit.
    private static let byteLimit = 150 * 1024 * 1024
    private static let countLimit = 400

    private let images: NSCache<NSString, NSImage>
    /// Largest pixel cap already decoded for a sha256. A small source cannot fill a larger request, and must not be decoded again on every scroll.
    private var decodedLimit: [String: Int] = [:]
    private var inflight: [String: Task<SendableThumbnail?, Never>] = [:]

    private init() {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = Self.countLimit
        cache.totalCostLimit = Self.byteLimit
        cache.name = "Cardfile.ImageCache"
        images = cache
    }

    /// Longest side, in pixels, for a preview zone measured in points. Two times the zone is enough for a retina screen and far smaller than a camera original.
    nonisolated static func pixelLimit(forPointSize pointSize: CGFloat) -> Int {
        let pixels = Int((max(1, pointSize) * 2).rounded(.up))
        return min(2048, max(1, pixels))
    }

    func peek(sha256: String, minPixel: Int) -> NSImage? {
        cached(sha256: sha256, minPixel: minPixel)
    }

    func image(for asset: AssetRecord, root: URL, maxPointSize: CGFloat) async -> NSImage? {
        let maxPixel = Self.pixelLimit(forPointSize: maxPointSize)
        if let hit = cached(sha256: asset.sha256, minPixel: maxPixel) {
            return hit
        }
        let flightKey = "\(asset.sha256)#\(maxPixel)"
        let task: Task<SendableThumbnail?, Never>
        if let existing = inflight[flightKey] {
            task = existing
        } else {
            let url = asset.fileURL(in: root)
            let created = Task.detached(priority: .userInitiated) {
                Self.decode(url: url, maxPixel: maxPixel)
            }
            inflight[flightKey] = created
            task = created
        }
        let decoded = await task.value
        inflight[flightKey] = nil
        guard let decoded else { return nil }
        return store(decoded, sha256: asset.sha256, requestedPixel: maxPixel)
    }

    private func cached(sha256: String, minPixel: Int) -> NSImage? {
        guard let image = images.object(forKey: sha256 as NSString) else { return nil }
        let prepared = decodedLimit[sha256] ?? 0
        let longest = max(image.size.width, image.size.height)
        if prepared >= minPixel || longest + 1 >= CGFloat(minPixel) {
            return image
        }
        return nil
    }

    private func store(_ decoded: SendableThumbnail, sha256: String, requestedPixel: Int) -> NSImage {
        let key = sha256 as NSString
        if let existing = images.object(forKey: key) {
            let prepared = decodedLimit[sha256] ?? 0
            let longest = max(existing.size.width, existing.size.height)
            if prepared >= requestedPixel || longest + 1 >= CGFloat(requestedPixel) {
                return existing
            }
        }
        let image = NSImage(
            cgImage: decoded.image,
            size: NSSize(width: CGFloat(decoded.pixelWidth), height: CGFloat(decoded.pixelHeight))
        )
        images.setObject(image, forKey: key, cost: decoded.cost)
        decodedLimit[sha256] = max(decodedLimit[sha256] ?? 0, requestedPixel)
        return image
    }

    nonisolated private static func decode(url: URL, maxPixel: Int) -> SendableThumbnail? {
        autoreleasepool { () -> SendableThumbnail? in
            let sourceOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else { return nil }
            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel as NSNumber
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
            let width = max(image.width, 1)
            let height = max(image.height, 1)
            let cost = max(1, image.bytesPerRow * height)
            return SendableThumbnail(image: image, cost: cost, pixelWidth: width, pixelHeight: height)
        }
    }
}

/// Immutable thumbnail produced off the main actor. `CGImage` is not consistently `Sendable` across SDKs; the image is only read after the decode task finishes.
private struct SendableThumbnail: @unchecked Sendable {
    let image: CGImage
    let cost: Int
    let pixelWidth: Int
    let pixelHeight: Int
}

struct ThumbnailStatus: Equatable {
    var loaded = false
    var settled = false
}

struct ThumbnailStatusKey: PreferenceKey {
    static let defaultValue = ThumbnailStatus()
    static func reduce(value: inout ThumbnailStatus, nextValue: () -> ThumbnailStatus) {
        let next = nextValue()
        value.loaded = value.loaded || next.loaded
        value.settled = value.settled || next.settled
    }
}

/// Loads a cached, downsampled thumbnail. A missing file or a failed decode shows `placeholder` instead of throwing.
struct AsyncThumbnail<Placeholder: View>: View {
    var asset: AssetRecord?
    var root: URL?
    var maxPointSize: CGFloat
    private let placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var failed = false

    init(asset: AssetRecord?, root: URL?, maxPointSize: CGFloat, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.asset = asset
        self.root = root
        self.maxPointSize = maxPointSize
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let displayed {
                Image(nsImage: displayed)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder()
            }
        }
        .preference(
            key: ThumbnailStatusKey.self,
            value: ThumbnailStatus(loaded: displayed != nil, settled: displayed != nil || failed)
        )
        .task(id: loadID) {
            await load()
        }
    }

    @MainActor
    private var displayed: NSImage? {
        if let image { return image }
        guard let asset else { return nil }
        return ImageCache.shared.peek(
            sha256: asset.sha256,
            minPixel: ImageCache.pixelLimit(forPointSize: maxPointSize)
        )
    }

    private var loadID: String {
        "\(asset?.sha256 ?? "")|\(root?.path ?? "")|\(ImageCache.pixelLimit(forPointSize: maxPointSize))"
    }

    @MainActor
    private func load() async {
        failed = false
        guard let asset, let root else {
            image = nil
            failed = true
            return
        }
        let minPixel = ImageCache.pixelLimit(forPointSize: maxPointSize)
        if ImageCache.shared.peek(sha256: asset.sha256, minPixel: minPixel) == nil {
            image = nil
        }
        let loaded = await ImageCache.shared.image(for: asset, root: root, maxPointSize: maxPointSize)
        guard !Task.isCancelled else { return }
        image = loaded
        failed = loaded == nil
    }
}
