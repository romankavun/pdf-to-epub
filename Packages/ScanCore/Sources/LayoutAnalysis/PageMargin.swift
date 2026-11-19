import OCR

/// Where unindented lines start on one page, as a function of the height on
/// the page.
///
/// On clean pages every page has the document's margin. A scanned leaf
/// is cropped differently on every page, and lies at a slant or curves
/// towards the gutter, so its lines start further left or right the lower
/// they are; with the document's margin alone, every line of such a page would
/// look indented and become a paragraph of its own. The page's own margin
/// follows that drift: a straight line through the left edges of its
/// lines.
struct PageMargin {
    /// Margin at the top of the page (y = 0).
    let intercept: Double
    /// Change of the margin per unit of page height.
    let slope: Double

    /// The constant margin of a page that is not measured on its own.
    init(constant margin: Double) {
        self.init(intercept: margin, slope: 0)
    }

    init(intercept: Double, slope: Double) {
        self.intercept = intercept
        self.slope = slope
    }

    /// Fewer lines than this give no reliable margin of their own; the
    /// page then uses the document's.
    static let minimumLines = 6

    /// The margin measured from `lines`, or the document's `margin` when the page
    /// has too few lines.
    ///
    /// The slope is the one under which the left edges bunch together most
    /// tightly. Candidates are the slopes through the left edges of every
    /// pair of lines far enough apart; each is scored by how many pairs of
    /// edges, with the slope taken out, lie within ``edgeTolerance`` of each
    /// other. Continuation lines lie on the margin and indented first lines
    /// on a parallel line, so under the true slope both families bunch; a
    /// slope that lines up the margin at the top with the indents of a run of
    /// dialogue at the bottom scatters the rest. (A median of pair slopes is
    /// pulled aside too, as first lines open the paragraphs and are not
    /// spread evenly.) The level is then the leftmost group of left edges
    /// that holds a fair share of the lines: indented first lines form a
    /// group further right, which on a page of dialogue may be the larger
    /// one.
    init(lines: [TextLine], documentMargin margin: Double) {
        guard lines.count >= Self.minimumLines else {
            self.init(constant: margin)
            return
        }
        let slope = Self.slope(of: lines.map { (y: Double($0.box.minY), x: Double($0.box.minX)) })

        // Every line counts for the level, short ones too: in a page of short
        // paragraphs the long lines are mostly indented first lines, while
        // the short last lines start at the margin.
        let levels = lines.map { Double($0.box.minX) - slope * Double($0.box.minY) }.sorted()
        guard let level = Self.leftmostLevel(of: levels) else {
            self.init(constant: margin)
            return
        }
        self.init(intercept: level, slope: slope)
    }

    /// The leftmost group of `levels` (left edges, with any slope taken out)
    /// that holds at least a tenth of them, and two: the margin. Indented
    /// first lines, centred lines and the like all lie to its right; a
    /// single stray edge further left does not count.
    static func leftmostLevel(of levels: [Double]) -> Double? {
        let bucketWidth = 0.01
        let needed = max(2, Int((0.1 * Double(levels.count)).rounded(.up)))
        let groups = Dictionary(grouping: levels) { ($0 / bucketWidth).rounded() }
        guard let leftmost = groups.filter({ $0.value.count >= needed }).keys.min() else { return nil }
        // Edges within one bucket width of the group's centre, as a group may
        // straddle a bucket boundary; narrow enough to leave out first lines
        // indented by little more than the indent threshold.
        let centre = leftmost * bucketWidth
        return Metrics.median(levels.filter { abs($0 - centre) <= bucketWidth })
    }

    /// How far a left edge may lie from a candidate margin and still count
    /// as on it: well under the indent threshold.
    private static let edgeTolerance = 0.006

    /// The candidate slope under which the edges bunch most; ties go to the
    /// gentler one, and a page with no pair of lines far enough apart is
    /// taken as upright.
    private static func slope(of edges: [(y: Double, x: Double)]) -> Double {
        var best = (score: 0, slope: 0.0)
        var tried: Set<Int> = []
        for (index, first) in edges.enumerated() {
            for second in edges[(index + 1)...] where abs(second.y - first.y) > 0.05 {
                let slope = (second.x - first.x) / (second.y - first.y)
                // A page leaning more than this is not text at a slant but
                // noise; slopes closer than a thousandth are the same one.
                guard abs(slope) < 0.3, tried.insert(Int((slope * 1000).rounded())).inserted else { continue }
                let score = bunching(of: edges.map { $0.x - slope * $0.y })
                if score > best.score || (score == best.score && abs(slope) < abs(best.slope)) {
                    best = (score, slope)
                }
            }
        }
        return best.slope
    }

    /// The number of pairs of `levels` that lie within ``edgeTolerance`` of
    /// each other.
    private static func bunching(of levels: [Double]) -> Int {
        let sorted = levels.sorted()
        var pairs = 0, start = 0
        for (index, level) in sorted.enumerated() {
            while level - sorted[start] > edgeTolerance {
                start += 1
            }
            pairs += index - start
        }
        return pairs
    }

    /// The margin at height `y`.
    func at(_ y: Double) -> Double {
        intercept + slope * y
    }
}
