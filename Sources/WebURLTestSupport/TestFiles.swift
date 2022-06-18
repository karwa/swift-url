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

/// A database of test cases.
///
/// Load a database using either
/// - ``loadBinaryTestFile(_:)``, to load the file as binary data, or
/// - ``loadTestFile(_:as:)``, providing to decode the file from JSON using Codable.
///
public enum TestFile: String, Equatable, Hashable, Codable {
  case WPTURLConstructorTests = "urltestdata"
  case WebURLAdditionalConstructorTests = "additional_constructor_tests"
  case WPTURLSetterTests = "setters_tests"
  case WebURLAdditionalSetterTests = "additional_setters_tests"
  case WPTToASCIITests = "toascii"
  case FilePathTests = "file_url_path_tests"
  case IdnaTest = "IdnaTestV2"

  fileprivate var fileExtension: String {
    if case .IdnaTest = self { return "txt" }
    return "json"
  }
}

internal enum LoadTestFileError: Error {
  case failedToLoad(TestFile, error: Error?)
  case failedToDecode(TestFile, error: Error)
}

/// Loads the given test database as binary data.
///
/// If the file cannot be loaded, an error is thrown.
///
public func loadBinaryTestFile(_ file: TestFile) throws -> Data {
  let fileData: Data
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    let url = Bundle.module.url(forResource: "TestFilesData/\(file.rawValue)", withExtension: file.fileExtension)!
    fileData = try Result {
      try Data(contentsOf: url)
    }.mapError {
      LoadTestFileError.failedToLoad(file, error: $0)
    }.get()
  #else
    // SwiftPM resources don't appear to work on other platforms, so just... load it from the repository (sigh).
    var path = #filePath
    path.removeLast("TestFiles.swift".utf8.count)
    path += "TestFilesData/\(file.rawValue).\(file.fileExtension)"
    guard let data = FileManager.default.contents(atPath: path) else {
      throw LoadTestFileError.failedToLoad(file, error: nil)
    }
    fileData = data
  #endif
  return fileData
}

/// Loads and decodes the given test database.
///
/// If the file cannot be loaded or decoded, an error is thrown.
///
public func loadTestFile<T: Decodable>(_ file: TestFile, as: T.Type) throws -> T {

  let fileData = try loadBinaryTestFile(file)
  return try Result {
    try JSONDecoder().decode(T.self, from: fileData)
  }.mapError {
    LoadTestFileError.failedToDecode(file, error: $0)
  }.get()
}
