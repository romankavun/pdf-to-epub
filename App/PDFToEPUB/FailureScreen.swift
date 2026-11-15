import AppModel
import SwiftUI

/// What went wrong with opening or converting a document, and the ways on.
struct FailureScreen: View {
    var failure: ConversionModel.Failure
    /// Whether a document is still open, so converting it again makes sense.
    var canRetry: Bool
    var retry: () -> Void
    var chooseFolder: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Could not convert the document", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if canRetry {
                Button("Try Again", action: retry)
            }
            Button("Choose Folder or PDF…", action: chooseFolder)
        }
        .accessibilityIdentifier("failureScreen")
    }

    private var message: LocalizedStringKey {
        switch failure {
        case .notAFolder: "This is not a folder."
        case .noImages: "The folder has no page images (PNG, JPEG, TIFF or HEIC)."
        case .pdfUnreadable: "This file is not a PDF that can be read."
        case .pdfPasswordRequired: "The PDF is protected by a password. Remove the password and try again."
        case .pdfNoPages: "The PDF has no pages."
        case .recognitionTimedOut: "Text recognition stopped responding. Try again."
        case let .other(description): "Unexpected error: \(description)"
        }
    }
}
