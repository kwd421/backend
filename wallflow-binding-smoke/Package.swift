// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallflowBindingSmoke",
    products: [
        .executable(name: "WallflowBindingSmoke", targets: ["WallflowBindingSmoke"])
    ],
    targets: [
        .executableTarget(name: "WallflowBindingSmoke")
    ]
)
