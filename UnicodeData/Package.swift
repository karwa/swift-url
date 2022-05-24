// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

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
    name: "swift-url-unicodedata",
    products: [
        .executable(name: "GenerateUnicodeData", targets: ["GenerateUnicodeData"])
    ],
    targets: [
      .target(
        name: "UnicodeDataTools",
        resources: [.copy("TableDefinitions")],
        swiftSettings: [.define("UNICODE_DB_INCLUDE_BUILDER")]
      ),
      .testTarget(
        name: "UnicodeDataToolsTests",
        dependencies: ["UnicodeDataTools"],
        swiftSettings: [.define("UNICODE_DB_INCLUDE_BUILDER")]
      ),

      .target(
        name: "GenerateUnicodeData",
        dependencies: ["UnicodeDataTools"]
      ),
    ]
)
