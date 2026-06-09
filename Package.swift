// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacWallpaperEngine",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MacWallpaperEngineCore",
            targets: ["MacWallpaperEngineCore"]
        ),
        .executable(
            name: "MacWallpaperEngine",
            targets: ["MacWallpaperEngineApp"]
        )
    ],
    targets: [
        .target(
            name: "MacWallpaperEngineCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .executableTarget(
            name: "MacWallpaperEngineApp",
            dependencies: ["MacWallpaperEngineCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftData"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(
            name: "MacWallpaperEngineCoreTests",
            dependencies: ["MacWallpaperEngineCore"]
        )
    ]
)
