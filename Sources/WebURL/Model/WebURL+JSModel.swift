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
    return stringForComponent(.scheme)!
  }

  public var username: String {
    get {
    	return stringForComponent(.username) ?? ""
    }
    set {
      // TODO: Switch the storage with something so we get a unique reference.
      switch variant {
      case .generic(var storage):
        var stringToInsert = newValue
        self.variant = stringToInsert.withUTF8 { utf8 in
          storage.replaceUsername(with: utf8).1
        }
      case .small(var storage):
        var stringToInsert = newValue
        self.variant = stringToInsert.withUTF8 { utf8 in
          storage.replaceUsername(with: utf8).1
        }
      }
    }
  }

  public var password: String {
    var string = stringForComponent(.password)
    if !(string?.isEmpty ?? true) {
      let separator = string?.removeFirst()
      assert(separator == ":")
    }
    return string ?? ""
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
