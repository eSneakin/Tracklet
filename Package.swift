// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tracklet",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Tracklet", targets: ["Tracklet"])
    ],
    targets: [
        .executableTarget(name: "Tracklet"),
        .testTarget(name: "TrackletTests", dependencies: ["Tracklet"])
    ]
)
