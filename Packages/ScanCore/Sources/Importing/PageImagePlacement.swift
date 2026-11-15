import CoreGraphics
import Foundation

/// Finds out how densely a scanned page's picture is stored.
///
/// A scanned document is a PDF whose pages are one image each, but the image is
/// not always stretched over the whole page: it may be placed smaller, with
/// margins around it. Drawing the page at the density of the image keeps its
/// pixels as they are whatever the page size in points says.
enum PageImagePlacement {
    /// Pixels of the page's image per point of the page, or `nil` when the
    /// page is not made of exactly one image drawn directly by its content
    /// stream (text, vector drawing, forms or several images).
    static func pixelsPerPoint(of page: CGPDFPage) -> Double? {
        let content = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(content) }
        let pass = Scan(content: content)
        guard let table = CGPDFOperatorTableCreate() else { return nil }
        CGPDFOperatorTableSetCallback(table, "q") { _, info in PageImagePlacement.current(info).save() }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in PageImagePlacement.current(info).restore() }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            var values = [CGPDFReal](repeating: 0, count: 6)
            for index in (0 ..< 6).reversed() {
                guard CGPDFScannerPopNumber(scanner, &values[index]) else { return }
            }
            PageImagePlacement.current(info).concatenate(CGAffineTransform(
                a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5]
            ))
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name else { return }
            PageImagePlacement.current(info).draw(named: name)
        }
        // Anything that paints other than an image disqualifies the page.
        for painter in ["f", "F", "f*", "B", "B*", "b", "b*", "S", "s", "sh", "BT", "Tj", "TJ", "'", "\"", "BI"] {
            CGPDFOperatorTableSetCallback(table, painter) { _, info in PageImagePlacement.current(info).other += 1 }
        }
        let retained = Unmanaged.passRetained(pass)
        defer { retained.release() }
        let scanner = CGPDFScannerCreate(content, table, retained.toOpaque())
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFOperatorTableRelease(table)

        guard pass.other == 0, pass.images.count == 1, let image = pass.images.first,
              image.pixels > 0, image.points > 0
        else { return nil }
        return image.pixels / image.points
    }

    /// Reads the shared state back from the scanner's context pointer.
    private static func current(_ info: UnsafeMutableRawPointer?) -> Scan {
        guard let info else { return Scan(content: nil) }
        return Unmanaged<Scan>.fromOpaque(info).takeUnretainedValue()
    }

    /// The running state of one pass over a content stream.
    final class Scan {
        let content: CGPDFContentStreamRef?
        var transform = CGAffineTransform.identity
        var saved: [CGAffineTransform] = []
        var images: [(pixels: Double, points: Double)] = []
        /// Count of operations that paint something other than a drawn XObject.
        var other = 0

        init(content: CGPDFContentStreamRef?) {
            self.content = content
        }

        func save() {
            saved.append(transform)
        }

        func restore() {
            if let last = saved.popLast() { transform = last }
        }

        func concatenate(_ matrix: CGAffineTransform) {
            transform = matrix.concatenating(transform)
        }

        func draw(named name: UnsafePointer<CChar>) {
            var stream: CGPDFStreamRef?
            guard let content, let object = CGPDFContentStreamGetResource(content, "XObject", name),
                  CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let info = CGPDFStreamGetDictionary(stream)
            else {
                other += 1
                return
            }
            var subtype: UnsafePointer<CChar>?
            var width: CGPDFInteger = 0
            guard CGPDFDictionaryGetName(info, "Subtype", &subtype), let subtype, String(cString: subtype) == "Image",
                  CGPDFDictionaryGetInteger(info, "Width", &width)
            else {
                other += 1
                return
            }
            images.append((Double(width), Double(hypot(transform.a, transform.b))))
        }
    }
}
