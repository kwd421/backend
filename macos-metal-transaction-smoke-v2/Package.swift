// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacOSMetalTransactionSmokeV2",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "MetalTransactionSmokeV2",
            targets: ["MetalTransactionSmokeV2"]
        )
    ],
    targets: [
        .executableTarget(name: "MetalTransactionSmokeV2")
    ]
)
