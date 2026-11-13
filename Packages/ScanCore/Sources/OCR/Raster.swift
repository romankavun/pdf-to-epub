import CoreGraphics

/// The pixels of a page image, for the small amount of image editing the
/// OCR adapter does itself: blanking regions and cutting out labels.
struct Raster {
    let width: Int
    let height: Int
    /// RGBX bytes, rows from the top down.
    private var pixels: [UInt8]

    private static let bytesPerPixel = 4

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        pixels = [UInt8](repeating: 0, count: width * height * Self.bytesPerPixel)
        let width = width, height = height
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * Self.bytesPerPixel, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, width > 0, height > 0 else { return nil }
    }

    /// The pixel rectangle of a normalized region, clipped to the image.
    private func pixelRect(_ region: CGRect, expandedBy margin: Int = 0) -> (columns: Range<Int>, rows: Range<Int>) {
        let left = max(0, Int((region.minX * CGFloat(width)).rounded(.down)) - margin)
        let right = min(width, Int((region.maxX * CGFloat(width)).rounded(.up)) + margin)
        let top = max(0, Int((region.minY * CGFloat(height)).rounded(.down)) - margin)
        let bottom = min(height, Int((region.maxY * CGFloat(height)).rounded(.up)) + margin)
        return (left ..< max(left, right), top ..< max(top, bottom))
    }

    /// The image with `regions` painted in the page colour, taken from the
    /// top-left corner pixel.
    func erasing(_ regions: [CGRect]) -> CGImage? {
        var copy = pixels
        let paper = Array(copy[0 ..< Self.bytesPerPixel])
        for region in regions {
            // One pixel more on each side covers the anti-aliased edge.
            let rect = pixelRect(region, expandedBy: 1)
            for row in rect.rows {
                for column in rect.columns {
                    let offset = (row * width + column) * Self.bytesPerPixel
                    copy.replaceSubrange(offset ..< offset + Self.bytesPerPixel, with: paper)
                }
            }
        }
        let width = width, height = height
        return copy.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * Self.bytesPerPixel, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )?.makeImage()
        }
    }

    /// A region as grey dark-on-white pixels with full contrast.
    ///
    /// Markers are drawn in a link colour that is light in some channels;
    /// the darker of red and green separates it from the page best.
    func label(in region: CGRect) -> LabelCrop {
        let rect = pixelRect(region)
        var grey: [UInt8] = []
        grey.reserveCapacity(rect.columns.count * rect.rows.count)
        for row in rect.rows {
            for column in rect.columns {
                let offset = (row * width + column) * Self.bytesPerPixel
                grey.append(min(pixels[offset], pixels[offset + 1]))
            }
        }
        if let darkest = grey.min(), let lightest = grey.max(), lightest > darkest {
            let range = Int(lightest) - Int(darkest)
            grey = grey.map { UInt8((Int($0) - Int(darkest)) * 255 / range) }
        } else {
            grey = grey.map { _ in 255 }
        }
        return LabelCrop(width: rect.columns.count, height: rect.rows.count, grey: grey)
    }
}

/// A label cut out of a page: one grey byte per pixel, rows from the top.
struct LabelCrop {
    var width: Int
    var height: Int
    var grey: [UInt8]
}

/// Labels enlarged and laid out left to right on a white ground.
struct LabelStrip {
    let image: CGImage
    /// The horizontal extent of each label as fractions of the image width,
    /// widened a little: recognized boxes are approximate.
    let spans: [ClosedRange<Double>]

    /// - Returns: `nil` when there is nothing to draw.
    init?(crops: [LabelCrop], scale: Int, gap: Int) {
        let visible = crops.filter { $0.width > 0 && $0.height > 0 }
        guard !visible.isEmpty, let tallest = crops.map(\.height).max() else { return nil }
        let width = crops.reduce(gap) { $0 + $1.width * scale + gap }
        let height = tallest * scale + 2 * gap
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high

        var spans: [ClosedRange<Double>] = []
        var x = gap
        for crop in crops {
            let extent = crop.width * scale
            if let image = Self.image(of: crop) {
                context.draw(image, in: CGRect(x: x, y: gap, width: extent, height: crop.height * scale))
            }
            let margin = Double(gap) / 3
            spans.append((Double(x) - margin) / Double(width) ... (Double(x + extent) + margin) / Double(width))
            x += extent + gap
        }
        guard let image = context.makeImage() else { return nil }
        self.image = image
        self.spans = spans
    }

    private static func image(of crop: LabelCrop) -> CGImage? {
        guard crop.width > 0, crop.height > 0 else { return nil }
        var grey = crop.grey
        return grey.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: crop.width, height: crop.height, bitsPerComponent: 8,
                bytesPerRow: crop.width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )?.makeImage()
        }
    }
}
