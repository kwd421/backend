// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallflowSceneScriptAdmissionSmoke",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "wallflow-scenescript-admission-smoke",
            targets: ["SceneScriptAdmissionSmoke"]
        )
    ],
    targets: [
        .executableTarget(name: "SceneScriptAdmissionSmoke")
    ]
)
