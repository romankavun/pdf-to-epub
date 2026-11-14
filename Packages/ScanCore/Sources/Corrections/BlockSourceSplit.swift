import CoreGraphics
import LayoutAnalysis

extension BlockSource {
    /// A cut closer than this share of an area to its start or end is taken
    /// to be at that edge: the estimate is rough, and a sliver of a few
    /// characters is more likely a misjudged page break than a real cut.
    private static let edgeSnap = 0.15
    /// Each part of a cut area keeps at least this share of its height, so
    /// neither part ends up with no place to click.
    private static let minimumShare = 0.05
    /// The height of one line of body text, as a share of the page.
    private static let lineHeight = 0.0175
    /// An area shorter than this holds a line or two (a heading, a caption)
    /// and is never cut inside: it goes to the part that reaches it.
    private static let singleLineHeight = 0.045
    /// Characters per unit of page width on a line of body text, and on a
    /// line of a heading, whose type is larger.
    private static let bodyDensity = 100.0
    private static let headingDensity = 70.0

    /// The source cut in two, where the text is cut after `offset` of its
    /// `total` characters.
    ///
    /// Line boxes are not kept, so the cut is estimated: every area is given
    /// the number of characters it could hold (lines times width), scaled
    /// down when the text is shorter than the areas, and the characters of
    /// the shorter part are laid out from its own end of the block. That
    /// keeps a short tail, such as a heading run into the end of a note,
    /// from being placed by the error in the estimate of a long text. Areas
    /// of a line or two are not cut; an area the cut falls near an edge of
    /// is cut at the edge.
    func split(afterCharacters offset: Int, of total: Int) -> (first: BlockSource, second: BlockSource) {
        guard total > 0, !areas.isEmpty else { return (self, self) }
        let fromEnd = offset > total - offset
        let walk = fromEnd ? Array(areas.reversed()) : areas
        var budget = Double(fromEnd ? total - offset : offset)
        let capacities = Self.capacities(of: walk, forText: total)

        var near: [PageArea] = []
        var far: [PageArea] = []
        for (index, area) in walk.enumerated() {
            let capacity = capacities[index]
            if budget >= capacity, index < walk.count - 1 {
                near.append(area)
                budget -= capacity
                continue
            }
            let isLast = index == walk.count - 1
            let share = capacity > 0 ? budget / capacity : 1
            let isSmall = area.box.height < Self.singleLineHeight
            if budget <= 0 || (!isSmall && share < Self.edgeSnap && !near.isEmpty) {
                far = Array(walk[index...])
            } else if isSmall || (share > 1 - Self.edgeSnap && !isLast) || share >= 1 {
                near.append(area)
                far = Array(walk[(index + 1)...])
            } else {
                let (consumed, rest) = Self.cut(area, consumedShare: share, fromEnd: fromEnd)
                near.append(consumed)
                far = [rest] + Array(walk[(index + 1)...])
            }
            break
        }
        if near.isEmpty || far.isEmpty {
            // One part would have no area: give it a sliver of the nearest.
            return Self.sliver(of: self, headFirst: !fromEnd, budget: budget, total: total, offset: offset)
        }
        let head = fromEnd ? far.reversed() : near
        let tail = fromEnd ? near.reversed() : far
        return (Self(areas: Array(head)), Self(areas: Array(tail)))
    }

    /// How many characters each of `areas` is taken to hold.
    private static func capacities(of areas: [PageArea], forText total: Int) -> [Double] {
        let raw = areas.map { area -> Double in
            let box = area.box
            if box.height < singleLineHeight {
                return box.width * headingDensity
            }
            return (box.height / lineHeight).rounded() * box.width * bodyDensity
        }
        let sum = raw.reduce(0, +)
        guard sum > Double(total) else { return raw }
        return raw.map { $0 * Double(total) / sum }
    }

    /// `area` cut so that the part at the walked end holds `consumedShare`
    /// of its height: the top part when walking from the start, the bottom
    /// part when walking from the end.
    private static func cut(_ area: PageArea, consumedShare: Double, fromEnd: Bool) -> (PageArea, PageArea) {
        let box = area.box
        let share = min(max(consumedShare, minimumShare), 1 - minimumShare)
        let consumedHeight = box.height * share
        let top = CGRect(
            x: box.minX,
            y: box.minY,
            width: box.width,
            height: fromEnd ? box.height - consumedHeight : consumedHeight
        )
        let bottom = CGRect(x: box.minX, y: top.maxY, width: box.width, height: box.maxY - top.maxY)
        return fromEnd
            ? (PageArea(page: area.page, box: bottom), PageArea(page: area.page, box: top))
            : (PageArea(page: area.page, box: top), PageArea(page: area.page, box: bottom))
    }

    /// The cut of a block that has only one area (or where the estimate
    /// left a part without one): the first area is cut where the text share
    /// puts it.
    private static func sliver(
        of source: BlockSource, headFirst _: Bool, budget _: Double, total: Int, offset: Int
    ) -> (first: BlockSource, second: BlockSource) {
        guard let area = source.areas.first else { return (source, source) }
        let share = Double(offset) / Double(total)
        let (top, bottom) = cut(area, consumedShare: share, fromEnd: false)
        return (
            Self(areas: [top]),
            Self(areas: [bottom] + Array(source.areas.dropFirst()))
        )
    }

    private init(areas: [PageArea]) {
        self.init(page: areas[0].page, box: areas[0].box)
        continuations = Array(areas.dropFirst())
    }
}
