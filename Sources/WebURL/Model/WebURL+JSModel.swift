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
        withMutableStorage(
          { small in small.setScheme(to: utf8).1 },
          { generic in generic.setScheme(to: utf8).1 }
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
    return stringForComponent(.hostname) ?? ""
  }

  public var port: String {
    var string = stringForComponent(.port)
    if !(string?.isEmpty ?? true) {
      let separator = string?.removeFirst()
      assert(separator == ":")
    }
    return string ?? ""
  }

  public var path: String {
    return stringForComponent(.path) ?? ""
  }

  public var query: String {
    let string = stringForComponent(.query)
    guard string != "?" else { return "" }
    return string ?? ""
  }

  public var fragment: String {
    let string = stringForComponent(.fragment)
    guard string != "#" else { return "" }
    return string ?? ""
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
      Query: \(query)
      Fragment: \(fragment)
      CannotBeABaseURL: \(cannotBeABaseURL)
      """
  }
}
