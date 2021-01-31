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
  }
}

// In-place mutation hack.

private let _tempStorage = AnyURLStorage(
  URLStorage<GenericURLHeader<UInt8>>(
    count: 0, structure: .init(), initializingCodeUnitsWith: { _ in return 0 }
  )!
)

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
      return storage.entireString
    }
    set {
      guard let newURL = WebURL(newValue) else { return }
      self = newURL.jsModel
    }
  }

  private func stringForComponent(_ component: WebURL.Component) -> String? {
    return storage.withComponentBytes(component) { maybeBuffer in
      return maybeBuffer.map { buffer in String(decoding: buffer, as: UTF8.self) }
    }
  }

  public var scheme: String {
    get {
      return stringForComponent(.scheme)!
    }
    set {
      var stringToInsert = newValue
      stringToInsert.withUTF8 { utf8 in
        // URLStorage's setter requires that the ":", if present, be the last character.
        // The JS model's setter succeeds even if the ":" is not the last character,
        // but everything after the ":" gets silently dropped.
        let newSchemeBytes = UnsafeBufferPointer(rebasing: utf8.prefix(while: { $0 != ASCII.colon.codePoint }))
        withMutableStorage(
          { small in small.setScheme(to: newSchemeBytes).0 },
          { generic in generic.setScheme(to: newSchemeBytes).0 }
        )
      }
    }
  }

  public var username: String {
    get {
      return stringForComponent(.username) ?? ""
    }
    set {
      var stringToInsert = newValue
      stringToInsert.withUTF8 { utf8 in
        withMutableStorage(
          { small in small.setUsername(to: utf8).0 },
          { generic in generic.setUsername(to: utf8).0 }
        )
      }
    }
  }

  public var password: String {
    get {
      var string = stringForComponent(.password)
      if !(string?.isEmpty ?? true) {
        let separator = string?.removeFirst()
        assert(separator == ":")
      }
      return string ?? ""
    }
    set {
      var stringToInsert = newValue
      stringToInsert.withUTF8 { utf8 in
        withMutableStorage(
          { small in small.setPassword(to: utf8).0 },
          { generic in generic.setPassword(to: utf8).0 }
        )
      }
    }
  }

  public var hostname: String {
    get {
      return stringForComponent(.hostname) ?? ""
    }
    set {
      var stringToInsert = newValue
      stringToInsert.withUTF8 { utf8 in
        var callback = IgnoreValidationErrors()
        guard let hostnameEnd = findEndOfHostnamePrefix(utf8, scheme: schemeKind, callback: &callback) else {
          return
        }
        let newHostname = utf8[..<hostnameEnd]
        withMutableStorage(
          { small in small.setHostname(to: newHostname, filter: true).0 },
          { generic in generic.setHostname(to: newHostname, filter: true).0 }
        )
      }
    }
  }

  public var port: String {
    get {
      var string = stringForComponent(.port)
      if !(string?.isEmpty ?? true) {
        let separator = string?.removeFirst()
        assert(separator == ":")
      }
      return string ?? ""
    }
    set {
      var stringToInsert = newValue
      stringToInsert.withUTF8 { utf8 in
        // The JS model allows non-numeric junk to be attached to the end of the string,
        // (e.g. "8080stuff" sets port to 8080).
        let portString = utf8.prefix(while: { ASCII($0)?.isA(\.digits) ?? false })
        // - No number => not an error => remove existing port.
        // - Invalid number (e.g. overflow) => error => keep existing port.
        var newPort: UInt16? = nil
        if portString.isEmpty == false {
          guard let parsedPort = UInt16(String(decoding: portString, as: UTF8.self)) else {
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
  }

  public var pathname: String {
    get {
      return stringForComponent(.path) ?? ""
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
      let string = stringForComponent(.query)
      guard string != "?" else { return "" }
      return string ?? ""
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
      let string = stringForComponent(.fragment)
      guard string != "#" else { return "" }
      return string ?? ""
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
      URL Constructor output:

      Href: \(href)

      Scheme: \(scheme) (\(schemeKind))
      Username: \(username)
      Password: \(password)
      Hostname: \(hostname)
      Port: \(port)
      Path: \(pathname)
      Query: \(search)
      Fragment: \(fragment)
      CannotBeABaseURL: \(cannotBeABaseURL)
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
