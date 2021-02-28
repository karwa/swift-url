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

/// A storage type for the properties exposed in the WHATWG URL model.
///
public struct URLValues: Equatable, Hashable {
  public var href: String
  public var `protocol`: String
  public var username: String
  public var password: String
  public var host: String
  public var hostname: String
  public var port: String
  public var pathname: String
  public var search: String
  public var hash: String

  // Unfortunately, the WPT constructor tests often omit the origin 😐.
  // "The origin key may be missing. In that case, the API’s origin attribute is not tested."
  public var origin: String?

  public static var allProperties: [(name: String, keyPath: PartialKeyPath<URLValues>)] {
    var result = [(String, PartialKeyPath<URLValues>)]()
    result.append(("href", \URLValues.href))
    result.append(("origin", \URLValues.origin))
    result.append(contentsOf: [
      ("protocol", \URLValues.protocol),
      ("username", \URLValues.username), ("password", \URLValues.password),
      ("hostname", \URLValues.hostname), ("port", \URLValues.port),
      ("pathname", \URLValues.pathname), ("search", \URLValues.search), ("hash", \URLValues.hash),
    ])

    return result
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
      host: "<unsupported>", hostname: hostname, port: port,
      pathname: pathname, search: search, hash: fragment
    )
  }
}


extension URLValues {

  /// The properties which must always be present, and always be tested.
  private static var requiredProperties: [KeyPath<URLValues, String>] {
    return [
      \.href,
      \.protocol,
      \.username, \.password,
      // TODO: 'host' not yet supported by WebURL.
      \.hostname, \.port,
      \.pathname, \.search, \.hash,
    ]
  }

  public static func diff(_ lhs: URLValues?, _ rhs: URLValues?) -> [PartialKeyPath<URLValues>] {
    switch (lhs, rhs) {
    case (.none, .none): return []
    case (.some, .none), (.none, .some): return requiredProperties
    case (.some(let lhs), .some(let rhs)): return rhs.allMismatchingURLProperties(comparedWith: lhs)
    }
  }

  func allMismatchingURLProperties(comparedWith other: URLValues) -> [PartialKeyPath<URLValues>] {
    var results = [PartialKeyPath<URLValues>]()
    for property in Self.requiredProperties {
      if self[keyPath: property] != other[keyPath: property] {
        results.append(property)
      }
    }
    if let origin = self.origin, let otherOrigin = other.origin, origin != otherOrigin {
      results.append(\URLValues.origin)
    }
    return results
  }
}
