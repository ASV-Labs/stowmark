import AppKit
import PDFKit

enum Thumbnail {
    static func makePNG(from data: Data) -> Data? {
        makePreview(from: data)
    }

    static func makePreview(from data: Data) -> Data? {
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) {
            return pdfCover(data)
        }
        guard let image = NSImage(data: data) else { return nil }
        return jpeg(from: image)
    }

    static func pdfCover(at url: URL) -> Data? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
        let image = page.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox)
        return jpeg(from: image)
    }

    private static func pdfCover(_ data: Data) -> Data? {
        guard let document = PDFDocument(data: data), let page = document.page(at: 0) else { return nil }
        return jpeg(from: page.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox))
    }

    private static func jpeg(from image: NSImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 720 / longest)
        let target = NSSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let canvas = NSImage(size: target)
        canvas.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target))
        canvas.unlockFocus()
        guard let tiff = canvas.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78])
    }
}
