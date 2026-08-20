// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TypingScape",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TypingScape",
            exclude: ["Resources/Info.plist"],
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
            dependencies: ["TypingScape"],
            // Photos aren't shipped as presets anymore, but the photo mask
            // pipeline is still live for user-uploaded images — these keep
            // `SubjectMaskGenerator` covered against real photos.
            resources: [.copy("Fixtures/mountain-outline.png"), .copy("Fixtures/album-cover.png")]
        ),
    ]
)
