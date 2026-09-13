// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "routun",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "routun", targets: ["routun"])
    ],
    targets: [
        .executableTarget(
            name: "routun",
            path: "Sources"
        ),
        .testTarget(
            name: "routunTests",
            dependencies: ["routun"],
            path: "Tests/routunTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
