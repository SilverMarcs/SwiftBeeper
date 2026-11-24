// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RelayUpdates",
    platforms: [.macOS("26.2"), .iOS("26.2")],
    products: [.library(name: "RelayUpdates", targets: ["RelayUpdates"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(
            name: "RelayUpdates",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS]))
            ]
        )
    ]
)
