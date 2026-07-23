// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwMediaKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SwMediaKit", targets: ["SwMediaKit"]),
    ],
    targets: [
        .target(name: "SwMediaKit"),
        .testTarget(name: "SwMediaKitTests", dependencies: ["SwMediaKit"]),
    ]
)
