// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppOffice",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "OfficeCore"),
        .executableTarget(name: "officectl", dependencies: ["OfficeCore"]),
        .executableTarget(name: "AppOffice", dependencies: ["OfficeCore"]),
        .testTarget(name: "OfficeCoreTests", dependencies: ["OfficeCore"]),
    ]
)
