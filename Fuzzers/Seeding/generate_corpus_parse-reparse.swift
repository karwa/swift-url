#!/usr/bin/swift

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

import Foundation

let seed_urls: [String] = [
  // Add URLs for the seed corpus here.
  #"http://a/b/c?d#e"#,
]

let dirName = "parse-reparse"
let fileManager = FileManager()

guard !fileManager.fileExists(atPath: dirName) else {
  fatalError("Unable to generate seed corpus - directory '\(dirName)' already exists")
}
try fileManager.createDirectory(atPath: dirName, withIntermediateDirectories: false)

for (i, url) in seed_urls.enumerated() {
  guard fileManager.createFile(atPath: "\(dirName)/\(i)", contents: Data(url.utf8)) else {
    print("Unable to create seed file - \(i)")
    break
  }
}
