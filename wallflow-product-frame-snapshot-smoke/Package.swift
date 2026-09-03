// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallflowProductFrameSnapshotSmoke",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "wallflow-product-frame-snapshot-smoke",
            targets: ["SnapshotSmoke"]
        ),
        .executable(
            name: "wallflow-metal-type-boundary-smoke",
            targets: ["MetalTypeBoundarySmoke"]
        ),
        .executable(
            name: "wallflow-audio-publication-owner-smoke",
            targets: ["AudioPublicationOwnerSmoke"]
        )
    ],
    targets: [
        .executableTarget(name: "SnapshotSmoke"),
        .executableTarget(name: "MetalTypeBoundarySmoke"),
        .executableTarget(name: "AudioPublicationOwnerSmoke")
    ]
)
