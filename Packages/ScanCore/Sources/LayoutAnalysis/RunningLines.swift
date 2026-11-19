import CoreGraphics
import Foundation
import OCR

extension LayoutAnalyzer {
    /// Removes running headers, running footers and page numbers: lines at
    /// the top or bottom edge of the page whose text, with digits ignored,
    /// recurs at the same height on many pages.
    ///
    /// Repetition is the one signal that tells them from content: a chapter
    /// title at the top of a page is unique, a running title is not. Digits
    /// are ignored so that a header carrying the page number ("12 TITLE")
    /// still repeats; a line that is only a number (Arabic or Roman) always
    /// has the same shape, so page numbers at the top need no rule of their
    /// own. Documents with different left and right headers repeat each text on
    /// every other page, which the share threshold allows for.
    ///
    /// - Parameter pages: The elements of every page, top to bottom.
    func withoutRunningLines(_ pages: [[PageElement]]) -> [[PageElement]] {
        struct Candidate {
            let page: Int
            let top: Double
        }
        var candidates: [String: [Candidate]] = [:]
        for (pageIndex, page) in pages.enumerated() {
            for element in page {
                guard let line = element.row?.line, let key = runningKey(of: line) else { continue }
                candidates[key, default: []].append(Candidate(page: pageIndex, top: Double(line.box.minY)))
            }
        }

        let needed = max(
            options.runningLineMinimumPages,
            Int((options.runningLineMinimumShare * Double(pages.count)).rounded(.up))
        )
        var dropped: [String: (top: Double, pages: Set<Int>)] = [:]
        for (key, found) in candidates {
            let tops = found.map(\.top).sorted()
            let median = tops[(tops.count - 1) / 2]
            let atHeight = found.filter { abs($0.top - median) <= options.runningLineHeightTolerance }
            if Set(atHeight.map(\.page)).count >= needed {
                dropped[key] = (median, Set(atHeight.map(\.page)))
            }
        }
        guard !dropped.isEmpty else { return pages }

        return pages.enumerated().map { pageIndex, page in
            page.filter { element in
                guard let line = element.row?.line, let key = runningKey(of: line), let match = dropped[key]
                else { return true }
                return !(match.pages.contains(pageIndex)
                    && abs(Double(line.box.minY) - match.top) <= options.runningLineHeightTolerance)
            }
        }
    }

    /// What a line must be to repeat as a running line: `nil` when it is not
    /// near the top or bottom edge or carries no letters or digits (a
    /// repeated ornament such as "* * *" is content).
    private func runningKey(of line: TextLine) -> String? {
        let top = Double(line.box.minY)
        guard top < options.runningHeaderZone || top > options.runningFooterZone else { return nil }
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if text.wholeMatch(of: /[ivxlcdm]{1,8}/) != nil {
            return "#"
        }
        // Spaces are left out: in small or spaced capitals the engine reads
        // the same name with and without them ("ANDY WEIR", "ANDYWEIR").
        let key = text.replacing(/[0-9]+/, with: "#").replacing(/\s+/, with: "")
        return key.contains { $0.isLetter || $0 == "#" } ? key : nil
    }
}
