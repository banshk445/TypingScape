// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TypingScape",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TypingScape",
            exclude: ["Resources/Info.plist"],
            resources: [.copy("Resources/mountain-outline.png"), .copy("Resources/album-cover.png")],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/TypingScape/Resources/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "TypingScapeTests",
            dependencies: ["TypingScape"]
        ),
    ]
)
