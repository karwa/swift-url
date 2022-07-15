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
import XCTest

@testable import WebURL
@testable import WebURLFoundationExtras

/// Asserts that the given URLs contain an equivalent set of components,
/// without taking any shortcuts or making assumptions that they originate from the same string.
///
fileprivate func XCTAssertEquivalentURLs(_ webURL: WebURL, _ foundationURL: URL, _ message: String = "") {
  var urlString = foundationURL.absoluteString
  let areEquivalent = urlString.withUTF8 {
    WebURL._SPIs._checkEquivalence_f2w(webURL, foundationURL, foundationString: $0, shortcuts: false)
  }
  var prefix = message
  if !prefix.isEmpty {
    prefix += " -- "
  }
  XCTAssertTrue(areEquivalent, "\(prefix)Foundation: \(foundationURL) -- WebURL: \(webURL)")
}

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
      // On Windows, pipes are valid characters which can be used
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
      "NSURLWithString-parse-ambiguous-url-001",  // Foundation's test is incorrect.
      skippedPipeTest,
    ]

    let expectedWebURLConversionFailures: Set<String> = [
      // Not a URL - just a file path with no scheme.
      "NSURLWithString-parse-absolute-file-005",
      // Localhost and file: URLs.
      "NSURLWithString-parse-absolute-file-003",
      "NSURLWithString-parse-absolute-file-006",
      "NSURLWithString-parse-absolute-file-007",
      "NSURLWithString-parse-absolute-file-008",
      // Empty username.
      "NSURLWithString-parse-absolute-ftp-005",
      // Port with no host.
      "NSURLWithString-parse-absolute-ftp-009",
      // HTTP wth no host.
      "NSURLWithString-parse-absolute-query-007",
      "NSURLWithString-parse-absolute-escape-015",
      "NSURLWithString-parse-absolute-escape-016",
      "NSURLWithString-parse-absolute-escape-017",
      "NSURLWithString-parse-absolute-escape-018",
      "NSURLWithString-parse-absolute-escape-019",
      // Space in HTTP hostname.
      "NSURLWithString-parse-absolute-escape-009",
      // Not a URL - just a bunch of random characters (?!).
      "NSURLWithString-parse-absolute-invalid-001",
      // IPv6 with zone.
      "NSURLWithString-parse-absolute-real-world-003",
      // HTTP with no host.
      "NSURLWithString-parse-absolute-real-world-008",
      // Not a URL - just a file path with no scheme.
      "NSURLWithString-parse-ambiguous-url-003",
      "NSURLWithString-parse-ambiguous-url-004",
      "NSURLWithString-parse-ambiguous-url-005",
      "NSURLWithString-parse-ambiguous-url-006",
      "NSURLWithString-parse-ambiguous-url-007",
      "NSURLWithString-parse-ambiguous-url-009",
      // HTTP with no host.
      "NSURLWithString-parse-ambiguous-url-010",
      "NSURLWithString-parse-relative-rfc-042",
      "NSURLWithString-parse-relative-rfc-044",
      "NSURLWithString-parse-relative-real-world-004",
      // IPv6 with zone.
      "NSURLWithString-parse-relative-real-world-005",
    ]

    var numParsed = 0
    var numConverted = 0

    for obj in loadFoundationTests()! {
      let testDict = obj as! [String: Any]

      let title = testDict[kURLTestTitleKey] as! String
      let inURL = testDict[kURLTestUrlKey]! as! String
      let inBase = testDict[kURLTestBaseKey] as! String?
      let expectedNSResult = testDict[kURLTestNSResultsKey]!

      if skippedTests.contains(title) {
        continue
      }
      guard testDict[kURLTestURLCreatorKey]! as! String == kNSURLWithStringCreator else {
        continue
      }
      guard testDict[kURLTestPathComponentKey] == nil, testDict[kURLTestPathExtensionKey] == nil else {
        continue
      }

      // 1. Parse the (input, base) pair with Foundation.
      numParsed += 1
      guard let url = _FoundationURLWithString(inURL, baseString: inBase) else {
        XCTAssertEqual(expectedNSResult as? String, kNullURLString)
        continue
      }

      // 2. Check that the URL is what Foundation expects.
      if let expected = expectedNSResult as? [String: Any] {
        let results = _gatherTestResults(url: url)
        let (isEqual, differences) = _compareTestResults(url, expected: expected, got: results)
        XCTAssertTrue(isEqual, "\(title): \(differences.joined(separator: "\n"))")
      } else {
        XCTFail("\(url) should not be a valid url")
      }

      // 3. Convert to WebURL.
      guard let convertedURL = WebURL(url) else {
        XCTAssert(expectedWebURLConversionFailures.contains(title), "Unexpected fail: \(title) -- Foundation: \(url)")
        continue
      }
      numConverted += 1
      XCTAssert(
        !expectedWebURLConversionFailures.contains(title),
        "Unexpected pass: \(title) -- Foundation: \(url) -- WebURL: \(convertedURL)"
      )

      // 4. Check equivalence without shortcuts.
      XCTAssertEquivalentURLs(convertedURL, url, title)

      // 5. Round-trip back to a Foundation.URL.
      //    Note: Some URLs may not round-trip (see `testRoundTripFailures`),
      //          but everything in the Foundation suite does.
      guard let roundtripURL = URL(convertedURL) else {
        XCTFail("Failed to round trip converted WebURL back to a Foundation URL")
        continue
      }

      // 6. Check equivalence again, using the WebURL-to-Foundation equivalence function without shortcuts.
      //    Note that the conversion to WebURL may change the string, so we check equivalence to the round-trip
      //    result rather than the original Foundation.URL.
      var roundtripString = roundtripURL.absoluteString
      let areEquivalent = roundtripString.withUTF8 {
        WebURL._SPIs._checkEquivalence_w2f(convertedURL, roundtripURL, foundationString: $0, shortcuts: false)
      }
      XCTAssertTrue(areEquivalent)
    }

    XCTAssertEqual(numParsed, 197, "Number of tests changed. Did you update the test database?")
    // Apparently one more test passes on Windows than Mac/Linux. TODO: investigate.
    #if os(Windows)
      XCTAssertEqual(numConverted, 164, "Number of successful conversion changed. Did you update the test database?")
    #else
      XCTAssertEqual(numConverted, 163, "Number of successful conversion changed. Did you update the test database?")
    #endif
  }

  private func _FoundationURLWithString(_ urlString: String, baseString: String?) -> URL? {
    if let baseString = baseString {
      let baseURL = URL(string: baseString)
      return URL(string: urlString, relativeTo: baseURL)
    } else {
      return URL(string: urlString)
    }
  }

  private func _gatherTestResults(url: URL) -> [String: Any] {
    var result = [String: Any]()
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
    return result
  }

  private func _compareTestResults(_ url: Any, expected: [String: Any], got: [String: Any]) -> (Bool, [String]) {
    var differences = [String]()
    for (key, expectation) in expected {
      // Skip non-string expected results
      if ["standardizedURL", "pathComponents"].contains(key) {
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
// MARK: - Extra Foundation.URL Parser/API Tests
// --------------------------------
// Tests various aspects of Foundation's parser/API which are not obvious or well-documented.


extension FoundationToWebTests {

  func testFoundationParser_backslashesAreRejected() {
    // Check that Foundation does not allow unescaped backslashes.
    // The WHATWG URL Standard considers back-slashes to be equivalent to forward-slashes for special schemes.
    // Component-level verification would catch these when converting, but we can't verify the path,
    // and they would change the path's meaning.

    // Just to make sure URL rejects these.
    // https://bugs.xdavidhu.me/google/2021/12/31/fixing-the-unfixable-story-of-a-google-cloud-ssrf/
    XCTAssertNil(URL(string: "http://creds\\@host.com"))
    XCTAssertNil(URL(string: "foo://creds\\@host.com"))
    XCTAssertNil(URLComponents(string: "http://creds\\@host.com"))
    XCTAssertNil(URLComponents(string: "foo://creds\\@host.com"))
    XCTAssertEqual(WebURL("http://creds\\@host.com")?.serialized(), "http://creds/@host.com")
    XCTAssertEqual(WebURL("foo://creds\\@host.com")?.serialized(), "foo://creds%5C@host.com")

    // Backslashes in the path are interpreted differently,
    // but since URL rejects them, we don't need to worry about it.
    XCTAssertNil(URL(string: "http://host.com/a/b\\c\\d"))
    XCTAssertNil(URL(string: "foo://host.com/a/b\\c\\d"))
    XCTAssertNil(URLComponents(string: "http://host.com/a/b\\c\\d"))
    XCTAssertNil(URLComponents(string: "foo://host.com/a/b\\c\\d"))
    XCTAssertEqual(WebURL("http://host.com/a/b\\c\\d")?.serialized(), "http://host.com/a/b/c/d")
    XCTAssertEqual(WebURL("foo://host.com/a/b\\c\\d")?.serialized(), "foo://host.com/a/b\\c\\d")
  }

  func testFoundationAPI_percentDecodedComponents_nonUTF8() {
    // Some Foundation.URL components are only returned percent-decoded, which raises the question of what
    // to do if the decoded bytes are not UTF-8:
    //
    // - Currently, Foundation just returns empty strings (!!!)
    // - Even if it inserted Unicode replacement characters, the components would be non-equivalent
    //
    // So there's nothing else to do but reject components which are returned decoded if they contain non-UTF8.

    let inputs: [(String, String?)] = [
      // Username: Foundation.user is decoded; cannot be verified.
      (string: "http://us%82er@host/path?query#frag", webURL: nil),
      // Password: Foundation.password is encoded, so we can verify it.
      (string: "http://user:pa%82ss@host/path?query#frag", webURL: "http://user:pa%82ss@host/path?query#frag"),

      // Host (domain): WebURL will reject this, as it is not a valid domain.
      (string: "http://user:pass@ho%82st/path?query#frag", webURL: nil),
      // Host (opaque): Foundation.host is decoded; cannot be verified.
      (string: "sc://user:pass@ho%82st/path?query#frag", webURL: nil),

      // Path: cannot be verified.
      (string: "http://user:pass@host/pa%82th?query#frag", webURL: "http://user:pass@host/pa%82th?query#frag"),
      (string: "data:,Hello%F2%80World%EE", webURL: "data:,Hello%F2%80World%EE"),

      // Query: Foundation.query is encoded, so we can verify it.
      (string: "http://user:pass@host/path?que%82ry#frag", webURL: "http://user:pass@host/path?que%82ry#frag"),
      // Fragment: Foundation.fragment is encoded, so we can verify it.
      (string: "http://user:pass@host/path#fra%82g", webURL: "http://user:pass@host/path#fra%82g"),
    ]
    for (string, _expectedWebURLString) in inputs {
      guard let url = URL(string: string) else {
        XCTFail("Invalid URL: \(string)")
        continue
      }
      guard let expectedWebURLString = _expectedWebURLString else {
        XCTAssertNil(WebURL(url), "Unexpected conversion: \(string)")
        continue
      }
      guard let actualWebURL = WebURL(url) else {
        XCTFail("Unexpected failure to convert: \(string)")
        continue
      }
      XCTAssertEqual(
        expectedWebURLString, actualWebURL.serialized(),
        "Unexpected result for \(string) -- Expected: \(expectedWebURLString) -- Actual: \(actualWebURL.serialized())"
      )
      XCTAssertEquivalentURLs(actualWebURL, url, "String: \(string)")
    }
  }

  func testFoundationAPI_emptyAndNilComponents() {
    // Check that URL.host returns nil for empty hostnames.
    // When verifying components, we're not able to tell the difference.

    if let url = URL(string: "foo:///bar") {
      XCTAssertEqual(url.scheme, "foo")
      XCTAssertEqual(url.host, nil)
      XCTAssertEqual(url.path, "/bar")
    } else {
      XCTFail("Failed to parse URL")
    }
    if let url = URL(string: "foo:/bar") {
      XCTAssertEqual(url.scheme, "foo")
      XCTAssertEqual(url.host, nil)
      XCTAssertEqual(url.path, "/bar")
    } else {
      XCTFail("Failed to parse URL")
    }

    if let url = URL(string: "http:///bar") {
      XCTAssertEqual(url.scheme, "http")
      XCTAssertEqual(url.host, nil)
      XCTAssertEqual(url.path, "/bar")
    } else {
      XCTFail("Failed to parse URL")
    }
    if let url = URL(string: "http:/bar") {
      XCTAssertEqual(url.scheme, "http")
      XCTAssertEqual(url.host, nil)
      XCTAssertEqual(url.path, "/bar")
    } else {
      XCTFail("Failed to parse URL")
    }

    if let url = URL(string: "file:///bar") {
      XCTAssertEqual(url.scheme, "file")
      XCTAssertEqual(url.host, nil)
      XCTAssertEqual(url.path, "/bar")
    } else {
      XCTFail("Failed to parse URL")
    }
    if let url = URL(string: "file:/bar") {
      XCTAssertEqual(url.scheme, "file")
      XCTAssertEqual(url.host, nil)
      XCTAssertEqual(url.path, "/bar")
    } else {
      XCTFail("Failed to parse URL")
    }
  }
}


// --------------------------------
// MARK: - Extra Conversion Tests
// --------------------------------


extension FoundationToWebTests {

  func testEncodeSetCompatibility() {
    for char in ASCII.allCharacters {
      // WebURL's user-info encode-set includes a few more characters than Foundation's encode-set.
      do {
        let allowedByWebURL = !URLEncodeSet.UserInfo().shouldPercentEncode(ascii: char.codePoint)
        let allowedByFoundation_user = CharacterSet.urlUserAllowed.contains(.init(char.codePoint))
        let allowedByFoundation_pass = CharacterSet.urlPasswordAllowed.contains(.init(char.codePoint))
        // Foundation's username and password encode-sets are identical.
        XCTAssertEqual(allowedByFoundation_user, allowedByFoundation_pass)
        if allowedByFoundation_user {
          switch char {
          case ASCII.semicolon, ASCII.equalSign:
            XCTAssertFalse(allowedByWebURL)
            XCTAssertTrue(UserInfoExtras().shouldPercentEncode(ascii: char.codePoint))
          default:
            XCTAssertTrue(allowedByWebURL)
          }
        }
      }
      // WebURL's path encode-set is a subset of Foundation's encode-set.
      do {
        let allowedByWebURL = !URLEncodeSet.Path().shouldPercentEncode(ascii: char.codePoint)
        let allowedByFoundation = CharacterSet.urlPathAllowed.contains(.init(char.codePoint))
        if allowedByFoundation {
          XCTAssertTrue(allowedByWebURL)
        }
      }
      // WebURL's query encode-set is a subset of Foundation's encode-set.
      do {
        let allowedByWebURL = !URLEncodeSet.Query().shouldPercentEncode(ascii: char.codePoint)
        let allowedByFoundation = CharacterSet.urlQueryAllowed.contains(.init(char.codePoint))
        if allowedByFoundation {
          XCTAssertTrue(allowedByWebURL)
        }
      }
      // WebURL's special-query encode-set is a subset of Foundation's encode-set, save for the apostrophe character.
      do {
        let allowedByWebURL = !URLEncodeSet.SpecialQuery().shouldPercentEncode(ascii: char.codePoint)
        let allowedByFoundation = CharacterSet.urlQueryAllowed.contains(.init(char.codePoint))
        if allowedByFoundation {
          switch char {
          case ASCII.apostrophe:
            XCTAssertFalse(allowedByWebURL)
            XCTAssertTrue(SpecialQueryExtras().shouldPercentEncode(ascii: char.codePoint))
          default:
            XCTAssertTrue(allowedByWebURL)
          }
        }
      }
      // WebURL's fragment encode-set is a subset of Foundation's encode-set.
      do {
        let allowedByWebURL = !URLEncodeSet.Fragment().shouldPercentEncode(ascii: char.codePoint)
        let allowedByFoundation = CharacterSet.urlFragmentAllowed.contains(.init(char.codePoint))
        if allowedByFoundation {
          XCTAssertTrue(allowedByWebURL)
        }
      }
    }
  }

  func testSafeNormalization() {

    // [Scheme]: may be lowercased.
    test: do {
      let foundationURL = URL(string: "HtTp://example.com/")!
      XCTAssertEqual(foundationURL.absoluteString, "HtTp://example.com/")
      XCTAssertEqual(foundationURL.scheme, "HtTp")
      XCTAssertEqual(foundationURL.host, "example.com")

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "http://example.com/")
      XCTAssertEqual(convertedURL.scheme, "http")
      XCTAssertEqual(convertedURL.host, .domain(WebURL.Domain("example.com")!))
    }
    test: do {
      let foundationURL = URL(string: "sChEmE://example.com/")!
      XCTAssertEqual(foundationURL.absoluteString, "sChEmE://example.com/")
      XCTAssertEqual(foundationURL.scheme, "sChEmE")
      XCTAssertEqual(foundationURL.host, "example.com")

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "scheme://example.com/")
      XCTAssertEqual(convertedURL.scheme, "scheme")
      XCTAssertEqual(convertedURL.host, .opaque("example.com"))
    }

    // [Username, Password]: may have percent-encoding added, due to differences in encode-set.
    test: do {
      let foundationURL = URL(string: "http://us=er:pa;ss@example.com/")!
      XCTAssertEqual(foundationURL.absoluteString, "http://us=er:pa;ss@example.com/")
      XCTAssertEqual(foundationURL.scheme, "http")
      XCTAssertEqual(foundationURL.user, "us=er")
      XCTAssertEqual(foundationURL.password, "pa;ss")
      XCTAssertEqual(foundationURL.host, "example.com")

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "http://us%3Der:pa%3Bss@example.com/")
      XCTAssertEqual(convertedURL.scheme, "http")
      XCTAssertEqual(convertedURL.username, "us%3Der")
      XCTAssertEqual(convertedURL.password, "pa%3Bss")
      XCTAssertEqual(convertedURL.host, .domain(WebURL.Domain("example.com")!))
    }

    // [Hostname]: may be percent-decoded and lowercased, if the URL has a special scheme.
    test: do {
      let foundationURL = URL(string: "http://EX%61mpLe.com/")!
      XCTAssertEqual(foundationURL.absoluteString, "http://EX%61mpLe.com/")
      XCTAssertEqual(foundationURL.scheme, "http")
      XCTAssertEqual(foundationURL.host, "EXampLe.com")

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "http://example.com/")
      XCTAssertEqual(convertedURL.scheme, "http")
      XCTAssertEqual(convertedURL.host, .domain(WebURL.Domain("example.com")!))
    }
    test: do {
      let foundationURL = URL(string: "http://%3127%2e0%2e0%2e1/")!
      XCTAssertEqual(foundationURL.absoluteString, "http://%3127%2e0%2e0%2e1/")
      XCTAssertEqual(foundationURL.scheme, "http")
      XCTAssertEqual(foundationURL.host, "127.0.0.1")

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "http://127.0.0.1/")
      XCTAssertEqual(convertedURL.scheme, "http")
      XCTAssertEqual(convertedURL.host, .ipv4Address(IPv4Address(octets: (127, 0, 0, 1))))
    }
    // But not if it has a non-special scheme.
    test: do {
      let foundationURL = URL(string: "sc://EX%61mpLe.com/")!
      XCTAssertEqual(foundationURL.absoluteString, "sc://EX%61mpLe.com/")
      XCTAssertEqual(foundationURL.scheme, "sc")
      XCTAssertEqual(foundationURL.host, "EXampLe.com")

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "sc://EX%61mpLe.com/")
      XCTAssertEqual(convertedURL.scheme, "sc")
      XCTAssertEqual(convertedURL.host, .opaque("EX%61mpLe.com"))
    }
    test: do {
      let foundationURL = URL(string: "sc://%3127%2e0%2e0%2e1/")!
      XCTAssertEqual(foundationURL.absoluteString, "sc://%3127%2e0%2e0%2e1/")
      XCTAssertEqual(foundationURL.scheme, "sc")
      XCTAssertEqual(foundationURL.host, "127.0.0.1")

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "sc://%3127%2e0%2e0%2e1/")
      XCTAssertEqual(convertedURL.scheme, "sc")
      XCTAssertEqual(convertedURL.host, .opaque("%3127%2e0%2e0%2e1"))
    }

    // [Hostname]: RFC-2396 says if the last label starts with a number, the host is IPv4,
    // but the WHATWG's standard says the last label must be entirely digits or a hex number.
    // We consider this safe; it means some hostnames that are not valid IP addresses are considered
    // valid domains, so there is no ambiguity and it also agrees with RFC-3986.
    test: do {
      let foundationURL = URL(string: "http://ab.0a")!
      XCTAssertEqual(foundationURL.absoluteString, "http://ab.0a")
      XCTAssertEqual(foundationURL.host, "ab.0a")

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "http://ab.0a/")
      XCTAssertEqual(convertedURL.host, .domain(WebURL.Domain("ab.0a")!))
    }
    // Non-special schemes are not even interpreted by the WHATWG standard,
    // so this concern would never have applied to them anyway.
    test: do {
      let foundationURL = URL(string: "foo://ab.0a")!
      XCTAssertEqual(foundationURL.absoluteString, "foo://ab.0a")
      XCTAssertEqual(foundationURL.host, "ab.0a")

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }
      XCTAssertEqual(convertedURL.serialized(), "foo://ab.0a")
      XCTAssertEqual(convertedURL.host, .opaque("ab.0a"))
    }

    // [Port]: may be omitted if it is the scheme's default port.
    test: do {
      let foundationURL = URL(string: "http://example.com:80/")!
      XCTAssertEqual(foundationURL.absoluteString, "http://example.com:80/")
      XCTAssertEqual(foundationURL.scheme, "http")
      XCTAssertEqual(foundationURL.host, "example.com")
      XCTAssertEqual(foundationURL.port, 80)

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "http://example.com/")
      XCTAssertEqual(convertedURL.scheme, "http")
      XCTAssertEqual(convertedURL.host, .domain(WebURL.Domain("example.com")!))
      XCTAssertEqual(convertedURL.port, nil)
      XCTAssertEqual(convertedURL.portOrKnownDefault, 80)
    }
    test: do {
      let foundationURL = URL(string: "https://example.com:443/")!
      XCTAssertEqual(foundationURL.absoluteString, "https://example.com:443/")
      XCTAssertEqual(foundationURL.scheme, "https")
      XCTAssertEqual(foundationURL.host, "example.com")
      XCTAssertEqual(foundationURL.port, 443)

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "https://example.com/")
      XCTAssertEqual(convertedURL.scheme, "https")
      XCTAssertEqual(convertedURL.host, .domain(WebURL.Domain("example.com")!))
      XCTAssertEqual(convertedURL.port, nil)
      XCTAssertEqual(convertedURL.portOrKnownDefault, 443)
    }
    // But non-default ports may not be omitted.
    test: do {
      let foundationURL = URL(string: "http://example.com:8080/")!
      XCTAssertEqual(foundationURL.absoluteString, "http://example.com:8080/")
      XCTAssertEqual(foundationURL.scheme, "http")
      XCTAssertEqual(foundationURL.host, "example.com")
      XCTAssertEqual(foundationURL.port, 8080)

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "http://example.com:8080/")
      XCTAssertEqual(convertedURL.scheme, "http")
      XCTAssertEqual(convertedURL.host, .domain(WebURL.Domain("example.com")!))
      XCTAssertEqual(convertedURL.port, 8080)
      XCTAssertEqual(convertedURL.portOrKnownDefault, 8080)
    }

    // [Path]: may be simplified.
    test: do {
      let foundationURL = URL(string: "http://example.com/foo/bar/././baz/../qux")!
      XCTAssertEqual(foundationURL.absoluteString, "http://example.com/foo/bar/././baz/../qux")
      XCTAssertEqual(foundationURL.scheme, "http")
      XCTAssertEqual(foundationURL.host, "example.com")
      XCTAssertEqual(foundationURL.path, "/foo/bar/././baz/../qux")

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "http://example.com/foo/bar/qux")
      XCTAssertEqual(convertedURL.scheme, "http")
      XCTAssertEqual(convertedURL.host, .domain(WebURL.Domain("example.com")!))
      XCTAssertEqual(convertedURL.path, "/foo/bar/qux")
    }
    // This includes Windows drive letter compatibility quirks.
    test: do {
      let foundationURL = URL(string: "file:///foo/bar/../../C:/../../../baz/../qux/foo2/")!
      XCTAssertEqual(foundationURL.absoluteString, "file:///foo/bar/../../C:/../../../baz/../qux/foo2/")
      XCTAssertEqual(foundationURL.scheme, "file")
      XCTAssertEqual(foundationURL.host, nil)
      // Foundation strips the trailing slash for some reason (even though .absoluteString still has it ¯\_(ツ)_/¯).
      XCTAssertEqual(foundationURL.path, "/foo/bar/../../C:/../../../baz/../qux/foo2")

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "file:///C:/qux/foo2/")
      XCTAssertEqual(convertedURL.scheme, "file")
      XCTAssertEqual(convertedURL.host, .empty)
      XCTAssertEqual(convertedURL.path, "/C:/qux/foo2/")
    }

    // [Query]: may have percent-encoding added if the scheme is special, due to differences in encode-set.
    test: do {
      let foundationURL = URL(string: "http://example.com/?what's+the+time=qu%61rter+past+nine")!
      XCTAssertEqual(foundationURL.absoluteString, "http://example.com/?what's+the+time=qu%61rter+past+nine")
      XCTAssertEqual(foundationURL.scheme, "http")
      XCTAssertEqual(foundationURL.host, "example.com")
      XCTAssertEqual(foundationURL.path, "/")
      XCTAssertEqual(foundationURL.query, "what's+the+time=qu%61rter+past+nine")

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "http://example.com/?what%27s+the+time=qu%61rter+past+nine")
      XCTAssertEqual(convertedURL.scheme, "http")
      XCTAssertEqual(convertedURL.host, .domain(WebURL.Domain("example.com")!))
      XCTAssertEqual(convertedURL.path, "/")
      XCTAssertEqual(convertedURL.query, "what%27s+the+time=qu%61rter+past+nine")
    }
    // But not for non-special schemes.
    test: do {
      let foundationURL = URL(string: "sc://example.com/?what's+the+time=qu%61rter+past+nine")!
      XCTAssertEqual(foundationURL.absoluteString, "sc://example.com/?what's+the+time=qu%61rter+past+nine")
      XCTAssertEqual(foundationURL.scheme, "sc")
      XCTAssertEqual(foundationURL.host, "example.com")
      XCTAssertEqual(foundationURL.path, "/")
      XCTAssertEqual(foundationURL.query, "what's+the+time=qu%61rter+past+nine")

      guard let convertedURL = WebURL(foundationURL) else {
        XCTFail("Unexpected failure to convert: \(foundationURL)")
        break test
      }

      XCTAssertEqual(convertedURL.serialized(), "sc://example.com/?what's+the+time=qu%61rter+past+nine")
      XCTAssertEqual(convertedURL.scheme, "sc")
      XCTAssertEqual(convertedURL.host, .opaque("example.com"))
      XCTAssertEqual(convertedURL.path, "/")
      XCTAssertEqual(convertedURL.query, "what's+the+time=qu%61rter+past+nine")
    }

    // [Fragment]: no normalization is applied.
  }

  func testUnsafeNormalization() {

    // [Username, Password]: delimiters must not be removed.
    // Since the WHATWG URL Standard requires it, these must fail to convert.
    test: do {
      let foundationURL = URL(string: "http://user:@hostname.com")!
      XCTAssertEqual(foundationURL.absoluteString, "http://user:@hostname.com")
      XCTAssertEqual(foundationURL.user, "user")
      XCTAssertEqual(foundationURL.password, "")
      XCTAssertEqual(foundationURL.host, "hostname.com")

      XCTAssertNil(WebURL(foundationURL))

      let webURL = WebURL("http://user:@hostname.com")!
      XCTAssertEqual(webURL.serialized(), "http://user@hostname.com/")
      //                                              ^ - password delimiter removed.
      XCTAssertEqual(webURL.username, "user")
      XCTAssertEqual(webURL.password, nil)
      XCTAssertEqual(webURL.hostname, "hostname.com")
    }
    test: do {
      let foundationURL = URL(string: "http://:@hostname.com")!
      XCTAssertEqual(foundationURL.absoluteString, "http://:@hostname.com")
      XCTAssertEqual(foundationURL.user, "")
      XCTAssertEqual(foundationURL.password, "")
      XCTAssertEqual(foundationURL.host, "hostname.com")

      XCTAssertNil(WebURL(foundationURL))

      let webURL = WebURL("http://:@hostname.com")!
      XCTAssertEqual(webURL.serialized(), "http://hostname.com/")
      //                                          ^ - userinfo delimiter removed.
      XCTAssertEqual(webURL.username, nil)
      XCTAssertEqual(webURL.password, nil)
      XCTAssertEqual(webURL.hostname, "hostname.com")
    }

    // Stripping "localhost" from file URLs is not a safe conversion.
    test: do {
      let foundationURL = URL(string: "file://localhost/usr/bin/swift")!
      XCTAssertEqual(foundationURL.absoluteString, "file://localhost/usr/bin/swift")
      XCTAssertEqual(foundationURL.host, "localhost")
      XCTAssertEqual(foundationURL.path, "/usr/bin/swift")

      XCTAssertNil(WebURL(foundationURL))

      let webURL = WebURL("file://localhost/usr/bin/swift")!
      XCTAssertEqual(webURL.serialized(), "file:///usr/bin/swift")
      XCTAssertEqual(webURL.host, .empty)
      XCTAssertEqual(webURL.path, "/usr/bin/swift")
    }
  }

  func testRoundTripFailures() {

    // If a domain includes percent-encoded disallowed characters, WebURL will decode them,
    // and Foundation will reject them when round-tripping.
    test: do {
      let foundationURL = URL(string: "http://te%7Bs%7Dt/foo/bar")!
      XCTAssertEqual(foundationURL.absoluteString, "http://te%7Bs%7Dt/foo/bar")
      XCTAssertEqual(foundationURL.host, "te{s}t")
      XCTAssertEqual(foundationURL.path, "/foo/bar")

      let convertedURL = WebURL(foundationURL)!
      XCTAssertEqual(convertedURL.serialized(), "http://te{s}t/foo/bar")
      XCTAssertEqual(convertedURL.hostname, "te{s}t")
      XCTAssertEqual(convertedURL.path, "/foo/bar")

      XCTAssertNil(URL(convertedURL))
    }
  }

  func testAmbiguousURLs() {

    var inputs: [(string: String, webURL: String?)] = [
      // Adding lots of '@'s and ':'s confuses Foundation.URL.
      // Since the components are inconsistent, WebURL should fail to convert these.
      (string: "http://@abc", webURL: nil),
      (string: "http://:@abc", webURL: nil),
      (string: "http://abc:@def", webURL: nil),
      (string: "http://:abc@def", webURL: "http://:abc@def/"),
      (string: "http://abc@def@ghi", webURL: nil),
      (string: "http://:abc@def@ghi", webURL: nil),
      (string: "http://abc:@def@ghi", webURL: nil),
      (string: "http://abc@:def@ghi", webURL: nil),
      (string: "http://abc@def:@ghi", webURL: nil),
      (string: "http://abc@def@:ghi", webURL: nil),
      (string: "http://abc@def@ghi:", webURL: nil),
      (string: "http://u@x:@x", webURL: nil),
      (string: "sc://@abc", webURL: nil),
      (string: "sc://:@abc", webURL: nil),
      (string: "sc://abc:@def", webURL: nil),
      (string: "sc://:abc@def", webURL: "sc://:abc@def"),
      (string: "sc://abc@def@ghi", webURL: nil),
      (string: "sc://:abc@def@ghi", webURL: nil),
      (string: "sc://abc:@def@ghi", webURL: nil),
      (string: "sc://abc@:def@ghi", webURL: nil),
      (string: "sc://abc@def:@ghi", webURL: nil),
      (string: "sc://abc@def@:ghi", webURL: nil),
      (string: "sc://abc@def@ghi:", webURL: nil),
      (string: "s://u@x:@x", webURL: nil),
      // As above, but all components have the same contents.
      (string: "http://@2:@2/", webURL: nil),
      (string: "http://@2:@2:@2/", webURL: nil),
      (string: "http://@2:@2:@2/?", webURL: nil),
      (string: "http://@2:@2:@2?/", webURL: nil),
      (string: "http://@2:@2:@?2/", webURL: nil),
      (string: "http://@2:@2:?@2/", webURL: nil),
      (string: "http://@2:@2?:@2/", webURL: nil),
      (string: "sc://@2:@2/", webURL: nil),
      (string: "sc://@2:@2:@2/", webURL: nil),
      (string: "sc://@2:@2:@2/?", webURL: nil),
      (string: "sc://@2:@2:@2?/", webURL: nil),
      (string: "sc://@2:@2:@?2/", webURL: nil),
      (string: "sc://@2:@2:?@2/", webURL: nil),
      (string: "sc://@2:@2?:@2/", webURL: nil),
      // Foundation accepts these, but shouldn't. The returned password includes a non-encoded ":".
      (string: "http://a:b:c@d/private/", webURL: nil),
      (string: "http://2:2:2@2/private/", webURL: nil),
      (string: "sc://a:b:c@d/private/", webURL: nil),
      (string: "sc://2:2:2@2/private/", webURL: nil),
      // You can trick Foundation.URL to read a password after the hostname.
      // Here, the URL's hostname is "hostname" and password is "@password".
      // WebURL should refuse to convert these. https://bugs.swift.org/browse/SR-15513
      (string: "http://@hostname:@password:@whydoesthishappen/", webURL: nil),
      (string: "http://@hostname:@password:@whydoesthishappen@/", webURL: nil),
      (string: "sc://@hostname:@password:@whydoesthishappen/", webURL: nil),
      (string: "sc://@hostname:@password:@whydoesthishappen@/", webURL: nil),
      // You can have a single component appear as both the hostname AND the password.
      (string: "http://:@hostname_and_password:@/", webURL: nil),
      (string: "sc://:@hostname_and_password:@/", webURL: nil),

      // Host-port split.
      (string: "http://abc:99@def@ghi", webURL: nil),
      (string: "http://abc@def:99@ghi", webURL: nil),
      (string: "http://abc@def@ghi:99", webURL: nil),
      (string: "sc://abc:99@def@ghi", webURL: nil),
      (string: "sc://abc@def:99@ghi", webURL: nil),
      (string: "sc://abc@def@ghi:99", webURL: nil),

      // Opaque paths which start with "?".
      // For file URLs, WebURL would turn these in to a URL with non-opaque path.
      (string: "http:?xyz", webURL: nil),
      (string: "http:?%82yz", webURL: nil),
      (string: "file:?xyz", webURL: nil),
      (string: "file:?%82yz", webURL: nil),
      (string: "sc:?xyz", webURL: "sc:?xyz"),
      (string: "sc:?%82yz", webURL: "sc:?%82yz"),
      // Opaque paths which start with "#". Foundation borks these URLs before we see them.
      // https://bugs.swift.org/browse/SR-15381
      (string: "http:#xyz", webURL: nil),
      (string: "http:#%82yz", webURL: nil),
      (string: "file:#xyz", webURL: "file:///%23xyz"),
      (string: "file:#%82yz", webURL: "file:///%23%82yz"),
      (string: "sc:#xyz", webURL: "sc:%23xyz"),
      (string: "sc:#%82yz", webURL: "sc:%23%82yz"),

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

      // Foundation allows any percent-encoding in IPv6 addresses, including newlines, null bytes, etc.
      // https://bugs.swift.org/browse/SR-15514
      (string: "http://[::1%0Aen0]/c/d", webURL: nil),
      (string: "http://[::1%0Aen0]@c@d", webURL: nil),
    ]

    #if canImport(Darwin)
      // Password overlaps the fragment. This seems to only happen on Apple platforms;
      // on other platforms, it returns the correct components and thus can be converted.
      // https://bugs.swift.org/browse/SR-15738
      inputs += [
        (string: "sc://]0#::[@", webURL: nil)
      ]
    #else
      inputs += [
        (string: "sc://]0#::[@", webURL: "sc://%5D0#::%5B@")
      ]
    #endif

    for (string, _expectedWebURLString) in inputs {
      guard let url = URL(string: string) else {
        XCTFail("Invalid URL: \(string)")
        continue
      }
      guard let expectedWebURLString = _expectedWebURLString else {
        XCTAssertNil(WebURL(url), "Unexpected conversion: \(string)")
        continue
      }
      guard let actualWebURL = WebURL(url) else {
        XCTFail("Unexpected failure to convert: \(string)")
        continue
      }
      XCTAssertEqual(
        expectedWebURLString, actualWebURL.serialized(),
        "Unexpected result for \(string) -- Expected: \(expectedWebURLString) -- Actual: \(actualWebURL.serialized())"
      )
      XCTAssertEquivalentURLs(actualWebURL, url, "String: \(string)")
    }
  }
}


// --------------------------------
// MARK: - Fuzz Corpus Tests
// --------------------------------


final class FoundationToWeb_CorpusTests: XCTestCase {

  func testFuzzCorpus() {
    for bytes in corpus_foundation_to_web {
      let input = String(decoding: bytes, as: UTF8.self)
      guard let foundationURL = URL(string: input) else {
        continue  // Not a valid URL.
      }
      guard let webURL = WebURL(foundationURL) else {
        continue  // WebURL didn't convert the URL. That's fine.
      }
      XCTAssertEquivalentURLs(webURL, foundationURL, "String: \(input)")
    }
  }
}
