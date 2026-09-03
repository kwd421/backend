// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacOSMetalSendableCompletionSmoke",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "MetalSendableCompletionSmoke",
            targets: ["MetalSendableCompletionSmoke"]
        )
    ],
    targets: [
        .executableTarget(name: "MetalSendableCompletionSmoke")
    ]
)
