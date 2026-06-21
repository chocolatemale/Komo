// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Komo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Komo",
            path: "Sources/Komo"
        )
    ],
    swiftLanguageModes: [.v5]
)
