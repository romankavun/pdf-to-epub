// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScanCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "ScanCore",
            targets: [
                "DocumentModel",
                "EPUBExport",
                "OCR",
                "LayoutAnalysis",
                "Importing",
                "Conversion",
                "TextReview",
                "Corrections",
                "ProjectStore",
                "AppModel",
            ]
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
        .target(name: "TextReview"),
        .target(name: "Corrections", dependencies: ["DocumentModel", "LayoutAnalysis", "Conversion"]),
        .target(name: "ProjectStore", dependencies: ["DocumentModel", "LayoutAnalysis", "Conversion", "Corrections"]),
        .target(
            name: "AppModel",
            dependencies: [
                "DocumentModel", "OCR", "Importing", "LayoutAnalysis", "Conversion", "EPUBExport", "TextReview",
                "Corrections", "ProjectStore",
            ]
        ),
        .executableTarget(
            name: "pagescan",
            dependencies: ["DocumentModel", "OCR", "Importing", "Conversion", "EPUBExport"]
        ),
        // Test-only helpers: synthetic page rendering and golden-file comparison.
        .target(
            name: "TestSupport",
            dependencies: ["DocumentModel", "LayoutAnalysis", "Conversion"],
            path: "Tests/TestSupport"
        ),
        .testTarget(
            name: "InvariantTests",
            dependencies: [
                "TestSupport", "AppModel", "ProjectStore", "Corrections", "Conversion", "DocumentModel",
                "EPUBExport", "LayoutAnalysis", "OCR",
            ]
        ),
        .testTarget(
            name: "GoldenPagesTests",
            dependencies: ["TestSupport", "Conversion", "DocumentModel", "LayoutAnalysis", "OCR"]
        ),
        .testTarget(name: "TextReviewTests", dependencies: ["TextReview"]),
        .testTarget(
            name: "CorrectionsTests",
            dependencies: ["Corrections", "Conversion", "DocumentModel", "LayoutAnalysis"]
        ),
        .testTarget(
            name: "ProjectStoreTests",
            dependencies: ["ProjectStore", "Corrections", "Conversion", "DocumentModel", "LayoutAnalysis"]
        ),
        .testTarget(
            name: "AppModelTests",
            dependencies: [
                "AppModel", "Conversion", "DocumentModel", "Importing", "LayoutAnalysis", "TextReview",
                "Corrections", "ProjectStore",
            ]
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
