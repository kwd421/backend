// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallflowObjectAdmissionSmoke",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "wallflow-object-admission-smoke",
            targets: ["ObjectAdmissionSmoke"]
        )
    ],
    targets: [
        .executableTarget(name: "ObjectAdmissionSmoke")
    ]
)
