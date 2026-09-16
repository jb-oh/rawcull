// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RawCull",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../favren-works/brand/apple/FavrenUI")
    ],
    targets: [
        .executableTarget(
            name: "RawCull",
            dependencies: ["FavrenUI"]
        ),
        .testTarget(
            name: "RawCullTests",
            dependencies: ["RawCull"]
        )
    ]
)
