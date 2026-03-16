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
    dependencies: [
        // SwiftPM test frameworks are not always present in minimal CLT-only environments.
        // Vendoring swift-testing keeps `swift test` working reliably.
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.12.0")
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
        ),
        .testTarget(
            name: "GitwCoreTests",
            dependencies: [
                "GitwCore",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
