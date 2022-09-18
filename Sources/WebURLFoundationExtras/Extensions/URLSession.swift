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
// MARK: - URLSessionDataTask
// --------------------------------


// For APIs which return a URLSessionDataTask/URLSessionDataTaskPublisher, users idiomatically handle errors
// via the task's callback, or via the error sent through the Combine stream.
//
// Unfortunately, there is no way to create a URLSessionDataTask/URLSessionDataTaskPublisher
// which throws a particular error, so conversion failures instead make a request to a 'nil' URL.
// We can reasonably assume that no URLProtocol handlers will process these, and they result in
// a '.unsupportedURL' error.
//
// There are other designs for this: these functions could be throwing, or return a different type.
// However, that would make them much more difficult to adopt, and WebURL -> Foundation.URL conversion errors
// are so exceptionally rare that it is considered not worth the churn.
//
// However, on non-Apple platforms, executing a URLRequest whose url is nil will actually 'fatalError'.
// As such, these extensions are currently limited to Apple platforms only.
// Fixed by https://github.com/apple/swift-corelibs-foundation/pull/3154

#if canImport(Darwin)

  extension URLSession {

    /// Creates a task that retrieves the contents of the specified URL.
    ///
    /// After you create the task, you must start it by calling its `resume()` method.
    /// The task calls methods on the session’s delegate to provide you with the response metadata,
    /// response data, and so on.
    ///
    /// - parameters:
    ///   - url:               The URL to be retrieved.
    ///
    /// - returns: The new session data task.
    ///
    public func dataTask(
      with url: WebURL
    ) -> URLSessionDataTask {
      URL(url).map { dataTask(with: $0) }
        ?? dataTask(with: .requestForConversionFailure(url))
    }

    /// Creates a task that retrieves the contents of the specified URL, then calls a handler upon completion.
    ///
    /// After you create the task, you must start it by calling its `resume()` method.
    ///
    /// By using the completion handler, the task bypasses calls to delegate methods for response and data delivery,
    /// and instead provides any resulting `Data`, `URLResponse`, and `Error` objects inside the completion handler.
    /// Delegate methods for handling authentication challenges, however, are still called.
    /// The completion handler is executed on the delegate queue.
    ///
    /// - If the request completes successfully, the data parameter of the completion handler block contains
    ///   the resource data, and the error parameter is `nil`.
    /// - If the request fails, the data parameter is `nil` and the error parameter contains
    ///   information about the failure.
    /// - If a response from the server is received, regardless of whether the request completes successfully or fails,
    ///   the response parameter contains that information. If you are making an HTTP or HTTPS request,
    ///   the returned object is actually an `HTTPURLResponse` object.
    ///
    /// - parameters:
    ///   - url:               The URL to be retrieved.
    ///   - completionHandler: The completion handler to call when the load request is complete.
    ///
    /// - returns: The new session data task.
    ///
    public func dataTask(
      with url: WebURL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
      URL(url).map { dataTask(with: $0, completionHandler: completionHandler) }
        ?? dataTask(with: .requestForConversionFailure(url), completionHandler: completionHandler)
    }
  }

#endif  // canImport(Darwin)


#if canImport(Darwin) && canImport(Combine)

  import Combine

  extension URLSession {

    /// Returns a publisher that wraps a URL session data task for a given URL.
    ///
    /// The publisher publishes data when the task completes, or terminates if the task fails with an error.
    ///
    /// - parameters:
    ///   - url: The URL for which to create a data task.
    ///
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public func dataTaskPublisher(
      for url: WebURL
    ) -> URLSession.DataTaskPublisher {
      URL(url).map { dataTaskPublisher(for: $0) }
        ?? dataTaskPublisher(for: .requestForConversionFailure(url))
    }
  }

#endif  // canImport(Darwin) && canImport(Combine)


// URLSession's async APIs are throwing, so we don't need to rely on the "request to nil URL" trick
// to signal conversion failures, and they are no more difficult to adopt.
//
// Unfortunately, as of Swift 5.7, these APIs still only exist on Apple platforms.


