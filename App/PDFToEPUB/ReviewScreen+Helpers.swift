import AppModel
import SwiftUI

extension ReviewModel.Kind {
    var isNote: Bool {
        if case .note = self {
            true
        } else {
            false
        }
    }
}

extension ReviewModel.Item {
    /// Flagged blocks stand out; note texts are told apart from the body.
    var outlineColor: Color {
        switch outline {
        case .flagged: .orange
        case .note: .teal
        case .ignored: .gray
        case .plain: .accentColor
        }
    }
}

extension View {
    @ViewBuilder func selectable(_ isOn: Bool) -> some View {
        if isOn {
            textSelection(.enabled)
        } else {
            textSelection(.disabled)
        }
    }
}
