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
    // The WebURL library.
    // Includes everything.
    .library(name: "WebURL", targets: ["WebURL"]),

    // The WebURL Core library.
    // Includes the WebURL type, minus anything requiring external dependencies.
    .library(name: "WebURLCore", targets: ["WebURLCore"]),

    // Test support library. Used by WebURLCoreTests and swift-url-tools package.
    // Useful for comparing results with other URL implementations (e.g. JSDOM reference impl).
    .library(name: "WebURLTestSupport", targets: ["WebURLTestSupport"]),
  ],
  dependencies: [
    // Swift-checkit for testing protocol conformances.
    .package(name: "Checkit", url: "https://github.com/karwa/swift-checkit.git", from: "0.0.2"),
  ],
  targets: [
    // Products.
    .target(
      name: "WebURL",
      dependencies: ["WebURLCore"]
    ),
    .target(
      name: "WebURLCore"
    ),
    // Test targets and test support libraries.
    .target(
      name: "WebURLTestSupport",
      dependencies: ["WebURLCore"]
    ),
    .testTarget(
      name: "WebURLCoreTests",
      dependencies: ["WebURLCore", "WebURLTestSupport", "Checkit"],
      resources: [.copy("Resources")]
    ),
  ]
)
