// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacOSMetalTransactionSmoke",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MetalTransactionSmoke",
            targets: ["MetalTransactionSmoke"]
        )
    ],
    targets: [
        .executableTarget(name: "MetalTransactionSmoke")
    ]
)
