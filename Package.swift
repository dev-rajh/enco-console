// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EncoConsole",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "EncoConsole",
            path: "Sources/EncoConsole",
            linkerSettings: [
                .linkedFramework("IOBluetooth")
            ]
        )
    ]
)
