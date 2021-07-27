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

import WebURL

// --------------------------------------------
// MARK: - FilePathToURLTests
// --------------------------------------------


extension FilePathToURLTests {

  public struct WebURLReportHarness {
    public private(set) var report = SimpleTestReport()
    public private(set) var entriesSeen = 0
    public let expectedFailures: Set<Int>

    public init(expectedFailures: Set<Int> = []) {
      self.expectedFailures = expectedFailures
    }
  }
}

extension FilePathToURLTests.WebURLReportHarness: FilePathToURLTests.Harness {

  public func filePathToURL(
    _ path: String, format: FilePathFormat
  ) -> Result<String, FilePathToURLTests.FailureReason> {
    Result { try WebURL.fromFilePathBytes(path.utf8, format: format).serialized }
      .mapError { Self.errorToFailureReason($0 as! FilePathToURLError) }
  }

  private static func errorToFailureReason(_ error: FilePathToURLError) -> FilePathToURLTests.FailureReason {
    switch error {
    case .emptyInput: return .emptyInput
    case .relativePath: return .relativePath
    case .unsupportedHostname: return .unsupportedHostname
    case .nullBytes: return .nullBytes
    case .upwardsTraversal: return .upwardsTraversal
    case .transcodingFailure: fatalError("WebURL.fromFilePathBytes should not be transcoding anything")
    default: fatalError("Unknown error")
    }
  }

  public func parseSerializedURL(_ serializedURL: String) -> String? {
    WebURL(serializedURL)?.serialized
  }

  public mutating func markSection(_ name: String) {
    report.markSection(name)
  }

  public mutating func reportTestResult(_ result: TestResult<Suite>) {
    entriesSeen += 1
    report.performTest { reporter in
      if expectedFailures.contains(result.testNumber) { reporter.expectedResult = .fail }
      reporter.reportTestResult(result)
    }
  }
}


// --------------------------------------------
// MARK: - URLToFilePathTests
// --------------------------------------------


extension URLToFilePathTests {

  public struct WebURLReportHarness {
    public private(set) var report = SimpleTestReport()
    public private(set) var entriesSeen = 0
    public let expectedFailures: Set<Int>

    public init(expectedFailures: Set<Int> = []) {
      self.expectedFailures = expectedFailures
    }
  }
}

extension URLToFilePathTests.WebURLReportHarness: URLToFilePathTests.Harness {

  public func parseSerializedURL(_ string: String) -> WebURL? {
    WebURL(string)
  }

  public func urlToFilePath(
    _ url: WebURL, format: FilePathFormat
  ) -> Result<String, URLToFilePathTests.FailureReason> {
    Result { String(decoding: try WebURL.filePathBytes(from: url, format: format), as: UTF8.self) }
      .mapError { Self.errorToFailureReason($0 as! URLToFilePathError) }
  }

  private static func errorToFailureReason(_ error: URLToFilePathError) -> URLToFilePathTests.FailureReason {
    switch error {
    case .notAFileURL: return .notAFileURL
    case .encodedNullBytes: return .encodedNullByte
    case .encodedPathSeparator: return .encodedSeparator
    case .posixPathsCannotContainHosts: return .unsupportedNonLocalFile
    case .windowsPathIsNotFullyQualified: return .relativePath
    case .transcodingFailure: fatalError("WebURL.filePathBytes should not be transcoding anything")
    default: fatalError("Unknown error")
    }
  }

  public mutating func markSection(_ name: String) {
    report.markSection(name)
  }

  public mutating func reportTestResult(_ result: TestResult<Suite>) {
    entriesSeen += 1
    report.performTest { reporter in
      if expectedFailures.contains(result.testNumber) { reporter.expectedResult = .fail }
      reporter.reportTestResult(result)
    }
  }
}
