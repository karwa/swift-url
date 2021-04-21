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

  /// An interface to this URL whose properties have the same behaviour as the JavaScript `URL` class described in the [URL Standard][whatwg-js-type].
  ///
  /// - seealso: `WebURL.jsModel`
  ///
  /// [whatwg-js-type]: https://url.spec.whatwg.org/#url-class
  ///
  public struct JSModel {

    internal var storage: AnyURLStorage

    init(storage: AnyURLStorage) {
      self.storage = storage
    }

    public init?(_ input: String, base: String?) {
      if let baseStr = base {
        let _url = WebURL(baseStr)?.resolve(input)
        guard let url = _url else { return nil }
        self.init(storage: url.storage)

      } else if let url = WebURL(input) {
        self.init(storage: url.storage)

      } else {
        return nil
      }
    }
  }
}

extension WebURL {

  /// An interface to this URL whose properties have the same behaviour as the JavaScript `URL` class described in the [URL Standard][whatwg-js-type].
  ///
  /// Use of this interface should be considered carefully; the other APIs exposed by `WebURL` are designed as a better fit for Swift developers.
  /// The primary purpose of this API is to facilitate testing (this API is tested directly against the common web-platform-tests used by major browsers to
  /// ensure standards compliance), and to aid developers porting applications from JavaScript or other languages.
  ///
  /// The main differences between the Swift `WebURL` API and the JavaScript `URL` class are:
  ///
  /// - `WebURL` uses `nil` to represent not-present values, rather than empty strings.
  ///   This can be a more accurate description of a component which may be the empty string.
  ///
  /// - `WebURL` does not include delimiters in its components.
  ///    For example, the leading "?" of the query string is not part of the string returned by `WebURL.query`, but it _is_ part of `URL.search` in JS.
  ///
  /// - If modifying a component of a parsed URL and the new value contains ASCII whitespace, the JavaScript class will filter (ignore) those characters.
  ///   `WebURL` does not; if the new value contains whitespace, it will be percent-encoded as other disallowed characters are.
  ///
  /// - `WebURL` does not ignore trailing content when setting a component.
  ///    In this example, JavaScript's `URL` class finds a hostname at the start of the given new value, but silently drops the path and query which it also contains:
  ///    ```
  ///    var url = new URL("http://example.com/");
  ///    url.hostname = "test.com/some/path?query";
  ///    url.href; // "http://test.com/"
  ///    ```
  ///    This example would fail with `WebURL`.
  ///
  /// [whatwg-js-type]: https://url.spec.whatwg.org/#url-class
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
}

extension WebURL.JSModel {

  /// The `WebURL` interface to this URL, with properties and functionality designed for Swift developers.
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
    swiftModel.serialized
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
      swiftModel.serialized
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

  // Setters for the following components tend to be more complex. They tend to go through the URL parser,
  // which filters tabs and newlines (but doesn't trim ASCII C0 or spaces),
  // and allows trailing data that just gets silently ignored.
  //
  // The Swift model setters do not filter tabs or newlines, nor do they silently drop any part of the given value,
  // and they may choose to represent non-present values as 'nil' rather than empty strings,
  // but in all other respects they should behave the same.

  /// Gets and sets the protocol portion of the URL.
  ///
  ///  - Note: This property is called `protocol` in Javascript.
  ///
  public var scheme: String {
    get {
      swiftModel.scheme + ":"
    }
    set {
      let trimmedAndFiltered: ASCII.NewlineAndTabFiltered<Substring.UTF8View>
      if let terminatorIdx = newValue.firstIndex(of: ":") {
        trimmedAndFiltered = ASCII.NewlineAndTabFiltered(newValue[..<newValue.index(after: terminatorIdx)].utf8)
      } else {
        trimmedAndFiltered = ASCII.NewlineAndTabFiltered(newValue[...].utf8)
      }
      try? swiftModel.utf8.setScheme(trimmedAndFiltered)
    }
  }

  /// Gets and sets the host name portion of the URL. Does not include the port.
  ///
  public var hostname: String {
    get {
      swiftModel.hostname ?? ""
    }
    set {
      let filtered = ASCII.NewlineAndTabFiltered(newValue.utf8)
      var callback = IgnoreValidationErrors()
      let schemeKind = swiftModel.schemeKind
      guard let hostnameEnd = findEndOfHostnamePrefix(filtered, scheme: schemeKind, callback: &callback) else {
        return
      }
      try? swiftModel.utf8.setHostname(filtered[..<hostnameEnd])
    }
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
      try? swiftModel.utf8.setPath(ASCII.NewlineAndTabFiltered(newValue.utf8))
    }
  }

  /// The `search` property consists of the entire "query string" portion of the URL, including the leading ASCII question mark (?) character.
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
      var newQuery = newValue[...]
      if newValue.first?.asciiValue == ASCII.questionMark.codePoint {
        newQuery = newValue.dropFirst()
      }
      swiftModel.utf8.setQuery(ASCII.NewlineAndTabFiltered(newQuery.utf8))
    }
  }

  /// Gets and sets the fragment portion of the URL.
  ///
  ///  - Note: This property is called `hash` in Javascript.
  ///
  public var fragment: String {
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
      var newFragment = newValue[...]
      if newValue.first?.asciiValue == ASCII.numberSign.codePoint {
        newFragment = newValue.dropFirst()
      }
      swiftModel.utf8.setFragment(ASCII.NewlineAndTabFiltered(newFragment.utf8))
    }
  }
}
