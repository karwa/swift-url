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

final class URLRequestResponseExtensions: XCTestCase {}


// --------------------------------
// MARK: - Constructing a URLRequest
// --------------------------------


// On non-Apple platforms, executing a URLRequest whose url is nil will 'fatalError'.
// Since that is how we prefer to signal conversion failures, we don't even offer the extensions to create
// a URLRequest from a WebURL on those platforms. Fixed by https://github.com/apple/swift-corelibs-foundation/pull/3154
#if canImport(Darwin)

  extension URLRequestResponseExtensions {

    func testCreateRequest_simpleConversion() {
      let webURL = WebURL("http://example.com/foo/bar?baz=qux")!
      XCTAssertEqual(webURL.serialized(), "http://example.com/foo/bar?baz=qux")

      let urlRequest = URLRequest(url: webURL)
      XCTAssertEqual(urlRequest.url?.absoluteString, "http://example.com/foo/bar?baz=qux")
      XCTAssertEqual(urlRequest.webURL, webURL)
      XCTAssertEqual(urlRequest.webURL, webURL.encodedForFoundation)

      XCTAssertEqual(urlRequest.mainDocumentURL, nil)
      XCTAssertEqual(urlRequest.mainDocumentWebURL, nil)
    }

    func testCreateRequest_addPercentEncoding() {
      let webURL = WebURL("http://example.com/foo/bar?baz=[qux]")!
      XCTAssertEqual(webURL.serialized(), "http://example.com/foo/bar?baz=[qux]")

      // The default behavior is to add percent-encoding.
      do {
        let urlRequest = URLRequest(url: webURL)
        XCTAssertEqual(urlRequest.url?.absoluteString, "http://example.com/foo/bar?baz=%5Bqux%5D")
        XCTAssertEqual(urlRequest.webURL?.serialized(), "http://example.com/foo/bar?baz=%5Bqux%5D")
        XCTAssertEqual(urlRequest.webURL, webURL.encodedForFoundation)

        XCTAssertEqual(urlRequest.mainDocumentURL, nil)
        XCTAssertEqual(urlRequest.mainDocumentWebURL, nil)
      }
      // If we explicitly set 'addPercentEncoding' to false, the conversion will fail.
      do {
        let urlRequest = URLRequest(url: webURL, addPercentEncoding: false)
        XCTAssertEqual(urlRequest.url, nil)
        XCTAssertEqual(urlRequest.webURL, nil)

        XCTAssertEqual(urlRequest.mainDocumentURL, nil)
        XCTAssertEqual(urlRequest.mainDocumentWebURL, nil)
      }
    }

    func testCreateRequest_conversionFailure() {
      let webURL = WebURL("http://ex{am}ple.com/")!
      XCTAssertEqual(webURL.serialized(), "http://ex{am}ple.com/")

      let urlRequest = URLRequest(url: webURL)
      XCTAssertEqual(urlRequest.url, nil)
      XCTAssertEqual(urlRequest.webURL, nil)

      XCTAssertEqual(urlRequest.mainDocumentURL, nil)
      XCTAssertEqual(urlRequest.mainDocumentWebURL, nil)
    }
  }

#endif


// --------------------------------
// MARK: - URLRequest Getters/Setters
// --------------------------------


extension URLRequestResponseExtensions {

  func testWebURLProperty_simpleConversion() {
    // Construct a URLRequest with a Foundation.URL.
    var request = URLRequest(url: URL(string: "http://example.com/foo/bar?baz=qux")!)

    // Get the converted URL via the .webURL property.
    XCTAssertEqual(request.url?.absoluteString, "http://example.com/foo/bar?baz=qux")
    XCTAssertEqual(request.webURL?.serialized(), "http://example.com/foo/bar?baz=qux")
    XCTAssertEqual(request.mainDocumentURL, nil)
    XCTAssertEqual(request.mainDocumentWebURL, nil)

    // Set the URL via the .webURL property. Percent-encoding should be added as needed.
    let webURL = WebURL("https://localhost/qux/baz?bar=[foo]")!
    XCTAssertEqual(webURL.serialized(), "https://localhost/qux/baz?bar=[foo]")

    request.webURL = webURL
    XCTAssertEqual(request.url?.absoluteString, "https://localhost/qux/baz?bar=%5Bfoo%5D")
    XCTAssertEqual(request.webURL, webURL.encodedForFoundation)
    XCTAssertEqual(request.mainDocumentURL, nil)
    XCTAssertEqual(request.mainDocumentWebURL, nil)
  }

