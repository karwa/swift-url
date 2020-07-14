// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Base",
  products: [
    .library(name: "Base", targets: ["Base"]),
    .library(name: "WebURL", targets: ["WebURL"]),
    .executable(name: "BaseBenchmarks", targets: ["BaseBenchmarks"]),
  ],
  dependencies: [
    .package(  // Swift-checkit for testing protocol conformances.
      url: "https://github.com/karwa/swift-checkit.git",
      .branch("master"))
  ],
  targets: [
    .target(name: "Algorithms"),
    .testTarget(name: "AlgorithmsTests", dependencies: ["Algorithms", "Checkit"]),

    .target(name: "Concurrency"),
    .testTarget(name: "ConcurrencyTests", dependencies: ["Concurrency"]),

    .target(name: "WebURL", dependencies: ["Algorithms"]),
    .testTarget(name: "WebURLTests", dependencies: ["WebURL", "BaseTestUtils"]),

    .target(name: "Base", dependencies: ["Algorithms", "Concurrency", "WebURL"]),
    .target(name: "BaseTestUtils", dependencies: ["Base"]),
    .testTarget(name: "BaseTests", dependencies: ["Base"]),
    
    .target(name: "BaseBenchmarks", dependencies: ["Base"]),
  ]
)
