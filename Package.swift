// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "machidpi",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "CGVirtualDisplayShim",
            path: "Sources/CGVirtualDisplayShim",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MacHiDPIKit",
            dependencies: ["CGVirtualDisplayShim"],
            path: "Sources/MacHiDPIKit"
        ),
        .executableTarget(
            name: "machidpi",
            dependencies: ["MacHiDPIKit"],
            path: "Sources/machidpi"
        ),
        .testTarget(
            name: "MacHiDPIKitTests",
            dependencies: ["MacHiDPIKit"],
            path: "Tests/MacHiDPIKitTests"
        ),
    ]
)
