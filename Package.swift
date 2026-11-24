// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "NetKit", targets: ["NetKit"])
    ],
    targets: [
        .target(name: "NetKit"),
        .testTarget(name: "NetKitTests", dependencies: ["NetKit"])
    ]
)