  func testWebURLProperty_getterConversionFailure() {
    // Construct a URLRequest with a Foundation.URL.
    var request = URLRequest(url: URL(string: "foo")!)

    // The URL is relative and cannot be converted to a WebURL.
    XCTAssertEqual(request.url?.absoluteString, "foo")
    XCTAssertEqual(request.webURL, nil)
    XCTAssertEqual(request.mainDocumentURL, nil)
    XCTAssertEqual(request.mainDocumentWebURL, nil)

    // Set the URL to a convertible WebURL via the .webURL property.
    let webURL = WebURL("https://localhost/qux/baz?bar=foo")!
    XCTAssertEqual(webURL.serialized(), "https://localhost/qux/baz?bar=foo")

    request.webURL = webURL
    XCTAssertEqual(request.url?.absoluteString, "https://localhost/qux/baz?bar=foo")
    XCTAssertEqual(request.webURL, webURL.encodedForFoundation)
    XCTAssertEqual(request.mainDocumentURL, nil)
    XCTAssertEqual(request.mainDocumentWebURL, nil)
  }

  func testWebURLProperty_setterConversionFailure() {
    // Construct a URLRequest with a Foundation.URL.
    var request = URLRequest(url: URL(string: "http://example.com/foo/bar?baz=qux")!)

    // Get the converted URL via the .webURL property.
    XCTAssertEqual(request.url?.absoluteString, "http://example.com/foo/bar?baz=qux")
    XCTAssertEqual(request.webURL?.serialized(), "http://example.com/foo/bar?baz=qux")
    XCTAssertEqual(request.mainDocumentURL, nil)
    XCTAssertEqual(request.mainDocumentWebURL, nil)

    // Set the URL via the .webURL property. The URL cannot be converted to a Foundation.URL.
    let webURL = WebURL("https://loc{alh}ost/qux/baz?bar=foo")!
    XCTAssertEqual(webURL.serialized(), "https://loc{alh}ost/qux/baz?bar=foo")

    request.webURL = webURL
    XCTAssertEqual(request.url, nil)
    XCTAssertEqual(request.webURL, nil)
    XCTAssertEqual(request.mainDocumentURL, nil)
    XCTAssertEqual(request.mainDocumentWebURL, nil)
  }

  func testMainDocumentWebURLProperty() {
    // Construct a URLRequest with a Foundation.URL. The value doesn't matter.
    var request = URLRequest(url: URL(string: "foo")!)
    XCTAssertEqual(request.url?.absoluteString, "foo")
    XCTAssertEqual(request.webURL, nil)

    XCTAssertEqual(request.mainDocumentURL, nil)
    XCTAssertEqual(request.mainDocumentWebURL, nil)

    // Set the mainDocumentWebURL to a convertible WebURL value. Percent-encoding should be added as needed.
    do {
      let webURL = WebURL("http://example.com/foo/bar?baz=[qux]")!
      XCTAssertEqual(webURL.serialized(), "http://example.com/foo/bar?baz=[qux]")

      request.mainDocumentWebURL = webURL
      XCTAssertEqual(request.url?.absoluteString, "foo")
      XCTAssertEqual(request.webURL, nil)
      XCTAssertEqual(request.mainDocumentURL?.absoluteString, "http://example.com/foo/bar?baz=%5Bqux%5D")
      XCTAssertEqual(request.mainDocumentWebURL, webURL.encodedForFoundation)
    }

    // Set the mainDocumentWebURL to a non-convertible WebURL value. Should set the value to nil.
    do {
      let webURL = WebURL("https://loc{alh}ost/qux/baz?bar=foo")!
      XCTAssertEqual(webURL.serialized(), "https://loc{alh}ost/qux/baz?bar=foo")

      request.mainDocumentWebURL = webURL
      XCTAssertEqual(request.url?.absoluteString, "foo")
      XCTAssertEqual(request.webURL, nil)
      XCTAssertEqual(request.mainDocumentURL?.absoluteString, nil)
      XCTAssertEqual(request.mainDocumentWebURL, nil)
    }
  }
}


// --------------------------------
// MARK: - URLResponse Getters
// --------------------------------


final class URLResponseTests: XCTestCase {}

extension URLResponseTests {

  func testWebURLProperty_simpleConversion() {
    let response = URLResponse(
      url: URL(string: "http://example.com/foo/bar?baz=qux")!,
      mimeType: nil, expectedContentLength: 42, textEncodingName: nil
    )
    XCTAssertEqual(response.url?.absoluteString, "http://example.com/foo/bar?baz=qux")
    XCTAssertEqual(response.webURL?.serialized(), "http://example.com/foo/bar?baz=qux")
  }

  func testWebURLProperty_getterConversionFailure() {
    let response = URLResponse(
      url: URL(string: "foo")!,
      mimeType: nil, expectedContentLength: 42, textEncodingName: nil
    )
    XCTAssertEqual(response.url?.absoluteString, "foo")
    XCTAssertEqual(response.webURL, nil)
  }
}
