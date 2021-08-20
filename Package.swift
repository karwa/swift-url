// swift-tools-version:5.3

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

    // Test support library.
    // Various infrastructure components to run the URL web-platform-tests and other tests contained in JSON files.
    // Used by https://github.com/karwa/swift-url-tools to provide a GUI test runner.
    .library(name: "WebURLTestSupport", targets: ["WebURLTestSupport"]),
  ],
  dependencies: [
    // swift-system for WebURLSystemExtras.
    // FIXME: Move to a tagged release which includes https://github.com/apple/swift-system/pull/51
    .package(url: "https://github.com/apple/swift-system.git", .branch("main")),

    // swift-checkit for testing protocol conformances. Test-only dependency.
    .package(name: "Checkit", url: "https://github.com/karwa/swift-checkit.git", from: "0.0.2"),
  ],
  targets: [
    // Products.
    .target(
      name: "WebURL"
    ),
    .target(
      name: "WebURLSystemExtras",
      dependencies: ["WebURL", .product(name: "SystemPackage", package: "swift-system", condition: .when(platforms: [
        .android, .linux, .wasi, .windows
      ]))]
    ),
    .target(
      name: "WebURLTestSupport",
      dependencies: ["WebURL"]
    ),
		// Tests.
    .testTarget(
      name: "WebURLTests",
      dependencies: ["WebURL", "WebURLTestSupport", "Checkit"],
      resources: [.copy("Resources")]
    ),
    .testTarget(
      name: "WebURLSystemExtrasTests",
      dependencies: ["WebURLSystemExtras", "WebURL", .product(name: "SystemPackage", package: "swift-system")]
    ),
  ]
)
