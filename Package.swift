// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "gitw",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "gitw", targets: ["gitw"]),
        .executable(name: "gitw-askpass", targets: ["gitw-askpass"])
    ],
    targets: [
        .target(
            name: "GitwCore"
        ),
        .executableTarget(
            name: "gitw",
            dependencies: ["GitwCore"]
        ),
        .executableTarget(
            name: "gitw-askpass",
            dependencies: ["GitwCore"]
        )
    ]
)
