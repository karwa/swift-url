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

import Foundation
import WebURL

// -----------------------------------------------------
// MARK: - Foundation.URL - WebURL Semantic Equivalence
// -----------------------------------------------------
//
// The `checkSemanticEquivalence` function is used by all unit tests and fuzz tests
// to judge whether the result of Foundation <-> WebURL conversion is an accurate
// representation of the source URL. It is our core definition of what it means
// for 2 URLs to be equivalent.
//
// -----------------------------------------------------


/// The ways in which the interpretation of a URL string may differ.
///
public enum URLEquivalenceFailure {
  case differentSchemes
  case differentUsernames
  case differentPasswords
  case differentHostnames
  case differentPorts
  case differentPaths
  case differentQuerys
  case differentFragments
  case failuedToDetectIPv6
  case failuedToDetectIPv4
}

/// Checks that the given URLs are semantically equivalent.
///
/// This function assumes the Foundation value is the source, as it is generally stricter and does
/// not normalize components, and checks each component in the WebURL representation is a valid interpretation
/// of Foundation's component.
///
public func checkSemanticEquivalence(_ fndURL: URL, _ webURL: WebURL) -> Set<URLEquivalenceFailure> {
  var failures = Set<URLEquivalenceFailure>()
  checkSemanticEquivalence(fndURL, webURL, failures: &failures)
  return failures
}

