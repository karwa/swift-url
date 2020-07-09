// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Base",
    products: [
        .library(name: "Base", targets: ["Base"]),
        .library(name: "WebURL", targets: ["URL"]),
        .executable(name: "URLBenchmarks", targets: ["URLBenchmarks"])
    ],
    dependencies: [
        .package( // Swift-checkit for testing protocol conformances.
            url: "https://github.com/karwa/swift-checkit.git",
            .branch("master"))
    ],
    targets: [
        .target(name: "Algorithms"),
        .testTarget(name: "AlgorithmsTests", dependencies: ["Algorithms", "Checkit"]),

        .target(name: "Concurrency"),
        .testTarget(name: "ConcurrencyTests", dependencies: ["Concurrency"]),

        .target(name: "URL", dependencies: ["Algorithms"]),
        .target(name: "URLBenchmarks", dependencies: ["URL"]),
        .testTarget(name: "URLTests", dependencies: ["URL"]),
        
        .target(name: "Base", dependencies: ["Algorithms", "Concurrency", "URL"]),
        .testTarget(name: "BaseTests", dependencies: ["Base"]),
    ]
)
