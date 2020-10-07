public struct WebURL {
  var variant: Variant

  init(variant: Variant) {
    self.variant = variant
  }
  
  public init?(_ input: String) {
    var input = input
    guard let url = input.withUTF8({ urlFromBytes($0, baseURL: nil) }) else {
      return nil
    }
    self = url
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

  // Flags used by the parser.

  var _schemeKind: WebURL.Scheme {
    return variant.schemeKind
  }

  var _cannotBeABaseURL: Bool {
    return variant.cannotBeABaseURL
  }
}

// Standard protocols.

extension WebURL: CustomStringConvertible, LosslessStringConvertible, TextOutputStreamable {
  
  public var description: String {
    return variant.entireString
  }
  
  public func write<Target>(to target: inout Target) where Target : TextOutputStream {
    target.write(description)
  }
}

extension WebURL: Equatable, Hashable {
  
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.variant.withEntireString { lhsBuffer in
      rhs.variant.withEntireString { rhsBuffer in
        return (lhsBuffer.baseAddress == rhsBuffer.baseAddress && lhsBuffer.count == rhsBuffer.count) ||
          lhsBuffer.elementsEqual(rhsBuffer)
      }
    }
  }
  
  public func hash(into hasher: inout Hasher) {
    variant.withEntireString { buffer in
      hasher.combine(bytes: UnsafeRawBufferPointer(buffer))
    }
  }
}

extension WebURL: Codable {
  
  public init(from decoder: Decoder) throws {
    let box = try decoder.singleValueContainer()
    guard let decoded = WebURL(try box.decode(String.self)) else {
      throw DecodingError.dataCorruptedError(in: box, debugDescription: "Invalid URL")
    }
    self = decoded
  }
  
  public func encode(to encoder: Encoder) throws {
    var box = encoder.singleValueContainer()
    try box.encode(self.description)
  }
}


// Note: All of these are now dead. To be replaced with a new object model.
// It might be worth having the JS model call through and make any adjustments that it needs,
// to improve test coverage.
extension WebURL {
  
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

