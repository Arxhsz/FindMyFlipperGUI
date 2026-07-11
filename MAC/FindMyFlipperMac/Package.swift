// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FindMyFlipperMac",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "FindMyFlipperMac",
            path: "Sources/FindMyFlipperMac",
            exclude: ["FindMyFlipperMac.entitlements"],
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/PreviewData")
            ]
        ),
        .testTarget(
            name: "FindMyFlipperMacTests",
            dependencies: ["FindMyFlipperMac"],
            path: "Tests/FindMyFlipperMacTests"
        )
    ]
)
// Bundle ID: com.findmyflipper.mac
