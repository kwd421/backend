// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallflowProductPlanAdmissionSmoke",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "wallflow-product-plan-admission-smoke",
            targets: ["ProductPlanAdmissionSmoke"]
        )
    ],
    targets: [
        .executableTarget(name: "ProductPlanAdmissionSmoke")
    ]
)
