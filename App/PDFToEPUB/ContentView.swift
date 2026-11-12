import SwiftUI

/// Placeholder start screen shown until the import flow is built.
struct ContentView: View {
    var body: some View {
        ContentUnavailableView(
            "No document open",
            systemImage: "document.closed",
            description: Text("Importing a PDF or a folder of page images is not implemented yet.")
        )
        .frame(minWidth: 640, minHeight: 420)
    }
}

#Preview {
    ContentView()
}