#if swift(>=5.5) && canImport(_Concurrency) && canImport(Darwin)

  extension URLSession {

    /// Retrieves the contents of a URL and delivers the data asynchronously.
    ///
    /// Use this method to wait until the session finishes transferring data and receive it in a single `Data` instance.
    /// To process the bytes as the session receives them, use `bytes(from:delegate:)`.
    ///
    /// - parameters:
    ///   - url:      The URL to retrieve.
    ///   - delegate: A delegate that receives life cycle and authentication challenge callbacks
    ///               as the transfer progresses.
    ///
    /// - returns: An asynchronously-delivered tuple that contains the URL contents as a `Data` instance,
    ///            and a `URLResponse`.
    ///
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public func data(
      from url: WebURL, delegate: URLSessionTaskDelegate? = nil
    ) async throws -> (Data, URLResponse) {
      guard let convertedURL = URL(url) else { throw WebURLToFoundationConversionError(url) }
      return try await data(from: convertedURL, delegate: delegate)
    }

    /// Retrieves the contents of a given URL and delivers an asynchronous sequence of bytes.
    ///
    /// Use this method when you want to process the bytes while the transfer is underway.
    /// You can use a `for-await-in` loop to handle each byte. For textual data, use the `URLSession.AsyncBytes`
    /// properties `characters`, `unicodeScalars`, or `lines` to receive the content as asynchronous sequences
    /// of those types. To wait until the session finishes transferring data and receive it in a single `Data` instance,
    /// use `data(from:delegate:)`.
    ///
    /// - parameters:
    ///   - url:      The URL to retrieve.
    ///   - delegate: A delegate that receives life cycle and authentication challenge callbacks
    ///               as the transfer progresses.
    ///
    /// - returns: An asynchronously-delivered tuple that contains a `URLSession.AsyncBytes` sequence to iterate over,
    ///            and a `URLResponse`.
    ///
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public func bytes(
      from url: WebURL, delegate: URLSessionTaskDelegate? = nil
    ) async throws -> (URLSession.AsyncBytes, URLResponse) {
      guard let convertedURL = URL(url) else { throw WebURLToFoundationConversionError(url) }
      return try await bytes(from: convertedURL, delegate: delegate)
    }
  }

#endif  // swift(>=5.5) && canImport(_Concurrency) && canImport(Darwin)


// --------------------------------
// MARK: - URLSessionUploadTask
// --------------------------------


// TODO: How can we handle conversion failures for the body file URL?
// - uploadTask(with: URLRequest, fromFile: URL)
// - uploadTask(with: URLRequest, fromFile: URL, completionHandler: (Data?, URLResponse?, Error?) -> Void)


// --------------------------------
// MARK: - URLSessionDownloadTask
// --------------------------------


