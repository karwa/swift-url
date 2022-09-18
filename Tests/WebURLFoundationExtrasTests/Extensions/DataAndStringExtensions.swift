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
import XCTest

@testable import WebURLFoundationExtras

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class DataAndStringExtensions: XCTestCase {}


// --------------------------------
// MARK: - Test URLs
// --------------------------------


extension DataAndStringExtensions {

  static let TestURLs: [(webURL: WebURL, convertedURL: URL)] = {
    [
      // File.
      ("file:///usr/bin/swift", "file:///usr/bin/swift"),
      ("file:///C:/Windows/System32/notepad.exe", "file:///C:/Windows/System32/notepad.exe"),
      // Directory path.
      ("file:///usr/bin/", "file:///usr/bin/"),
      ("file:///G:/usr/bin/", "file:///G:/usr/bin/"),
      // Directory with no trailing slash.
      ("file:///usr/bin", "file:///usr/bin"),
      ("file:///C:/Windows", "file:///C:/Windows"),
      // HTTP.
      ("http://foo.com/bar/baz", "http://foo.com/bar/baz"),
      // Custom scheme.
      ("foo://bar/baz/", "foo://bar/baz/"),
      // Percent-encoding added to path.
      ("file:///usr/bin/sw[if]t", "file:///usr/bin/sw%5Bif%5Dt"),
      // Percent-encoding added to query.
      ("http://foo.com/bar/baz?id={xx}", "http://foo.com/bar/baz?id=%7Bxx%7D"),
    ].map {
      let webURL = WebURL($0)!
      XCTAssertEqual(webURL.serialized(), $0, "Given string is not a valid WebURL")
      XCTAssertEqual(webURL.encodedForFoundation.serialized(), $1)
      let foundationURL = URL(string: $1)!
      XCTAssertEqual(foundationURL.absoluteString, $1, "Given string is not a valid Foundation.URL")
      return (webURL, foundationURL)
    }
  }()

  static let ConversionFailureURLs: [WebURL] = {
    [
      "file://loc{al}host/foo/bar",
      "http://loc{al}host/foo/bar",
    ].map {
      let webURL = WebURL($0)!
      XCTAssertEqual(webURL.serialized(), $0, "Given string is not a valid WebURL")
      XCTAssertNil(URL(webURL), "WebURL to Foundation.URL conversion was unexpectedly successful")
      return webURL
    }
  }()
}


// --------------------------------
// MARK: - Data
// --------------------------------


extension DataAndStringExtensions {

  func testData_contentsOfURL() {

    // 1. Install test stub.

    var expectedArguments: (url: URL, options: Data.ReadingOptions)? = nil
    var stubWasCalled = false

    defer { Data.extendedFunctions = .default }
    Data.extendedFunctions = Data._ExtendedFunctions(
      contentsOfURL: { actualFoundationURL, actualOptions in
        precondition(!stubWasCalled, "stubWasCalled must be reset between invocations")
        XCTAssertEqual(actualFoundationURL, expectedArguments?.url)
        XCTAssertEqual(actualOptions, expectedArguments?.options)
        stubWasCalled = true
        return Data([1, 2, 3])
      },
      writeToURL: { _, _, _ in
        XCTFail("Should not be invoked")
      }
    )

    // 2. Invoke with some example URLs and options,
    //    ensure the stub is called with the correct values.

    let _testOptions: [Data.ReadingOptions] = [[], [.uncached], [.mappedIfSafe], [.uncached, .mappedIfSafe]]
    var _optionsIter = _testOptions.makeIterator()
    func getNextOption() -> Data.ReadingOptions {
      if let next = _optionsIter.next() {
        return next
      } else {
        _optionsIter = _testOptions.makeIterator()
        return _optionsIter.next()!
      }
    }

    for (webURL, convertedURL) in Self.TestURLs {
      let options = getNextOption()

      expectedArguments = (convertedURL, options)
      stubWasCalled = false
      XCTAssertEqual(try! Data(contentsOf: webURL, options: options), Data([1, 2, 3]))
      XCTAssertTrue(stubWasCalled)
    }
  }

