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

extension WebURL {

  /// A read-write view of this URL with the same API as JavaScript's `URL` class.
  ///
  /// This view matches the API of JavaScript's `URL` class as defined by the [WHATWG URL Standard][whatwg-url-class],
  /// and is validated using the `web-platform-tests` suite of cross-browser tests. It is designed to support
  /// developers porting applications from JavaScript, or who have cross JavaScript-Swift codebases.
  ///
  /// We recommend that developers who do not have a strong need for JavaScript's exact API stick to using
  /// `WebURL`'s component properties directly rather than through this view. The differences between `WebURL`
  /// and JavaScript are minimal: a slightly more ergonomic value returned for some components,
  /// and some more predictable edge-case behavior. These differences are documented below.
  ///
  /// This view allows modifying the URL's components, making it simple to isolate areas where the JavaScript
  /// API is required.
  ///
  /// ```swift
  /// // This demonstrates filtering of tabs and newlines,
  /// // which is something JS does but WebURL normally does not do.
  /// var url = WebURL("https://example.com/foo")!
  /// url.jsModel.search = "\t\thello\n"
  /// url.fragment
  /// // ✅ "hello"
  ///
  /// // You can use the JSModel for multiple operations and
  /// // return to the WebURL model when finished.
  /// var jsURL = url.jsModel
  /// // ...(some operations)
  /// return jsURL.swiftModel
  /// ```
  ///
  /// ## Differences Between WebURL and JavaScript
  ///
  /// This view behaves like JavaScript in all of the described situations. When we mention WebURL's behavior,
  /// we are referring to the component properties available directly on the `WebURL` type (not through this view).
  ///
  /// Note that the JavaScript property named "protocol" is named "scheme" in this view,
  /// as it can be awkward to work with a property named "protocol" in Swift.
  ///
  /// ### More Noticeable
  ///
  /// 1. `WebURL` components do not include delimiters.
  ///
  ///    Considering the URL `"http://example.com?foo#bar"`, the components returned by each API would be:
  ///
  ///    | JS Name    | Example | WebURL Name | Example |
  ///    | ---------- | ------- | ----------- | ------- |
  ///    | `protocol` | `http:` | `scheme`    | `http`  |
  ///    | `search`   | `?foo`  | `query`     | `foo`   |
  ///    | `hash`     | `#bar`  | `fragment`  | `bar`   |
  ///
  ///    This difference only applies to the above 3 components; both models do not include delimiters for
  ///    other components. Most consumers of these values are going to immediately drop the delimiter anyway,
  ///    so WebURL just does it for you. Additionally, it matches the behavior of Foundation's `URL` type,
  ///    which makes transitioning code to WebURL a little bit easier.
  ///
  /// ### Adjustments to Edge-Cases
  ///
  /// 1. `WebURL` uses `nil` to signal that a value is not present, rather than an empty string.
  ///
  ///    This is a more accurate description of components which keep their delimiter even when empty.
  ///    For example, consider the following URLs:
  ///
  ///    - `http://example.com/`
  ///    - `http://example.com/?`
  ///
  ///    According to the URL Standard, these URLs are different; however, JavaScript's `search` property returns
  ///    an empty string for both. In fact, these URLs return identical values for _every_ component in JS,
  ///    and yet still the overall URLs compare as not equal to each other. This has some subtle secondary effects,
  ///    such as `url.search = url.search` potentially changing the URL.
  ///
  ///    `WebURL` avoids this by saying that the first URL has a `nil` query (to mean "not present"),
  ///    and the latter has an empty query. This has the nice property that every unique URL has
  ///    a unique combination of URL components.
  ///
  /// 2. `WebURL` does not filter ASCII whitespace characters in component setters.
  ///
  ///    In JavaScript, tabs and newlines are silently filtered when setting a URL component:
  ///
  ///    ```js
  ///    // JavaScript
  ///    url.search = "\t\thello\n";
  ///    url.search; // "hello"
  ///    ```
  ///
  ///    `WebURL` does not; instead, these characters will be percent-encoded as other disallowed characters are.
  ///    URLs are complex enough; why add things?
  ///
  /// 3. `WebURL` does not ignore trailing content when setting a component.
  ///
  ///    Many properties in the JavaScript model do this. It's totally weird, and surely nobody will miss it.
  ///
  ///    ```js
  ///    // JavaScript
  ///    var url      = new URL("https://example.com/");
  ///    url.protocol = "ftp://foobar.org/";
  ///    url.href;
  ///    // "ftp://example.com"
  ///    //  ^^^
  ///    ```
  ///
  ///    This operation would fail with WebURL, because `"ftp://foobar.org/"` is not a valid scheme.
  ///
  /// [whatwg-url-class]: https://url.spec.whatwg.org/#url-class
  ///
  /// ## Topics
  ///
  /// ### Reading and Writing a URL's Components
  ///
  /// - ``WebURL/WebURL/JSModel-swift.struct/scheme``
  /// - ``WebURL/WebURL/JSModel-swift.struct/username``
  /// - ``WebURL/WebURL/JSModel-swift.struct/password``
  /// - ``WebURL/WebURL/JSModel-swift.struct/hostname``
  /// - ``WebURL/WebURL/JSModel-swift.struct/host``
  /// - ``WebURL/WebURL/JSModel-swift.struct/port``
  /// - ``WebURL/WebURL/JSModel-swift.struct/pathname``
  /// - ``WebURL/WebURL/JSModel-swift.struct/search``
  /// - ``WebURL/WebURL/JSModel-swift.struct/hash``
  /// - ``WebURL/WebURL/JSModel-swift.struct/href``
  /// - ``WebURL/WebURL/JSModel-swift.struct/origin``
  ///
  /// ### Returning to WebURL
  ///
  /// - ``WebURL/WebURL/JSModel-swift.struct/swiftModel``
  ///
  /// ### View Type
  ///
  /// - ``WebURL/WebURL/JSModel-swift.struct``
  ///
  public var jsModel: JSModel {
    get {
      JSModel(storage: storage)
    }
    _modify {
      var view = JSModel(storage: storage)
      storage = _tempStorage
      defer { storage = view.storage }
      yield &view
    }
    set {
      storage = newValue.storage
    }
  }

