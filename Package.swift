// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GPU-Monitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "GPU-Monitor"),
    ]
)
