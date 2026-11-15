@testable import AppModel
import Conversion
import CoreGraphics
import Corrections
import Foundation
import LayoutAnalysis
import Testing

@MainActor
@Suite("ReviewModel item presentation")
struct ReviewItemPresentationTests {
    private func item(_ kind: ReviewModel.Kind, issues: Int = 0) -> ReviewModel.Item {
        ReviewModel.Item(
            id: .block(0), kind: kind,
            anchor: BlockAnchor(BlockSource(page: 0, box: .zero)),
            runs: [], box: .zero, issueCount: issues
        )
    }

    @Test("a paragraph or heading can be edited, retyped and merged")
    func textActions() {
        let all: [ReviewModel.ItemAction] = [.editText, .changeType, .mergeWithNext]
        #expect(item(.paragraph).actions == all)
        #expect(item(.heading(level: 2)).actions == all)
    }

    @Test("a note text can only be edited; a figure's caption can be edited and the figure ignored")
    func otherActions() {
        #expect(item(.note(label: "1")).actions == [.editText])
        #expect(item(.figure(imageID: "f")).actions == [.editCaption, .ignore])
    }

    @Test("an ignored block can only be brought back")
    func ignoredActions() {
        #expect(item(.ignored).actions == [.bringBack])
    }

    @Test("only text blocks and note texts offer a split")
    func split() {
        #expect(item(.paragraph).offersSplit)
        #expect(item(.heading(level: 1)).offersSplit)
        #expect(item(.note(label: "1")).offersSplit)
        #expect(!item(.figure(imageID: "f")).offersSplit)
        #expect(!item(.ignored).offersSplit)
    }

    @Test("flagged words win over the kind in the outline")
    func outline() {
        #expect(item(.paragraph, issues: 1).outline == .flagged)
        #expect(item(.note(label: "1"), issues: 1).outline == .flagged)
        #expect(item(.note(label: "1")).outline == .note)
        #expect(item(.ignored).outline == .ignored)
        #expect(item(.paragraph).outline == .plain)
    }
}
