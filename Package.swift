// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "saguri",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Saguri", targets: ["Saguri"])
    ],
    targets: [
        .target(name: "Saguri"),
        .testTarget(name: "SaguriTests", dependencies: ["Saguri"]),
    ]
)
