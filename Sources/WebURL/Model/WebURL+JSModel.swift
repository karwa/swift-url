// Javascript-y object model.
// Documentation comments adapted from Mozilla (https://developer.mozilla.org/en-US/docs/Web/API/URL)

extension WebURL {

  var jsModel: JSModel {
    return JSModel(variant: self.variant)
  }

  /// The `WebURL` interface is used to parse, construct, normalize, and encode URLs.
  ///
  /// It works by providing properties which allow you to easily read and modify the components of a URL.
  /// You normally create a new URL object by specifying the URL as a string when calling its initializer,
  /// or by providing a relative URL and a base URL.
  /// You can then easily read the parsed components of the URL or make changes to the URL.
  ///
  /// The parser and API are designed according to the WHATWG specification (https://url.spec.whatwg.org/)
  /// as it was on 14.06.2020. Therefore, it should match the expectations of web developers and more accurately reflect
  /// the kinds of URLs a browser will accept or reject.
  ///
  public struct JSModel {
    var variant: AnyURLStorage

    var swiftModel: WebURL {
      return WebURL(variant: self.variant)
    }
  }
}

// In-place mutations.

fileprivate let _tempStorage = AnyURLStorage(
  URLStorage<GenericURLHeader<UInt8>>(
    count: 0, structure: .init(), initializingCodeUnitsWith: { _ in return 0 }
  )!
)

extension WebURL.JSModel {
  
  mutating func withMutableStorage(
    _ small: (inout URLStorage<GenericURLHeader<UInt8>>)->AnyURLStorage,
    _ generic: (inout URLStorage<GenericURLHeader<Int>>)->AnyURLStorage
  ) {
    // We need to go through a bit of a dance in order to get a unique reference to the storage.
    //
    // Basically: swap the enum to point to some read-only storage, then extract the URLStorage (which is a value)
    // from our local variable, then set the local variable to also point to read-only storage.
    var localRef = self.variant
    self.variant = _tempStorage
    switch localRef {
    case .generic(var storage):
      localRef = _tempStorage
      self.variant = generic(&storage)
    case .small(var storage):
      localRef = _tempStorage
      self.variant = small(&storage)
    }
  }
}

extension WebURL.JSModel {

  // Flags.

  var schemeKind: WebURL.Scheme {
    return variant.schemeKind
  }

  public var cannotBeABaseURL: Bool {
    return variant.cannotBeABaseURL
  }

  // Components.
  // Note: erasure to empty strings is done to fit the Javascript model for WHATWG tests.

  public var href: String {
    get {
      return variant.entireString
    }
    set {
      guard let newURL = WebURL(newValue) else { return }
      self = newURL.jsModel
    }
  }

  func stringForComponent(_ component: WebURL.Component) -> String? {
    return variant.withComponentBytes(component) { maybeBuffer in
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
          { small in small.setScheme(to: newSchemeBytes).1 },
          { generic in generic.setScheme(to: newSchemeBytes).1 }
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
          { small in small.setUsername(to: utf8).1 },
          { generic in generic.setUsername(to: utf8).1 }
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
          { small in small.setPassword(to: utf8).1 },
          { generic in generic.setPassword(to: utf8).1 }
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
          { small in small.setHostname(to: newHostname, filter: true).1 },
          { generic in generic.setHostname(to: newHostname, filter: true).1 }
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
          { small in small.setPort(to: newPort).1 },
          { generic in generic.setPort(to: newPort).1 }
        )
      }
    }
  }

  public var path: String {
    return stringForComponent(.path) ?? ""
  }

  public var search: String {
    get {
      let string = stringForComponent(.query)
      guard string != "?" else { return "" }
      return string ?? ""
    }
//    set {
//      var stringToInsert = newValue
//      stringToInsert.withUTF8 { utf8 in
//        withMutableStorage(
//          { small in small.setQuery(to: utf8, filter: true).1 },
//          { generic in generic.setQuery(to: utf8, filter: true).1 }
//        )
//      }
//    }
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
          { small in small.setFragment(to: newFragment, filter: true).1 },
          { generic in generic.setFragment(to: newFragment, filter: true).1 }
        )
      }
    }
  }
}

extension WebURL.JSModel: CustomStringConvertible {

  public var description: String {
    return
      """
      URL Constructor output:

      Href: \(href)

      Scheme: \(scheme) (\(schemeKind))
      Username: \(username)
      Password: \(password)
      Hostname: \(hostname)
      Port: \(port)
      Path: \(path)
      Query: \(search)
      Fragment: \(fragment)
      CannotBeABaseURL: \(cannotBeABaseURL)
      """
  }
}
