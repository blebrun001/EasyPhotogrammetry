// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "EasyPhotogrammetry",
    platforms: [
        .macOS("26.0"),
    ],
    targets: [
        .executableTarget(
            name: "EasyPhotogrammetry",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "EasyPhotogrammetryTests",
            dependencies: ["EasyPhotogrammetry"]
        ),
    ]
)
