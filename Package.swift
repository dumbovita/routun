// swift-tools-version: 5.9
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
        )
    ]
)
