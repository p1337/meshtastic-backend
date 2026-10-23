// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClickBridgeKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "ClickBridgeCore", targets: ["ClickBridgeCore"]),
        .library(name: "ClickBridgeBLE", targets: ["ClickBridgeBLE"])
    ],
    targets: [
        .target(name: "ClickBridgeCore"),
        .target(name: "ClickBridgeBLE", dependencies: ["ClickBridgeCore"]),
        .testTarget(name: "ClickBridgeCoreTests", dependencies: ["ClickBridgeCore"],
                    resources: [.copy("Fixtures")])
    ]
)