/// Checks that the given URLs are semantically equivalent.
///
/// This function assumes the Foundation value is the source, as it is generally stricter and does
/// not normalize components, and checks each component in the WebURL representation is a valid interpretation
/// of Foundation's component.
///
public func checkSemanticEquivalence(_ srcURL: URL, _ webURL: WebURL, failures: inout Set<URLEquivalenceFailure>) {

  let srcComponents = URLComponents(url: srcURL, resolvingAgainstBaseURL: true)

  scheme: do {
    // URL.scheme preserves case, WebURL.scheme is lowercased.
    // It is safe to consider these equivalent.
    if srcURL.scheme?.lowercased() != webURL.scheme {
      failures.insert(.differentSchemes)
    }
  }

  username: do {
    if let srcUsername = srcURL.user, !srcUsername.isEmpty {
      // URL.user is percent-decoded, WebURL.username is not. Check decoded equivalence.
      if srcUsername != webURL.username?.percentDecoded() { failures.insert(.differentUsernames) }
    } else {
      // WebURL.username normalizes empty usernames to nil.
      if webURL.username != nil { failures.insert(.differentUsernames) }
    }
  }

  password: do {
    if let srcPasswd = srcURL.password, !srcPasswd.isEmpty {
      // URL.password is not percent-decoded, but the encode-sets may differ. Check decoded equivalence.
      if srcPasswd.percentDecoded() != webURL.password?.percentDecoded() { failures.insert(.differentPasswords) }
    } else {
      // WebURL.password normalizes empty passwords to nil.
      if webURL.password != nil { failures.insert(.differentUsernames) }
    }
  }

  hostname: do {
    // If URLComponents.percentEncodedHost returns 'nil', that could mean either an empty or not-present hostname.
    // Note that URLComponents sometimes inserts empty hosts, so check URL.host as well.
    guard let srcHost = srcComponents?.percentEncodedHost, srcURL.host != nil else {
      guard webURL.hostname == nil || webURL.hostname?.isEmpty == true else {
        failures.insert(.differentHostnames)
        break hostname
      }
      break hostname
    }

    // If the host contains an IPv6 address, rewriting it in canonical form preserves semantic equivalence.
    if srcHost.first == "[", srcHost.last == "]", let srcIP = IPv6Address(srcHost.dropFirst().dropLast()) {

      guard case .ipv6Address(let webURLIP) = webURL.host else {
        failures.insert(.failuedToDetectIPv6)
        break hostname
      }
      guard srcIP == webURLIP else {
        failures.insert(.differentHostnames)
        break hostname
      }

      // If the host contains an IPv4 address, rewriting it in canonical form preserves semantic equivalence.
    } else if webURL._spis._isSpecial, let srcIP = IPv4Address(utf8: srcHost.utf8.lazy.percentDecoded()) {

      guard case .ipv4Address(let webURLIP) = webURL.host else {
        failures.insert(.failuedToDetectIPv4)
        break hostname
      }
      guard srcIP == webURLIP else {
        failures.insert(.differentHostnames)
        break hostname
      }

      // If the host contains a domain, certain DNS-related normalization preserves semantic equivalence.
      // - For domains without IDNA, normalization amounts to lowercasing.
      // - Domains may not be empty.
    } else if webURL._spis._isSpecial, webURL.utf8.hostname?.isEmpty == false {

      guard srcHost.percentDecoded().lowercased() == webURL.hostname else {
        failures.insert(.differentHostnames)
        break hostname
      }

      // If the host contains an opaque hostname, adding percent-encoding is allowed, but the percent-decoded
      // contents must be an exact match.
    } else {

      guard srcHost.percentDecoded() == webURL.hostname?.percentDecoded() else {
        failures.insert(.differentHostnames)
        break hostname
      }
    }
  }

  port: do {
    // Stripping default ports for well-known schemes preserves semantic equivalence.
    guard srcURL.port == webURL.port || srcURL.port == webURL.portOrKnownDefault else {
      failures.insert(.differentPorts)
      break port
    }
  }

  path: do {
    if webURL.hasOpaquePath {
      // URL.path doesn't seem to work for URLs with opaque paths, so we need to ask URLComponents for that.
      guard srcComponents!.percentEncodedPath.percentDecoded() == webURL.path.percentDecoded() else {
        // URLComponents will percent-decode the path if it contains semicolons,
        // meaning there is literally no way to get an accurate path string from Foundation if
        // it contains a semicolon. If that looks like the reason for the difference, let it slide.
        // https://bugs.swift.org/browse/SR-15512
        let pathContainsSemicolon = webURL.utf8.path.contains(UInt8(ascii: ";"))
        if srcComponents!.percentEncodedPath.isEmpty, !webURL.utf8.path.isEmpty, pathContainsSemicolon {
          break path
        }
        failures.insert(.differentPaths)
        break path
      }
      break path
    }

    // Checking hierarchical path equivalence is tricky, because WebURL simplifies "." and ".." components,
    // and it can be scheme-specific (e.g. Windows drive letters in "file" URLs).
    //
    // Ideally, we'd check that WebURL produces the same resuls as URL.standardized, but:
    // 1. It isn't documented which algorithm '.standardized' uses.
    // 2. '.standardized' is sometimes inaccurate (see: SR-14145, SR-15504, SR-15505).
    // 3. WebURL's path normalization is not the same as Foundation's '.standardized'.
    //    It includes things like Windows drive letter quirks in file URLs, on all platforms, and special
    //    behavior for HTTP path normalization as required for web compatibility.
    //    The different normalization is not really incorrect (it's what people expect when creating a WebURL from a URL),
    //    as long as we check it came from the same source path.
    //
    // So what we do is: use WebURL's algorithm to simplify Foundation.URL's path.
    //
    // The idea is that WebURL's own test suite ensures its algorithm works correctly, and to check semantic equivalence,
    // we only need to verify that it correctly applied that algorithm to what the source URL considered its path.
    //
    // There's one caveat: that there's a werid bug in URLComponents where it will percent-decode the path if it contains
    // a semicolon (!), and that can even lead to the path becoming empty if it contains percent-encoded bytes that are
    // not valid UTF8 (e.g. "%82"). That means in some cases, it's literally not possible for us to know exactly what
    // the source URL considered to be its path. https://bugs.swift.org/browse/SR-15512

    // If URLComponents refuses to accept the source path, there's not much we can do to verify it.
    guard let urlComponents = srcComponents else {
      break path
    }

    // If URL.path is empty, but URLComponents.percentEncodedPath is not, consider URLComponents unreliable
    // and skip further verification. There's not much we can do here.
    guard srcURL.path.isEmpty == urlComponents.percentEncodedPath.isEmpty else {
      break path
    }

    let normalizedSrcPath = webURL._spis._simplyPathInContext(urlComponents.percentEncodedPath)

    guard normalizedSrcPath.percentDecoded() == webURL.path.percentDecoded() else {
      // URLComponents will percent-decode the path if it contains semicolons,
      // meaning there is literally no way to get an accurate path string from Foundation if
      // it contains a semicolon. If that looks like the reason for the difference, let it slide.
      if (srcURL.path.isEmpty != webURL.utf8.path.isEmpty) || webURL.path.contains(";") || srcURL.path.contains(";") {
        break path
      }
      failures.insert(.differentPaths)
      break path
    }
  }

  query: do {
    // URL.query doesn't seem to work for URLs with opaque paths, so we need to ask URLComponents for that.
    if srcComponents!.percentEncodedQuery?.percentDecoded() != webURL.query?.percentDecoded() {
      failures.insert(.differentQuerys)
    }
  }

  fragment: do {
    // URL.fragment doesn't seem to work for URLs with opaque paths, so we need to ask URLComponents for that.
    if srcComponents!.percentEncodedFragment?.percentDecoded() != webURL.fragment?.percentDecoded() {
      failures.insert(.differentFragments)
    }
  }

  // Finished. If we made it here without failures, the URLs look semantically equivalent.
}
