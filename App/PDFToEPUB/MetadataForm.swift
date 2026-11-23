import AppModel
import SwiftUI

/// Document metadata and the button that starts the conversion; when the
/// document already has a project, opening it or starting over instead.
struct MetadataForm: View {
    @Bindable var model: ConversionModel
    var chooseFolder: () -> Void
    @State private var isConfirmingStartOver = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Source") {
                    HStack {
                        Text(model.input?.path(percentEncoded: false) ?? "")
                            .lineLimit(1)
                            .truncationMode(.head)
                        Button("Change…", action: chooseFolder)
                    }
                }
                LabeledContent("Pages", value: model.pageCount.formatted())
            }
            if let existing = model.existingProject {
                Section {
                    LabeledContent("Already converted") {
                        HStack {
                            Text(existing.lastPathComponent)
                            Button("Open Project", action: model.openExistingProject)
                                .accessibilityIdentifier("openExistingProjectButton")
                        }
                    }
                } footer: {
                    Text(
                        // swiftlint:disable:next line_length
                        "Start Over converts the document again into a new project and moves this one, with its corrections, to the Trash."
                    )
                }
            }
            Section {
                TextField("Title", text: $model.title)
                TextField("Author", text: $model.author)
                Picker("Language", selection: $model.language) {
                    Text("Ukrainian").tag("uk")
                    Text("English").tag("en")
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                if model.existingProject == nil {
                    Button("Convert", action: model.start)
                        .accessibilityIdentifier("convertButton")
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canStart)
                } else {
                    Button("Start Over…") { isConfirmingStartOver = true }
                        .accessibilityIdentifier("startOverButton")
                        .disabled(!model.canStartOver)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .confirmationDialog(
            "Start over and discard the corrections?", isPresented: $isConfirmingStartOver
        ) {
            Button("Start Over", role: .destructive, action: model.startOver)
        } message: {
            Text(
                "The existing project and its corrections are moved to the Trash once the new conversion has finished."
            )
        }
    }
}
