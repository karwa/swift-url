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
import WebURL
import WebURLFoundationExtras
import WebURLTestSupport
import XCTest

final class FoundationToWebTests: XCTestCase {}


// -------------------------------
// MARK: - Foundation Test Suite.
// -------------------------------
// From swift-corelibs-foundation.
// https://github.com/apple/swift-corelibs-foundation/blob/6a6b505ea7152b24310aea1ffb67ed39ac8a17c1/Tests/Foundation/Tests/TestURL.swift


let kURLTestParsingTestsKey = "ParsingTests"
let kURLTestTitleKey = "In-Title"
let kURLTestUrlKey = "In-Url"
let kURLTestBaseKey = "In-Base"
let kURLTestURLCreatorKey = "In-URLCreator"
let kURLTestPathComponentKey = "In-PathComponent"
let kURLTestPathExtensionKey = "In-PathExtension"
let kURLTestCFResultsKey = "Out-CFResults"
let kURLTestNSResultsKey = "Out-NSResults"
let kNSURLWithStringCreator = "NSURLWithString"
let kCFURLCreateWithStringCreator = "CFURLCreateWithString"
let kCFURLCreateWithBytesCreator = "CFURLCreateWithBytes"
let kCFURLCreateAbsoluteURLWithBytesCreator = "CFURLCreateAbsoluteURLWithBytes"
let kNullURLString = "<null url>"
let kNullString = "<null>"

fileprivate func loadFoundationTests() -> [Any]? {
  let data: Data
  #if os(macOS)
    let url = Bundle.module.url(forResource: "Resources/NSURLTestData", withExtension: "plist")!
    data = try! Data(contentsOf: url)
  #else
    var path = #filePath
    path.removeLast("FoundationToWebTests.swift".utf8.count)
    path += "Resources/NSURLTestData.plist"
    data = FileManager.default.contents(atPath: path)!
  #endif
  guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
    XCTFail("Unable to deserialize property list data")
    return nil
  }
  guard let testRoot = plist as? [String: Any] else {
    XCTFail("Unable to deserialize property list data")
    return nil
  }
  guard let parsingTests = testRoot[kURLTestParsingTestsKey] as? [Any] else {
    XCTFail("Unable to create the parsingTests dictionary")
    return nil
  }
  return parsingTests
}

extension FoundationToWebTests {

