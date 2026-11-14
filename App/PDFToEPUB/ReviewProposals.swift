import AppModel
import Corrections
import SwiftUI

/// The offer to repeat the correction just made, below the review.
struct ProposalBar: View {
    var model: ReviewModel
    @State private var isChoosing = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            message
            Spacer()
            switch model.proposal {
            case .type:
                Button("Choose…") { isChoosing = true }
                Button("Apply to All", action: applyToAll)
            case .word:
                Button("Replace Everywhere", action: model.acceptWordProposal)
            case nil:
                EmptyView()
            }
            Button("Not Now", action: model.dismissProposal)
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $isChoosing) {
            CandidateSheet(model: model)
        }
    }

    @ViewBuilder private var message: some View {
        switch model.proposal {
        case let .type(.heading(level), candidates):
            Text("\(candidates.count) similar blocks look like this one. Make them heading \(level) too?")
        case let .type(.paragraph, candidates):
            Text("\(candidates.count) similar blocks look like this one. Make them paragraphs too?")
        case .type(.ignored, _):
            EmptyView()
        case let .word(find, replacement, occurrences):
            Text("Replace “\(find)” with “\(replacement)” in \(occurrences) other places?")
        case nil:
            EmptyView()
        }
    }

    private func applyToAll() {
        model.acceptTypeProposal(for: Set(model.proposalCandidates.map(\.anchor)))
    }
}

/// The similar blocks, each with a switch, to pick the ones to change.
private struct CandidateSheet: View {
    var model: ReviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<BlockAnchor> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Similar blocks")
                .font(.headline)
            List(model.proposalCandidates) { candidate in
                Toggle(isOn: binding(for: candidate.anchor)) {
                    VStack(alignment: .leading) {
                        Text(candidate.text)
                            .lineLimit(2)
                        Text("Page \(candidate.page + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Button("Select All") { chosen = Set(model.proposalCandidates.map(\.anchor)) }
                Button("Select None") { chosen = [] }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    model.acceptTypeProposal(for: chosen)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { chosen = Set(model.proposalCandidates.map(\.anchor)) }
    }

    private func binding(for anchor: BlockAnchor) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(anchor) },
            set: { isOn in
                if isOn {
                    chosen.insert(anchor)
                } else {
                    chosen.remove(anchor)
                }
            }
        )
    }
}
