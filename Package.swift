// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MotionSpec",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MotionSpec", targets: ["MotionSpec"]),
        .library(name: "MotionSpecCore", targets: ["MotionSpecCore"])
    ],
    targets: [
        .executableTarget(
            name: "MotionSpec",
            dependencies: ["MotionSpecCore"]
        ),
        .target(
            name: "MotionSpecCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "MotionSpecCoreTests",
            dependencies: ["MotionSpecCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "MotionSpecTests",
            dependencies: ["MotionSpec"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
