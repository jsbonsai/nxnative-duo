// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DuoBuilder",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "DuoBuilder", path: "Sources/DuoBuilder"),
        .testTarget(name: "DuoBuilderTests", dependencies: ["DuoBuilder"], path: "Tests/DuoBuilderTests"),
    ]
)
