import Corrections
import Styles

public extension ReviewModel {
    /// What changing the type of a style did (see ``changeType(of:to:)``).
    struct StyleTypeChange: Sendable, Equatable {
        /// The style whose blocks were changed, by ``Styles/Style/id``.
        public var style: Styles.Style.ID
        /// The type its blocks were given.
        public var type: BlockType
        /// How many blocks got the type.
        public var changed: Int
        /// How many blocks were left as they are.
        public var skipped: Int
    }

    /// The types the blocks of `style` can be given at once: those a single
    /// block can be changed to in the review, but its own. A figure can only
    /// be ignored; note texts and page furniture have none.
    func typeChoices(for style: Styles.Style) -> [BlockType] {
        let text: [BlockType] = [.paragraph, .heading(level: 1), .heading(level: 2), .heading(level: 3), .ignored]
        return switch style.type {
        case .paragraph: text.filter { $0 != .paragraph }
        case let .heading(level): text.filter { $0 != .heading(level: level) }
        case .figure: [.ignored]
        case .note, .pageFurniture: []
        }
    }

    /// Gives every block of `style` the type `type`: one ordinary type
    /// correction per block, as one step to undo, the way a type
    /// ``Proposal`` is accepted. Blocks the user already gave a type, and
    /// blocks a merge or split changed (they are no longer as recognized),
    /// are left as they are and counted as skipped. The style stays as
    /// recognized; a later change to one of its blocks wins. The result is
    /// also kept in ``styleTypeChange`` until the next change of the project
    /// or of the selected style. A type that is not among
    /// ``typeChoices(for:)`` changes nothing.
    @discardableResult
    func changeType(of style: Styles.Style, to type: BlockType) -> StyleTypeChange {
        guard typeChoices(for: style).contains(type) else {
            return StyleTypeChange(style: style.id, type: type, changed: 0, skipped: 0)
        }
        let anchors = style.members.compactMap { member -> BlockAnchor? in
            guard case let .block(index) = member, project.base.blockSources.indices.contains(index) else { return nil }
            return BlockAnchor(project.base.blockSources[index])
        }
        let changing = anchors.filter(isAsRecognized)
        cancelEditing()
        proposal = nil
        if !changing.isEmpty {
            project.setType(type, for: changing)
            rebuild()
        }
        let change = StyleTypeChange(
            style: style.id, type: type, changed: changing.count, skipped: anchors.count - changing.count
        )
        styleTypeChange = change
        return change
    }
}

extension ReviewModel {
    /// Whether the recognized block at `anchor` still stands as recognized
    /// and undecided: no type of the user's, and no merge or split.
    private func isAsRecognized(_ anchor: BlockAnchor) -> Bool {
        let corrections = project.corrections
        guard corrections.type(for: anchor) == nil,
              project.conversion.blockSources.contains(where: { anchor.matches($0) })
        else { return false }
        return !corrections.corrections.contains { correction in
            switch correction {
            case let .merge(first, second): first.matches(anchor) || second.matches(anchor)
            case let .split(other, _, _): other.matches(anchor)
            case .retype, .edit, .replaceWord: false
            }
        }
    }
}
