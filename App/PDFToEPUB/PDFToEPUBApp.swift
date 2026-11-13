import AppModel
import SwiftUI

/// Application entry point. The app is a thin shell over the `ScanCore`
/// package; conversion logic lives there, not here.
@main
struct PDFToEPUBApp: App {
    @State private var model = ConversionModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
