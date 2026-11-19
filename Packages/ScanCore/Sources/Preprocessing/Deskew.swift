import Foundation

/// Measures how far the text lines of a page are tilted and rotates the
/// page level.
///
/// The angle is found by projection profiles: ink is summed along lines of
/// a trial angle, and the angle at which the sums change most sharply from
/// one line to the next (dense text rows, empty gaps between them) is the
/// angle of the text. It needs several lines of text; a page of mostly
/// pictures or of one line gives a weak answer, which is why small angles
/// are left alone.
///
/// A page whose lines curve towards the gutter (a document that does not lie
/// flat) has no single angle; the measured angle is the average tilt, and
/// rotating by it levels the middle of the lines, not their ends.
public struct Deskew: Sendable {
    /// The largest tilt looked for, in degrees. A page tilted more than this
    /// was placed carelessly enough that the crop would be off too.
    static let maximumAngle = 5.0
    /// Tilts smaller than this, in degrees, are left alone: rotating costs
    /// sharpness, and Vision reads lines this close to level without help.
    static let minimumAngle = 0.1
    /// A pixel at most this bright is ink for the profile.
    static let inkLevel = 128

    public init() {}

    /// The tilt of the page's text lines in degrees, positive when they
    /// descend to the right; zero for a page without ink.
    public func skewAngle(of bitmap: ScanBitmap) -> Double {
        let ink = inkPoints(of: bitmap)
        guard !ink.isEmpty else { return 0 }
        var best = (angle: 0.0, score: score(ink, angle: 0, height: bitmap.height))
        // Coarse, then fine around the best coarse angle.
        for step in [0.25, 0.05] {
            let centre = best.angle, span = step == 0.25 ? Self.maximumAngle : 0.25
            var angle = centre - span
            while angle <= centre + span + 1e-9 {
                let value = score(ink, angle: angle, height: bitmap.height)
                if value > best.score {
                    best = (angle, value)
                }
                angle += step
            }
        }
        return (best.angle * 100).rounded() / 100
    }

    /// The page rotated so its text lines are level, on a canvas grown to
    /// hold the whole rotated page, with white corners; the page itself
    /// when its tilt is below the threshold.
    public func straightened(_ bitmap: ScanBitmap) -> ScanBitmap {
        let angle = skewAngle(of: bitmap)
        guard abs(angle) >= Self.minimumAngle else { return bitmap }
        return Self.rotated(bitmap, levelling: angle)
    }

    /// Ink pixel positions, x measured from the middle of the page.
    private func inkPoints(of bitmap: ScanBitmap) -> [(x: Double, y: Double)] {
        let luminance = bitmap.luminance
        let middle = Double(bitmap.width) / 2
        var points: [(x: Double, y: Double)] = []
        for (index, value) in luminance.enumerated() where Int(value) <= Self.inkLevel {
            points.append((Double(index % bitmap.width) - middle, Double(index / bitmap.width)))
        }
        return points
    }

    /// How sharply the ink summed along lines of `angle` changes from line
    /// to line.
    private func score(_ ink: [(x: Double, y: Double)], angle: Double, height: Int) -> Double {
        let slope = tan(angle * .pi / 180)
        // Lines can leave the page by the slope times half the width.
        let reach = Int((abs(slope) * Double(ink.map { abs($0.x) }.max() ?? 0)).rounded(.up)) + 1
        var rows = [Int](repeating: 0, count: height + 2 * reach)
        for point in ink {
            let row = Int((point.y - point.x * slope).rounded()) + reach
            if rows.indices.contains(row) {
                rows[row] += 1
            }
        }
        var total = 0.0
        for index in 1 ..< rows.count {
            let change = Double(rows[index] - rows[index - 1])
            total += change * change
        }
        return total
    }

    /// `bitmap` rotated by `-angle` around its centre, bilinear.
    static func rotated(_ bitmap: ScanBitmap, levelling angle: Double) -> ScanBitmap {
        let radians = angle * .pi / 180
        let cosine = cos(radians), sine = sin(radians)
        let width = Int((Double(bitmap.width) * abs(cosine) + Double(bitmap.height) * abs(sine)).rounded(.up))
        let height = Int((Double(bitmap.width) * abs(sine) + Double(bitmap.height) * abs(cosine)).rounded(.up))
        let sourceX = Double(bitmap.width) / 2, sourceY = Double(bitmap.height) / 2
        let targetX = Double(width) / 2, targetY = Double(height) / 2
        var pixels = [UInt8](repeating: 255, count: width * height * ScanBitmap.bytesPerPixel)

        bitmap.pixels.withUnsafeBufferPointer { source in
            func sample(_ x: Int, _ y: Int, _ channel: Int) -> Double {
                guard x >= 0, x < bitmap.width, y >= 0, y < bitmap.height else { return 255 }
                return Double(source[(y * bitmap.width + x) * ScanBitmap.bytesPerPixel + channel])
            }
            for row in 0 ..< height {
                for column in 0 ..< width {
                    // A level line of the result is a line of slope `angle`
                    // in the source.
                    let dx = Double(column) + 0.5 - targetX, dy = Double(row) + 0.5 - targetY
                    let x = dx * cosine - dy * sine + sourceX - 0.5
                    let y = dx * sine + dy * cosine + sourceY - 0.5
                    let left = Int(x.rounded(.down)), top = Int(y.rounded(.down))
                    let fx = x - Double(left), fy = y - Double(top)
                    let offset = (row * width + column) * ScanBitmap.bytesPerPixel
                    for channel in 0 ..< 3 {
                        let upper = sample(left, top, channel) * (1 - fx) + sample(left + 1, top, channel) * fx
                        let lower = sample(left, top + 1, channel) * (1 - fx) + sample(left + 1, top + 1, channel) * fx
                        pixels[offset + channel] = UInt8((upper * (1 - fy) + lower * fy).rounded())
                    }
                }
            }
        }
        return ScanBitmap(uncheckedWidth: width, height: height, pixels: pixels)
    }
}
