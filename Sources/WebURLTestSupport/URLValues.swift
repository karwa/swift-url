
/// A storage type for the properties exposed in the WHATWG URL model.
///
public struct URLValues: Equatable, Hashable {
  public var href: String
  public var origin: String?
  public var `protocol`: String
  public var username: String
  public var password: String
  public var host: String
  public var hostname: String
  public var port: String
  public var pathname: String
  public var search: String
  public var hash: String
  
  public static var allTestableURLProperties: [(name: String, keyPath: KeyPath<URLValues, String>)] {
    return [
      ("href", \.href),
      // TODO: 'origin' not yet supported by WebURL.
      ("protocol", \.protocol),
      ("username", \.username), ("password", \.password),
      // TODO: 'host' not yet supported by WebURL.
      ("hostname", \.hostname), ("port", \.port),
      ("pathname", \.pathname), ("search", \.search), ("hash", \.hash)
    ]
  }

  public init(
    href: String, origin: String? = nil, protocol: String, username: String, password: String, host: String,
    hostname: String, port: String, pathname: String, search: String, hash: String
  ) {
    self.href = href
    self.origin = origin
    self.protocol = `protocol`
    self.username = username
    self.password = password
    self.host = host
    self.hostname = hostname
    self.port = port
    self.pathname = pathname
    self.search = search
    self.hash = hash
  }
}

import WebURL

extension WebURL.JSModel {
  public var urlValues: URLValues {
    return .init(
      href: href, origin: nil, protocol: scheme,
      username: username, password: password,
      host: "<unsupported>", hostname: hostname, port: port,
      pathname: pathname, search: search, hash: fragment
    )
  }
}


extension URLValues {
  
  public static func diff(_ lhs: URLValues?, _ rhs: URLValues?) -> [KeyPath<URLValues, String>] {
    switch (lhs, rhs) {
    case (.none, .none):                   return []
    case (.some, .none), (.none, .some):   return allTestableURLProperties.map { $0.keyPath }
    case (.some(let lhs), .some(let rhs)): return rhs.unequalURLProperties(comparedWith: lhs)
    }
  }

  func unequalURLProperties(comparedWith other: URLValues) -> [KeyPath<URLValues, String>] {
    var results = [KeyPath<URLValues, String>]()
    for property in Self.allTestableURLProperties {
      if self[keyPath: property.keyPath] != other[keyPath: property.keyPath] {
        results.append(property.keyPath)
      }
    }
    return results
  }
}
