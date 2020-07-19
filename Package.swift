// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "swift-url",
  products: [
    .library(name: "WebURL", targets: ["WebURL"]),
    .executable(name: "URLBenchmarks", targets: ["URLBenchmarks"]),
  ],
  dependencies: [
    // Swift-checkit for testing protocol conformances.
    .package(url: "https://github.com/karwa/swift-checkit.git", from: "0.0.1"),
  ],
  targets: [
    .target(name: "Algorithms"),
    .testTarget(name: "AlgorithmsTests", dependencies: ["Algorithms", "Checkit"]),

    .target(name: "WebURL", dependencies: ["Algorithms"]),
    
    .target(name: "URLTestUtils", dependencies: ["WebURL"]),
    .testTarget(name: "WebURLTests", dependencies: ["WebURL", "URLTestUtils"]),
    
    .target(name: "URLBenchmarks", dependencies: ["WebURL"]),
  ]
)
