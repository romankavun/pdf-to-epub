// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScanCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ScanCore", targets: ["DocumentModel"]),
    ],
    targets: [
        .target(name: "DocumentModel"),
        .testTarget(name: "DocumentModelTests", dependencies: ["DocumentModel"]),
    ],
    swiftLanguageModes: [.v6]
)
