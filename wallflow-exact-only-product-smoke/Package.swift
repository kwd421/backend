// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallflowExactOnlyProductSmoke",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "wallflow-exact-only-product-smoke",
            targets: ["ExactOnlyProductSmoke"]
        )
    ],
    targets: [
        .executableTarget(name: "ExactOnlyProductSmoke")
    ]
)