#if canImport(Darwin)

  extension URLSession {

    /// Creates a download task that retrieves the contents of the specified URL and saves the results to a file.
    ///
    /// After you create the task, you must start it by calling its `resume()` method.
    ///
    /// - parameters:
    ///   - url: The URL to download.
    ///
    /// - returns: The new session download task.
    ///
    public func downloadTask(with url: WebURL) -> URLSessionDownloadTask {
      URL(url).map { downloadTask(with: $0) }
        ?? downloadTask(with: .requestForConversionFailure(url))
    }

    /// Creates a download task that retrieves the contents of the specified URL, saves the results to a file,
    /// and calls a handler upon completion.
    ///
    /// By using the completion handler, the task bypasses calls to delegate methods for response and data delivery,
    /// and instead provides any resulting `WebURL`, `URLResponse`, and `Error` objects inside the completion handler.
    /// Delegate methods for handling authentication challenges, however, are still called.
    /// The completion handler is executed on the delegate queue.
    ///
    /// After you create the task, you must start it by calling its resume() method.
    ///
    /// - If the request completes successfully, the location parameter of the completion handler block
    ///   contains the location of a temporary file where the server’s response is stored, and the error parameter
    ///   is `nil`. You must move this file or open it for reading before your completion handler returns.
    ///   Otherwise, the file is deleted, and the data is lost.
    ///
    /// - If the request fails, the location parameter is `nil` and the error parameter contains information
    ///   about the failure.
    ///
    /// - If a response from the server is received, regardless of whether the request completes successfully or fails,
    ///   the response parameter contains that information. If you are making an HTTP or HTTPS request,
    ///   the returned object is actually an `HTTPURLResponse` object.
    ///
    /// - It is possible for both location and error to be `nil`. The best way to process the result is:
    ///   if the temporary file location is not `nil`, use it, otherwise fail (if the error parameter is not `nil`,
    ///   you can show that, otherwise fall-back to a generic failure message).
    ///
    /// - parameters:
    ///   - url: The URL to download.
    ///   - completionHandler: The completion handler to call when the load request is complete.
    ///
    /// - returns: The new session download task.
    ///
    public func downloadTask(
      with url: WebURL, completionHandler: @escaping (WebURL?, URLResponse?, Error?) -> Void
    ) -> URLSessionDownloadTask {

      let wrappedCompletionHandler = { (location: URL?, response: URLResponse?, error: Error?) -> Void in
        // - If the temporary file location cannot be represented as a web-compatible URL,
        //   we have no choice but to pass `nil` here, meaning both error and location parameters may be nil.
        // - We could fix that by passing a non-nil error in, but that means the 'error' parameter may differ
        //   from the task's 'error' property - which seems more subtle and probably a worse decision overall.
        //   Also, the user couldn't really handle the error without dropping down to Foundation.URL.
        // - This shouldn't be a problem for "file:" URLs, but Foundation has a lot of quirky stuff
        //   (sandbox URLs, etc), so who knows? Foundation URLs really are nothing like actual URLs
        //   so it's _not impossible_ that some of them cannot even be represented textually.
        guard let fileURL = location, let convertedFileURL = WebURL(fileURL) else {
          if let fileURL = location {
            print("⚠️ Download task temporary file URL could not be converted to WebURL: \(fileURL)")
          }
          completionHandler(nil, response, error)
          return
        }
        completionHandler(convertedFileURL, response, error)
      }

      return URL(url).map { downloadTask(with: $0, completionHandler: wrappedCompletionHandler) }
        ?? downloadTask(with: .requestForConversionFailure(url), completionHandler: wrappedCompletionHandler)
    }
  }

#endif  // canImport(Darwin)


// --------------------------------
// MARK: - URLSessionWebSocketTask
// --------------------------------


#if canImport(Darwin)  // URLSessionWebSocketTask is not implemented in swift-corelibs-foundation.

  extension URLSession {

    /// Creates a WebSocket task for the provided URL.
    ///
    /// The provided URL must have a ws or wss scheme.
    ///
    /// - parameters:
    ///   - url:       The WebSocket URL with which to connect.
    ///
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public func webSocketTask(with url: WebURL) -> URLSessionWebSocketTask {
      URL(url).map { webSocketTask(with: $0) }
        ?? webSocketTask(with: .requestForConversionFailure(url))
    }

    /// Creates a WebSocket task given a URL and an array of protocols.
    ///
    /// During the WebSocket handshake, the task uses the provided protocols to negotiate
    /// a preferred protocol with the server.
    ///
    /// > Note:
    /// > The protocol doesn’t affect the WebSocket framing.
    /// > More details on the protocol are available in [RFC 6455, The WebSocket Protocol][rfc-6455].
    ///
    /// [rfc-6455]: https://datatracker.ietf.org/doc/html/rfc6455
    ///
    /// - parameters:
    ///   - url:       The WebSocket URL with which to connect.
    ///   - protocols: An array of protocols to negotiate with the server.
    ///
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public func webSocketTask(with url: WebURL, protocols: [String]) -> URLSessionWebSocketTask {
      URL(url).map { webSocketTask(with: $0, protocols: protocols) }
        ?? webSocketTask(with: .requestForConversionFailure(url))
    }
  }

#endif  // canImport(Darwin)
