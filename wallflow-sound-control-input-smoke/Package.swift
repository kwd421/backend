// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallflowSoundControlInputSmoke",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "wallflow-sound-control-input-smoke",
            targets: ["SoundControlInputSmoke"]
        )
    ],
    targets: [
        .executableTarget(name: "SoundControlInputSmoke")
    ]
)
