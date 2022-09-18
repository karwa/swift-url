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

var package = Package(
  name: "swift-url",
  products: [

    // 🧩 Core functionality.
    //    The WebURL type. You definitely want this.
    .library(name: "WebURL", targets: ["WebURL"]),

    // 🔗 Integration with swift-system.
    //    Adds WebURL <-> FilePath conversions.
    .library(name: "WebURLSystemExtras", targets: ["WebURLSystemExtras"]),

    // 🔗 Integration with Foundation.
    //    Adds WebURL <-> Foundation.URL conversions, and URLSession integration.
    .library(name: "WebURLFoundationExtras", targets: ["WebURLFoundationExtras"]),

    // 🧰 Support Libraries (internal use only).
    // =========================================
    // These libraries expose some convenient hooks for testing, benchmarking, and other tools
    // - either in this repo or at <https://github.com/karwa/swift-url-tools>.
    .library(name: "_WebURLIDNA", targets: ["IDNA"]),
    .library(name: "_WebURLTestSupport", targets: ["WebURLTestSupport"]),

  ],
  dependencies: [

    // 🔗 Integrations.
    // ================
    // WebURLSystemExtras supports swift-system 1.0+.
    .package(url: "https://github.com/apple/swift-system.git", .upToNextMajor(from: "1.0.0")),

    // 🧪 Test-Only Dependencies.
    // ==========================
    // Checkit - Exercises for stdlib protocol conformances.
    .package(name: "Checkit", url: "https://github.com/karwa/swift-checkit.git", from: "0.0.2"),

  ],
  targets: [

    // 🗺 Unicode and IDNA.
    // ====================

    .target(
      name: "UnicodeDataStructures",
      swiftSettings: [.define("WEBURL_UNICODE_PARSE_N_PRINT", .when(configuration: .debug))]
    ),
    .testTarget(
      name: "UnicodeDataStructuresTests",
      dependencies: ["UnicodeDataStructures"],
      resources: [.copy("GenerateData/TableDefinitions")]
    ),

    .target(
      name: "IDNA",
      dependencies: ["UnicodeDataStructures"]
    ),
    .testTarget(
      name: "IDNATests",
      dependencies: ["IDNA", "WebURLTestSupport"]
    ),

    // 🌐 WebURL.
    // ==========

    .target(
      name: "WebURL",
      dependencies: ["IDNA"],
      exclude: ["WebURL.docc"]
    ),
    .target(
      name: "WebURLTestSupport",
      dependencies: ["WebURL", "IDNA"],
      resources: [.copy("TestFilesData")]
    ),
    .testTarget(
      name: "WebURLTests",
      dependencies: ["WebURL", "WebURLTestSupport", "Checkit"]
    ),
    .testTarget(
      name: "WebURLDeprecatedAPITests",
      dependencies: ["WebURL"]
    ),

    // 🔗 WebURLSystemExtras.
    // ======================

    .target(
      name: "WebURLSystemExtras",
      dependencies: ["WebURL", .product(name: "SystemPackage", package: "swift-system")]
    ),
    .testTarget(
      name: "WebURLSystemExtrasTests",
      dependencies: ["WebURLSystemExtras", "WebURL", .product(name: "SystemPackage", package: "swift-system")]
    ),

    // 🔗 WebURLFoundationExtras.
    // ==========================

    .target(
      name: "WebURLFoundationExtras",
      dependencies: ["WebURL"]
    ),
    .testTarget(
      name: "WebURLFoundationExtrasTests",
      dependencies: ["WebURLFoundationExtras", "WebURLTestSupport", "WebURL"],
      resources: [.copy("URLConversion/Resources")]
    ),
    .testTarget(
      name: "WebURLFoundationEndToEndTests",
      dependencies: ["WebURLFoundationExtras", "WebURL"]
    )
  ]
)
