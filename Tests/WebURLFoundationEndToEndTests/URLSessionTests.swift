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

final class URLSessionEndToEndTests: XCTestCase {}


// --------------------------------
// MARK: - Helpers
// --------------------------------


// On non-Apple platforms, executing a URLRequest whose url is nil will actually 'fatalError'.
// As such, these extensions are currently limited to Apple platforms only.
// Fixed by https://github.com/apple/swift-corelibs-foundation/pull/3154
#if canImport(Darwin)

  extension URLSessionEndToEndTests {

    fileprivate final class SyncBox<T> {
      private var _value: T
      private let _queue: DispatchQueue

      init(initialValue: T) {
        self._value = initialValue
        self._queue = DispatchQueue(label: "SyncBox")
      }

      var value: T {
        get { _queue.sync { _value } }
        set { _queue.sync { _value = newValue } }
      }
    }

    fileprivate func expectation(function: StaticString = #function, line: Int = #line) -> XCTestExpectation {
      expectation(description: "\(function):\(line)")
    }

    fileprivate enum ExpectedConversionResult {
      case noEncodingAdded
      case encodingAdded
      case failure
    }

    /// Makes a request via a `URLSessionDataTask`, and checks that the URLs exposed
    /// via the task's `originalRequest.url/webURL` properties are converted from WebURL as expected.
    ///
    /// When the task's completion handler is invoked, it also checks:
    /// - That the callback's `URLResponse.url/webURL` values are consistent with the task's `currentRequest.url/webURL`.
    /// - That the callback's `error` is consistent with the task's `error`.
    ///
    /// Finally, the `checkResponse` closure is invoked to check the actual response data,
    /// as well as the values of `URLResponse.url/webURL` and `error`.
    ///
    /// This function creates an XCTest expectation.
    /// You must call `waitForExpectations` to wait for the result.
    ///
    /// - parameters:
    ///   - urlString: The URL to make a request to. Must be a normalized WebURL.
    ///   - expectedConversionResult: How the converted Foundation.URL relates to `urlString`.
    ///   - nilURLHandlerIsInstalled: Whether or not `NilURLHandler` is registered in `URLSession.shared`.
    ///   - checkResponse: A closure which checks the data, URLResponse, and error returned by the response.
    ///
    fileprivate func makeDataTaskRequest(
      to urlString: String,
      expectedConversionResult: ExpectedConversionResult = .noEncodingAdded,
      nilURLHandlerIsInstalled: Bool = false,
      function: StaticString = #function, line: Int = #line,
      checkResponse: @escaping (Data?, URLResponse?, Error?) -> Void
    ) {
      let webURL = WebURL(urlString)!
      XCTAssertEqual(webURL.serialized(), urlString, "Given string must be a normalized WebURL")

      let expectn = expectation(function: function, line: line)
      let taskBox = SyncBox<URLSessionDataTask?>(initialValue: nil)
      taskBox.value = URLSession.shared.dataTask(with: webURL) { data, response, error in

        let task = taskBox.value!
        taskBox.value = nil
        defer { expectn.fulfill() }

        // Check the URL that was used to make the 'originalRequest'.

        switch expectedConversionResult {
        case .encodingAdded:
          let encodedURLString = webURL.encodedForFoundation.serialized()
          XCTAssertNotEqual(urlString, encodedURLString, "Expected pct-encoding to be added, but it is not required")
          XCTAssertEqual(task.originalRequest?.url?.absoluteString, encodedURLString)
          XCTAssertEqual(task.originalRequest?.webURL?.serialized(), encodedURLString)
        case .noEncodingAdded:
          XCTAssertEqual(task.originalRequest?.url?.absoluteString, urlString)
          XCTAssertEqual(task.originalRequest?.webURL?.serialized(), urlString)
        case .failure:
          XCTAssertNil(task.originalRequest?.url)
          XCTAssertNil(task.originalRequest?.webURL)
        }

        // Generally, the 'URLResponse.url' should equal the 'currentRequest.url'.
        // There is one situation where that isn't guaranteed to be the case: if a custom URLProtocol handler
        // handles the request, it can decide which value to use for 'URLResponse.url'.

        if nilURLHandlerIsInstalled && task.currentRequest?.url == nil {
          precondition(response?.url?.absoluteString == NilURLHandler.ResponseURLString)
          XCTAssertEqual(response?.webURL?.serialized(), NilURLHandler.ResponseURLString)
        } else {
          precondition(
            task.currentRequest?.url?.absoluteString == response?.url?.absoluteString,
            "URLSessionDataTask.currentRequest.url/URLResponse.url mismatch"
          )
          XCTAssertEqual(task.currentRequest?.webURL, response?.webURL)
        }

        // The callback's error should be the same as the 'error' property on the task object.
        // We should not be injecting a different error in the callback.

        let callbackError = (error as? NSError)
        let taskError = (task.error as? NSError)
        XCTAssertEqual(callbackError?.code, taskError?.code)
        XCTAssertEqual(callbackError?.domain, taskError?.domain)

        // The closure verifies the URLResponse, data, and error.

        checkResponse(data, response, error)
      }
      taskBox.value!.resume()
    }

    /// A `URLProtocol` handler which responds to requests whose URL is 'nil'.
    ///
    /// Even though `URLRequest`s may have a nil URL, `URLResponse`s may not.
    /// Therefore, the response's URL will be `"made-up://imaginary"`.
    ///
    fileprivate final class NilURLHandler: URLProtocol {

      static let ReturnedData: Data = {
        var rng = SystemRandomNumberGenerator()
        return Data((0..<1024).map { _ in rng.next() as UInt8 })
      }()

      static let ResponseURLString = "made-up://imaginary"

      override class func canInit(with request: URLRequest) -> Bool {
        request.url == nil
      }
      override class func canInit(with task: URLSessionTask) -> Bool {
        task.currentRequest?.url == nil
      }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        // Note: This override is required on Darwin, but is never called in swift-corelibs-foundation.
        // https://bugs.swift.org/browse/SR-15987
        request
      }
      override func startLoading() {
        let url = URL(string: NilURLHandler.ResponseURLString)!
        precondition(url.absoluteString == NilURLHandler.ResponseURLString)

        let response = URLResponse(url: url, mimeType: "", expectedContentLength: 0, textEncodingName: nil)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.ReturnedData)
        client?.urlProtocolDidFinishLoading(self)
      }
      override func stopLoading() {
      }
    }

    /// A URLSessionTaskDelegate which invokes a closure on task completion.
    ///
    fileprivate final class TaskDelegate: NSObject, URLSessionTaskDelegate {
      var onComplete: Optional<(URLSessionTask, Error?) -> Void> = nil

      func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete?(task, error)
      }
    }
  }


  // -----------------------------------
  // MARK: - URLSessionDataTask (Basic)
  // -----------------------------------


  extension URLSessionEndToEndTests {

    func testDataTask() throws {

      var rng = SystemRandomNumberGenerator()
      let referenceData = (0..<1024).map { _ in rng.next() as UInt8 }
      let referenceData_pathEncode = (0..<1024).map { _ in rng.next() as UInt8 }
      let referenceData_queryEncode = (0..<1024).map { _ in rng.next() as UInt8 }

      let localServer = LocalServer { request, _ in

        if request.starts(with: "GET /foo/bar?baz=qux HTTP/".utf8) {
          return .data(referenceData)
        }
        if request.starts(with: "GET /p-encode/%5Bbaz%5D HTTP/".utf8) {
          return .data(referenceData_pathEncode)
        }
        if request.starts(with: "GET /q-encode?id=%7Bxx%7D HTTP/".utf8) {
          return .data(referenceData_queryEncode)
        }

        return .notFound
      }

      let port = try localServer.start()
      defer { localServer.stop() }

      // Simple request, no additional percent-encoding required.
      // The response's Foundation.URL and WebURL are identical.

      makeDataTaskRequest(to: "http://localhost:\(port)/foo/bar?baz=qux") {
        data, response, error in
        XCTAssertEqual(data, Data(referenceData))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/foo/bar?baz=qux")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/foo/bar?baz=qux")
      }

      // Foundation requires additional percent-encoding in the path.
      // The encoding is added as part of making the request,
      // so the response's Foundation.URL and WebURL are identical.

      makeDataTaskRequest(to: "http://localhost:\(port)/p-encode/[baz]", expectedConversionResult: .encodingAdded) {
        data, response, error in
        XCTAssertEqual(data, Data(referenceData_pathEncode))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/p-encode/%5Bbaz%5D")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/p-encode/%5Bbaz%5D")
      }

      // Foundation requires additional percent-encoding in the query.
      // The encoding is added as part of making the request,
      // so the response's Foundation.URL and WebURL are identical.

      makeDataTaskRequest(to: "http://localhost:\(port)/q-encode?id={xx}", expectedConversionResult: .encodingAdded) {
        data, response, error in
        XCTAssertEqual(data, Data(referenceData_queryEncode))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/q-encode?id=%7Bxx%7D")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/q-encode?id=%7Bxx%7D")
      }

      // Conversion failures.
      //
      // Some APIs (the ones which return a URLSessionDataTask/URLSessionDataTaskPublisher)
      // signal URL conversion failures by making a request to a 'nil' URL.
      //
      // This will generally result in a '.unsupportedURL' error - but Foundation actually allows
      // registered URLProtocol handlers to process those requests! We can't prevent it.
      //
      // It is highly unlikely that anybody is doing this (at least, not on purpose) -
      // not only is URLProtocol hardly used in the first place, but URLResponse requires a non-nil URL,
      // so the URLProtocol handler would have to create a URL out of thin air.
      //
      // Still, it's interesting behavior so we test it.

      makeDataTaskRequest(to: "http://local{host}/", expectedConversionResult: .failure) {
        data, response, error in
        XCTAssertNil(data)
        XCTAssertNil(response)
        XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
      }

      waitForExpectations(timeout: 5)

      #if !os(watchOS)  // URLProtocol handlers are not supported on watchOS.

        do {
          let didRegisterHandler = URLProtocol.registerClass(NilURLHandler.self)
          precondition(didRegisterHandler)
          defer { URLProtocol.unregisterClass(NilURLHandler.self) }

          makeDataTaskRequest(
            to: "http://loc{alh}ost/files/test",
            expectedConversionResult: .failure,
            nilURLHandlerIsInstalled: true
          ) {
            data, response, error in
            XCTAssertEqual(data, NilURLHandler.ReturnedData)
            XCTAssertNotNil(response)
            XCTAssertNil(error)

            XCTAssertEqual(response?.url?.absoluteString, NilURLHandler.ResponseURLString)
            XCTAssertEqual(response?.webURL?.serialized(), NilURLHandler.ResponseURLString)
          }

          waitForExpectations(timeout: 2)
        }

      #endif

      // URLSessionTaskDelegate.
      //
      // A copy of the simple request test above, but using a URLSession with delegate object
      // rather than a completion-handler.

      do {
        let urlString = "http://localhost:\(port)/foo/bar?baz=qux"
        let convertedURLString = urlString

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let delegate = TaskDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let exptn = expectation()
        let _task = session.dataTask(with: webURL)
        delegate.onComplete = { task, error in

          XCTAssertEqual(task.taskIdentifier, _task.taskIdentifier)

          XCTAssertEqual(task.originalRequest?.url?.absoluteString, convertedURLString)
          XCTAssertEqual(task.currentRequest?.url?.absoluteString, convertedURLString)

          XCTAssertEqual(task.originalRequest?.webURL?.serialized(), convertedURLString)
          XCTAssertEqual(task.currentRequest?.webURL?.serialized(), convertedURLString)

          XCTAssertEqual(task.response?.url?.absoluteString, convertedURLString)
          XCTAssertEqual(task.response?.webURL?.serialized(), convertedURLString)

          XCTAssertNil(error)
          XCTAssertNil(task.error)

          exptn.fulfill()
        }
        _task.resume()
        waitForExpectations(timeout: 2)
      }
    }

    func testDataTask_redirect() throws {

      // Redirects are particularly interesting because 'URLResponse.url' always
      // comes from Foundation's URL processing, even if the request was made using WebURL.
      //
      // This can lead to situations where 'response.url' and '.webURL' are different in more ways
      // than just percent-encoding. For example, WebURL will simplify the path.

      let localServer = LocalServer { request, serverInfo in

        if request.starts(with: "GET /foo/bar HTTP/".utf8) {
          return .text("Hello, world!")
        }
        if request.starts(with: "GET /redirect/simple/url HTTP/".utf8) {
          return .redirect("http://localhost:\(serverInfo.port)/foo/bar")
        }
        if request.starts(with: "GET /redirect/simple/absolute-path HTTP/".utf8) {
          return .redirect("/foo/bar")
        }

        if request.starts(with: "GET /redirect/special/dot HTTP/".utf8) {
          return .redirect("/foo/./bar")
        }
        if request.starts(with: "GET /foo/./bar HTTP/".utf8) {
          return .text("Got a dot")
        }

        if request.starts(with: "GET /redirect/special/dotdot HTTP/".utf8) {
          return .redirect("/foo/tmp/../bar")
        }
        if request.starts(with: "GET /foo/tmp/../bar HTTP/".utf8) {
          return .text("Got dotdot")
        }

        return .notFound
      }

      let port = try localServer.start()
      defer { localServer.stop() }

      // Simple redirect to absolute URL.
      // The response's Foundation.URL and WebURL are identical.

      makeDataTaskRequest(to: "http://localhost:\(port)/redirect/simple/url") { data, response, error in
        XCTAssertTrue(data?.elementsEqual("Hello, world!".utf8) == true)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/foo/bar")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/foo/bar")
      }

      // Simple redirect to absolute path.
      // The response's Foundation.URL and WebURL are identical.

      makeDataTaskRequest(to: "http://localhost:\(port)/redirect/simple/absolute-path") { data, response, error in
        XCTAssertTrue(data?.elementsEqual("Hello, world!".utf8) == true)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/foo/bar")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/foo/bar")
      }

      // Redirect to an absolute path containing a dot component.
      // Foundation keeps the dot, and actually makes a request to "/foo/./bar".
      // WebURL simplifies the path, so it looks like this response came from "/foo/bar".

      makeDataTaskRequest(to: "http://localhost:\(port)/redirect/special/dot") { data, response, error in
        XCTAssertTrue(data?.elementsEqual("Got a dot".utf8) == true)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/foo/bar")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/foo/./bar")
      }

      // Redirect to an absolute path containing a dot-dot component.
      // Foundation keeps the dot-dot, and actually makes a request to "/foo/tmp/../bar".
      // WebURL simplifies the path, so it looks like this response came from "/foo/bar".

      makeDataTaskRequest(to: "http://localhost:\(port)/redirect/special/dotdot") { data, response, error in
        XCTAssertTrue(data?.elementsEqual("Got dotdot".utf8) == true)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)

        XCTAssertEqual(response?.webURL?.serialized(), "http://localhost:\(port)/foo/bar")
        XCTAssertEqual(response?.url?.absoluteString, "http://localhost:\(port)/foo/tmp/../bar")
      }

      waitForExpectations(timeout: 5)
    }

    func testDataTask_customProtocol() throws {

      #if os(watchOS)
        throw XCTSkip("Custom URL protocol handling is not available on watchOS")
      #endif

      final class FooSchemeHandler: URLProtocol {

        override class func canInit(with request: URLRequest) -> Bool {
          request.webURL?.scheme == "foo"
        }
        override class func canInit(with task: URLSessionTask) -> Bool {
          task.currentRequest?.webURL?.scheme == "foo"
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
          // Note: This override is required on Darwin, but is never called in swift-corelibs-foundation.
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

      let didRegisterHandler = URLProtocol.registerClass(FooSchemeHandler.self)
      precondition(didRegisterHandler)
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

      // Conversion failures.
      // URL conversion does not add percent-encoding to opaque paths.

      makeDataTaskRequest(to: "foo:path has a space", expectedConversionResult: .failure) { data, response, error in
        XCTAssertNil(data)
        XCTAssertNil(response)
        XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
      }

      makeDataTaskRequest(to: "foo:path[br{ack}ets]!", expectedConversionResult: .failure) { data, response, error in
        XCTAssertNil(data)
        XCTAssertNil(response)
        XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
      }

      waitForExpectations(timeout: 5)
    }
  }

#endif  // canImport(Darwin)


// -------------------------------------
// MARK: - URLSessionDataTask (Combine)
// -------------------------------------


#if canImport(Darwin) && canImport(Combine)

  import Combine

  extension URLSessionEndToEndTests {

    func testDataTaskPublisher() throws {

      guard #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *) else {
        throw XCTSkip("Combine requires macOS 10.15/iOS 13.0/watchOS 6.0 or newer")
      }

      var rng = SystemRandomNumberGenerator()
      let referenceData = (0..<1024).map { _ in rng.next() as UInt8 }
      let referenceData_pathEncode = (0..<1024).map { _ in rng.next() as UInt8 }

      let localServer = LocalServer { request, _ in

        if request.starts(with: "GET /foo/bar?baz=qux HTTP/".utf8) {
          return .data(referenceData)
        }
        if request.starts(with: "GET /p-encode/%5Bbaz%5D HTTP/".utf8) {
          return .data(referenceData_pathEncode)
        }

        return .notFound
      }

      let port = try localServer.start()
      defer { localServer.stop() }

      var tokens = [AnyCancellable]()

      // Simple request, no additional percent-encoding required.
      // The response's Foundation.URL and WebURL are identical.

      do {
        let urlString = "http://localhost:\(port)/foo/bar?baz=qux"
        let convertedURLString = urlString

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let publisher = URLSession.shared.dataTaskPublisher(for: webURL)
        let expectatn = expectation()

        XCTAssertEqual(publisher.request.webURL?.serialized(), convertedURLString)
        XCTAssertEqual(publisher.request.url?.absoluteString, convertedURLString)

        publisher.sink { completion in
          if case .failure(let error) = completion {
            XCTFail("Unexpected error: \(error)")
          }
          expectatn.fulfill()
        } receiveValue: { (data, response) in
          XCTAssertEqual(data, Data(referenceData))
          XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
          XCTAssertEqual(response.webURL?.serialized(), convertedURLString)
          XCTAssertEqual(response.url?.absoluteString, convertedURLString)
        }.store(in: &tokens)
      }

      // Foundation requires additional percent-encoding in the path.
      // The encoding is added as part of making the request,
      // so the response's Foundation.URL and WebURL are identical.

      do {
        let urlString = "http://localhost:\(port)/p-encode/[baz]"
        let convertedURLString = "http://localhost:\(port)/p-encode/%5Bbaz%5D"

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let publisher = URLSession.shared.dataTaskPublisher(for: webURL)
        let expectatn = expectation()

        XCTAssertEqual(publisher.request.webURL?.serialized(), convertedURLString)
        XCTAssertEqual(publisher.request.url?.absoluteString, convertedURLString)

        publisher.sink { completion in
          if case .failure(let error) = completion {
            XCTFail("Unexpected error: \(error)")
          }
          expectatn.fulfill()
        } receiveValue: { (data, response) in
          XCTAssertEqual(data, Data(referenceData_pathEncode))
          XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
          XCTAssertEqual(response.webURL?.serialized(), convertedURLString)
          XCTAssertEqual(response.url?.absoluteString, convertedURLString)
        }.store(in: &tokens)
      }

      // Conversion failures.
      //
      // Some APIs (the ones which return a URLSessionDataTask/URLSessionDataTaskPublisher)
      // signal URL conversion failures by making a request to a 'nil' URL.
      //
      // This will generally result in a '.unsupportedURL' error - but Foundation actually allows
      // registered URLProtocol handlers to process those requests! We can't prevent it.
      //
      // It is highly unlikely that anybody is doing this (at least, not on purpose) -
      // not only is URLProtocol hardly used in the first place, but URLResponse requires a non-nil URL,
      // so the URLProtocol handler would have to create a URL out of thin air.
      //
      // Still, it's interesting behavior so we test it.

      do {
        let urlString = "http://loc{alh}ost:\(port)/"

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let publisher = URLSession.shared.dataTaskPublisher(for: webURL)
        let expectatn = expectation()

        XCTAssertEqual(publisher.request.webURL, nil)
        XCTAssertEqual(publisher.request.url, nil)

        publisher.sink { completion in
          switch completion {
          case .failure(let error):
            XCTAssertEqual(error.code, .unsupportedURL)
          default:
            XCTFail("Unexpected non-error result: \(completion)")
          }
          expectatn.fulfill()
        } receiveValue: { (data, response) in
          XCTFail("Unexpected response: \(data) \(response)")
        }.store(in: &tokens)
      }

      waitForExpectations(timeout: 5)

      #if !os(watchOS)  // URLProtocol handlers are not supported on watchOS.

        do {
          let didRegisterHandler = URLProtocol.registerClass(NilURLHandler.self)
          precondition(didRegisterHandler)
          defer { URLProtocol.unregisterClass(NilURLHandler.self) }

          let urlString = "http://loc{alh}ost:\(port)/"

          let webURL = WebURL(urlString)!
          XCTAssertEqual(webURL.serialized(), urlString)

          let publisher = URLSession.shared.dataTaskPublisher(for: webURL)
          let expectatn = expectation()

          XCTAssertEqual(publisher.request.webURL, nil)
          XCTAssertEqual(publisher.request.url, nil)

          publisher.sink { completion in
            if case .failure(let error) = completion {
              XCTFail("Unexpected error: \(error)")
            }
            expectatn.fulfill()
          } receiveValue: { (data, response) in
            XCTAssertEqual(data, NilURLHandler.ReturnedData)
            XCTAssertEqual(response.webURL?.serialized(), NilURLHandler.ResponseURLString)
            XCTAssertEqual(response.url?.absoluteString, NilURLHandler.ResponseURLString)
          }.store(in: &tokens)

          waitForExpectations(timeout: 5)
        }

      #endif

      withExtendedLifetime(tokens) {}
    }
  }

