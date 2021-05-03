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

import WebURL

/// A property exposed by the WHATWG URL model.
///
public enum URLModelProperty: String, CaseIterable, Equatable, Hashable, CodingKey {
  case href = "href"
  case origin = "origin"
  case `protocol` = "protocol"
  case username = "username"
  case password = "password"
  case host = "host"
  case hostname = "hostname"
  case port = "port"
  case pathname = "pathname"
  case search = "search"
  case hash = "hash"

  public var name: String {
    stringValue
  }
}

/// A storage type for the properties exposed in the WHATWG URL model.
///
public struct URLValues: Equatable, Hashable {
  private var href: String
  private var `protocol`: String
  private var username: String
  private var password: String
  private var host: String
  private var hostname: String
  private var port: String
  private var pathname: String
  private var search: String
  private var hash: String
  // Unfortunately, the WPT constructor tests often omit the origin 😐.
  // "The origin key may be missing. In that case, the API’s origin attribute is not tested."
  public var origin: String?

  public subscript(property: URLModelProperty) -> String? {
    get {
      switch property {
      case .href: return href
      case .origin: return origin
      case .protocol: return self.protocol
      case .username: return username
      case .password: return password
      case .host: return host
      case .hostname: return hostname
      case .port: return port
      case .pathname: return pathname
      case .search: return search
      case .hash: return hash
      }
    }
  }

  public init(
    href: String, origin: String?, protocol: String, username: String, password: String, host: String,
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

extension URLValues: CustomStringConvertible {

  public var description: String {
    return """
      {
        .href:     \(href)
        .origin:   \(origin ?? "<not present>")
        .protocol: \(`protocol`)
        .username: \(username)
        .password: \(password)
        .host:     \(host)
        .hostname: \(hostname)
        .port:     \(port)
        .pathname: \(pathname)
        .search:   \(search)
        .hash:     \(hash)
      }
      """
  }
}


extension WebURL.JSModel {
  public var urlValues: URLValues {
    return .init(
      href: href, origin: origin, protocol: scheme,
      username: username, password: password,
      host: host, hostname: hostname, port: port,
      pathname: pathname, search: search, hash: hash
    )
  }
}


extension URLValues {

  public static func diff(_ lhs: URLValues?, _ rhs: URLValues?) -> [URLModelProperty] {
    switch (lhs, rhs) {
    case (.none, .none): return []
    case (.some, .none), (.none, .some): return URLModelProperty.allCases
    case (.some(let lhs), .some(let rhs)): return rhs.allMismatchingURLProperties(comparedWith: lhs)
    }
  }

  /// The properties which must always be present, and always be tested.
  private static var minimumPropertiesToDiff: [URLModelProperty] {
    return [
      .href,
      .protocol,
      .username, .password,
      .hostname, .port, .host,
      .pathname, .search, .hash,
    ]
  }

  func allMismatchingURLProperties(comparedWith other: URLValues) -> [URLModelProperty] {
    var results = [URLModelProperty]()
    for property in Self.minimumPropertiesToDiff {
      if self[property] != other[property] {
        results.append(property)
      }
    }
    if let origin = self.origin, let otherOrigin = other.origin, origin != otherOrigin {
      results.append(.origin)
    }
    return results
  }
}
