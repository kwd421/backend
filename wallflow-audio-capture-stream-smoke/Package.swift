// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallflowAudioCaptureStreamSmoke",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "wallflow-audio-capture-stream-smoke",
            targets: ["StreamSmoke"]
        ),
        .executable(
            name: "wallflow-avfoundation-tap-type-smoke",
            targets: ["AVFoundationTapTypeSmoke"]
        )
    ],
    targets: [
        .executableTarget(name: "StreamSmoke"),
        .executableTarget(name: "AVFoundationTapTypeSmoke")
    ]
)
