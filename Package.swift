// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FabricTray",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "FabricTray",
            targets: ["FabricTray"]
        )
    ],
    targets: [
        .executableTarget(
            name: "FabricTray",
            path: "Sources/FabricTray",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "FabricTrayTests",
            dependencies: ["FabricTray"],
            path: "Tests/FabricTrayTests"
        )
    ]
)
