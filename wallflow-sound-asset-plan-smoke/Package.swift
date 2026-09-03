// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallflowSoundAssetPlanSmoke",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "wallflow-sound-asset-plan-smoke",
            targets: ["SoundAssetPlanSmoke"]
        )
    ],
    targets: [
        .executableTarget(name: "SoundAssetPlanSmoke")
    ]
)
