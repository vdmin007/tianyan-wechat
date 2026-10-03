// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TianYanWeChat",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "TianYanWeChat",
            path: "Sources/TianYanWeChat"
        )
    ]
)