import CoreGraphics
import Foundation

/// Builds small PDFs in memory for the tests; no real document is involved.
enum SyntheticPDF {
    /// A page of `size` points, drawn by `draw` in PDF coordinates.
    struct Page {
        var size: CGSize
        var draw: (CGContext) -> Void = { _ in }
    }

    /// Writes a PDF with `pages` to a new temporary file.
    static func write(_ pages: [Page], password: String? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        var info: [CFString: Any] = [:]
        if let password {
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextOwnerPassword] = password
        }
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: nil, info as CFDictionary)
        else { throw CocoaError(.fileWriteUnknown) }
        for page in pages {
            var box = CGRect(origin: .zero, size: page.size)
            context.beginPDFPage([kCGPDFContextMediaBox: Data(
                bytes: &box,
                count: MemoryLayout<CGRect>.size
            )] as CFDictionary)
            page.draw(context)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    /// A bitmap of one flat colour, to be embedded as a page's only image.
    static func solidImage(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> CGImage? {
        var pixels = [UInt8]()
        for _ in 0 ..< width * height {
            pixels += [red, green, blue, 255]
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        return provider.flatMap {
            CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            )
        }
    }
}