#endif  // canImport(Darwin) && canImport(Combine)


// -----------------------------------
// MARK: - URLSessionDataTask (Async)
// -----------------------------------


#if swift(>=5.5) && canImport(_Concurrency) && canImport(Darwin)

  extension URLSessionEndToEndTests {

    func testDataAsync() async throws {

      guard #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) else {
        throw XCTSkip("URLSession async support requires macOS 12.0/iOS 15.0/watchOS 8.0 or newer")
      }

      var rng = SystemRandomNumberGenerator()
      let referenceData = (0..<1024).map { _ in rng.next() as UInt8 }
      let referenceData_pathEncode = (0..<1024).map { _ in rng.next() as UInt8 }

      let localServer = LocalServer { request, _ in

        if request.starts(with: "GET /foo/bar?baz=qux HTTP/".utf8) {
          return .data(referenceData)
        }
        if request.starts(with: "GET /p-encode/%5Bbaz%5D HTTP/".utf8) {
          return .data(referenceData_pathEncode)
        }

        return .notFound
      }

      let port = try localServer.start()
      defer { localServer.stop() }

      // Simple request, no additional percent-encoding required.
      // The response's Foundation.URL and WebURL are identical.

      do {
        let urlString = "http://localhost:\(port)/foo/bar?baz=qux"
        let convertedURLString = urlString

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let (data, response) = try await URLSession.shared.data(from: webURL)

        XCTAssertEqual(data, Data(referenceData))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(response.webURL?.serialized(), convertedURLString)
        XCTAssertEqual(response.url?.absoluteString, convertedURLString)
      } catch {
        XCTFail("Unexpected error: \(error)")
      }

      // Foundation requires additional percent-encoding in the path.
      // The encoding is added as part of making the request,
      // so the response's Foundation.URL and WebURL are identical.

      do {
        let urlString = "http://localhost:\(port)/p-encode/[baz]"
        let convertedURLString = "http://localhost:\(port)/p-encode/%5Bbaz%5D"

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let (data, response) = try await URLSession.shared.data(from: webURL)

        XCTAssertEqual(data, Data(referenceData_pathEncode))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(response.webURL?.serialized(), convertedURLString)
        XCTAssertEqual(response.url?.absoluteString, convertedURLString)
      } catch {
        XCTFail("Unexpected error: \(error)")
      }

      // Conversion failures.
      // Since the URLSession async APIs are throwing, we can ensure that a specific error is always thrown,
      // even if a URLProtocol handler is registered which would process requests with a 'nil' URL.

      do {
        let urlString = "http://loc{alh}ost:\(port)/"

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let (data, response) = try await URLSession.shared.data(from: webURL)
        XCTFail("Unexpected response: \(data) \(response)")
      } catch let error as WebURLToFoundationConversionError {
        XCTAssertEqual(error.url.serialized(), "http://loc{alh}ost:\(port)/")
      } catch {
        XCTFail("Unexpected error: \(error)")
      }

      #if !os(watchOS)  // URLProtocol handlers are not supported on watchOS.

        do {
          let didRegister = URLProtocol.registerClass(NilURLHandler.self)
          precondition(didRegister)
          defer { URLProtocol.unregisterClass(NilURLHandler.self) }

          let urlString = "http://loc{alh}ost:\(port)/"

          let webURL = WebURL(urlString)!
          XCTAssertEqual(webURL.serialized(), urlString)

          let (data, response) = try await URLSession.shared.data(from: webURL)
          XCTFail("Unexpected response: \(data) \(response)")
        } catch let error as WebURLToFoundationConversionError {
          XCTAssertEqual(error.url.serialized(), "http://loc{alh}ost:\(port)/")
        } catch {
          XCTFail("Unexpected error: \(error)")
        }

      #endif
    }

    func testBytesAsync() async throws {

      guard #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) else {
        throw XCTSkip("URLSession async support requires macOS 12.0/iOS 15.0/watchOS 8.0 or newer")
      }

      var rng = SystemRandomNumberGenerator()
      let referenceData = (0..<1024).map { _ in rng.next() as UInt8 }
      let referenceData_pathEncode = (0..<1024).map { _ in rng.next() as UInt8 }

      let localServer = LocalServer { request, _ in

        if request.starts(with: "GET /foo/bar?baz=qux HTTP/".utf8) {
          return .data(referenceData)
        }
        if request.starts(with: "GET /p-encode/%5Bbaz%5D HTTP/".utf8) {
          return .data(referenceData_pathEncode)
        }

        return .notFound
      }

      let port = try localServer.start()
      defer { localServer.stop() }

      // Simple request, no additional percent-encoding required.
      // The response's Foundation.URL and WebURL are identical.

      do {
        let urlString = "http://localhost:\(port)/foo/bar?baz=qux"
        let convertedURLString = urlString

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let (stream, response) = try await URLSession.shared.bytes(from: webURL)
        var expectedBytesIter = referenceData.makeIterator()
        for try await byte in stream {
          XCTAssertEqual(byte, expectedBytesIter.next())
        }
        XCTAssertNil(expectedBytesIter.next())

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(response.webURL?.serialized(), convertedURLString)
        XCTAssertEqual(response.url?.absoluteString, convertedURLString)

        XCTAssertEqual(stream.task.originalRequest?.url, response.url)
        XCTAssertEqual(stream.task.currentRequest?.url, response.url)

        XCTAssertEqual(stream.task.originalRequest?.webURL, response.webURL)
        XCTAssertEqual(stream.task.currentRequest?.webURL, response.webURL)
      } catch {
        XCTFail("Unexpected error: \(error)")
      }

      // Foundation requires additional percent-encoding in the path.
      // The encoding is added as part of making the request,
      // so the response's Foundation.URL and WebURL are identical.

      do {
        let urlString = "http://localhost:\(port)/p-encode/[baz]"
        let convertedURLString = "http://localhost:\(port)/p-encode/%5Bbaz%5D"

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let (stream, response) = try await URLSession.shared.bytes(from: webURL)
        var expectedBytesIter = referenceData_pathEncode.makeIterator()
        for try await byte in stream {
          XCTAssertEqual(byte, expectedBytesIter.next())
        }
        XCTAssertNil(expectedBytesIter.next())

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(response.webURL?.serialized(), convertedURLString)
        XCTAssertEqual(response.url?.absoluteString, convertedURLString)

        XCTAssertEqual(stream.task.originalRequest?.url, response.url)
        XCTAssertEqual(stream.task.currentRequest?.url, response.url)

        XCTAssertEqual(stream.task.originalRequest?.webURL, response.webURL)
        XCTAssertEqual(stream.task.currentRequest?.webURL, response.webURL)
      } catch {
        XCTFail("Unexpected error: \(error)")
      }

      // Conversion failures.
      // Since the URLSession async APIs are throwing, we can ensure that a specific error is always thrown,
      // even if a URLProtocol handler is registered which would process requests with a 'nil' URL.

      do {
        let urlString = "http://loc{alh}ost:\(port)/"

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let (stream, response) = try await URLSession.shared.bytes(from: webURL)
        XCTFail("Unexpected response: \(stream) \(response)")
      } catch let error as WebURLToFoundationConversionError {
        XCTAssertEqual(error.url.serialized(), "http://loc{alh}ost:\(port)/")
      } catch {
        XCTFail("Unexpected error: \(error)")
      }

      #if !os(watchOS)  // URLProtocol handlers are not supported on watchOS.

        do {
          let didRegister = URLProtocol.registerClass(NilURLHandler.self)
          precondition(didRegister)
          defer { URLProtocol.unregisterClass(NilURLHandler.self) }

          let urlString = "http://loc{alh}ost:\(port)/"

          let webURL = WebURL(urlString)!
          XCTAssertEqual(webURL.serialized(), urlString)

          let (stream, response) = try await URLSession.shared.bytes(from: webURL)
          XCTFail("Unexpected response: \(stream) \(response)")
        } catch let error as WebURLToFoundationConversionError {
          XCTAssertEqual(error.url.serialized(), "http://loc{alh}ost:\(port)/")
        } catch {
          XCTFail("Unexpected error: \(error)")
        }

      #endif
    }
  }

