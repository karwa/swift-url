public struct WebURL {
  var variant: Variant

  init(variant: Variant) {
    self.variant = variant
  }

  public init?(_ input: String, base: String?) {
    var baseURL: WebURL?
    var input = input
    if var baseString = base {
      baseURL = baseString.withUTF8 { urlFromBytes($0, baseURL: nil) }
      guard baseURL != nil else { return nil }
    }
    guard let url = input.withUTF8({ urlFromBytes($0, baseURL: baseURL) }) else {
      return nil
    }
    self = url
  }
}

extension WebURL {

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
    return variant.entireString
  }

  func stringForComponent(_ component: Component) -> String? {
    return variant.withComponentBytes(component) { maybeBuffer in
      return maybeBuffer.map { buffer in String(decoding: buffer, as: UTF8.self) }
    }
  }

  public var scheme: String {
    return stringForComponent(.scheme)!
  }

  public var username: String {
    return stringForComponent(.username) ?? ""
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

extension WebURL: CustomStringConvertible {

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
