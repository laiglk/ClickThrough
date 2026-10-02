// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClickThrough",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ClickThrough", targets: ["ClickThrough"])],
    targets: [
        .target(name: "ClickThroughCore"),
        .executableTarget(name: "ClickThrough", dependencies: ["ClickThroughCore"]),
        .executableTarget(name: "ClickThroughCoreTests", dependencies: ["ClickThroughCore"], path: "Tests/ClickThroughCoreTests")
    ]
)
