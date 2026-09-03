// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallflowWPEAudioOccurrenceSmoke",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "wallflow-wpe-audio-occurrence-smoke",
            targets: ["WPEAudioOccurrenceSmoke"]
        )
    ],
    targets: [
        .executableTarget(name: "WPEAudioOccurrenceSmoke")
    ]
)