#endif  // swift(>=5.5) && canImport(_Concurrency) && canImport(Darwin)


// ---------------------------------------
// MARK: - URLSessionDownloadTask (Basic)
// ---------------------------------------


#if canImport(Darwin)

  extension URLSessionEndToEndTests {

    func testDownloadTask() throws {

      var rng = SystemRandomNumberGenerator()
      let referenceData = (0..<1024).map { _ in rng.next() as UInt8 }
      let referenceData_pathEncode = (0..<1024).map { _ in rng.next() as UInt8 }

      let localServer = LocalServer { request, _ in

        if request.starts(with: "GET /files/test HTTP/".utf8) {
          return .data(referenceData)
        }
        if request.starts(with: "GET /files/%5Babc%5D HTTP/".utf8) {
          return .data(referenceData_pathEncode)
        }

        return .notFound
      }

      let port = try localServer.start()
      defer { localServer.stop() }

      // Simple request, no additional percent-encoding required.
      // The response's Foundation.URL and WebURL are identical.

      do {
        let urlString = "http://localhost:\(port)/files/test"
        let convertedURLString = urlString

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let expt = expectation()
        let task = URLSession.shared.downloadTask(with: webURL) { fileWebURL, response, error in
          XCTAssertNotNil(fileWebURL)
          XCTAssertNotNil(response)
          XCTAssertNil(error)

          XCTAssertEqual(response?.url?.absoluteString, convertedURLString)
          XCTAssertEqual(response?.webURL?.serialized(), convertedURLString)

          if let fileWebURL = fileWebURL {
            XCTAssertEqual(try? Data(contentsOf: fileWebURL), Data(referenceData))
          }
          expt.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 2)
        XCTAssertNil(task.error)
      }

      // Foundation requires additional percent-encoding in the path.
      // The encoding is added as part of making the request,
      // so the response's Foundation.URL and WebURL are identical.

      do {
        let urlString = "http://localhost:\(port)/files/[abc]"
        let convertedURLString = "http://localhost:\(port)/files/%5Babc%5D"

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let expt = expectation()
        let task = URLSession.shared.downloadTask(with: webURL) { fileWebURL, response, error in
          XCTAssertNotNil(fileWebURL)
          XCTAssertNotNil(response)
          XCTAssertNil(error)

          XCTAssertEqual(response?.url?.absoluteString, convertedURLString)
          XCTAssertEqual(response?.webURL?.serialized(), convertedURLString)

          if let fileWebURL = fileWebURL {
            XCTAssertEqual(try? Data(contentsOf: fileWebURL), Data(referenceData_pathEncode))
          }
          expt.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 2)
        XCTAssertNil(task.error)
      }

      // Conversion failures.
      //
      // As with other functions that return a URLSessionTask, this returns a '.unsupportedURL' error
      // for conversion failures. They can also be intercepted using a URLProtocol handler.

      do {
        let urlString = "http://loc{alh}ost:\(port)/files/test"

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let expt = expectation()
        let task = URLSession.shared.downloadTask(with: webURL) { fileWebURL, response, error in
          XCTAssertNil(fileWebURL)
          XCTAssertNil(response)
          XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
          expt.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 2)
        XCTAssertEqual((task.error as? URLError)?.code, .unsupportedURL)
      }

      #if !os(watchOS)  // URLProtocol handlers are not supported on watchOS.

        do {
          let didRegisterHandler = URLProtocol.registerClass(NilURLHandler.self)
          precondition(didRegisterHandler)
          defer { URLProtocol.unregisterClass(NilURLHandler.self) }

          let urlString = "http://loc{alh}ost:\(port)/files/test"

          let webURL = WebURL(urlString)!
          XCTAssertEqual(webURL.serialized(), urlString)

          let expt = expectation()
          let task = URLSession.shared.downloadTask(with: webURL) { fileWebURL, response, error in
            XCTAssertNotNil(fileWebURL)
            XCTAssertNotNil(response)
            XCTAssertNil(error)

            XCTAssertEqual(response?.url?.absoluteString, NilURLHandler.ResponseURLString)
            XCTAssertEqual(response?.webURL?.serialized(), NilURLHandler.ResponseURLString)

            if let fileWebURL = fileWebURL {
              XCTAssertEqual(try? Data(contentsOf: fileWebURL), NilURLHandler.ReturnedData)
            }
            expt.fulfill()
          }
          task.resume()
          waitForExpectations(timeout: 2)
          XCTAssertNil(task.error)
        }

      #endif

      // URLSessionTaskDelegate.
      //
      // A copy of the simple request test above, but using a URLSession with delegate object
      // rather than a completion-handler.

      do {
        let urlString = "http://localhost:\(port)/files/test"
        let convertedURLString = "http://localhost:\(port)/files/test"

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let delegate = TaskDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let exptn = expectation()
        let _task = session.downloadTask(with: webURL)
        delegate.onComplete = { task, error in
          XCTAssertEqual(task.taskIdentifier, _task.taskIdentifier)

          XCTAssertEqual(task.originalRequest?.url?.absoluteString, convertedURLString)
          XCTAssertEqual(task.currentRequest?.url?.absoluteString, convertedURLString)

          XCTAssertEqual(task.originalRequest?.webURL?.serialized(), convertedURLString)
          XCTAssertEqual(task.currentRequest?.webURL?.serialized(), convertedURLString)

          XCTAssertEqual(task.response?.url?.absoluteString, convertedURLString)
          XCTAssertEqual(task.response?.webURL?.serialized(), convertedURLString)

          XCTAssertNil(error)
          XCTAssertNil(task.error)
          exptn.fulfill()
        }
        _task.resume()
        waitForExpectations(timeout: 2)
      }
    }
  }

