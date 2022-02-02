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

import struct WebURL.FilePathFormat

// --------------------------------------------
// MARK: - Test file data model
// --------------------------------------------


/// The contents of the file path test file.
///
/// The single file contains the test data for 2 test suites, since they are closely related and you often want to check
/// round-trip behavior by including the same paths and URLs in both suites.
///
public struct FilePathTestFile: Codable {
  public var file_path_to_url: FlatSectionedArray<FilePathToURLTests.TestCase>
  public var url_to_file_path: FlatSectionedArray<URLToFilePathTests.TestCase>
}


// --------------------------------------------
// MARK: - FilePathToURLTests
// --------------------------------------------


/// The file-path-to-URL test suite.
///
/// Tests the ability to create a file URL from a file path interpreted as being in a particular format.
///
public enum FilePathToURLTests: TestSuite {

  public typealias Harness = _FilePathToURL_Harness

  public struct TestCase: Hashable, Codable {

    /// An optional comment describing the test case.
    ///
    public var comment: String?

    /// The given file path to create a URL from.
    ///
    public var file_path: String

    /// The URL created by interpreting `file_path` as a POSIX path.
    ///
    public var URL_posix: EncodedResult<String, FailureReason>

    /// The URL created by interpreting `file_path` as a Windows path.
    ///
    public var URL_windows: EncodedResult<String, FailureReason>
  }

  public enum FailureReason: String, Error, Codable {
    case emptyInput = "empty-input"
    case nullBytes = "null-byte"
    case relativePath = "relative-path"
    case upwardsTraversal = "upwards-traversal"
    case invalidHostname = "invalid-hostname"
    case invalidPath = "invalid-namespaced-path"
    case unsupportedWin32NamespacedPath = "unsupported-namespaced-path"
  }

  public struct CapturedData: Hashable {
    public var posix: Result<String, FailureReason>? = nil
    public var reparsedPosix: String?
    public var windows: Result<String, FailureReason>? = nil
    public var reparsedWindows: String?
  }

  // swift-format-ignore
  public enum TestFailure: String, Hashable, CustomStringConvertible {
    case unexpectedFileURL_posix = "A URL was created from the given file path, but it was incorrect (POSIX)."
    case unexpectedFailureReason_posix = "The file path was correctly rejected, but for the wrong reason (POSIX)."
    case unexpectedResult_posix = "The file path unexpectedly failed to be turned in to a URL, or unexpectedly succeeded (POSIX)."
    case notIdempotent_posix = "Re-parsing the URL created from the given file path resulted in a different URL (POSIX)."

    case unexpectedFileURL_windows = "A URL was created from the given file path, but it was incorrect (WINDOWS)."
    case unexpectedFailureReason_windows = "The file path was correctly rejected, but for the wrong reason (WINDOWS)."
    case unexpectedResult_windows = "The file path unexpectedly failed to be turned in to a URL, or unexpectedly succeeded (WINDOWS)."
    case notIdempotent_windows = "Re-parsing the URL created from the given file path resulted in a different URL (WINDOWS)."
  }
}

public protocol _FilePathToURL_Harness: TestHarnessProtocol where Suite == FilePathToURLTests {

  /// Creates a URL by processing the given file path in the given style. The URL is returned in its serialized form.
  ///
  func filePathToURL(_ path: String, format: FilePathFormat) -> Result<String, FilePathToURLTests.FailureReason>

  /// Parses the given serialized URL string, and returns its serialization.
  ///
  func parseSerializedURL(_ serializedURL: String) -> String?
}

extension FilePathToURLTests.Harness {

  public func _runTestCase(_ testcase: Suite.TestCase, _ result: inout TestResult<Suite>) {

    var captures = Suite.CapturedData()
    defer { result.captures = captures }

    do {
      let actual_URL_posix = filePathToURL(testcase.file_path, format: .posix)
      captures.posix = actual_URL_posix

      switch (testcase.URL_posix, actual_URL_posix) {
      case (.success(let expected), .success(let actual)):
        if expected != actual {
          result.failures.insert(.unexpectedFileURL_posix)
        }
      case (.failure(let expected), .failure(let actual)):
        if expected != actual {
          result.failures.insert(.unexpectedFailureReason_posix)
        }
      default:
        result.failures.insert(.unexpectedResult_posix)
      }

      if case .success(let serializedURL) = actual_URL_posix {
        let reparsed = parseSerializedURL(serializedURL)
        captures.reparsedPosix = reparsed
        if reparsed != serializedURL {
          result.failures.insert(.notIdempotent_posix)
        }
      }
    }

    do {
      let actual_URL_windows = filePathToURL(testcase.file_path, format: .windows)
      captures.windows = actual_URL_windows

      switch (testcase.URL_windows, actual_URL_windows) {
      case (.success(let expected), .success(let actual)):
        if expected != actual {
          result.failures.insert(.unexpectedFileURL_windows)
        }
      case (.failure(let expected), .failure(let actual)):
        if expected != actual {
          result.failures.insert(.unexpectedFailureReason_windows)
        }
      default:
        result.failures.insert(.unexpectedResult_windows)
      }

      if case .success(let serializedURL) = actual_URL_windows {
        let reparsed = parseSerializedURL(serializedURL)
        captures.reparsedWindows = reparsed
        if reparsed != serializedURL {
          result.failures.insert(.notIdempotent_windows)
        }
      }
    }
  }
}


