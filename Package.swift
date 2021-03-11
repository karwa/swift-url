// swift-tools-version:5.1

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
    .library(name: "WebURL", targets: ["WebURL"]),
    .library(name: "WebURLTestSupport", targets: ["WebURLTestSupport"]),
  ],
  dependencies: [
    // Swift-checkit for testing protocol conformances.
    .package(url: "https://github.com/karwa/swift-checkit.git", from: "0.0.2"),
  ],
  targets: [
    .target(name: "WebURL"),
    .target(name: "WebURLTestSupport", dependencies: ["WebURL"]),
    .testTarget(name: "WebURLTests", dependencies: ["WebURL", "WebURLTestSupport", "Checkit"]),
  ]
)
