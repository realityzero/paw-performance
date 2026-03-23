// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PawPerformance",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PawPerformance", targets: ["PawPerformance"])
    ],
    targets: [
        .executableTarget(
            name: "PawPerformance",
            path: "PawPerformance",
            exclude: [
                "App/Info.plist"
            ],
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