  /// A read-write view of a URL with the same API as JavaScript's `URL` class.
  ///
  /// This view matches the definition of JavaScript's `URL` class in the [URL Standard][whatwg-url-class],
  /// and is validated using the `web-platform-tests` suite of cross-browser tests. It is designed to support
  /// developers porting applications from JavaScript, or who have cross JavaScript-Swift codebases.
  ///
  /// We recommend that developers who do not have a strong need for JavaScript's exact API stick to using
  /// `WebURL` directly rather than through this view. The differences between `WebURL` and JavaScript are
  /// minimal: a slightly more ergonomic value returned for some components, and some more predictable edge-case
  /// behavior.
  ///
  /// To access this interface, use the URL's ``WebURL/jsModel-swift.property`` property.
  ///
  /// ```swift
  /// let url = WebURL("https://example.com/foo?bar#baz")!
  /// url.query          // "foo"  - WebURL property.
  /// url.jsModel.search // "?foo" - JS property.
  /// ```
  ///
  /// > Tip:
  /// > The documentation for this type can be found at: ``WebURL/jsModel-swift.property``.
  ///
  /// [whatwg-url-class]: https://url.spec.whatwg.org/#url-class
  ///
  public struct JSModel {

    internal var storage: URLStorage

    init(storage: URLStorage) {
      self.storage = storage
    }

