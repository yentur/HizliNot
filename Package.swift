// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HizliNot",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "HizliNot",
            path: "Sources/HizliNot"
        )
    ]
)
