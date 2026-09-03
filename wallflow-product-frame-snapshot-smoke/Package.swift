// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallflowProductFrameSnapshotSmoke",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "wallflow-product-frame-snapshot-smoke",
            targets: ["SnapshotSmoke"]
        )
    ],
    targets: [
        .executableTarget(name: "SnapshotSmoke")
    ]
)
