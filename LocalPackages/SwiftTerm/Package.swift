// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftTerm",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "SwiftTerm", targets: ["SwiftTerm"])
    ],
    targets: [
        .target(
            name: "SwiftTerm",
            dependencies: [],
            path: "Sources/SwiftTerm",
            exclude: ["Mac/README.md"]
        )
    ]
)
