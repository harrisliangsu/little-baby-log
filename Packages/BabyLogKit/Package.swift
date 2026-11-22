// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BabyLogKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/6tail/lunar-swift.git", from: "1.1.9"),
    ],
    products: [
        .library(name: "BabyLogKit", targets: ["BabyLogKit"]),
    ],
    targets: [
        .target(name: "BabyLogKit", dependencies: ["LunarSwift"]),
        .testTarget(name: "BabyLogKitTests", dependencies: ["BabyLogKit"]),
    ],
    swiftLanguageModes: [.v5]
)
