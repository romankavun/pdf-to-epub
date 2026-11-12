// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScanCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ScanCore", targets: ["DocumentModel", "EPUBExport"]),
    ],
    targets: [
        .target(name: "DocumentModel"),
        .target(name: "EPUBExport", dependencies: ["DocumentModel"]),
        .testTarget(name: "DocumentModelTests", dependencies: ["DocumentModel"]),
        .testTarget(name: "EPUBExportTests", dependencies: ["EPUBExport", "DocumentModel"]),
    ],
    swiftLanguageModes: [.v6]
)
