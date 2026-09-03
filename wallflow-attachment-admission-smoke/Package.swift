// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallflowAttachmentAdmissionSmoke",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "wallflow-attachment-admission-smoke",
            targets: ["AttachmentAdmissionSmoke"]
        )
    ],
    targets: [
        .executableTarget(name: "AttachmentAdmissionSmoke")
    ]
)
