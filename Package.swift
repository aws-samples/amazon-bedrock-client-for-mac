// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BedrockLocalWorkbench",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LocalWorkbench", targets: ["LocalWorkbench"])],
    targets: [
        .target(name: "LocalWorkbench", path: "Sources/Bedrock/LocalCore"),
        .testTarget(name: "LocalWorkbenchTests", dependencies: ["LocalWorkbench"], path: "Tests/LocalWorkbenchTests")
    ]
)