  func testFoundationSuite() {

    #if os(Windows)
      // On Windows, pipes are valid charcters which can be used
      // to replace a ':'. See RFC 8089 Section E.2.2 for
      // details.
      //
      // Skip the test which expects pipes to be invalid
      let skippedPipeTest = "NSURLWithString-parse-absolute-escape-006-pipe-invalid"
    #else
      // On other platforms, pipes are not valid
      //
      // Skip the test which expects pipes to be valid
      let skippedPipeTest = "NSURLWithString-parse-absolute-escape-006-pipe-valid"
    #endif
    let skippedTests = [
      "NSURLWithString-parse-ambiguous-url-001",  // TODO: Fix Test
      skippedPipeTest,
    ]

    let expectedWebURLConversionFailures: Set<String> = [
      // not even a URL - just a file path with no scheme.
      "NSURLWithString-parse-absolute-file-005",
      // localhost and file: URLs.
      "NSURLWithString-parse-absolute-file-003",
      "NSURLWithString-parse-absolute-file-006",
      "NSURLWithString-parse-absolute-file-007",
      "NSURLWithString-parse-absolute-file-008",
      // port with no host.
      "NSURLWithString-parse-absolute-ftp-009",
      // http wth no host.
      "NSURLWithString-parse-absolute-query-007",
      "NSURLWithString-parse-absolute-escape-015",
      "NSURLWithString-parse-absolute-escape-016",
      "NSURLWithString-parse-absolute-escape-017",
      "NSURLWithString-parse-absolute-escape-018",
      "NSURLWithString-parse-absolute-escape-019",
      // percent-encoding in HTTP hostname.
      "NSURLWithString-parse-absolute-escape-009",
      // not a URL - just a bunch of random characters (?!).
      "NSURLWithString-parse-absolute-invalid-001",
      // IPv6 with zone.
      "NSURLWithString-parse-absolute-real-world-003",
      // http with no host.
      "NSURLWithString-parse-absolute-real-world-008",
      // not even a URL - just a file path with no scheme.
      "NSURLWithString-parse-ambiguous-url-003",
      "NSURLWithString-parse-ambiguous-url-004",
      "NSURLWithString-parse-ambiguous-url-005",
      "NSURLWithString-parse-ambiguous-url-006",
      "NSURLWithString-parse-ambiguous-url-007",
      "NSURLWithString-parse-ambiguous-url-009",
      // http with no host.
      "NSURLWithString-parse-ambiguous-url-010",
      "NSURLWithString-parse-relative-rfc-042",
      "NSURLWithString-parse-relative-rfc-044",
      "NSURLWithString-parse-relative-real-world-004",
      // IPv6 with zone.
      "NSURLWithString-parse-relative-real-world-005",
      // file with nil host. -- TODO: could relax these?
      "NSURLWithString-parse-absolute-file-010",
      "NSURLWithString-parse-absolute-file-012",
      "NSURLWithString-parse-ambiguous-url-008",
      "NSURLWithString-parse-relative-rfc-043",
    ]

    var numParsed = 0
    var numSuccess = 0

    for obj in loadFoundationTests()! {
      let testDict = obj as! [String: Any]

      let title = testDict[kURLTestTitleKey] as! String
      let inURL = testDict[kURLTestUrlKey]! as! String
      let inBase = testDict[kURLTestBaseKey] as! String?
      let expectedNSResult = testDict[kURLTestNSResultsKey]!

      if skippedTests.contains(title) { continue }

      // Create a Foundation URL.
      var _url: URL? = nil
      switch testDict[kURLTestURLCreatorKey]! as! String {
      case kNSURLWithStringCreator:
        _url = _URLWithString(inURL, baseString: inBase)
      case kCFURLCreateWithStringCreator, kCFURLCreateWithBytesCreator, kCFURLCreateAbsoluteURLWithBytesCreator:
        // Not supported
        continue
      default:
        XCTFail()
      }
      numParsed += 1

      // Check that the URL is what Foundation expects.
      guard let url = _url else {
        XCTAssertEqual(expectedNSResult as? String, kNullURLString)
        continue
      }
      if let expected = expectedNSResult as? [String: Any] {
        let inPathComponent = testDict[kURLTestPathComponentKey] as! String?
        let inPathExtension = testDict[kURLTestPathExtensionKey] as! String?
        let results = _gatherTestResults(url: url, pathComponent: inPathComponent, pathExtension: inPathExtension)
        let (isEqual, differences) = _compareTestResults(url, expected: expected, got: results)
        XCTAssertTrue(isEqual, "\(title): \(differences.joined(separator: "\n"))")
      } else {
        XCTFail("\(url) should not be a valid url")
      }

      // Try to convert to WebURL. Not all Foundation URLs can safely be converted.
      guard let webURL = WebURL(url) else {
        XCTAssert(expectedWebURLConversionFailures.contains(title), "Unexpected failure: \(title). URL: \(url)")
        continue
      }

      // If WebURL did the conversion, the URLs must be semantically equivalent.
      let diffs = checkSemanticEquivalence(url, webURL)
      XCTAssert(diffs.isEmpty, "\(title) - \(url) - \(diffs.map { String(describing: $0) }.joined(separator: ","))")
      numSuccess += 1
    }

    XCTAssertEqual(numParsed, 197, "Number of tests changed. Did you update the test database?")
    // Apparently one more test passes on Windows than Mac/Linux. TODO: investigate.
    #if os(Windows)
      XCTAssertEqual(numSuccess, 165, "Number of successful conversion changed. Did you update the test database?")
    #else
      XCTAssertEqual(numSuccess, 164, "Number of successful conversion changed. Did you update the test database?")
    #endif
  }

  private func _URLWithString(_ urlString: String, baseString: String?) -> URL? {
    if let baseString = baseString {
      let baseURL = URL(string: baseString)
      return URL(string: urlString, relativeTo: baseURL)
    } else {
      return URL(string: urlString)
    }
  }

  private func _gatherTestResults(url: URL, pathComponent: String?, pathExtension: String?) -> [String: Any] {
    var result = [String: Any]()
    if let pathComponent = pathComponent {
      let newFileURL = url.appendingPathComponent(pathComponent, isDirectory: false)
      result["appendingPathComponent-File"] = newFileURL.relativeString
      result["appendingPathComponent-File-BaseURL"] = newFileURL.baseURL?.relativeString ?? kNullString

      let newDirURL = url.appendingPathComponent(pathComponent, isDirectory: true)
      result["appendingPathComponent-Directory"] = newDirURL.relativeString
      result["appendingPathComponent-Directory-BaseURL"] = newDirURL.baseURL?.relativeString ?? kNullString
    } else if let pathExtension = pathExtension {
      let newURL = url.appendingPathExtension(pathExtension)
      result["appendingPathExtension"] = newURL.relativeString
      result["appendingPathExtension-BaseURL"] = newURL.baseURL?.relativeString ?? kNullString
    } else {
      result["relativeString"] = url.relativeString
      result["baseURLString"] = url.baseURL?.relativeString ?? kNullString
      result["absoluteString"] = url.absoluteString
      result["absoluteURLString"] = url.absoluteURL.relativeString
      result["scheme"] = url.scheme ?? kNullString
      result["host"] = url.host ?? kNullString

      result["port"] = url.port ?? kNullString
      result["user"] = url.user ?? kNullString
      result["password"] = url.password ?? kNullString
      result["path"] = url.path
      result["query"] = url.query ?? kNullString
      result["fragment"] = url.fragment ?? kNullString
      result["relativePath"] = url.relativePath
      result["isFileURL"] = url.isFileURL ? "YES" : "NO"
      result["standardizedURL"] = url.standardized.relativeString

      result["pathComponents"] = url.pathComponents
      result["lastPathComponent"] = url.lastPathComponent
      result["pathExtension"] = url.pathExtension
      result["deletingLastPathComponent"] = url.deletingLastPathComponent().relativeString
      result["deletingLastPathExtension"] = url.deletingPathExtension().relativeString
    }
    return result
  }

