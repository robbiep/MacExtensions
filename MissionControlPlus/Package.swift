// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MissionControlPlus",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MissionControlPlusCore", targets: ["MissionControlPlusCore"]),
        .executable(name: "MissionControlPlus", targets: ["MissionControlPlus"]),
    ],
    targets: [
        .target(
            name: "MissionControlPlusCore",
            path: "Sources/MissionControlPlusCore"
        ),
        .executableTarget(
            name: "MissionControlPlus",
            dependencies: ["MissionControlPlusCore"],
            path: "Sources/MissionControlPlus",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "MissionControlPlusCoreTests",
            dependencies: ["MissionControlPlusCore"],
            path: "Tests/MissionControlPlusCoreTests"
        ),
    ]
)
