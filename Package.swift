// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CardVoice",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CardVoice", targets: ["CardVoice"])],
    targets: [.executableTarget(name: "CardVoice", path: "Sources/CardVoice")]
)