  func testData_contentsOfURL_conversionFailure() {

    // 1. Install test stub.

    defer { Data.extendedFunctions = .default }
    Data.extendedFunctions = Data._ExtendedFunctions(
      contentsOfURL: { _, _ in
        XCTFail("Should not be invoked")
        return Data([1, 2, 3])
      },
      writeToURL: { _, _, _ in
        XCTFail("Should not be invoked")
      }
    )

    // 2. Invoke with some example URLs.
    //    Conversion failures should not actually invoke any stubs.

    for webURL in Self.ConversionFailureURLs {
      do {
        let _ = try Data(contentsOf: webURL)
        XCTFail("Expected an error to be thrown")
      } catch let error as WebURLToFoundationConversionError {
        XCTAssertEqual(error.url, webURL)
      } catch {
        XCTFail("Unexpected error \(error)")
      }
    }
  }

  func testData_writeToURL() {

    // 1. Install test stub.

    var expectedArguments: (data: Data, url: URL, options: Data.WritingOptions)? = nil
    var stubWasCalled = false

    defer { Data.extendedFunctions = .default }
    Data.extendedFunctions = Data._ExtendedFunctions(
      contentsOfURL: { _, _ in
        XCTFail("Should not be invoked")
        return Data([1, 2, 3])
      },
      writeToURL: { actualData, actualFoundationURL, actualOptions in
        precondition(!stubWasCalled, "stubWasCalled must be reset between invocations")
        XCTAssertEqual(actualData, expectedArguments?.data)
        XCTAssertEqual(actualFoundationURL, expectedArguments?.url)
        XCTAssertEqual(actualOptions, expectedArguments?.options)
        stubWasCalled = true
      }
    )

    // 2. Invoke with some example URLs and options,
    //    ensure the stub is called with the correct values.

    let _testOptions: [Data.WritingOptions] = [[], [.atomic], [.withoutOverwriting], [.atomic, .withoutOverwriting]]
    var _optionsIter = _testOptions.makeIterator()
    func getNextOption() -> Data.WritingOptions {
      if let next = _optionsIter.next() {
        return next
      } else {
        _optionsIter = _testOptions.makeIterator()
        return _optionsIter.next()!
      }
    }

    var rng = SystemRandomNumberGenerator()

    for (webURL, convertedURL) in Self.TestURLs {
      let options = getNextOption()
      let data = Data((0..<10).map { _ in rng.next() as UInt8 })

      expectedArguments = (data, convertedURL, options)
      stubWasCalled = false
      XCTAssertNoThrow(try data.write(to: webURL, options: options))
      XCTAssertTrue(stubWasCalled)
    }
  }

  func testData_writeToURL_conversionFailure() {

    // 1. Install test stub.

    defer { Data.extendedFunctions = .default }
    Data.extendedFunctions = Data._ExtendedFunctions(
      contentsOfURL: { _, _ in
        XCTFail("Should not be invoked")
        return Data([1, 2, 3])
      },
      writeToURL: { _, _, _ in
        XCTFail("Should not be invoked")
      }
    )

    // 2. Invoke with some example URLs.
    //    Conversion failures should not actually invoke any stubs.

    var rng = SystemRandomNumberGenerator()
    let data = Data((0..<10).map { _ in rng.next() as UInt8 })

    for webURL in Self.ConversionFailureURLs {
      do {
        try data.write(to: webURL)
        XCTFail("Expected an error to be thrown")
      } catch let error as WebURLToFoundationConversionError {
        XCTAssertEqual(error.url, webURL)
      } catch {
        XCTFail("Unexpected error \(error)")
      }
    }
  }
}


// --------------------------------
// MARK: - String
// --------------------------------


extension DataAndStringExtensions {

