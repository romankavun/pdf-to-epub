import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws a folder of synthetic page images for the UI test.
///
/// The UI test target cannot import the package's `TestSupport` (it is a test
/// target of another package), so this draws just enough: dark serif lines on
/// a white 1200x1700 page, the first line of each paragraph indented, like the
/// clean pages the app is built for. The text is invented.
enum PageFolder {
    private static let size = CGSize(width: 1200, height: 1700)

    private static let pages: [[String]] = [
        [
            ">The river ran slowly past the old stone mill and the lantern",
            "kept burning in the window of the house on the hill above it.",
            "Nobody in the village could say who had lit it, and nobody",
            "asked, because the light had always been there at night.",
            "The children counted the boats that passed beneath the bridge",
            "and the old men argued about the weather until the evening.",
            ">A letter arrived on the first morning of the autumn market",
            "and was passed from one stall to another until it reached",
            "the baker, who read it aloud to the whole square twice.",
            "Everyone agreed that the news was good, though nobody",
            "could explain exactly why they felt so pleased about it.",
            "The mill wheel turned, the lantern glowed, and the river",
            "carried the afternoon quietly down toward the distant sea.",
        ],
        [
            ">By winter the bridge had been painted and the market moved",
            "indoors, where the stalls stood in long rows under lamps.",
            "The baker kept the letter in a drawer beside the flour and",
            "showed it to anyone who asked, which was nearly everyone.",
            "Snow covered the roofs, and the children built a small boat",
            "of ice that floated for an hour before it finally sank.",
            ">Spring returned with rain, and the river rose against the",
            "mill wall, but the lantern in the window never went out.",
            "The old men agreed that it had been a fine year after all,",
            "and went home early to tell their wives about the weather.",
            "The village slept, the water ran, and the light went on.",
        ],
    ]

    /// Writes `page-001.png`, `page-002.png`… into a new folder inside `parent`
    /// and returns the folder.
    static func make(in parent: URL) throws -> URL {
        let folder = parent.appendingPathComponent("UITest Document", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, lines) in pages.enumerated() {
            let url = folder.appendingPathComponent(String(format: "page-%03d.png", index + 1))
            try write(render(lines), to: url)
        }
        return folder
    }

    private static func render(_ lines: [String]) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw PageFolderError.drawing }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let font = CTFontCreateWithName("Times New Roman" as CFString, 40, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0.1, alpha: 1),
        ]
        var baseline = size.height - 160
        for line in lines {
            let indented = line.hasPrefix(">")
            let text = indented ? String(line.dropFirst()) : line
            let ctLine = CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: attributes as [NSAttributedString.Key: Any])
            )
            context.textPosition = CGPoint(x: indented ? 168 : 120, y: baseline)
            CTLineDraw(ctLine, context)
            baseline -= 64
        }
        guard let image = context.makeImage() else { throw PageFolderError.drawing }
        return image
    }

    private static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw PageFolderError.drawing }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PageFolderError.drawing }
    }
}

enum PageFolderError: Error {
    case drawing
}
