// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScanCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "ScanCore",
            targets: ["DocumentModel", "EPUBExport", "OCR", "LayoutAnalysis", "Importing", "Conversion"]
        ),
        .executable(name: "pagescan", targets: ["pagescan"]),
    ],
    targets: [
        .target(name: "DocumentModel"),
        .target(name: "EPUBExport", dependencies: ["DocumentModel"]),
        .target(name: "OCR"),
        .target(name: "LayoutAnalysis", dependencies: ["DocumentModel", "OCR"]),
        .target(name: "Importing"),
        .target(name: "Conversion", dependencies: ["DocumentModel", "OCR", "LayoutAnalysis"]),
        .executableTarget(
            name: "pagescan",
            dependencies: ["DocumentModel", "OCR", "Importing", "Conversion", "EPUBExport"]
        ),
        .testTarget(name: "ImportingTests", dependencies: ["Importing"]),
        .testTarget(name: "ConversionTests", dependencies: ["Conversion", "DocumentModel", "OCR"]),
        .testTarget(name: "OCRTests", dependencies: ["OCR"]),
        .testTarget(name: "pagescanTests", dependencies: ["pagescan"]),
        .testTarget(name: "LayoutAnalysisTests", dependencies: ["LayoutAnalysis", "DocumentModel", "OCR"]),
        .testTarget(name: "DocumentModelTests", dependencies: ["DocumentModel"]),
        .testTarget(name: "EPUBExportTests", dependencies: ["EPUBExport", "DocumentModel"]),
    ],
    swiftLanguageModes: [.v6]
)