    /// Constructs a new URL by parsing `string` against the given `base` URL string.
    ///
    /// If `base` is `nil`, this is equivalent to `WebURL(string)`.
    /// Otherwise, it is equivalent to `WebURL(base)?.resolve(string)`.
    ///
    public init?(_ string: String, base: String?) {
      if let baseString = base {
        let _url = WebURL(baseString)?.resolve(string)
        guard let url = _url else { return nil }
        self.init(storage: url.storage)

      } else if let url = WebURL(string) {
        self.init(storage: url.storage)

      } else {
        return nil
      }
    }
  }
}

extension WebURL.JSModel {

  /// The `WebURL` interface to this URL.
  ///
  public var swiftModel: WebURL {
    get {
      WebURL(storage: storage)
    }
    _modify {
      var view = WebURL(storage: storage)
      storage = _tempStorage
      defer { storage = view.storage }
      yield &view
    }
    set {
      storage = newValue.storage
    }
  }
}


// --------------------------------------------
// MARK: - Standard Protocols
// --------------------------------------------


extension WebURL.JSModel: CustomStringConvertible {

  public var description: String {
    swiftModel.serialized()
  }
}

extension WebURL.JSModel: Equatable, Hashable {

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.swiftModel == rhs.swiftModel
  }

  public func hash(into hasher: inout Hasher) {
    swiftModel.hash(into: &hasher)
  }
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension WebURL.JSModel: Sendable {}
#endif


// --------------------------------------------
// MARK: - Components
// --------------------------------------------


// Note: Documentation comments for these properties is copied from Node.js (MIT-licensed).
//       It is not the primary interface for WebURL, so it isn't worth copying the whole thing or writing our own,
//       but it is API and should at least have a brief comment.
//       Node docs: https://nodejs.org/api/url.html#url_class_url

extension WebURL.JSModel {

  /// Gets and sets the serialized URL.
  ///
  public var href: String {
    get {
      swiftModel.serialized()
    }
    set {
      if let newURL = WebURL(newValue) {
        self = newURL.jsModel
      }
    }
  }

  /// Gets the read-only serialization of the URL's origin.
  ///
  public var origin: String {
    swiftModel.origin.serialized
  }

  /// Gets and sets the username portion of the URL.
  ///
  public var username: String {
    get {
      swiftModel.username ?? ""
    }
    set {
      try? swiftModel.setUsername(newValue)
    }
  }

  /// Gets and sets the password portion of the URL.
  ///
  public var password: String {
    get {
      swiftModel.password ?? ""
    }
    set {
      try? swiftModel.setPassword(newValue)
    }
  }

  // Setters for the following components are a bit more complex.
  // In the standard, they tend to go through the URL parser, which filters tabs and newlines
  // (but doesn't trim ASCII C0 or spaces), and allows trailing data that just gets silently ignored.
  //
  // The Swift model setters do not filter tabs or newlines, nor do they silently drop any part of the given value,
  // and they may choose to represent non-present values as 'nil' rather than empty strings,
  // but in all other respects they should behave the same.

  /// Gets and sets the protocol portion of the URL.
  ///
  /// > Note:
  /// > This property is called `protocol` in Javascript.
  ///
  public var scheme: String {
    get {
      swiftModel.scheme + ":"
    }
    set {
      newValue._withContiguousUTF8 { _newValue in
        let newValue = _newValue.boundsChecked
        let trimmedAndFiltered: ASCII.NewlineAndTabFiltered<UnsafeBoundsCheckedBufferPointer<UInt8>>
        if let terminatorIdx = newValue.fastFirstIndex(of: ASCII.colon.codePoint) {
          trimmedAndFiltered = ASCII.NewlineAndTabFiltered(newValue[..<newValue.index(after: terminatorIdx)])
        } else {
          trimmedAndFiltered = ASCII.NewlineAndTabFiltered(newValue[...])
        }
        try? swiftModel.utf8.setScheme(trimmedAndFiltered)
      }
    }
  }

