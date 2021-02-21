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

  /// An interface to this URL with the same names and behaviour as the Javascript `URL` type.
  ///
  public var jsModel: JSModel {
    return JSModel(storage: self.storage)
  }

  /// The Javascript `URL` model as described by the [WHATWG URL Specification](https://url.spec.whatwg.org/#url-class) .
  ///
  public struct JSModel {
    var storage: AnyURLStorage

    /// An interface to this URL designed for Swift :)
    ///
    var swiftModel: WebURL {
      return WebURL(storage: self.storage)
    }

    init(storage: AnyURLStorage) {
      self.storage = storage
    }

    public init?(_ input: String, base: String?) {
      if let baseStr = base {
        let _url = WebURL(baseStr)?.join(input)
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

// In-place mutation hack.

extension WebURL.JSModel {

  private mutating func withMutableStorage(
    _ small: (inout URLStorage<GenericURLHeader<UInt8>>) -> AnyURLStorage,
    _ generic: (inout URLStorage<GenericURLHeader<Int>>) -> AnyURLStorage
  ) {
    // We need to go through a bit of a dance in order to get a unique reference to the storage.
    // It's like if you have tape stuck to one hand and try to remove it with the other hand.
    //
    // Basically:
    // 1. Swap our storage to temporarily point to some read-only global, so our only storage reference is
    //    via a local variable.
    // 2. Extract the URLStorage (which is a COW value type) from local variable's payload, and set
    //    the local to also point that read-only global.
    // 3. Hand that extracted storage off to closure (`inout`, but `__consuming` might also work),
    //    which returns a storage object back (possibly the same storage object).
    // 4. We round it all off by assigning that value as our new storage. Phew.
    var localRef = self.storage
    self.storage = _tempStorage
    switch localRef {
    case .generic(var extracted_storage):
      localRef = _tempStorage
      self.storage = generic(&extracted_storage)
    case .small(var extracted_storage):
      localRef = _tempStorage
      self.storage = small(&extracted_storage)
    }
  }
}

extension WebURL.JSModel {

  // Flags.

  var schemeKind: WebURL.SchemeKind {
    return storage.schemeKind
  }

  public var cannotBeABaseURL: Bool {
    return storage.cannotBeABaseURL
  }

  // Components.
  // Note: erasure to empty strings is done to fit the Javascript model for WHATWG tests.

  public var href: String {
    get {
      swiftModel.serialized
    }
    set {
      guard let newURL = WebURL(newValue) else { return }
      self = newURL.jsModel
    }
  }

  public var username: String {
    get {
      swiftModel.username ?? ""
    }
    set {
      var swift = swiftModel
      try? swift.setUsername(to: newValue)
      self = swift.jsModel
    }
  }

  public var password: String {
    get {
      swiftModel.password ?? ""
    }
    set {
      var swift = swiftModel
      try? swift.setPassword(to: newValue)
      self = swift.jsModel
    }
  }

  // Setters for the following components tend to be more complex. They tend to go through the URL parser,
  // which filters tabs and newlines (but won't trim ASCII C0 or spaces),
  // and allows trailing data that just gets silently ignored.
  //
  // The Swift model setters do not filter tabs or newlines, nor do they silently drop any part of the given value,
  // and they may choose to represent non-present values as 'nil' rather than empty strings,
  // but in all other respects they should behave the same.

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
      var swift = swiftModel
      try? swift.setScheme(utf8: trimmedAndFiltered)
      self = swift.jsModel
    }
  }

  public var hostname: String {
    get {
      swiftModel.hostname ?? ""
    }
    set {
      let filtered = ASCII.NewlineAndTabFiltered(newValue.utf8)
      var callback = IgnoreValidationErrors()
      guard let hostnameEnd = findEndOfHostnamePrefix(filtered, scheme: schemeKind, callback: &callback) else {
        return
      }
      var swift = swiftModel
      try? swift.setHostname(utf8: filtered[..<hostnameEnd])
      self = swift.jsModel
    }
  }

  public var port: String {
    get {
      swiftModel.port.map { String($0) } ?? ""
    }
    set {
      let filtered = ASCII.NewlineAndTabFiltered(newValue.utf8)
      let portString = filtered.prefix(while: { ASCII($0)?.isA(\.digits) ?? false })

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

      withMutableStorage(
        { small in small.setPort(to: newPort).0 },
        { generic in generic.setPort(to: newPort).0 }
      )
    }
  }

  public var pathname: String {
    get {
      swiftModel.path ?? ""
    }
    set {
      var stringToInsert = newValue
      stringToInsert.withUTF8 { utf8 in
        var newQuery = Optional(utf8)
        if utf8.isEmpty {
          newQuery = nil
        }
        withMutableStorage(
          { small in small.setPath(to: newQuery, filter: true).1 },
          { generic in generic.setPath(to: newQuery, filter: true).1 }
        )
      }
    }
  }

  public var search: String {
    get {
      let swiftValue = swiftModel.query ?? ""
      if swiftValue.isEmpty {
        return swiftValue
      }
      return "?" + swiftValue
    }
    set {
      var stringToInsert = newValue
      stringToInsert.withUTF8 { utf8 in
        // It is important that these steps happen in this order.
        // - If the new value is empty, the fragment is removed (set to nil)
        // - If the new value starts with a "?", it is dropped.
        // - The remainder gets filtered of particular ASCII whitespace characters.
        var newQuery = Optional(utf8)
        if utf8.isEmpty {
          newQuery = nil
        } else if utf8.first == ASCII.questionMark.codePoint {
          newQuery = UnsafeBufferPointer(rebasing: utf8.dropFirst())
        }
        withMutableStorage(
          { small in small.setQuery(to: newQuery, filter: true) },
          { generic in generic.setQuery(to: newQuery, filter: true) }
        )
      }
    }
  }

  public var fragment: String {
    get {
      let swiftValue = swiftModel.fragment ?? ""
      if swiftValue.isEmpty {
        return swiftValue
      }
      return "#" + swiftValue
    }
    set {
      var stringToInsert = newValue
      stringToInsert.withUTF8 { utf8 in
        // It is important that these steps happen in this order.
        // - If the new value is empty, the fragment is removed (set to nil)
        // - If the new value starts with a "#", it is dropped.
        // - The remainder gets filtered of particular ASCII whitespace characters.
        var newFragment = Optional(utf8)
        if utf8.isEmpty {
          newFragment = nil
        } else if utf8.first == ASCII.numberSign.codePoint {
          newFragment = UnsafeBufferPointer(rebasing: utf8.dropFirst())
        }
        withMutableStorage(
          { small in small.setFragment(to: newFragment, filter: true) },
          { generic in generic.setFragment(to: newFragment, filter: true) }
        )
      }
    }
  }
}

// Standard protocols.

extension WebURL.JSModel: CustomStringConvertible, TextOutputStreamable {

  public var description: String {
    return storage.entireString
  }

  public func write<Target>(to target: inout Target) where Target: TextOutputStream {
    target.write(description)
  }

  /* testable */
  var _debugDescription: String {
    return """
      {
        .href:     \(href)
        .protocol: \(scheme) (\(schemeKind))
        .username: \(username)
        .password: \(password)
        .hostname: \(hostname)
        .port:     \(port)
        .pathname: \(pathname)
        .search:   \(search)
        .hash:     \(fragment)
        .cannotBeABaseURL: \(cannotBeABaseURL)
      }
      """
  }
}

extension WebURL.JSModel: Equatable, Hashable {

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.storage.withEntireString { lhsBuffer in
      rhs.storage.withEntireString { rhsBuffer in
        return (lhsBuffer.baseAddress == rhsBuffer.baseAddress && lhsBuffer.count == rhsBuffer.count)
          || lhsBuffer.elementsEqual(rhsBuffer)
      }
    }
  }

  public func hash(into hasher: inout Hasher) {
    storage.withEntireString { buffer in
      hasher.combine(bytes: UnsafeRawBufferPointer(buffer))
    }
  }
}
