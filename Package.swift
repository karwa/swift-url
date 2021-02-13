// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "swift-url",
  products: [
    .library(name: "WebURL", targets: ["WebURL"]),
    .library(name: "WebURLTestSupport", targets: ["WebURLTestSupport"]),
  ],
  dependencies: [
    // Swift-checkit for testing protocol conformances.
    .package(url: "https://github.com/karwa/swift-checkit.git", from: "0.0.2"),
  ],
  targets: [
    .target(name: "Algorithms"),
    .testTarget(name: "AlgorithmsTests", dependencies: ["Algorithms", "Checkit"]),
    
    .target(name: "WebURL", dependencies: ["Algorithms"]),
    .target(name: "WebURLTestSupport", dependencies: ["WebURL"]),
    .testTarget(name: "WebURLTests", dependencies: ["WebURL", "WebURLTestSupport", "Checkit"]),
  ]
)
