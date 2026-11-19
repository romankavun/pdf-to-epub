/// Finds the document page lying on a scanner bed and crops the image to it.
///
/// A flatbed scan of a small document is mostly bed: a frame of one exact colour
/// (saturated white on the scans seen so far) around the page. The paper is
/// nearly as light as the bed, so it is told apart by its grain rather than
/// by its tone: almost no pixel of real paper is exactly the bed colour,
/// while almost every pixel of the bed is. Text alone would not do, because
/// the page's edges and the space around the text belong to the page too.
///
/// a clean-page source clean page may also have a frame of one exact colour, its
/// margins, so a page box alone does not make a scan; ``InputProfile``
/// decides that, and only pages of scanned documents are cropped.
public struct PageCrop: Sendable {
    /// A row or column belongs to the page when more than this share of its
    /// pixels differs from the bed. Low enough for a page a third the width
    /// of the bed, whose paper is only partly grainy; high enough to skip
    /// dust.
    static let pageShare = 0.04
    /// A pixel is grain rather than ink when it differs from the bed by at
    /// most this much, summed over the three channels.
    static let grainLimit = 12
    /// A scanned page is grainy: at least this share of its pixels is
    /// grain. Scanned pages measured 0.21-0.48, clean pages at most 0.07.
    /// Used by ``InputProfile``.
    static let minimumGrain = 0.15
    /// The bed must show on every side, at least this share of the image's
    /// size, or the image is not a page lying on a bed.
    static let minimumBed = 0.02
    /// Kept around the page, as a share of its width, so a skewed or curled
    /// page edge is not cut.
    static let margin = 0.02

    public init() {}

    /// The rectangle of the document page with a small margin, or `nil` when the
    /// image is not a page lying on a bed of one colour with the bed
    /// showing on every side.
    ///
    /// The bed colour is the most common colour on the image's border.
    public func pageBox(in bitmap: ScanBitmap) -> PixelRect? {
        let width = bitmap.width, height = bitmap.height
        guard width > 0, height > 0 else { return nil }
        let bed = bitmap.borderColor

        var rowCounts = [Int](repeating: 0, count: height)
        var columnCounts = [Int](repeating: 0, count: width)
        bitmap.pixels.withUnsafeBufferPointer { pixels in
            for row in 0 ..< height {
                var offset = row * width * ScanBitmap.bytesPerPixel
                for column in 0 ..< width {
                    if pixels[offset] != bed.red || pixels[offset + 1] != bed.green || pixels[offset + 2] != bed.blue {
                        rowCounts[row] += 1
                        columnCounts[column] += 1
                    }
                    offset += ScanBitmap.bytesPerPixel
                }
            }
        }
        guard let top = rowCounts.firstIndex(where: { Double($0) > Self.pageShare * Double(width) }),
              let bottom = rowCounts.lastIndex(where: { Double($0) > Self.pageShare * Double(width) }),
              let left = columnCounts.firstIndex(where: { Double($0) > Self.pageShare * Double(height) }),
              let right = columnCounts.lastIndex(where: { Double($0) > Self.pageShare * Double(height) })
        else { return nil }

        let bedX = Self.minimumBed * Double(width), bedY = Self.minimumBed * Double(height)
        guard Double(left) >= bedX, Double(width - 1 - right) >= bedX,
              Double(top) >= bedY, Double(height - 1 - bottom) >= bedY
        else { return nil }

        let page = PixelRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)

        let margin = max(2, Int((Self.margin * Double(page.width)).rounded()))
        let x = max(0, page.x - margin), y = max(0, page.y - margin)
        return PixelRect(
            x: x, y: y,
            width: min(width, page.x + page.width + margin) - x,
            height: min(height, page.y + page.height + margin) - y
        )
    }

    /// The image cropped to ``pageBox(in:)``; the image itself when there is
    /// no page box.
    public func cropped(_ bitmap: ScanBitmap) -> ScanBitmap {
        pageBox(in: bitmap).map { bitmap.cropped(to: $0) } ?? bitmap
    }
}

extension ScanBitmap {
    /// The most common colour on the image's border; ties go to the larger
    /// value so the result does not depend on dictionary order.
    var borderColor: ScanColor {
        var counts: [UInt32: Int] = [:]
        func count(_ x: Int, _ y: Int) {
            counts[color(x: x, y: y).key, default: 0] += 1
        }
        for x in 0 ..< width {
            count(x, 0)
            count(x, height - 1)
        }
        for y in 0 ..< height {
            count(0, y)
            count(width - 1, y)
        }
        let key = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }?.key ?? 0
        return ScanColor(red: UInt8(key >> 16 & 0xFF), green: UInt8(key >> 8 & 0xFF), blue: UInt8(key & 0xFF))
    }

    /// The share of pixels in `rect` that differ from `color` a little, by
    /// 1 to ``PageCrop/grainLimit`` summed over the channels.
    func grainShare(in rect: PixelRect, against color: ScanColor) -> Double {
        guard rect.width > 0, rect.height > 0 else { return 0 }
        var grain = 0
        pixels.withUnsafeBufferPointer { pixels in
            for row in rect.y ..< rect.y + rect.height {
                var offset = (row * width + rect.x) * Self.bytesPerPixel
                for _ in 0 ..< rect.width {
                    let difference = abs(Int(pixels[offset]) - Int(color.red))
                        + abs(Int(pixels[offset + 1]) - Int(color.green))
                        + abs(Int(pixels[offset + 2]) - Int(color.blue))
                    if difference > 0, difference <= PageCrop.grainLimit {
                        grain += 1
                    }
                    offset += Self.bytesPerPixel
                }
            }
        }
        return Double(grain) / Double(rect.width * rect.height)
    }
}
