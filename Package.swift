// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clipboard",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Clipboard", targets: ["Clipboard"])
    ],
    targets: [
        .executableTarget(
            name: "Clipboard",
            dependencies: [],
            path: "Sources/Clipboard",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        )
    ]
)
