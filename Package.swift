// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Baguette",
    platforms: [
        .macOS("26.0"),
    ],
    targets: [
        .executableTarget(
            name: "Baguette",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "BaguetteTests",
            dependencies: ["Baguette"]
        ),
    ]
)
