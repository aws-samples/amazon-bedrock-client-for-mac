// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BedrockCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BedrockCore", targets: ["BedrockCore"])],
    targets: [
        .target(name: "BedrockCore", path: "Sources/Bedrock/Core"),
        .testTarget(name: "BedrockCoreTests", dependencies: ["BedrockCore"], path: "Tests/BedrockCoreTests")
    ]
)
