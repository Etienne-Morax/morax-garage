// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoraxCockpit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MoraxCockpitKit", targets: ["MoraxCockpitKit"]),
        .executable(name: "MoraxCockpit", targets: ["MoraxCockpit"]),
        .executable(name: "MoraxCockpitMenu", targets: ["MoraxCockpitMenu"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.7")
    ],
    targets: [
        .target(
            name: "MoraxCockpitKit",
            dependencies: [],
            path: "Sources/MoraxCockpitKit",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MoraxCockpit",
            dependencies: [
                "MoraxCockpitKit",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/MoraxCockpit",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MoraxCockpitMenu",
            dependencies: [
                "MoraxCockpitKit"
            ],
            path: "Sources/MoraxCockpitMenu",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MoraxCockpitTests",
            dependencies: [
                "MoraxCockpitKit"
            ],
            path: "Tests/MoraxCockpitTests"
        )
    ]
)