  private func _compareTestResults(_ url: Any, expected: [String: Any], got: [String: Any]) -> (Bool, [String]) {
    var differences = [String]()
    for (key, expectation) in expected {
      // Skip non-string expected results
      if ["port", "standardizedURL", "pathComponents"].contains(key) {
        continue
      }
      var obj: Any? = expectation
      if obj as? String == kNullString {
        obj = nil
      }
      if let expectedValue = obj as? String {
        if let testedValue = got[key] as? String {
          if expectedValue != testedValue {
            differences.append(" \(key)  Expected = '\(expectedValue)',  Got = '\(testedValue)'")
          }
        } else {
          differences.append(" \(key)  Expected = '\(expectedValue)',  Got = '\(String(describing: got[key]))'")
        }
      } else if let expectedValue = obj as? [String] {
        if let testedValue = got[key] as? [String] {
          if expectedValue != testedValue {
            differences.append(" \(key)  Expected = '\(expectedValue)',  Got = '\(testedValue)'")
          }
        } else {
          differences.append(" \(key)  Expected = '\(expectedValue)',  Got = '\(String(describing: got[key]))'")
        }
      } else if let expectedValue = obj as? Int {
        if let testedValue = got[key] as? Int {
          if expectedValue != testedValue {
            differences.append(" \(key)  Expected = '\(expectedValue)',  Got = '\(testedValue)'")
          }
        } else {
          differences.append(" \(key)  Expected = '\(expectedValue)',  Got = '\(String(describing: got[key]))'")
        }
      } else if obj == nil {
        if got[key] != nil && got[key] as? String != kNullString {
          differences.append(
            " \(key)  Expected = '\(String(describing: obj))',  Got = '\(String(describing: got[key]))'")
        }
      }
    }
    for (key, obj) in got {
      if expected[key] == nil {
        differences.append(" \(key)  Expected = 'nil',  Got = '\(obj)'")
      }
    }
    if differences.count > 0 {
      differences.sort()
      differences.insert(" url:  '\(url)' ", at: 0)
      return (false, differences)
    } else {
      return (true, [])
    }
  }
}


// --------------------------------
// MARK: - Extra tests and fuzzing.
// --------------------------------


extension FoundationToWebTests {

