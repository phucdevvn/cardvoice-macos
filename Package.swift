// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CardVoice",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CardVoice", targets: ["CardVoice"])],
    dependencies: [
        .package(url: "https://github.com/k2-fsa/sherpa-onnx", exact: "1.13.6")
    ],
    targets: [
        .executableTarget(
            name: "CardVoice",
            dependencies: [
                .product(name: "sherpa-onnx", package: "sherpa-onnx")
            ],
            path: "Sources/CardVoice"
        ),
        .testTarget(name: "CardVoiceTests", dependencies: ["CardVoice"], path: "Tests/CardVoiceTests")
    ]
)
