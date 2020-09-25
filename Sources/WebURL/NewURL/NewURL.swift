
public struct NewURL {
  var variant: Variant
  
  init(variant: Variant) {
    self.variant = variant
  }
  
  public init?(_ input: String, base: String?) {
    var baseURL: NewURL?
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

extension NewURL {
  
  enum Component {
    case scheme, username, password, hostname, port, path, query, fragment
  }
  
  enum Variant {
    case small(ArrayWithInlineHeader<GenericURLHeader<UInt8>, UInt8>)
    case generic(ArrayWithInlineHeader<GenericURLHeader<Int>, UInt8>)
  
    var schemeKind: NewURL.Scheme {
      switch self {
      case .small(let storage): return storage.header.schemeKind
      case .generic(let storage): return storage.header.schemeKind
      }
    }
    
    var cannotBeABaseURL: Bool {
      switch self {
      case .small(let storage): return storage.header.cannotBeABaseURL
      case .generic(let storage): return storage.header.cannotBeABaseURL
      }
    }
    
    var entireString: String {
      switch self {
      case .small(let storage): return storage.asUTF8String()
      case .generic(let storage): return storage.asUTF8String()
      }
    }
    
    func withComponentBytes<T>(_ component: Component, _ block: (UnsafeBufferPointer<UInt8>?) -> T) -> T {
      switch self {
      case .small(let storage):
        guard let range = storage.header.rangeOfComponent(component) else { return block(nil) }
        return storage.withElements(range: Range(uncheckedBounds: (Int(range.lowerBound), Int(range.upperBound)))) { buffer in block(buffer) }
      case .generic(let storage):
        guard let range = storage.header.rangeOfComponent(component) else { return block(nil) }
        return storage.withElements(range: range) { buffer in block(buffer) }
      }
    }
    
    func withAllAuthorityComponentBytes<T>(_ block: (
      _ authorityString: UnsafeBufferPointer<UInt8>?,
      _ usernameLength: Int,
      _ passwordLength: Int,
      _ hostnameLength: Int,
      _ portLength: Int
    )->T) -> T {
      switch self {
      case .small(let storage):
        guard let range = storage.header.rangeOfAuthorityString else { return block(nil, 0, 0, 0, 0) }
        return storage.withElements(range: Range(uncheckedBounds: (Int(range.lowerBound), Int(range.upperBound)))) { buffer in
          block(
            buffer,
            Int(storage.header.usernameLength),
            Int(storage.header.passwordLength),
            Int(storage.header.hostnameLength),
            Int(storage.header.portLength)
          )
        }
      case .generic(let storage):
        guard let range = storage.header.rangeOfAuthorityString else { return block(nil, 0, 0, 0, 0) }
        return storage.withElements(range: range) { buffer in
          block(
            buffer,
            storage.header.usernameLength,
            storage.header.passwordLength,
            storage.header.hostnameLength,
            storage.header.portLength
          )
        }
      }
    }
  }
    
  // Flags.

  var schemeKind: NewURL.Scheme {
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

extension NewURL: CustomStringConvertible {
  
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
