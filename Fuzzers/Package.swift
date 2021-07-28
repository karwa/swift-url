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
  name: "swift-url-fuzzers",
  products: [
    // Parses a single input as a URL string.
    // Valid URLs are re-parsed to ensure parsing/serialization is idempotent.
    .executable(name: "url-parse-reparse", targets: ["url-parse-reparse"])
  ],
  dependencies: [
    .package(name: "swift-url", path: "..")
  ],
  targets: [
    .target(
      name: "url-parse-reparse",
      dependencies: [.product(name: "WebURLCore", package: "swift-url")],
      swiftSettings: [.unsafeFlags(["-parse-as-library", "-sanitize=fuzzer,address"])]
    )
  ]
)
