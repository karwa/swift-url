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
// MARK: - URLRequest
// --------------------------------


// On non-Apple platforms, executing a URLRequest whose url is nil will 'fatalError'.
// Since that is how we prefer to signal conversion failures, we don't offer extensions to create
// a URLRequest from a WebURL on those platforms. Fixed by https://github.com/apple/swift-corelibs-foundation/pull/3154
#if canImport(Darwin)

  extension URLRequest {

    /// A URLRequest to be executed when a WebURL could not be converted to a Foundation.URL.
    ///
    /// Firstly, it is important to note that WebURL -> Foundation.URL conversion failures are very, very rare.
    /// They occur for some URLs with opaque paths, and domains containing disallowed characters (e.g. curly braces),
    /// but otherwise all WebURLs can be converted. Most users will never see a conversion failure in this direction.
    ///
    /// Typically, errors which occur while executing a `URLSessionTask` are communicated via the task's error property,
    /// and the error parameter passed to delegate calls or the completion handler block. For example, making a request
    /// to <foo>, or <foo://bar>, or executing a request whose `url` is `nil` all return errors in this way.
    ///
    /// However, subclasses such as `URLSessionDataTask` cannot be instantiated except though methods such as
    /// `URLSession.dataTask(with: URLRequest)`, and there is no method to create a data task which always
    /// immediately completes with an error.
    ///
    /// So our options are to either:
    ///
    /// 1. Have all of these extensions return optional tasks. The returned tasks would be `nil` for one _particular_
    ///    and very rare kind of invalid URL, and all other invalid URLs would be notified via `URLSessionTask` errors
    ///    as usual. Or...
    ///
    /// 2. Create a dummy `URLRequest` which we can execute, but is malformed in some way that guarantees
    ///    it completes with an error, allowing users to handle all invalid URLs in the same way.
    ///
    /// We choose the latter approach. This request has a `nil` URL, resulting in a `.unsupportedURL` error.
    ///
    /// Technically, it is not entirely _guaranteed_ to return an error, because for some reason Foundation lets
    /// you register `URLProtocol`s which process requests with a `nil` URL. It may be worth registering our own
    /// `URLProtocol` as an additional safeguard, but that's a bit tricky because it depends on the
    /// session configuration.
    ///
    /// Hopefully, one day we will get an API which allows us to return an error and bypasses `URLProtocol` entirely.
    /// In the mean time, this is a reasonable compromise.
    ///
    internal static func requestForConversionFailure(
      _ url: WebURL, cachePolicy: CachePolicy = .useProtocolCachePolicy, timeoutInterval: TimeInterval = 60.0
    ) -> URLRequest {
      var req = URLRequest(url: URL(string: "invalid")!, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
      req.url = nil
      assert(req.url == nil)
      return req
    }

    /// Creates and initializes a URL request with the given URL, cache policy, and timeout interval.
    ///
    /// The given `url` will be converted to a `Foundation.URL` value and verified for equivalence.
    /// Percent-encoding will only be added as part of that conversion if the `addPercentEncoding` parameter is `true`
    /// (which is the default).
    ///
    /// It is very, very rare that a `WebURL` cannot be converted to a `Foundation.URL` despite adding percent-encoding.
    /// If it does occur, the created request's `url` will be `nil`, and attempts to execute it will, by default,
    /// fail with an `.unsupportedURL` error.
    ///
    /// - parameters:
    ///   - url:                 The URL for the request.
    ///   - addPercentEncoding:  Whether or not percent-encoding may be added to `url` in order to convert it
    ///                          to a `Foundation.URL` value. The default is `true`.
    ///   - cachePolicy:         The cache policy for the request. The default is `useProtocolCachePolicy`.
    ///   - timeoutInterval:     The timeout interval for the request. The default is `60.0`.
    ///                          See the commentary for the `timeoutInterval` for more information on timeout intervals.
    ///
    public init(
      url: WebURL, addPercentEncoding: Bool = true,
      cachePolicy: CachePolicy = .useProtocolCachePolicy, timeoutInterval: TimeInterval = 60.0
    ) {

      // This is not failable, because WebURL -> Foundation.URL conversion failures are exceptionally rare.
      // They can still happen, of course, but they are so uncommon that users should not have to consider
      // that possibility every time they make a URLRequest using a WebURL.
      //
      // The only WebURLs which cannot be converted are:
      //
      // - URLs with opaque paths, if the path contains a forbidden character or fragment component.
      //   This does not matter to http/s, ws/s, ftp or file URLs, as they cannot have opaque paths.
      //
      //   - The WHATWG URL standard allows these URLs to even contain non-percent-encoded spaces (!!!),
      //     e.g. <javascript:alert("hello, world!")>, and encoding them is considered not web-compatible.
      //
      //   - Foundation.URL encodes fragments in these URLs by itself, e.g. <sc:#foo> becomes <sc:%23foo>,
      //     but that seems like a bug. Hopefully it will be fixed one day. https://bugs.swift.org/browse/SR-15381
      //
      // - URLs with domains (i.e. special schemes like http/s), if the domain contains an invalid character.
      //
      //   For example, Foundation does not accept <http://loc{al}host/foo>. Percent-encoding the invalid characters
      //   is awkward because the WHATWG URL Standard technically does not allow it, but we **could** do it
      //   at the string level. If we decided that it preserved equivalence, of course -- who even knows
      //   what "loc{al}host" is supposed to connect to, or what "loc%7Bal%7Dhost" actually connects to?

      if let convertedURL = URL(url, addPercentEncoding: addPercentEncoding) {
        self.init(url: convertedURL, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
      } else {
        self = .requestForConversionFailure(url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
      }
    }
  }

#endif  // canImport(Darwin)

extension URLRequest {

  /// The URL of the request.
  ///
  /// This property returns the request's `url`, converted to its equivalent `WebURL` value.
  /// If the request was not created from a `WebURL` value (for example, if it was created by Foundation
  /// as part of an HTTP redirect), it may be normalized in ways that the URL sent over the wire is not.
  ///
  /// When assigning to this property, the request's `url` is assigned to the equivalent `Foundation.URL`
  /// of the new value.
  ///
  public var webURL: WebURL? {
    get { url.flatMap { WebURL($0) } }
    set { url = newValue.flatMap { URL($0) } }
  }

  /// The main document URL associated with this request.
  ///
  /// This property returns the request's `mainDocumentURL`, converted to its equivalent `WebURL` value.
  /// If the request was not created from a `WebURL` value (for example, if it was created by Foundation
  /// as part of an HTTP redirect), it may be normalized in ways that the URL sent over the wire is not.
  ///
  /// When assigning to this property, the request's `mainDocumentURL` is assigned to the equivalent `Foundation.URL`
  /// of the new value.
  ///
  public var mainDocumentWebURL: WebURL? {
    get { mainDocumentURL.flatMap { WebURL($0) } }
    set { mainDocumentURL = newValue.flatMap { URL($0) } }
  }
}


// --------------------------------
// MARK: - URLResponse
// --------------------------------


extension URLResponse {

  /// The URL for the response.
  ///
  /// This property returns the response's `url`, converted to its equivalent `WebURL` value.
  /// If the request was not created from a `WebURL` value (for example, if it was created by Foundation
  /// as part of an HTTP redirect), it may be normalized in ways that the URL sent over the wire is not.
  ///
  public var webURL: WebURL? {
    url.flatMap { WebURL($0) }
  }
}
