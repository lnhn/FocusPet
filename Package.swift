// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FocusPet",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "FocusPet",
            path: "Sources/FocusPet",
            exclude: ["Info.plist"],
            resources: [
                .copy("PetAssets"),
                .copy("Sounds")
            ]
        )
    ]
)
