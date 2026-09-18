// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyboardCore",
    platforms: [.iOS("18.0"), .macOS(.v13)],
    products: [.library(name: "KeyboardCore", targets: ["KeyboardCore"])],
    targets: [
        .target(name: "KeyboardCore", path: "Shared/Core"),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"], path: "Tests/Core")
    ]
)