  func testString_contentsOfURL() {

    // 1. Install test stub.

    var expectedArgument: URL? = nil
    var stubWasCalled = false

    defer { String.extendedFunctions = .default }
    String.extendedFunctions = String._ExtendedFunctions(
      contentsOfURL: { actualFoundationURL in
        precondition(!stubWasCalled, "stubWasCalled must be reset between invocations")
        XCTAssertEqual(actualFoundationURL, expectedArgument)
        stubWasCalled = true
        return "hello, world! \(#function)"
      },
      contentsOfURLWithEncoding: { _, _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      contentsOfURLWithUsedEncoding: { _, _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      writeToURL: { _, _, _, _ in
        XCTFail("Should not be invoked")
      }
    )

    // 2. Invoke with some example URLs,
    //    ensure the stub is called with the correct values.

    for (webURL, convertedURL) in Self.TestURLs {
      expectedArgument = convertedURL
      stubWasCalled = false
      XCTAssertEqual(try! String(contentsOf: webURL), "hello, world! \(#function)")
      XCTAssertTrue(stubWasCalled)
    }
  }

  func testString_contentsOfURL_withEncoding() {

    // 1. Install test stub.

    var expectedArguments: (url: URL, encoding: String.Encoding)? = nil
    var stubWasCalled = false

    defer { String.extendedFunctions = .default }
    String.extendedFunctions = String._ExtendedFunctions(
      contentsOfURL: { _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      contentsOfURLWithEncoding: { actualFoundationURL, actualEncoding in
        precondition(!stubWasCalled, "stubWasCalled must be reset between invocations")
        XCTAssertEqual(actualFoundationURL, expectedArguments?.url)
        XCTAssertEqual(actualEncoding, expectedArguments?.encoding)
        stubWasCalled = true
        return "hello, world! \(#function)"
      },
      contentsOfURLWithUsedEncoding: { _, _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      writeToURL: { _, _, _, _ in
        XCTFail("Should not be invoked")
      }
    )

    // 2. Invoke with some example URLs and options,
    //    ensure the stub is called with the correct values.

    let _testEncodings: [String.Encoding] = [.utf8, .utf16, .shiftJIS, .isoLatin1, .utf32LittleEndian]
    var _encodingsIter = _testEncodings.makeIterator()
    func getNextEncoding() -> String.Encoding {
      if let next = _encodingsIter.next() {
        return next
      } else {
        _encodingsIter = _testEncodings.makeIterator()
        return _encodingsIter.next()!
      }
    }

    for (webURL, convertedURL) in Self.TestURLs {
      let encoding = getNextEncoding()

      expectedArguments = (convertedURL, encoding)
      stubWasCalled = false
      XCTAssertEqual(try! String(contentsOf: webURL, encoding: encoding), "hello, world! \(#function)")
      XCTAssertTrue(stubWasCalled)
    }
  }

  func testString_contentsOfURL_withUsedEncoding() {

    // 1. Install test stub.

    var expectedArguments: (url: URL, encoding_in: String.Encoding)? = nil
    let expectedEncoding_out: String.Encoding = .utf16LittleEndian
    var stubWasCalled = false

    defer { String.extendedFunctions = .default }
    String.extendedFunctions = String._ExtendedFunctions(
      contentsOfURL: { _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      contentsOfURLWithEncoding: { _, _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      contentsOfURLWithUsedEncoding: { actualFoundationURL, actualEncoding in
        precondition(!stubWasCalled, "stubWasCalled should be reset between tests")
        XCTAssertEqual(actualFoundationURL, expectedArguments?.url)
        XCTAssertEqual(actualEncoding, expectedArguments?.encoding_in)
        actualEncoding = expectedEncoding_out
        stubWasCalled = true
        return "hello, world! \(#function)"
      },
      writeToURL: { _, _, _, _ in
        XCTFail("Should not be invoked")
      }
    )

    // 2. Invoke with some example URLs and options,
    //    ensure the stub is called with the correct values.

    let _testEncodings: [String.Encoding] = [.utf8, .utf16, .shiftJIS, .isoLatin1, .utf32LittleEndian]
    var _encodingsIter = _testEncodings.makeIterator()
    func getNextEncoding() -> String.Encoding {
      if let next = _encodingsIter.next() {
        return next
      } else {
        _encodingsIter = _testEncodings.makeIterator()
        return _encodingsIter.next()!
      }
    }

    for (webURL, convertedURL) in Self.TestURLs {
      var encoding = getNextEncoding()

      expectedArguments = (convertedURL, encoding)
      stubWasCalled = false
      XCTAssertEqual(try! String(contentsOf: webURL, usedEncoding: &encoding), "hello, world! \(#function)")
      XCTAssertTrue(stubWasCalled)

      XCTAssertEqual(encoding, expectedEncoding_out)
    }
  }

  func testString_contentsOfURL_conversionFailure() {

    // 1. Install test stub.

    defer { String.extendedFunctions = .default }
    String.extendedFunctions = String._ExtendedFunctions(
      contentsOfURL: { _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      contentsOfURLWithEncoding: { _, _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      contentsOfURLWithUsedEncoding: { _, _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      writeToURL: { _, _, _, _ in
        XCTFail("Should not be invoked")
      }
    )

    // 2. Invoke with some example URLs.
    //    Conversion failures should not actually invoke any stubs.

    for webURL in Self.ConversionFailureURLs {

      // String(contentsOf:)
      do {
        let _ = try String(contentsOf: webURL)
        XCTFail("Expected an error to be thrown")
      } catch let error as WebURLToFoundationConversionError {
        XCTAssertEqual(error.url, webURL)
      } catch {
        XCTFail("Unexpected error \(error)")
      }

      // String(contentsOf:encoding:)
      do {
        let _ = try String(contentsOf: webURL, encoding: .utf8)
        XCTFail("Expected an error to be thrown")
      } catch let error as WebURLToFoundationConversionError {
        XCTAssertEqual(error.url, webURL)
      } catch {
        XCTFail("Unexpected error \(error)")
      }

      // String(contentsOf:usedEncoding:)
      do {
        var encoding = String.Encoding.utf8
        let _ = try String(contentsOf: webURL, usedEncoding: &encoding)
        XCTFail("Expected an error to be thrown")
      } catch let error as WebURLToFoundationConversionError {
        XCTAssertEqual(error.url, webURL)
      } catch {
        XCTFail("Unexpected error \(error)")
      }
    }
  }

  func testString_writeToURL() {

    // 1. Install test stub.

    var expectedArguments: (string: String, url: URL, atomic: Bool, encoding: String.Encoding)? = nil
    var stubWasCalled = false

    defer { String.extendedFunctions = .default }
    String.extendedFunctions = String._ExtendedFunctions(
      contentsOfURL: { _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      contentsOfURLWithEncoding: { _, _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      contentsOfURLWithUsedEncoding: { _, _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      writeToURL: { actualString, actualFoundationURL, actualAtomic, actualEncoding in
        precondition(!stubWasCalled, "stubWasCalled must be reset between invocations")
        XCTAssertEqual(actualString, expectedArguments?.string)
        XCTAssertEqual(actualFoundationURL, expectedArguments?.url)
        XCTAssertEqual(actualAtomic, expectedArguments?.atomic)
        XCTAssertEqual(actualEncoding, expectedArguments?.encoding)
        stubWasCalled = true
      }
    )

    // 2. Invoke with some example URLs and options,
    //    ensure the stub is called with the correct values.

    let _testEncodings: [String.Encoding] = [.utf8, .utf16, .shiftJIS, .isoLatin1, .utf32LittleEndian]
    var _encodingsIter = _testEncodings.makeIterator()
    func getNextEncoding() -> String.Encoding {
      if let next = _encodingsIter.next() {
        return next
      } else {
        _encodingsIter = _testEncodings.makeIterator()
        return _encodingsIter.next()!
      }
    }

    var _lastBool = true
    func getNextBool() -> Bool {
      let value = _lastBool
      _lastBool.toggle()
      return value
    }

    for (webURL, convertedURL) in Self.TestURLs {
      let encoding = getNextEncoding()
      let atomic = getNextBool()
      let string = "hello, world! \(#function) - \(Int.random(in: 100..<10_000))"

      expectedArguments = (string, convertedURL, atomic, encoding)
      stubWasCalled = false
      XCTAssertNoThrow(try string.write(to: webURL, atomically: atomic, encoding: encoding))
      XCTAssertTrue(stubWasCalled)
    }
  }

  func testString_writeToURL_conversionFailure() throws {

    // 1. Install test stub.

    defer { String.extendedFunctions = .default }
    String.extendedFunctions = String._ExtendedFunctions(
      contentsOfURL: { _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      contentsOfURLWithEncoding: { _, _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      contentsOfURLWithUsedEncoding: { _, _ in
        XCTFail("Should not be invoked")
        return "FAIL"
      },
      writeToURL: { _, _, _, _ in
        XCTFail("Should not be invoked")
      }
    )

    // 2. Invoke with some example URLs.
    //    Conversion failures should not actually invoke any stubs.

    for webURL in Self.ConversionFailureURLs {
      do {
        let _ = try "hello, 🌍!".write(to: webURL, atomically: false, encoding: .utf8)
        XCTFail("Expected an error to be thrown")
      } catch let error as WebURLToFoundationConversionError {
        XCTAssertEqual(error.url, webURL)
      } catch {
        XCTFail("Unexpected error \(error)")
      }
    }
  }
}
