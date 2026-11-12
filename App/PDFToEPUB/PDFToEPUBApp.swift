import SwiftUI

/// Application entry point. The app is a thin shell over the `ScanCore`
/// package; conversion logic lives there, not here.
@main
struct PDFToEPUBApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
