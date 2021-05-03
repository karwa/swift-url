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

  /// An interface to this URL whose properties have the same behaviour as the JavaScript `URL` class described in the [URL Standard][whatwg-url-class].
  ///
  /// The other APIs exposed by `WebURL` are preferred over this interface, as they are designed to better match the expectations of Swift developers.
  /// JavaScript is JavaScript, and what is useful or expected functionality in that language may be undesirable and surprising in contexts where Swift is used.
  /// It is also subject to legacy and browser interoperability considerations which do not apply to the `WebURL` API.
  ///
  /// The primary purpose of this API is to facilitate testing (this API is tested directly against the common web-platform-tests used by major browsers to
  /// ensure compliance with the standard), and to aid developers porting applications from JavaScript or other languages, or interoperating with them,
  /// since this functionality exposed by this interface matches the JavaScript `URL` class.
  ///
  /// The main differences between the Swift `WebURL` API and the JavaScript `URL` class are:
  ///
  /// - `WebURL` uses `nil` to represent not-present values, rather than using empty strings.
  ///
  ///   This can be a more accurate description of components which keep their delimiter even when empty.
  ///   For example, in JavaScript, the URLs "http://example.com/" and "http://example.com/?" both return an empty string for the `search` property,
  ///   even though the "?" query delimiter is present in one of the strings and not in the other. This has secondary effects, such as
  ///   `url.search = url.search` potentially changing the serialized URL string. `WebURL` models the former as `nil` (to mean "not present"),
  ///   and the latter as an empty string, to more accurately describe the structure of the URL. URLs are confusing and complex enough.
  ///
  /// - `WebURL` does not include delimiters in its components.
  ///
  ///    For example, the query string's leading "?" is part of the JavaScript URL class's `.search` property, but _not_ part of `WebURL`'s `.query` property.
  ///    We assume that most consumers of the query or fragment strings are going to drop this delimiter as the first thing that they do, and it also happens
  ///    to match the behaviour of Foundation's `URL` type.
  ///
  ///    For setters, JavaScript also drops a leading "?" or "#" delimiter when setting the `search` or `hash`. `WebURL` does not - the value you provide
  ///    is the value that will be set, with percent-encoding if necessary to make it work.
  ///
  ///    Note that this only applies to 3 components, all of which have different names between JavaScript's URL class and `WebURL`
  ///    (`protocol` vs `scheme`, `search` vs `query`, `hash` vs `fragment`).
  ///
  /// - `WebURL` does not filter ASCII whitespace characters in component setters.
  ///
  ///    In JavaScript, you can set `url.search = "\t\thello\n"`, and the tabs and newlines will be silently removed.
  ///    `WebURL` percent-encodes those characters, like it does for other disallowed characters, so they are maintained in the component's value.
  ///
  /// - `WebURL` does not ignore trailing content when setting a component.
  ///
  ///    In the following example, JavaScript's `URL` class finds a hostname at the start of the given new value - but the new value also includes a path and query.
  ///    JavaScript detects these, but silently drops them while succesfully changing the hostname. This happens for many (but not all) of the setters in the
  ///    JavaScript model.
  ///
  ///    ```javascript
  ///    var url = new URL("http://example.com/hello/world?weather=sunny");
  ///    url.hostname = "test.com/some/path?query";
  ///    url.href; // "http://test.com/hello/world?weather=sunny"
  ///    ```
  ///
  ///    Continuing with the theme of `WebURL` component setters being stricter about setting precisely the string that you give them, this operation would
  ///    fail if setting `WebURL.hostname`, as "/" is a forbidden host code-point.
  ///
  /// If these deviations sound pretty reasonable to you, and you do not have a compelling need for something which exactly matches the JavaScript model,
  /// use the `WebURL` interface instead.
  ///
  /// [whatwg-url-class]: https://url.spec.whatwg.org/#url-class
  ///
  public struct JSModel {

    internal var storage: AnyURLStorage

    init(storage: AnyURLStorage) {
      self.storage = storage
    }

    /// Constructs a new URL by parsing `string` against the given `base` URL string.
    ///
    /// If `base` is `nil`, this is equivalent to `WebURL(string)`. Otherwise, it is equivalent to `WebURL(base)?.resolve(string)`.
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

extension WebURL {

  /// An interface to this URL whose properties have the same behaviour as the JavaScript `URL` class described in the [URL Standard][whatwg-url-class].
  ///
  /// See the documentation for the `WebURL.JSModel` type for more information.
  ///
  /// [whatwg-url-class]: https://url.spec.whatwg.org/#url-class
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

  /// The `WebURL` interface to this URL, with properties and functionality tailored to Swift developers.
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

  // Setters for the following components are a bit more complex.
  // In the standard, they tend to go through the URL parser, which filters tabs and newlines
  // (but doesn't trim ASCII C0 or spaces), and allows trailing data that just gets silently ignored.
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

  /// Gets and sets the host name portion of the URL.
  /// The key difference between `url.host` and `url.hostname` is that `url.hostname` does not include the port.
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

  /// Gets the host portion of the URL.
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
      try? swiftModel.utf8.setPath(ASCII.NewlineAndTabFiltered(newValue.utf8))
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
      var newQuery = newValue[...]
      if newValue.first?.asciiValue == ASCII.questionMark.codePoint {
        newQuery = newValue.dropFirst()
      }
      swiftModel.utf8.setQuery(ASCII.NewlineAndTabFiltered(newQuery.utf8))
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
      var newFragment = newValue[...]
      if newValue.first?.asciiValue == ASCII.numberSign.codePoint {
        newFragment = newValue.dropFirst()
      }
      swiftModel.utf8.setFragment(ASCII.NewlineAndTabFiltered(newFragment.utf8))
    }
  }
}
