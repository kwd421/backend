// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallflowMetalPairSmoke",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WallflowMetalPairSmoke", targets: ["WallflowMetalPairSmoke"])
    ],
    targets: [
        .executableTarget(name: "WallflowMetalPairSmoke")
    ]
)
