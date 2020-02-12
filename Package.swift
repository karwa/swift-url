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
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .target(name: "Base"),
        .testTarget(name: "BaseTests", dependencies: ["Base"]),
        
        .target(name: "Algorithms"),
        .testTarget(name: "AlgorithmsTests", dependencies: ["Algorithms", "TestUtilities"]),
        
        .target(name: "Concurrency"),
        .testTarget(name: "ConcurrencyTests", dependencies: ["Concurrency"]),
        
        .target(name: "TestUtilities"),
        .testTarget(name: "TestUtilitiesTests", dependencies: ["TestUtilities"]),
        
//        .target(name: "FileSystem"),
//        .testTarget(name: "FileSystemTests", dependencies: ["FileSystem"]),
    ]
)