  func testAmbiguousAndBuggyURLs() {

    let inputs: [(string: String, webURL: String?)] = [
      // Ambiguous username-password split.
      (string: "http://@abc", webURL: "http://abc/"),
      (string: "http://:@abc", webURL: "http://abc/"),
      (string: "http://abc:@def", webURL: "http://abc@def/"),
      (string: "http://:abc@def", webURL: "http://:abc@def/"),
      (string: "http://abc@def@ghi", webURL: nil),
      (string: "http://:abc@def@ghi", webURL: nil),
      (string: "http://abc:@def@ghi", webURL: nil),
      (string: "http://abc@:def@ghi", webURL: nil),
      (string: "http://abc@def:@ghi", webURL: nil),
      (string: "http://abc@def@:ghi", webURL: nil),
      (string: "http://abc@def@ghi:", webURL: nil),
      (string: "http://u@x:@x", webURL: nil),
      (string: "sc://@abc", webURL: "sc://abc"),
      (string: "sc://:@abc", webURL: "sc://abc"),
      (string: "sc://abc:@def", webURL: "sc://abc@def"),
      (string: "sc://:abc@def", webURL: "sc://:abc@def"),
      (string: "sc://abc@def@ghi", webURL: nil),
      (string: "sc://:abc@def@ghi", webURL: nil),
      (string: "sc://abc:@def@ghi", webURL: nil),
      (string: "sc://abc@:def@ghi", webURL: nil),
      (string: "sc://abc@def:@ghi", webURL: nil),
      (string: "sc://abc@def@:ghi", webURL: nil),
      (string: "sc://abc@def@ghi:", webURL: nil),
      (string: "s://u@x:@x", webURL: nil),
      // This can be particularly devious if all components appear to be the same.
      (string: "http://@2:@2/", webURL: nil),
      (string: "http://@2:@2:@2/", webURL: nil),
      (string: "http://@2:@2:@2/?", webURL: nil),
      (string: "http://@2:@2:@2?/", webURL: nil),
      (string: "http://@2:@2:@?2/", webURL: nil),
      (string: "http://@2:@2:?@2/", webURL: nil),
      (string: "http://@2:@2?:@2/", webURL: nil),
      (string: "http://2:2:2@2/private/", webURL: nil),
      (string: "sc://@2:@2/", webURL: nil),
      (string: "sc://@2:@2:@2/", webURL: nil),
      (string: "sc://@2:@2:@2/?", webURL: nil),
      (string: "sc://@2:@2:@2?/", webURL: nil),
      (string: "sc://@2:@2:@?2/", webURL: nil),
      (string: "sc://@2:@2:?@2/", webURL: nil),
      (string: "sc://@2:@2?:@2/", webURL: nil),
      (string: "sc://2:2:2@2/private/", webURL: nil),
      // Host-port split.
      (string: "http://abc:99@def@ghi", webURL: nil),
      (string: "http://abc@def:99@ghi", webURL: nil),
      (string: "http://abc@def@ghi:99", webURL: nil),
      (string: "sc://abc:99@def@ghi", webURL: nil),
      (string: "sc://abc@def:99@ghi", webURL: nil),
      (string: "sc://abc@def@ghi:99", webURL: nil),

      // Opaque paths which start with "?" or "#". File appears to have special behaviour.
      (string: "file:?xyz", webURL: "file:///?xyz"),
      (string: "file:#xyz", webURL: "file:///%23xyz"),
      (string: "file:?%82yz", webURL: "file:///?%82yz"),
      (string: "file:#%82yz", webURL: "file:///%23%82yz"),
      (string: "sc:?xyz", webURL: "sc:?xyz"),
      (string: "sc:#xyz", webURL: "sc:%23xyz"),
      (string: "sc:?%82yz", webURL: "sc:?%82yz"),
      (string: "sc:#%82yz", webURL: "sc:%23%82yz"),

      // Others, from fuzzing.
      (string: "s://4%3A%3A/", webURL: "s://4%3A%3A/"),

      // URL.path is empty if the path contains percent-encoded invalid UTF-8.
      // https://bugs.swift.org/browse/SR-15508
      (string: "s://s/somepath/%72", webURL: "s://s/somepath/%72"),
      (string: "s://s/somepath/%82", webURL: "s://s/somepath/%82"),
      (string: "s:%F2F", webURL: "s:%F2F"),

      // URLComponents percent-decodes the path if it contains a semicolon.
      // This also combines with SR-15508 to remove the path if its escaped bytes are not valid UTF8.
      // https://bugs.swift.org/browse/SR-15512
      (string: "file:%2F;", webURL: "file:///%2F;"),
      (string: "w:/s%E3;", webURL: "w:/s%E3;"),
      (string: "s:/;%2F.", webURL: "s:/;%2F."),
      (string: "fte:;%82", webURL: "fte:;%82"),
      (string: "s:/;%2F/../x", webURL: "s:/x"),
      (string: "B:/;/../%FF", webURL: "b:/%FF"),
      (string: "B:/;%2F/..", webURL: "b:/"),

      // If you use enough "@"s, you can trick the parser in to reading a password component after the hostname.
      // Here, the URL's hostname is "hostname" and password is "@password". WebURL should refuse to convert these.
      // https://bugs.swift.org/browse/SR-15513
      (string: "http://@hostname:@password:@whydoesthishappen/", webURL: nil),
      (string: "http://@hostname:@password:@whydoesthishappen@/", webURL: nil),
      // Even worse: you can have a single component appear as both the hostname AND the password. Again, no conversion.
      (string: "http://:@hostname_and_password:@/", webURL: nil),

      // Foundation allows any percent-encoding in IPv6 addresses, including newlines, null bytes, etc.
      // https://bugs.swift.org/browse/SR-15514
      (string: "http://[::1%0Aen0]/@c@d", webURL: nil),
    ]

    for (string, expectedWebURL) in inputs {
      guard let url = URL(string: string) else {
        XCTFail("Invalid URL: \(string)")
        continue
      }
      guard let expected = expectedWebURL else {
        XCTAssertNil(WebURL(url), string)
        continue
      }
      guard let actual = WebURL(url) else {
        XCTFail("Unexpected failure to convert \(string)")
        continue
      }
      // Check that the conversion produced the expected normalized WebURL.
      XCTAssertEqual(expected, actual.serialized(), "\(string)")
      // Check semantic equivalence of the result.
      let differences = checkSemanticEquivalence(url, actual)
      XCTAssert(differences.isEmpty, "\(string) - \(differences)")
    }
  }
}
