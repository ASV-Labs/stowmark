import AppKit
import Foundation
import Vision

/// On-device visual find helpers — dominant color labels and OCR text for suggested tags / search extras.
enum LocalImageAnalysis {
    struct Result: Sendable {
        var colorTags: [String]
        var ocrText: String?
    }

    static func analyze(_ data: Data) -> Result {
        Result(colorTags: dominantColorTags(from: data), ocrText: recognizeText(in: data))
    }

    static func dominantColorTags(from data: Data) -> [String] {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cg = bitmap.cgImage else { return [] }

        let width = min(cg.width, 48)
        let height = min(cg.height, 48)
        guard width > 0, height > 0 else { return [] }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        context.interpolationQuality = .low
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data else { return [] }

        var buckets: [String: Int] = [:]
        let ptr = pixels.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for i in 0..<(width * height) {
            let o = i * 4
            let r = Int(ptr[o])
            let g = Int(ptr[o + 1])
            let b = Int(ptr[o + 2])
            let a = Int(ptr[o + 3])
            guard a > 32 else { continue }
            let label = colorName(r: r, g: g, b: b)
            buckets[label, default: 0] += 1
        }
        return buckets.sorted { $0.value > $1.value }.prefix(2).map(\.key)
    }

    static func recognizeText(in data: Data) -> String? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cg = bitmap.cgImage else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
        guard !lines.isEmpty else { return nil }
        return lines.prefix(40).joined(separator: "\n")
    }

    private static func colorName(r: Int, g: Int, b: Int) -> String {
        let maxv = max(r, g, b)
        let minv = min(r, g, b)
        if maxv < 40 { return "Black" }
        if minv > 220 { return "White" }
        let sat = maxv == 0 ? 0 : Double(maxv - minv) / Double(maxv)
        if sat < 0.18 {
            return maxv > 160 ? "Gray" : "Charcoal"
        }
        // Hue in degrees roughly.
        let rf = Double(r), gf = Double(g), bf = Double(b)
        let d = Double(maxv - minv)
        var h = 0.0
        if maxv == r {
            h = (gf - bf) / d + (gf < bf ? 6 : 0)
        } else if maxv == g {
            h = (bf - rf) / d + 2
        } else {
            h = (rf - gf) / d + 4
        }
        h *= 60
        switch h {
        case 0..<30, 330..<361: return "Red"
        case 30..<55: return "Orange"
        case 55..<85: return "Yellow"
        case 85..<160: return "Green"
        case 160..<200: return "Teal"
        case 200..<255: return "Blue"
        case 255..<290: return "Purple"
        default: return "Pink"
        }
    }
}