// --------------------------------------------
// MARK: - URLToFilePathTests
// --------------------------------------------


/// The URL-to-file-path test suite.
///
/// Tests the ability to create a file path, in a particular format, from a URL.
///
public enum URLToFilePathTests: TestSuite {

  public typealias Harness = _URLToFilePath_Harness

  public struct TestCase: Hashable, Codable {

    /// An optional comment describing the test case.
    ///
    public var comment: String?

    /// The given URL to create a file path from. This serialized URL string must be normalized;
    /// the result of parsing this string and serializing the result must be exactly equal to this string.
    ///
    public var URL: String

    /// The POSIX-format file path created from `URL`.
    ///
    public var file_path_posix: EncodedResult<String, FailureReason>

    /// The Windows-format file path created from `URL`.
    ///
    public var file_path_windows: EncodedResult<String, FailureReason>
  }

  public enum FailureReason: String, Error, Codable {
    case notAFileURL = "not-a-file-url"
    case encodedNullByte = "null-byte"
    case encodedSeparator = "encoded-separator"
    case unsupportedNonLocalFile = "unsupported-non-local-file"
    case unsupportedHostname = "unsupported-hostname"
    case relativePath = "relative-path"
  }

  public struct CapturedData: Hashable {
    public var parsedURL: String? = nil
    public var posix: Result<String, FailureReason>? = nil
    public var windows: Result<String, FailureReason>? = nil
  }

  // swift-format-ignore
  public enum TestFailure: String, Hashable, CustomStringConvertible {
    case failedToParseURL = "Failed to parse the given URL."
    case URLIsNotNormalized = "Given URL is not normalized, was altered by the parser."

    case unexpectedPath_posix = "The path created from the URL was not correct (POSIX)."
    case unexpectedFailureReason_posix = "The URL correctly failed to produce a path, but the reason was incorrect (POSIX)."
    case unexpectedResult_posix = "The URL either unexpectedly produced a path, or unexpectedly failed to do so (POSIX)."

    case unexpectedPath_windows = "The path created from the URL was not correct (WINDOWS)."
    case unexpectedFailureReason_windows = "The URL correctly failed to produce a path, but the reason was incorrect (WINDOWS)."
    case unexpectedResult_windows = "The URL either unexpectedly produced a path, or unexpectedly failed to do so (WINDOWS)."
  }
}

public protocol _URLToFilePath_Harness: TestHarnessProtocol where Suite == URLToFilePathTests {

  associatedtype URLType: CustomStringConvertible

  /// Parses the given serialized URL.
  ///
  func parseSerializedURL(_ serializedURL: String) -> URLType?

  /// Creates a file-path in a particular format from the given URL.
  ///
  func urlToFilePath(_ url: URLType, format: FilePathFormat) -> Result<String, Suite.FailureReason>
}

extension URLToFilePathTests.Harness {

  public func _runTestCase(_ testcase: Suite.TestCase, _ result: inout TestResult<Suite>) {

    guard let url = parseSerializedURL(testcase.URL) else {
      result.failures.insert(.failedToParseURL)
      return
    }

    var captures = URLToFilePathTests.CapturedData()
    defer { result.captures = captures }

    captures.parsedURL = url.description
    if url.description != testcase.URL {
      result.failures.insert(.URLIsNotNormalized)
    }

    do {
      let posixPath = urlToFilePath(url, format: .posix)
      captures.posix = posixPath

      switch (testcase.file_path_posix, posixPath) {
      case (.success(let expected), .success(let actual)):
        if expected != actual {
          result.failures.insert(.unexpectedPath_posix)
        }
      case (.failure(let expected), .failure(let actual)):
        if expected != actual {
          result.failures.insert(.unexpectedFailureReason_posix)
        }
      default:
        result.failures.insert(.unexpectedResult_posix)
      }
    }

    do {
      let windowsPath = urlToFilePath(url, format: .windows)
      captures.windows = windowsPath

      switch (testcase.file_path_windows, windowsPath) {
      case (.success(let expected), .success(let actual)):
        if expected != actual {
          result.failures.insert(.unexpectedPath_windows)
        }
      case (.failure(let expected), .failure(let actual)):
        if expected != actual {
          result.failures.insert(.unexpectedFailureReason_windows)
        }
      default:
        result.failures.insert(.unexpectedResult_windows)
      }
    }
  }
}
