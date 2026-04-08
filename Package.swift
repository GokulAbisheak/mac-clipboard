// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacClipboard",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacClipboard", targets: ["MacClipboard"])
    ],
    targets: [
        .executableTarget(
            name: "MacClipboard",
            dependencies: [],
            path: "Sources/MacClipboard",
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        )
    ]
)
