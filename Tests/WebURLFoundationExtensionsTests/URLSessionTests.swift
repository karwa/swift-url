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
import XCTest

#if canImport(Swifter)
  import Swifter
#endif

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class URLSessionTests: XCTestCase {}


// --------------------------------
// MARK: - URLSessionDataTask
// --------------------------------
// It isn't really our business to check that URLSession works, but it is still nice to have these tests
// so we know exactly what developers are going to see when they make requests via the wrapper APIs we expose -
// including situations where percent-encoding needs to be added or when the WebURL cannot be converted to
// a Foundation.URL.


// On non-Apple platforms, executing a URLRequest whose url is nil will 'fatalError'.
// Since that is how we prefer to signal conversion failures, we don't offer extensions to create
// a URLRequest from a WebURL on those platforms. Fixed by https://github.com/apple/swift-corelibs-foundation/pull/3154
#if canImport(Darwin)

  fileprivate class Box<T> {
    internal var value: T

    internal init(_ value: T) {
      self.value = value
    }
  }

  fileprivate func XCTAssertEquivalentNSErrors(_ left: Error?, _ right: Error?) {
    // The errors must have the same domain and code, but the 'userInfo' may differ.
    if let left = (left as NSError?), let right = (right as NSError?) {
      XCTAssertEqual(left.domain, right.domain)
      XCTAssertEqual(left.code, right.code)
    } else {
      XCTAssertNil(left)
      XCTAssertNil(right)
    }
  }

  extension URLSessionTests {

    fileprivate enum ExpectedURLConversion {
      case encodingAdded
      case noEncodingAdded
      case failure
    }

    /// Makes a request via a `URLSessionDataTask`, checks the URLs exposed via the task's original/current
    /// `URLRequest`s, and invokes the given closure to check the resulting `URLResponse`/data/error.
    ///
    fileprivate func makeDataTaskRequest(
      to urlString: String,
      expectedURLConversion: ExpectedURLConversion = .noEncodingAdded,
      function: StaticString = #function, line: Int = #line,
      checkResponse: @escaping (Data?, URLResponse?, Error?) -> Void
    ) {
      let webURL = WebURL(urlString)!
      XCTAssertEqual(webURL.serialized(), urlString, "Given string must be a normalized WebURL")

      let ex = expectation(description: "\(function):\(line)")
      let task: Box<URLSessionDataTask?> = .init(nil)
      task.value = URLSession.shared.dataTask(with: webURL) { data, response, error in
        defer {
          task.value = nil
          ex.fulfill()
        }
        // Verify the URLSessionDataTask.
        // There should not be any redirects, so `originalRequest.url` should be the same as `currentRequest.url`.
        switch expectedURLConversion {
        case .encodingAdded:
          XCTAssertNotEqual(task.value?.originalRequest?.url?.absoluteString, webURL.serialized())
          XCTAssertNotEqual(task.value?.currentRequest?.url?.absoluteString, webURL.serialized())
          XCTAssertNotEqual(task.value?.originalRequest?.webURL, webURL)
          XCTAssertNotEqual(task.value?.currentRequest?.webURL, webURL)
          let encodedWebURL = webURL.encodedForFoundation
          XCTAssertEqual(task.value?.originalRequest?.url?.absoluteString, encodedWebURL.serialized())
          XCTAssertEqual(task.value?.currentRequest?.url?.absoluteString, encodedWebURL.serialized())
          XCTAssertEqual(task.value?.originalRequest?.webURL, encodedWebURL)
          XCTAssertEqual(task.value?.currentRequest?.webURL, encodedWebURL)
        case .noEncodingAdded:
          XCTAssertEqual(task.value?.originalRequest?.url?.absoluteString, webURL.serialized())
          XCTAssertEqual(task.value?.currentRequest?.url?.absoluteString, webURL.serialized())
          XCTAssertEqual(task.value?.originalRequest?.webURL, webURL)
          XCTAssertEqual(task.value?.currentRequest?.webURL, webURL)
        case .failure:
          XCTAssertNil(task.value?.originalRequest?.url)
          XCTAssertNil(task.value?.currentRequest?.url)
          XCTAssertNil(task.value?.originalRequest?.webURL)
          XCTAssertNil(task.value?.currentRequest?.webURL)
        }
        // The wrapper API should not return an error which differs from the task error.
        XCTAssertEquivalentNSErrors(task.value?.error, error)
        // The closure verifies the URLResponse, data, and error.
        checkResponse(data, response, error)
      }
      task.value!.resume()
    }

    fileprivate enum ExpectedURLOfRedirect {
      case exactly(String)
      case normalized(foundation: String, webURL: String)
    }

    fileprivate func makeDataTaskRequest(
      to urlString: String,
      expectedURLConversion: ExpectedURLConversion = .noEncodingAdded,
      expectedURLOfRedirect: ExpectedURLOfRedirect,
      function: StaticString = #function, line: Int = #line,
      checkResponse: @escaping (Data?, URLResponse?, Error?) -> Void
    ) {
      let webURL = WebURL(urlString)!
      XCTAssertEqual(webURL.serialized(), urlString, "Given string must be a normalized WebURL")

      let ex = expectation(description: "\(function):\(line)")
      let task: Box<URLSessionDataTask?> = .init(nil)
      task.value = URLSession.shared.dataTask(with: webURL) { data, response, error in
        defer {
          task.value = nil
          ex.fulfill()
        }
        // Verify the URLSessionDataTask.
        // `originalRequest` is the result of a WebURL -> Foundation conversion,
        // so it is already normalized (although percent-encoding may have been added).
        switch expectedURLConversion {
        case .encodingAdded:
          XCTAssertNotEqual(task.value?.originalRequest?.url?.absoluteString, webURL.serialized())
          XCTAssertNotEqual(task.value?.originalRequest?.webURL, webURL)
          let encodedURL = webURL.encodedForFoundation
          XCTAssertEqual(task.value?.originalRequest?.url?.absoluteString, encodedURL.serialized())
          XCTAssertEqual(task.value?.originalRequest?.webURL, encodedURL)
        case .noEncodingAdded:
          XCTAssertEqual(task.value?.originalRequest?.url?.absoluteString, webURL.serialized())
          XCTAssertEqual(task.value?.originalRequest?.webURL, webURL)
        case .failure:
          XCTAssertNil(task.value?.originalRequest?.url)
          XCTAssertNil(task.value?.originalRequest?.webURL)
        }
        // `currentRequest` may be the result of a Foundation -> WebURL conversion,
        // so it may go through more extensive normalization (e.g. simplifying the path).
        switch expectedURLOfRedirect {
        case .exactly(let string):
          XCTAssertEqual(task.value?.currentRequest?.url?.absoluteString, string)
          XCTAssertEqual(task.value?.currentRequest?.webURL?.serialized(), string)
        case .normalized(let foundation, let webURL):
          XCTAssertEqual(task.value?.currentRequest?.url?.absoluteString, foundation)
          XCTAssertEqual(task.value?.currentRequest?.webURL?.serialized(), webURL)
        }
        // The wrapper API should not return an error which differs from the task error.
        XCTAssertEquivalentNSErrors(task.value?.error, error)
        // The closure verifies the URLResponse, data, and error.
        checkResponse(data, response, error)
      }
      task.value!.resume()
    }
  }

  extension URLSessionTests {

    func testDataTask_http() throws {

      let localServer = HttpServer()
      try localServer.start(0)
      defer { localServer.stop() }
      let port = try localServer.port()
      print("ℹ️ Server started on port: \(port)")

      var rng = SystemRandomNumberGenerator()

      // Root path.
      let referenceData_root = Data((0...1024).lazy.map { _ in rng.next() })
      localServer["/"] = { _ in .ok(.data(referenceData_root)) }
      makeDataTaskRequest(to: "http://localhost:\(port)/") {
        data, response, error in
        XCTAssertEqual(data, referenceData_root)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/")
      }

      // Non-root path.
      let referenceData_nonRoot = Data((0...1024).lazy.map { _ in rng.next() })
      localServer["/foo/bar"] = { _ in .ok(.data(referenceData_nonRoot)) }
      makeDataTaskRequest(to: "http://localhost:\(port)/foo/bar") {
        data, response, error in
        XCTAssertEqual(data, referenceData_nonRoot)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/foo/bar")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/foo/bar")
      }

      // Path requires percent-encoding.
      // The encoding is added when the URLSessionTask is created.
      localServer["/encode/[baz]/"] = { _ in .ok(.text("You made it!")) }
      makeDataTaskRequest(to: "http://localhost:\(port)/encode/[baz]", expectedURLConversion: .encodingAdded) {
        data, response, error in
        XCTAssertEqual(data, Data("You made it!".utf8))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/encode/%5Bbaz%5D")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/encode/%5Bbaz%5D")
      }

      // Query requires percent-encoding.
      // The encoding is added when the URLSessionTask is created.
      localServer["/encode/q"] = { req in .ok(.text("You made it again! - \(req.queryParams.first?.1 ?? "")")) }
      makeDataTaskRequest(to: "http://localhost:\(port)/encode/q?product={xx}", expectedURLConversion: .encodingAdded) {
        data, response, error in
        XCTAssertEqual(data, Data("You made it again! - %7Bxx%7D".utf8))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/encode/q?product=%7Bxx%7D")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/encode/q?product=%7Bxx%7D")
      }

      // URLs which cannot be converted.
      // For HTTP, this means domains with disallowed characters.
      makeDataTaskRequest(to: "http://local{host}:\(port)/", expectedURLConversion: .failure) {
        data, response, error in
        XCTAssertNil(data)
        XCTAssertNil(response)
        XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
      }

      // Wait for all requests.
      waitForExpectations(timeout: 5)
    }

    func testDataTask_customProtocol() throws {

      #if os(watchOS)
        throw XCTSkip("Custom URL protocol handling is not available on watchOS")
      #endif

      class FooSchemeHandler: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
          request.webURL?.scheme == "foo"
        }
        override class func canInit(with task: URLSessionTask) -> Bool {
          task.currentRequest?.webURL?.scheme == "foo"
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
          // Note: this is never called in swift-corelibs-foundation.
          // https://bugs.swift.org/browse/SR-15987
          request
        }
        override func startLoading() {
          let response = URLResponse(url: request.url!, mimeType: "", expectedContentLength: 0, textEncodingName: nil)
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          if let payload = request.webURL?.path {
            let reversedPayload = String(payload.reversed())
            client?.urlProtocol(self, didLoad: Data(reversedPayload.utf8))
          }
          client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {
        }
      }

      XCTAssertTrue(URLProtocol.registerClass(FooSchemeHandler.self))
      defer { URLProtocol.unregisterClass(FooSchemeHandler.self) }

      // Opaque path.
      makeDataTaskRequest(to: "foo:barbazqux") { data, response, error in
        XCTAssertEqual(data, Data("xuqzabrab".utf8))
        XCTAssertNotNil(response)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "foo:barbazqux")
        XCTAssertEqual(response?.url?.absoluteString, "foo:barbazqux")
      }

      // List-style path.
      makeDataTaskRequest(to: "foo:/bar/baz/qux") { data, response, error in
        XCTAssertEqual(data, Data("xuq/zab/rab/".utf8))
        XCTAssertNotNil(response)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "foo:/bar/baz/qux")
        XCTAssertEqual(response?.url?.absoluteString, "foo:/bar/baz/qux")
      }

      // URLs which cannot be converted.
      // Disallowed characters in opaque paths won't be encoded.
      makeDataTaskRequest(to: "foo:path has a space", expectedURLConversion: .failure) {
        data, response, error in
        XCTAssertNil(data)
        XCTAssertNil(response)
        XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
      }
      makeDataTaskRequest(to: "foo:path[br{ack}ets]!", expectedURLConversion: .failure) {
        data, response, error in
        XCTAssertNil(data)
        XCTAssertNil(response)
        XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
      }

      // Wait for all requests.
      waitForExpectations(timeout: 5)
    }

    func testDataTask_redirects() throws {

      let localServer = HttpServer()
      try localServer.start(0)
      defer { localServer.stop() }
      let port = try localServer.port()
      print("ℹ️ Server started on port: \(port)")

      localServer["/foo/bar"] = { _ in .ok(.text("Hello, world!")) }

      // Standard redirect to absolute URL. No encoding needed.
      localServer["/redirect/normal-abs"] = { _ in .movedPermanently("http://localhost:\(port)/foo/bar") }
      makeDataTaskRequest(
        to: "http://localhost:\(port)/redirect/normal-abs",
        expectedURLOfRedirect: .exactly("http://localhost:\(port)/foo/bar")
      ) { data, response, error in
        XCTAssertTrue(data?.elementsEqual("Hello, world!".utf8) == true)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/foo/bar")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/foo/bar")
      }

      // Standard redirect to absolute path. No encoding needed.
      localServer["/redirect/normal-path"] = { _ in .movedPermanently("/foo/bar") }
      makeDataTaskRequest(
        to: "http://localhost:\(port)/redirect/normal-path",
        expectedURLOfRedirect: .exactly("http://localhost:\(port)/foo/bar")
      ) { data, response, error in
        XCTAssertTrue(data?.elementsEqual("Hello, world!".utf8) == true)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/foo/bar")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/foo/bar")
      }

      // Redirect to a protocol-relative URL. No encoding needed.
      localServer["/redirect/protorel"] = { _ in .movedPermanently("//foo/bar") }
      makeDataTaskRequest(
        to: "http://localhost:\(port)/redirect/protorel",
        expectedURLOfRedirect: .exactly("https://foo/bar")
      ) { data, response, error in
        XCTAssertNil(data)
        XCTAssertNil(response)
        XCTAssertEqual((error as? URLError)?.code, .cannotFindHost)
      }

      // Redirect to the same absolute URL in a loop. Fails due to redirect limit.
      localServer["/redirect/self"] = { _ in .movedPermanently("http://localhost:\(port)/redirect/self") }
      makeDataTaskRequest(
        to: "http://localhost:\(port)/redirect/self",
        expectedURLOfRedirect: .exactly("http://localhost:\(port)/redirect/self")
      ) { data, response, error in
        XCTAssertNil(data)
        XCTAssertNil(response)
        XCTAssertEqual((error as? URLError)?.code, .httpTooManyRedirects)
      }

      // Redirect to a dot, such that it resolves to the same URL in a loop. Fails due to redirect limit.
      localServer["/redirect/dot/"] = { _ in .movedPermanently(".") }
      makeDataTaskRequest(
        to: "http://localhost:\(port)/redirect/dot/",
        expectedURLOfRedirect: .exactly("http://localhost:\(port)/redirect/dot/")
      ) { data, response, error in
        XCTAssertNil(data)
        XCTAssertNil(response)
        XCTAssertEqual((error as? URLError)?.code, .httpTooManyRedirects)
      }

      // Redirect to a space. Ends up not redirecting, but also not failing.
      localServer["/redirect/space"] = { _ in .movedPermanently(" ") }
      makeDataTaskRequest(
        to: "http://localhost:\(port)/redirect/space",
        expectedURLOfRedirect: .exactly("http://localhost:\(port)/redirect/space")
      ) { data, response, error in
        XCTAssertEqual(data, Data())
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 301)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/redirect/space")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/redirect/space")
      }

      // Redirect to absolute path including tabs.
      // 404 due to not filtering internal tabs, as WebURL would do. Works in Chrome.
      // Foundation percent-encodes internal tabs, so they are preserved in the converted URL.
      localServer["/redirect/tab"] = { _ in .movedPermanently("\t/fo\to/bar\t") }
      makeDataTaskRequest(
        to: "http://localhost:\(port)/redirect/tab",
        expectedURLOfRedirect: .exactly("http://localhost:\(port)/fo%09o/bar")
      ) { data, response, error in
        XCTAssertEqual(data, Data())
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/fo%09o/bar")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/fo%09o/bar")
      }

      // Redirect to absolute path including a dot.
      // 404 due to not simplifying path, as WebURL would do. Works in Safari and Chrome.
      // The dot cannot be preserved in the converted URL, so it may not be clear as to why this request failed.
      localServer["/redirect/includes-dot"] = { _ in .movedPermanently("/foo/./bar") }
      makeDataTaskRequest(
        to: "http://localhost:\(port)/redirect/includes-dot",
        expectedURLOfRedirect: .normalized(
          foundation: "http://localhost:\(port)/foo/./bar",
          webURL: "http://localhost:\(port)/foo/bar"
        )
      ) { data, response, error in
        XCTAssertEqual(data, Data())
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/foo/bar")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/foo/./bar")
      }

      // Redirect to absolute path including a dot-dot.
      // 404 due to not simplifying path, as WebURL would do. Works in Safari and Chrome.
      // The dot-dot cannot be preserved in the converted URL, so it may not be clear as to why this request failed.
      localServer["/redirect/includes-dotdot"] = { _ in .movedPermanently("/foo/tmp/../bar") }
      makeDataTaskRequest(
        to: "http://localhost:\(port)/redirect/includes-dotdot",
        expectedURLOfRedirect: .normalized(
          foundation: "http://localhost:\(port)/foo/tmp/../bar",
          webURL: "http://localhost:\(port)/foo/bar"
        )
      ) { data, response, error in
        XCTAssertEqual(data, Data())
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/foo/bar")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/foo/tmp/../bar")
      }

      // Redirect to absolute path containing backslash.
      // 404 since back-slashes are not normalized to forward-slashes, as WebURL would do. Works in Chrome.
      // Foundation percent-encodes backslashes, so they are preserved in the converted URL.
      localServer["/redirect/backslash"] = { _ in .movedPermanently("\\foo\\bar") }
      makeDataTaskRequest(
        to: "http://localhost:\(port)/redirect/backslash",
        expectedURLOfRedirect: .exactly("http://localhost:\(port)/redirect/%5Cfoo%5Cbar")
      ) { data, response, error in
        XCTAssertEqual(data, Data())
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/redirect/%5Cfoo%5Cbar")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/redirect/%5Cfoo%5Cbar")
      }

      // Redirect to absolute path containing forbidden characters (square brackets).
      // Foundation percent-encodes these, so they are preserved in the converted URL.
      localServer["/foo/[bar]"] = { _ in .ok(.text("You found me!")) }
      localServer["/redirect/encode"] = { _ in .movedPermanently("/foo/[bar]") }
      makeDataTaskRequest(
        to: "http://localhost:\(port)/redirect/encode",
        expectedURLOfRedirect: .exactly("http://localhost:\(port)/foo/%5Bbar%5D")
      ) {
        data, response, error in
        XCTAssertEqual(data, Data("You found me!".utf8))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/foo/%5Bbar%5D")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/foo/%5Bbar%5D")
      }

      // Redirect to absolute path containing forbidden characters (curly braces).
      // Foundation percent-encodes these, so they are preserved in the converted URL.
      localServer["/foo/{bar}"] = { _ in .ok(.text("You found me, too!")) }
      localServer["/redirect/encode2"] = { _ in .movedPermanently("/foo/{bar}") }
      makeDataTaskRequest(
        to: "http://localhost:\(port)/redirect/encode2",
        expectedURLOfRedirect: .exactly("http://localhost:\(port)/foo/%7Bbar%7D")
      ) {
        data, response, error in
        XCTAssertEqual(data, Data("You found me, too!".utf8))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/foo/%7Bbar%7D")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/foo/%7Bbar%7D")
      }

      // Redirect to absolute URL with too many slashes between scheme/host.
      // 404 due to not treating as equivalent to a double-slash, as WebURL would. Works in Chrome.
      // Foundation does something really weird here.
      localServer["/redirect/toomanyslashes"] = { _ in .movedPermanently("http:///localhost:\(port)/foo/bar") }
      makeDataTaskRequest(
        to: "http://localhost:\(port)/redirect/toomanyslashes",
        expectedURLOfRedirect: .exactly("http://localhost/localhost:\(port)/foo/bar")
      ) { data, response, error in
        XCTAssertNil(data)
        XCTAssertNil(response)
        XCTAssertEqual((error as? URLError)?.code, .cannotConnectToHost)
      }

      // Wait for all requests.
      waitForExpectations(timeout: 5)
    }

    func testDataTask_sessionDelegate() throws {

      let localServer = HttpServer()
      try localServer.start(0)
      defer { localServer.stop() }
      let port = try localServer.port()
      print("ℹ️ Server started on port: \(port)")

      class Delegate: NSObject, URLSessionTaskDelegate {
        var onComplete: Optional<(URLSessionTask, Error?) -> Void> = nil
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
          onComplete?(task, error)
        }
      }

      let delegate = Delegate()
      defer { delegate.onComplete = nil }
      let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

      do {
        localServer["/foo/bar"] = { _ in .ok(.text("hello!")) }

        let ex = expectation(description: "Successful Request (Simple)")
        let url = WebURL("http://localhost:\(port)/foo/bar")!
        let _task = session.dataTask(with: url)

        XCTAssertEqual(url.serialized(), "http://localhost:\(port)/foo/bar")
        delegate.onComplete = { task, error in
          XCTAssertEqual(task.taskIdentifier, _task.taskIdentifier)
          XCTAssertEqual(task.originalRequest?.url?.absoluteString, "http://localhost:\(port)/foo/bar")
          XCTAssertEqual(task.currentRequest?.url?.absoluteString, "http://localhost:\(port)/foo/bar")
          XCTAssertEqual(task.response?.url?.absoluteString, "http://localhost:\(port)/foo/bar")
          XCTAssertEqual(task.originalRequest?.webURL, url)
          XCTAssertEqual(task.currentRequest?.webURL, url)
          XCTAssertEqual(task.response?.webURL, url)
          XCTAssertNil(error)
          XCTAssertEquivalentNSErrors(task.error, error)
          ex.fulfill()
        }
        _task.resume()
        waitForExpectations(timeout: 2)
      }

      do {
        localServer["/foo/[baz]"] = { _ in .ok(.text("world!")) }

        let ex = expectation(description: "Successful Request (Adding Percent-Encoding)")
        let url = WebURL("http://localhost:\(port)/foo/[baz]")!
        let _task = session.dataTask(with: url)

        XCTAssertEqual(url.serialized(), "http://localhost:\(port)/foo/[baz]")
        delegate.onComplete = { task, error in
          XCTAssertEqual(task.taskIdentifier, _task.taskIdentifier)
          XCTAssertEqual(task.originalRequest?.url?.absoluteString, "http://localhost:\(port)/foo/%5Bbaz%5D")
          XCTAssertEqual(task.currentRequest?.url?.absoluteString, "http://localhost:\(port)/foo/%5Bbaz%5D")
          XCTAssertEqual(task.response?.url?.absoluteString, "http://localhost:\(port)/foo/%5Bbaz%5D")
          XCTAssertEqual(task.originalRequest?.webURL, url.encodedForFoundation)
          XCTAssertEqual(task.currentRequest?.webURL, url.encodedForFoundation)
          XCTAssertEqual(task.response?.webURL, url.encodedForFoundation)
          XCTAssertNil(error)
          XCTAssertEquivalentNSErrors(task.error, error)
          ex.fulfill()
        }
        _task.resume()
        waitForExpectations(timeout: 2)
      }

      do {
        let ex = expectation(description: "Conversion Failure")
        let url = WebURL("http://loc{alh}ost:\(port)/foo/bar")!
        let _task = session.dataTask(with: url)

        XCTAssertEqual(url.serialized(), "http://loc{alh}ost:\(port)/foo/bar")
        delegate.onComplete = { task, error in
          XCTAssertEqual(task.taskIdentifier, _task.taskIdentifier)
          XCTAssertEqual(task.originalRequest?.webURL, nil)
          XCTAssertEqual(task.currentRequest?.webURL, nil)
          XCTAssertEqual(task.response?.webURL, nil)
          XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
          XCTAssertEquivalentNSErrors(task.error, error)
          ex.fulfill()
        }
        _task.resume()
        waitForExpectations(timeout: 2)
      }
    }

    func testDataTask_customNilURLHandler() throws {

      // This tests a special edge-case where the URL cannot be converted, but a custom URLProtocol handler
      // processes it anyway. This is a rather contrived example: for instance, the URLProtocol handler
      // must create a URL out of thin air for the URLResponse object.

      #if os(watchOS)
        throw XCTSkip("Custom URL protocol handling is not available on watchOS")
      #endif

      class NilURLHandler: URLProtocol {
        static var DataToLoad: Data? = nil

        override class func canInit(with request: URLRequest) -> Bool {
          request.url == nil
        }
        override class func canInit(with task: URLSessionTask) -> Bool {
          task.currentRequest?.url == nil
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
          // Note: this is never called in swift-corelibs-foundation.
          // https://bugs.swift.org/browse/SR-15987
          request
        }
        override func startLoading() {
          let url = URL(string: "made-up")!
          let response = URLResponse(url: url, mimeType: "", expectedContentLength: 0, textEncodingName: nil)
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          if let data = Self.DataToLoad {
            client?.urlProtocol(self, didLoad: data)
          }
          client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {
        }
      }

      XCTAssertTrue(URLProtocol.registerClass(NilURLHandler.self))
      defer { URLProtocol.unregisterClass(NilURLHandler.self) }

      do {
        let ex = expectation(description: "No data loaded")
        let url = WebURL("http://loc{alh}ost/files/test")!
        XCTAssertEqual(url.serialized(), "http://loc{alh}ost/files/test")

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
          XCTAssertNotNil(data)
          XCTAssertNotNil(response)
          XCTAssertNil(error)

          XCTAssertEqual(data, Data())
          XCTAssertEqual(data?.count, 0)
          XCTAssertEqual(response?.url?.absoluteString, "made-up")
          ex.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 2)
        XCTAssertNil(task.error)
      }

      do {
        let ex = expectation(description: "Zero bytes loaded")
        let url = WebURL("http://loc{alh}ost/files/test")!
        XCTAssertEqual(url.serialized(), "http://loc{alh}ost/files/test")

        NilURLHandler.DataToLoad = Data()

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
          XCTAssertNotNil(data)
          XCTAssertNotNil(response)
          XCTAssertNil(error)

          XCTAssertEqual(data, Data())
          XCTAssertEqual(data?.count, 0)
          XCTAssertEqual(response?.url?.absoluteString, "made-up")
          ex.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 2)
        XCTAssertNil(task.error)
      }

      do {
        let ex = expectation(description: "Some bytes loaded")
        let url = WebURL("http://loc{alh}ost/files/test")!
        XCTAssertEqual(url.serialized(), "http://loc{alh}ost/files/test")

        var rng = SystemRandomNumberGenerator()
        let bytes = (0..<10).map { _ in rng.next() as UInt8 }
        NilURLHandler.DataToLoad = Data(bytes)

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
          XCTAssertNotNil(data)
          XCTAssertNotNil(response)
          XCTAssertNil(error)

          XCTAssertEqual(data?.elementsEqual(bytes), true)
          XCTAssertEqual(response?.url?.absoluteString, "made-up")
          ex.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 2)
        XCTAssertNil(task.error)
      }
    }
  }

  #if canImport(Combine)

    import Combine

    extension URLSessionTests {

      func testDataTask_combine() throws {

        guard #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *) else {
          throw XCTSkip("Combine requires macOS 10.15/iOS 13.0/watchOS 6.0 or newer")
        }

        let localServer = HttpServer()
        try localServer.start(0)
        defer { localServer.stop() }
        let port = try localServer.port()
        print("ℹ️ Server started on port: \(port)")

        var rng = SystemRandomNumberGenerator()

        var tokens = [AnyCancellable]()
        do {
          let referenceData = Data((0..<1024).lazy.map { _ in rng.next() })
          localServer["/"] = { _ in .ok(.data(referenceData)) }

          let ex = expectation(description: "Root")
          let publisher = URLSession.shared.dataTaskPublisher(for: WebURL("http://localhost:\(port)/")!)
          XCTAssertEqual(publisher.request.webURL?.serialized(), "http://localhost:\(port)/")
          XCTAssertEqual(publisher.request.url?.absoluteString, "http://localhost:\(port)/")

          publisher.sink { completion in
            switch completion {
            case .failure(let error):
              XCTFail("Unexpected error: \(error)")
            case .finished:
              break
            }
            ex.fulfill()
          } receiveValue: { (data, response) in
            XCTAssertEqual(data, referenceData)
            XCTAssertEqual(response.webURL?.serialized(), "http://localhost:\(port)/")
            XCTAssertEqual(response.url?.absoluteString, "http://localhost:\(port)/")
          }.store(in: &tokens)
        }

        do {
          let referenceData = Data((0..<1024).lazy.map { _ in rng.next() })
          localServer["/foo/bar"] = { _ in .ok(.data(referenceData)) }

          let ex = expectation(description: "/Foo/Bar")
          let publisher = URLSession.shared.dataTaskPublisher(for: WebURL("http://localhost:\(port)/foo/bar")!)
          XCTAssertEqual(publisher.request.webURL?.serialized(), "http://localhost:\(port)/foo/bar")
          XCTAssertEqual(publisher.request.url?.absoluteString, "http://localhost:\(port)/foo/bar")

          publisher.sink { completion in
            switch completion {
            case .failure(let error):
              XCTFail("Unexpected error: \(error)")
            case .finished:
              break
            }
            ex.fulfill()
          } receiveValue: { (data, response) in
            XCTAssertEqual(data, referenceData)
            XCTAssertEqual(response.webURL?.serialized(), "http://localhost:\(port)/foo/bar")
            XCTAssertEqual(response.url?.absoluteString, "http://localhost:\(port)/foo/bar")
          }.store(in: &tokens)
        }

        do {
          let ex = expectation(description: "Conversion failure")
          let publisher = URLSession.shared.dataTaskPublisher(for: WebURL("http://loc{alh}ost:\(port)/foo/bar")!)
          XCTAssertEqual(publisher.request.webURL, nil)
          XCTAssertEqual(publisher.request.url, nil)

          publisher.sink { completion in
            switch completion {
            case .failure(let error):
              XCTAssertEqual(error.code, .unsupportedURL)
            default:
              XCTFail("Unexpected non-error result: \(completion)")
            }
            ex.fulfill()
          } receiveValue: { (data, response) in
            XCTFail("Unexpected response: \(data) \(response)")
          }.store(in: &tokens)
        }

        waitForExpectations(timeout: 5)
        withExtendedLifetime(tokens) {}
      }
    }

  #endif  // canImport(Combine)

  #if swift(>=5.5) && canImport(_Concurrency) && canImport(Darwin)

    extension URLSessionTests {
      // TODO: URLSessionDataTask Async Tests (macOS 12+)
    }

  #endif  // swift(>=5.5) && canImport(_Concurrency) && canImport(Darwin)


  // --------------------------------
  // MARK: - URLSessionDownloadTask
  // --------------------------------


  extension URLSessionTests {

    func testDownloadTask() throws {

      let localServer = HttpServer()
      try localServer.start(0)
      defer { localServer.stop() }
      let port = try localServer.port()
      print("ℹ️ Server started on port: \(port)")

      do {
        localServer["/files/test"] = { _ in .ok(.data(Data("hello, world!".utf8))) }

        let ex = expectation(description: "Successful Request (Simple)")
        let url = WebURL("http://localhost:\(port)/files/test")!

        XCTAssertEqual(url.serialized(), "http://localhost:\(port)/files/test")
        let task = URLSession.shared.downloadTask(with: url) { fileURL, response, error in
          XCTAssertNotNil(fileURL)
          XCTAssertNotNil(response)
          XCTAssertNil(error)

          XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/files/test")
          XCTAssertEqual(response?.webURL, url)

          if let fileURL = fileURL.flatMap({ URL($0) }) {
            XCTAssertEqual(try? Data(contentsOf: fileURL).elementsEqual("hello, world!".utf8), true)
          }
          ex.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 2)
        XCTAssertNil(task.error)
      }

      do {
        localServer["/files/[abc]"] = { _ in .ok(.data(Data("def".utf8))) }

        let ex = expectation(description: "Successful Request (Adding Percent-Encoding)")
        let url = WebURL("http://localhost:\(port)/files/[abc]")!

        XCTAssertEqual(url.serialized(), "http://localhost:\(port)/files/[abc]")
        let task = URLSession.shared.downloadTask(with: url) { fileURL, response, error in
          XCTAssertNotNil(fileURL)
          XCTAssertNotNil(response)
          XCTAssertNil(error)

          XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/files/%5Babc%5D")
          XCTAssertEqual(response?.webURL, url.encodedForFoundation)

          if let fileURL = fileURL.flatMap({ URL($0) }) {
            XCTAssertEqual(try? Data(contentsOf: fileURL).elementsEqual("def".utf8), true)
          }
          ex.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 2)
        XCTAssertNil(task.error)
      }

      do {
        let ex = expectation(description: "Conversion Failure")
        let url = WebURL("http://loc{alh}ost:\(port)/files/test")!

        XCTAssertEqual(url.serialized(), "http://loc{alh}ost:\(port)/files/test")
        let task = URLSession.shared.downloadTask(with: url) { fileURL, response, error in
          XCTAssertNil(fileURL)
          XCTAssertNil(response)
          XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
          ex.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 2)
        XCTAssertEqual((task.error as? URLError)?.code, .unsupportedURL)
      }
    }

    func testDownloadTask_sessionDelegate() throws {

      let localServer = HttpServer()
      try localServer.start(0)
      defer { localServer.stop() }
      let port = try localServer.port()
      print("ℹ️ Server started on port: \(port)")

      // Note: We don't really care about URLSessionDownloadDelegate because it uses Foundation.URL anyway.
      class Delegate: NSObject, URLSessionTaskDelegate {
        var onComplete: Optional<(URLSessionTask, Error?) -> Void> = nil
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
          onComplete?(task, error)
        }
      }

      let delegate = Delegate()
      defer { delegate.onComplete = nil }
      let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

      do {
        localServer["/files/test"] = { _ in .ok(.data(Data("hello, world!".utf8))) }

        let ex = expectation(description: "Successful Request (Simple)")
        let url = WebURL("http://localhost:\(port)/files/test")!
        let _task = session.downloadTask(with: url)

        XCTAssertEqual(url.serialized(), "http://localhost:\(port)/files/test")
        delegate.onComplete = { task, error in
          XCTAssertEqual(task.taskIdentifier, _task.taskIdentifier)
          XCTAssertEqual(task.originalRequest?.url?.absoluteString, "http://localhost:\(port)/files/test")
          XCTAssertEqual(task.currentRequest?.url?.absoluteString, "http://localhost:\(port)/files/test")
          XCTAssertEqual(task.response?.url?.absoluteString, "http://localhost:\(port)/files/test")
          XCTAssertEqual(task.originalRequest?.webURL, url)
          XCTAssertEqual(task.currentRequest?.webURL, url)
          XCTAssertEqual(task.response?.webURL, url)
          XCTAssertNil(error)
          XCTAssertEquivalentNSErrors(task.error, error)
          ex.fulfill()
        }
        _task.resume()
        waitForExpectations(timeout: 2)
      }

      do {
        localServer["/files/[abc]"] = { _ in .ok(.data(Data("def".utf8))) }

        let ex = expectation(description: "Successful Request (Adding Percent-Encoding)")
        let url = WebURL("http://localhost:\(port)/files/[abc]")!
        let _task = session.downloadTask(with: url)

        XCTAssertEqual(url.serialized(), "http://localhost:\(port)/files/[abc]")
        delegate.onComplete = { task, error in
          XCTAssertEqual(task.taskIdentifier, _task.taskIdentifier)
          XCTAssertEqual(task.originalRequest?.url?.absoluteString, "http://localhost:\(port)/files/%5Babc%5D")
          XCTAssertEqual(task.currentRequest?.url?.absoluteString, "http://localhost:\(port)/files/%5Babc%5D")
          XCTAssertEqual(task.response?.url?.absoluteString, "http://localhost:\(port)/files/%5Babc%5D")
          XCTAssertEqual(task.originalRequest?.webURL, url.encodedForFoundation)
          XCTAssertEqual(task.currentRequest?.webURL, url.encodedForFoundation)
          XCTAssertEqual(task.response?.webURL, url.encodedForFoundation)
          XCTAssertNil(error)
          XCTAssertEquivalentNSErrors(task.error, error)
          ex.fulfill()
        }
        _task.resume()
        waitForExpectations(timeout: 2)
      }

      do {
        let ex = expectation(description: "Conversion Failure")
        let url = WebURL("http://loc{alh}ost:\(port)/files/test")!
        let _task = session.downloadTask(with: url)

        XCTAssertEqual(url.serialized(), "http://loc{alh}ost:\(port)/files/test")
        delegate.onComplete = { task, error in
          XCTAssertEqual(task.taskIdentifier, _task.taskIdentifier)
          XCTAssertEqual(task.originalRequest?.webURL, nil)
          XCTAssertEqual(task.currentRequest?.webURL, nil)
          XCTAssertEqual(task.response?.webURL, nil)
          XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
          XCTAssertEquivalentNSErrors(task.error, error)
          ex.fulfill()
        }
        _task.resume()
        waitForExpectations(timeout: 2)
      }
    }

    func testDownloadTask_customNilURLHandler() throws {

      // This tests a special edge-case where the URL cannot be converted, but a custom URLProtocol handler
      // processes it anyway. This is a rather contrived example: for instance, the URLProtocol handler
      // must create a URL out of thin air for the URLResponse object.

      #if os(watchOS)
        throw XCTSkip("Custom URL protocol handling is not available on watchOS")
      #endif

      class NilURLHandler: URLProtocol {
        static var DataToLoad: Data? = nil

        override class func canInit(with request: URLRequest) -> Bool {
          request.url == nil
        }
        override class func canInit(with task: URLSessionTask) -> Bool {
          task.currentRequest?.url == nil
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
          // Note: this is never called in swift-corelibs-foundation.
          // https://bugs.swift.org/browse/SR-15987
          request
        }
        override func startLoading() {
          let url = URL(string: "made-up")!
          let response = URLResponse(url: url, mimeType: "", expectedContentLength: 0, textEncodingName: nil)
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          if let data = Self.DataToLoad {
            client?.urlProtocol(self, didLoad: data)
          }
          client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {
        }
      }

      XCTAssertTrue(URLProtocol.registerClass(NilURLHandler.self))
      defer { URLProtocol.unregisterClass(NilURLHandler.self) }

      do {
        let ex = expectation(description: "No data loaded")
        let url = WebURL("http://loc{alh}ost/files/test")!
        XCTAssertEqual(url.serialized(), "http://loc{alh}ost/files/test")

        let task = URLSession.shared.downloadTask(with: url) { fileURL, response, error in
          XCTAssertNotNil(fileURL)
          XCTAssertNotNil(response)
          XCTAssertNil(error)

          XCTAssertEqual(response?.url?.absoluteString, "made-up")
          if let fileURL = fileURL.flatMap({ URL($0) }) {
            let data = try? Data(contentsOf: fileURL)
            XCTAssertEqual(data, Data())
            XCTAssertEqual(data?.count, 0)
          }
          ex.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 2)
        XCTAssertNil(task.error)
      }

      do {
        let ex = expectation(description: "Zero bytes loaded")
        let url = WebURL("http://loc{alh}ost/files/test")!
        XCTAssertEqual(url.serialized(), "http://loc{alh}ost/files/test")

        NilURLHandler.DataToLoad = Data()

        let task = URLSession.shared.downloadTask(with: url) { fileURL, response, error in
          XCTAssertNotNil(fileURL)
          XCTAssertNotNil(response)
          XCTAssertNil(error)

          XCTAssertEqual(response?.url?.absoluteString, "made-up")
          if let fileURL = fileURL.flatMap({ URL($0) }) {
            let data = try? Data(contentsOf: fileURL)
            XCTAssertEqual(data, Data())
            XCTAssertEqual(data?.count, 0)
          }
          ex.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 2)
        XCTAssertNil(task.error)
      }

      do {
        let ex = expectation(description: "Some bytes loaded")
        let url = WebURL("http://loc{alh}ost/files/test")!
        XCTAssertEqual(url.serialized(), "http://loc{alh}ost/files/test")

        var rng = SystemRandomNumberGenerator()
        let bytes = (0..<10).map { _ in rng.next() as UInt8 }
        NilURLHandler.DataToLoad = Data(bytes)

        let task = URLSession.shared.downloadTask(with: url) { fileURL, response, error in
          XCTAssertNotNil(fileURL)
          XCTAssertNotNil(response)
          XCTAssertNil(error)

          XCTAssertEqual(response?.url?.absoluteString, "made-up")
          if let fileURL = fileURL.flatMap({ URL($0) }) {
            let data = try? Data(contentsOf: fileURL)
            XCTAssertEqual(data?.elementsEqual(bytes), true)
          }
          ex.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 2)
        XCTAssertNil(task.error)
      }
    }
  }


  // --------------------------------
  // MARK: - URLSessionWebSocketTask (Darwin-only)
  // --------------------------------


  #if canImport(Darwin)

    extension URLSessionTests {

      func testWebsocketTask() throws {

        guard #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *) else {
          throw XCTSkip("URLSessionWebSocketTask requires macOS 10.15/iOS 13.0/watchOS 6.0 or newer")
        }

        let localServer = HttpServer()
        try localServer.start(0)
        defer { localServer.stop() }
        let port = try localServer.port()
        print("ℹ️ Server started on port: \(port)")

        do {
          localServer["/foo/bar"] = websocket(
            text: { session, text in session.writeText(String(text.reversed())) },
            binary: { session, data in fatalError("Only sending text in this test") }
          )

          let ex = expectation(description: "Successful Connection (Simple)")
          let url = WebURL("ws://localhost:\(port)/foo/bar")!
          let task = URLSession.shared.webSocketTask(with: url)
          task.resume()

          XCTAssertEqual(url.serialized(), "ws://localhost:\(port)/foo/bar")
          task.send(.string("hello, world!")) { error in
            XCTAssertNil(error)
            // For some reason, Foundation makes all of these URLs http 🤷‍♂️
            XCTAssertEqual(task.originalRequest?.url?.absoluteString, "http://localhost:\(port)/foo/bar")
            XCTAssertEqual(task.currentRequest?.url?.absoluteString, "http://localhost:\(port)/foo/bar")
            XCTAssertEqual(task.response?.url?.absoluteString, "http://localhost:\(port)/foo/bar")
            var httpURL = url
            httpURL.scheme = "http"
            XCTAssertEqual(task.originalRequest?.webURL, httpURL)
            XCTAssertEqual(task.currentRequest?.webURL, httpURL)
            XCTAssertEqual(task.response?.webURL, httpURL)

            task.receive { result in
              guard case .success(.string(let msg)) = result else {
                XCTFail("Unexpected error - \(result)")
                ex.fulfill()
                return
              }
              XCTAssertEqual(msg, "!dlrow ,olleh")
              ex.fulfill()
            }
          }
          waitForExpectations(timeout: 2)
          XCTAssertNil(task.error)
        }

        do {
          localServer["/foo/[baz]"] = websocket(
            text: { session, text in session.writeText(String((text + text).reversed()).uppercased()) },
            binary: { session, data in fatalError("Only sending text in this test") }
          )

          let ex = expectation(description: "Successful Connection (Adding Percent-Encoding)")
          let url = WebURL("ws://localhost:\(port)/foo/[baz]")!
          let task = URLSession.shared.webSocketTask(with: url)
          task.resume()

          task.send(.string("hello, world!")) { error in
            XCTAssertNil(error)
            // For some reason, Foundation makes all of these URLs http 🤷‍♂️
            XCTAssertEqual(task.originalRequest?.url?.absoluteString, "http://localhost:\(port)/foo/%5Bbaz%5D")
            XCTAssertEqual(task.currentRequest?.url?.absoluteString, "http://localhost:\(port)/foo/%5Bbaz%5D")
            XCTAssertEqual(task.response?.url?.absoluteString, "http://localhost:\(port)/foo/%5Bbaz%5D")
            var httpURL = url
            httpURL.scheme = "http"
            XCTAssertEqual(task.originalRequest?.webURL, httpURL.encodedForFoundation)
            XCTAssertEqual(task.currentRequest?.webURL, httpURL.encodedForFoundation)
            XCTAssertEqual(task.response?.webURL, httpURL.encodedForFoundation)

            task.receive { result in
              guard case .success(.string(let msg)) = result else {
                XCTFail("Unexpected error - \(result)")
                ex.fulfill()
                return
              }
              XCTAssertEqual(msg, "!DLROW ,OLLEH!DLROW ,OLLEH")
              ex.fulfill()
            }
          }
          waitForExpectations(timeout: 2)
          XCTAssertNil(task.error)
        }

        do {
          let ex = expectation(description: "Conversion Failure")
          let url = WebURL("ws://loc{alh}ost:\(port)/foo/bar")!
          let task = URLSession.shared.webSocketTask(with: url)
          task.resume()

          task.send(.string("hello, world!")) { error in
            XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
            XCTAssertEquivalentNSErrors(task.error, error)
            XCTAssertNil(task.originalRequest?.url)
            XCTAssertNil(task.currentRequest?.url)
            XCTAssertNil(task.response?.url)
            XCTAssertNil(task.originalRequest?.webURL)
            XCTAssertNil(task.currentRequest?.webURL)
            XCTAssertNil(task.response?.webURL)
            ex.fulfill()
          }
          waitForExpectations(timeout: 2)
        }
      }
    }

  #endif  // canImport(Darwin)

#endif  // canImport(Darwin)
