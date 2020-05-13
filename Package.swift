// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Base",
    products: [
        .library(name: "Base", targets: [
            "Base", "Algorithms", "Concurrency", //"FileSystem"
        ]),

        .library(name: "TestUtilities", targets: ["TestUtilities"]),

    ],
    dependencies: [
        .package( // SE-0270: Add Collection Operations on Noncontiguous Elements.
            url: "https://github.com/apple/swift-se0270-range-set",
            from: "1.0.0"),
    ],
    targets: [
        .target(name: "Base"),
        .testTarget(name: "BaseTests", dependencies: ["Base"]),

        .target(name: "Algorithms"),
        .testTarget(name: "AlgorithmsTests", dependencies: ["Algorithms", "TestUtilities"]),

        .target(name: "URL", dependencies: ["Algorithms", "SE0270_RangeSet"]),
        .testTarget(name: "URLTests", dependencies: ["URL"]),

        .target(name: "Concurrency"),
        .testTarget(name: "ConcurrencyTests", dependencies: ["Concurrency"]),

        .target(name: "TestUtilities"),
        .testTarget(name: "TestUtilitiesTests", dependencies: ["TestUtilities"]),

        //        .target(name: "FileSystem"),
        //        .testTarget(name: "FileSystemTests", dependencies: ["FileSystem"]),
    ]
)