  /// Gets and sets the host name portion of the URL.
  ///
  /// > Tip:
  /// > The key difference between `url.host` and `url.hostname` is that `url.hostname` does not include the port.
  ///
  public var hostname: String {
    get {
      swiftModel.hostname ?? ""
    }
    set {
      newValue._withContiguousUTF8 { newValue in
        let filtered = ASCII.NewlineAndTabFiltered(newValue.boundsChecked)
        var callback = IgnoreValidationErrors()
        let schemeKind = swiftModel.schemeKind
        guard let hostnameEnd = findEndOfHostnamePrefix(filtered, scheme: schemeKind, callback: &callback) else {
          return
        }
        // Unlike other delimiters, including a port causes the entire operation to fail.
        if hostnameEnd < filtered.endIndex, filtered[hostnameEnd] == ASCII.colon.codePoint {
          return
        }
        try? swiftModel.utf8.setHostname(filtered[..<hostnameEnd])
      }
    }
  }

  /// Gets the host portion of the URL.
  ///
  /// > Tip:
  /// > The key difference between `url.host` and `url.hostname` is that `url.hostname` does not include the port.
  ///
  public var host: String {
    guard let hostname = storage.utf8.hostname else { return "" }
    if let port = storage.utf8.port {
      return String(decoding: storage.utf8[hostname.startIndex..<port.endIndex], as: UTF8.self)
    }
    return String(decoding: hostname, as: UTF8.self)
  }

  /// Gets and sets the port portion of the URL.
  ///
  public var port: String {
    get {
      swiftModel.port.map { String($0) } ?? ""
    }
    set {
      let filtered = ASCII.NewlineAndTabFiltered(newValue.utf8)
      let portString = filtered.prefix { ASCII($0)?.isDigit == true }

      var newPort: UInt16? = nil
      if portString.isEmpty {
        // No number => not an error => remove existing port (newPort == nil).
      } else {
        guard let parsedPort = UInt16(String(decoding: portString, as: UTF8.self)) else {
          // Invalid number (e.g. overflow) => error => keep existing port (abort setter).
          return
        }
        newPort = parsedPort
      }
      swiftModel.port = newPort.map { Int($0) }
    }
  }

  /// Gets and sets the path portion of the URL.
  ///
  public var pathname: String {
    get {
      swiftModel.path
    }
    set {
      newValue._withContiguousUTF8 { newValue in
        try? swiftModel.utf8.setPath(ASCII.NewlineAndTabFiltered(newValue.boundsChecked))
      }
    }
  }

  /// Gets and sets the serialized query portion of the URL.
  ///
  public var search: String {
    get {
      let swiftValue = swiftModel.query ?? ""
      if swiftValue.isEmpty {
        return swiftValue
      }
      return "?" + swiftValue
    }
    set {
      guard newValue.isEmpty == false else {
        swiftModel.query = nil
        return
      }
      newValue._withContiguousUTF8 { newValue in
        var newQuery = newValue.boundsChecked
        if newQuery.first == ASCII.questionMark.codePoint {
          newQuery = newQuery.dropFirst()
        }
        try? swiftModel.utf8.setQuery(ASCII.NewlineAndTabFiltered(newQuery))
      }
    }
  }

  /// Gets and sets the fragment portion of the URL.
  ///
  public var hash: String {
    get {
      let swiftValue = swiftModel.fragment ?? ""
      if swiftValue.isEmpty {
        return swiftValue
      }
      return "#" + swiftValue
    }
    set {
      guard newValue.isEmpty == false else {
        swiftModel.fragment = nil
        return
      }
      newValue._withContiguousUTF8 { newValue in
        var newFragment = newValue.boundsChecked
        if newFragment.first == ASCII.numberSign.codePoint {
          newFragment = newFragment.dropFirst()
        }
        try? swiftModel.utf8.setFragment(ASCII.NewlineAndTabFiltered(newFragment))
      }
    }
  }
}
