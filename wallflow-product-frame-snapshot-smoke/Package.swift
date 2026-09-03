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
        )
    ],
    targets: [
        .executableTarget(name: "SnapshotSmoke"),
        .executableTarget(name: "MetalTypeBoundarySmoke")
    ]
)
