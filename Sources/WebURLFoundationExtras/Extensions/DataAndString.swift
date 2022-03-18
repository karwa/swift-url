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

// Note: Some documentation comments are copied/adapted from Foundation,
// and are (c) Apple Inc and the Swift project authors.

import Foundation
import WebURL

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// --------------------------------
// MARK: - Data
// --------------------------------


extension Data {

  /// Produces a `Data` by loading the contents referred to by a URL.
  ///
  /// - parameters:
  ///   - url: The location of the data to load.
  ///   - options: Options for loading the data. Default value is `[]`.
  ///
  public init(contentsOf url: WebURL, options: Data.ReadingOptions = []) throws {
    try self.init(contentsOf: try URL(convertOrThrow: url), options: options)
  }

  /// Writes the contents of the data buffer to a location.
  ///
  /// - parameters:
  ///   - url: The location to write the data into.
  ///   - options: Options for writing the data. Default value is `[]`.
  ///
  public func write(to url: WebURL, options: Data.WritingOptions = []) throws {
    try self.write(to: try URL(convertOrThrow: url), options: options)
  }
}


// --------------------------------
// MARK: - String
// --------------------------------


extension String {

  /// Produces a `String` by loading data from a given URL and attempting to infer its encoding.
  ///
  /// - parameters:
  ///   - url: The location of the data to load.
  ///   - encoding: The encoding to use to interpret the loaded data as a string.
  ///
  public init(contentsOf url: WebURL) throws {
    try self.init(contentsOf: try URL(convertOrThrow: url))
  }

  /// Produces a `String` by loading data from a given URL and interpreting it using a given encoding.
  ///
  /// - parameters:
  ///   - url: The location of the data to load.
  ///   - encoding: The encoding to use to interpret the loaded data as a string.
  ///
  public init(contentsOf url: WebURL, encoding: String.Encoding) throws {
    try self.init(contentsOf: try URL(convertOrThrow: url), encoding: encoding)
  }

  /// Produces a `String` by loading data from a given URL, inferring its encoding, and returning the encoding
  /// which was inferred.
  ///
  /// - parameters:
  ///   - url: The location of the data to load.
  ///   - usedEncoding: The encoding which was used to interpret the loaded data as a string.
  ///
  public init(contentsOf url: WebURL, usedEncoding: inout String.Encoding) throws {
    try self.init(contentsOf: try URL(convertOrThrow: url), usedEncoding: &usedEncoding)
  }

  /// Writes the contents of the string to a location, using a specified encoding.
  ///
  /// - parameters:
  ///   - url:        The location to write the string into.
  ///   - atomically: If `true`, the string is first written to an auxiliary file, which replaces the original
  ///                 file when writing is complete.
  ///   - encoding:   The encoding to write the string as.
  ///
  public func write(to url: WebURL, atomically useAuxiliaryFile: Bool, encoding: String.Encoding) throws {
    try self.write(to: try URL(convertOrThrow: url), atomically: useAuxiliaryFile, encoding: encoding)
  }
}
