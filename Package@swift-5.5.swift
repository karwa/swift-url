// swift-tools-version:5.5

// Copyright The swift-url Contributors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import PackageDescription

let package = Package(
  name: "swift-url",
  products: [
    // Core functionality.
    .library(name: "WebURL", targets: ["WebURL"]),

    // Integration with swift-system.
    // FIXME: This should become a cross-import overlay once they exist and are supported by SwiftPM.
    .library(name: "WebURLSystemExtras", targets: ["WebURLSystemExtras"]),

    // Integration with Foundation.
    // FIXME: This should become a cross-import overlay once they exist and are supported by SwiftPM.
    .library(name: "WebURLFoundationExtras", targets: ["WebURLFoundationExtras"]),

    // Test support library.
    // Various infrastructure components to run the URL web-platform-tests and other tests contained in JSON files.
    // Used by https://github.com/karwa/swift-url-tools to provide a GUI test runner.
    .library(name: "WebURLTestSupport", targets: ["WebURLTestSupport"]),
  ],
  dependencies: [
    // swift-system for WebURLSystemExtras.
    .package(url: "https://github.com/apple/swift-system.git", .upToNextMajor(from: "1.0.0")),

    // [Test Only] No-dependency HTTP server for testing Foundation extensions.
    .package(name: "Swifter", url: "https://github.com/httpswift/swifter.git", .upToNextMajor(from: "1.5.0")),

    // [Test Only] Checkit for testing protocol conformances.
    .package(name: "Checkit", url: "https://github.com/karwa/swift-checkit.git", from: "0.0.2"),
  ],
  targets: [
    // Products.
    .target(
      name: "IDNA"
    ),
    .target(
      name: "WebURL",
      dependencies: ["IDNA"],
      exclude: ["WebURL.docc"]
    ),
    .target(
      name: "WebURLSystemExtras",
      dependencies: ["WebURL", .product(name: "SystemPackage", package: "swift-system")]
    ),
    .target(
      name: "WebURLFoundationExtras",
      dependencies: ["WebURL"]
    ),
    .target(
      name: "WebURLTestSupport",
      dependencies: ["WebURL"],
      resources: [.copy("TestFilesData")]
    ),
    // Tests.
    .testTarget(
      name: "IDNATests",
      dependencies: ["IDNA", "WebURLTestSupport"]
    ),
    .testTarget(
      name: "WebURLTests",
      dependencies: ["WebURL", "WebURLTestSupport", "Checkit"]
    ),
    .testTarget(
      name: "WebURLDeprecatedAPITests",
      dependencies: ["WebURL"]
    ),
    .testTarget(
      name: "WebURLSystemExtrasTests",
      dependencies: ["WebURLSystemExtras", "WebURL", .product(name: "SystemPackage", package: "swift-system")]
    ),
    .testTarget(
      name: "WebURLFoundationExtrasTests",
      dependencies: ["WebURLFoundationExtras", "WebURLTestSupport", "WebURL"],
      resources: [.copy("Resources")]
    ),
    .testTarget(
      name: "WebURLFoundationExtensionsTests",
      dependencies: [
        "WebURLFoundationExtras", "WebURL",
        .product(name: "Swifter", package: "Swifter", condition: .when(platforms: [.macOS, .iOS, .watchOS, .tvOS, .linux]))
      ]
    ),
  ]
)
