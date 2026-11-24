// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NetKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NetKit",
            targets: ["NetKit"]
        ),
    ],
    
    targets: [
        .target(name: "NetKit"),
        .testTarget(
            name: "NetKitTests",
            dependencies: ["NetKit"]
        )
    ]
)