#endif


// ----------------------------------------------
// MARK: - URLSessionWebSocketTask (Darwin-only)
// ----------------------------------------------


#if canImport(Darwin)

  extension URLSessionEndToEndTests {

    func testWebsocketTask() throws {

      guard #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *) else {
        throw XCTSkip("URLSessionWebSocketTask requires macOS 10.15/iOS 13.0/watchOS 6.0 or newer")
      }

      // It's not worth actually building a WebSocket server for this test.
      // Just mark which request we saw.

      enum RequestTarget {
        case simple
        case percentEncodingAdded
        case other
      }

      let requestInfo = SyncBox<(RequestTarget, isWebsocket: Bool)?>(initialValue: nil)
      let localServer = LocalServer { request, _ in

        let target: RequestTarget
        if request.starts(with: "GET /foo/bar HTTP/".utf8) {
          target = .simple
        } else if request.starts(with: "GET /foo/%5Bbaz%5D HTTP/".utf8) {
          target = .percentEncodingAdded
        } else {
          target = .other
        }

        let isWebsocket = request.split(separator: UInt8(ascii: "\n")).contains { line in
          line.elementsEqual("Upgrade: websocket\r".utf8)
        }

        requestInfo.value = (target, isWebsocket)

        return .notFound
      }

      let port = try localServer.start()
      defer { localServer.stop() }

      // Simple request, no additional percent-encoding required.
      // The response's Foundation.URL and WebURL are identical.

      do {
        let urlString = "ws://localhost:\(port)/foo/bar"

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let expt = expectation()
        let task = URLSession.shared.webSocketTask(with: webURL)
        task.resume()
        task.send(.string("hello, world!")) { error in

          XCTAssertTrue(requestInfo.value?.0 == .simple)
          XCTAssertTrue(requestInfo.value?.isWebsocket == true)
          XCTAssertEqual((error as? URLError)?.code, .badServerResponse)

          // For some reason, Foundation makes these URLs http 🤷‍♂️
          let convertedURLString = "http://localhost:\(port)/foo/bar"
          XCTAssertEqual(task.originalRequest?.url?.absoluteString, convertedURLString)
          XCTAssertEqual(task.currentRequest?.url?.absoluteString, convertedURLString)

          XCTAssertEqual(task.originalRequest?.webURL?.serialized(), convertedURLString)
          XCTAssertEqual(task.currentRequest?.webURL?.serialized(), convertedURLString)

          XCTAssertEqual(task.response?.url?.absoluteString, convertedURLString)
          XCTAssertEqual(task.response?.webURL?.serialized(), convertedURLString)

          expt.fulfill()
        }
        waitForExpectations(timeout: 2)
        XCTAssertEqual((task.error as? URLError)?.code, .badServerResponse)
      }

      requestInfo.value = nil

      // Foundation requires additional percent-encoding in the path.
      // The encoding is added as part of making the request,
      // so the response's Foundation.URL and WebURL are identical.

      do {
        let urlString = "ws://localhost:\(port)/foo/[baz]"

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let expt = expectation()
        let task = URLSession.shared.webSocketTask(with: webURL)
        task.resume()
        task.send(.string("hello, world!")) { error in

          XCTAssertTrue(requestInfo.value?.0 == .percentEncodingAdded)
          XCTAssertTrue(requestInfo.value?.isWebsocket == true)
          XCTAssertEqual((error as? URLError)?.code, .badServerResponse)

          // For some reason, Foundation makes these URLs http 🤷‍♂️
          let convertedURLString = "http://localhost:\(port)/foo/%5Bbaz%5D"
          XCTAssertEqual(task.originalRequest?.url?.absoluteString, convertedURLString)
          XCTAssertEqual(task.currentRequest?.url?.absoluteString, convertedURLString)

          XCTAssertEqual(task.originalRequest?.webURL?.serialized(), convertedURLString)
          XCTAssertEqual(task.currentRequest?.webURL?.serialized(), convertedURLString)

          XCTAssertEqual(task.response?.url?.absoluteString, convertedURLString)
          XCTAssertEqual(task.response?.webURL?.serialized(), convertedURLString)

          expt.fulfill()
        }
        waitForExpectations(timeout: 2)
        XCTAssertEqual((task.error as? URLError)?.code, .badServerResponse)
      }

      requestInfo.value = nil

      // Conversion failure.
      // No request should be sent.

      do {
        let urlString = "ws://loc{alh}ost:\(port)/foo/bar"

        let webURL = WebURL(urlString)!
        XCTAssertEqual(webURL.serialized(), urlString)

        let expt = expectation()
        let task = URLSession.shared.webSocketTask(with: webURL)
        task.resume()
        task.send(.string("hello, world!")) { error in

          XCTAssertNil(requestInfo.value)
          XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)

          XCTAssertNil(task.originalRequest?.url)
          XCTAssertNil(task.currentRequest?.url)

          XCTAssertNil(task.originalRequest?.webURL)
          XCTAssertNil(task.currentRequest?.webURL)

          XCTAssertNil(task.response?.url)
          XCTAssertNil(task.response?.webURL)

          expt.fulfill()
        }
        waitForExpectations(timeout: 2)
        XCTAssertEqual((task.error as? URLError)?.code, .unsupportedURL)
      }
    }
  }

#endif  // canImport(Darwin)
