// swift-tools-version: 6.2
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
    ]
)
