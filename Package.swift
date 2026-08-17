// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "quill",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.0"),
    ],
    targets: [
        .target(name: "QuillArtwork"),
        .executableTarget(
            name: "quill",
            dependencies: [
                "QuillArtwork",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed Info.plist into the binary so TCC can attribute
                // system-audio-capture permissions consistently whether
                // quill runs from the app bundle or as a direct executable.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/quill/Info.plist",
                ])
            ]
        ),
        .executableTarget(
            name: "quill-icon",
            dependencies: ["QuillArtwork"]
        ),
    ]
)
