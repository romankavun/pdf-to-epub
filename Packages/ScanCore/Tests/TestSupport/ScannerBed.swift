import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Where a synthetic page lies on the glass of a scanner, for tests of the
/// scanned-page path: the document page is smaller than the image, sits a little
/// off centre, leans by a small angle, and has grainy paper with a dark edge
/// along one side and a gutter shadow along the other.
public struct ScannerPlacement: Sendable {
    /// Offset of the page from the centre of the bed, as fractions of the
    /// bed's width and height.
    public var offset: CGPoint
    /// Rotation of the page in degrees, counter-clockwise.
    public var angle: Double

    public init(offset: CGPoint = .zero, angle: Double = 0) {
        self.offset = offset
        self.angle = angle
    }

    /// The bed is this many times the page's size along each side.
    static let bedScale: CGFloat = 1.6

    /// Replaces the page image at `url` with a scan of it lying on a white
    /// bed as this placement describes.
    public func placeOnBed(imageAt url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let page = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CocoaError(.fileReadCorruptFile) }
        let pageSize = CGSize(width: page.width, height: page.height)
        let bed = CGSize(width: pageSize.width * Self.bedScale, height: pageSize.height * Self.bedScale)
        guard let context = CGContext(
            data: nil, width: Int(bed.width), height: Int(bed.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ), let paper = Self.paper(size: pageSize) else { throw CocoaError(.fileWriteUnknown) }
        // The glass is pure white, which tells it from the paper.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: bed))

        context.translateBy(
            x: bed.width / 2 + offset.x * bed.width, y: bed.height / 2 - offset.y * bed.height
        )
        context.rotate(by: angle * .pi / 180)
        let frame = CGRect(
            x: -pageSize.width / 2, y: -pageSize.height / 2, width: pageSize.width, height: pageSize.height
        )
        context.draw(paper, in: frame)
        // Black print over grainy paper: white in the page keeps the grain.
        context.setBlendMode(.multiply)
        context.draw(page, in: frame)
        context.setBlendMode(.normal)
        // The leaf's outer edge and the shadow of the gutter.
        context.setFillColor(CGColor(gray: 0.25, alpha: 1))
        context.fill(CGRect(x: frame.maxX - 4, y: frame.minY, width: 4, height: frame.height))
        context.setFillColor(CGColor(gray: 0.55, alpha: 1))
        context.fill(CGRect(x: frame.minX, y: frame.minY, width: 6, height: frame.height))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Almost white paper with a fine deterministic grain, as a scanner sees
    /// it; the preprocessing stage finds the page by this grain.
    private static func paper(size: CGSize) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                // A few shades off the bed, as measured on real scans; more
                // would read as ink rather than grain.
                let tone = 255 - UInt8((x * 7 + y * 13) % 5)
                let offset = (y * width + x) * 4
                pixels[offset] = tone
                pixels[offset + 1] = tone
                pixels[offset + 2] = tone
            }
        }
        return pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )?.makeImage()
        }
    }
}
