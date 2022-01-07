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

// --------------------------------------------
// MARK: - Special-purpose interfaces.
// --------------------------------------------


extension WebURL {

  /// Special-purpose APIs intended for WebURL's support libraries.
  ///
  /// > Important:
  /// > This type, any nested types, and all of their static/member functions, are not considered
  /// > part of WebURL's supported API. Please **do not use** these APIs.
  /// > They may disappear, or their behavior may change, at any time.
  ///
  public struct _SPIs {
    @usableFromInline
    internal var _url: WebURL

    @inlinable
    internal init(_url: WebURL) {
      self._url = _url
    }
  }

  /// Special-purpose APIs intended for WebURL's support libraries.
  ///
  /// > Important:
  /// > This type, any nested types, and all of their static/member functions, are not considered
  /// > part of WebURL's supported API. Please **do not use** these APIs.
  /// > They may disappear, or their behavior may change, at any time.
  ///
  @inlinable
  public var _spis: _SPIs {
    get { _SPIs(_url: self) }
    set { self = newValue._url }
    _modify {
      var view = _SPIs(_url: self)
      self = WebURL(storage: _tempStorage)
      defer { self = view._url }
      yield &view
    }
  }
}

extension WebURL._SPIs {

  /// Whether or not this URL's scheme is considered "special".
  ///
  /// > Important:
  /// > This property is not considered part of WebURL's supported API.
  /// > Please **do not use** it. It may disappear, or its behavior may change, at any time.
  ///
  @inlinable
  public var _isSpecial: Bool {
    _url.schemeKind.isSpecial
  }
}

extension WebURL._SPIs {

  /// Returns a simplified path string, formed by parsing the given string
  /// in the context of this URL's scheme and authority.
  ///
  /// Components of the simplified path string are **not** percent-encoded as they are written,
  /// as this function is used to verify paths converted from Foundation URLs, which are already encoded
  /// with a compatible encode-set (``URLEncodeSet/Path`` is a subset of Foundation's `urlPathAllowed` encode-set).
  ///
  /// > Important:
  /// > This function is not considered part of WebURL's supported API.
  /// > Please **do not use** it. It may disappear, or its behavior may change, at any time.
  ///
  public func _simplifyPath(_ path: Substring) -> [UInt8] {

    // TODO: Write to an UnsafeMutableBufferPointer to avoid expensive prepending/element-shifting.
    //       For now, performance isn't important, as paths are only verified during testing/fuzzing.
    struct StringWriter: _PathParser {
      var utf8: [UInt8] = []

      typealias InputString = UnsafeBoundsCheckedBufferPointer<UInt8>
      mutating func visitEmptyPathComponent() {
        utf8.insert(ASCII.forwardSlash.codePoint, at: 0)
      }
      mutating func visitInputPathComponent(_ pathComponent: InputString.SubSequence) {
        utf8.insert(contentsOf: pathComponent, at: 0)
        utf8.insert(ASCII.forwardSlash.codePoint, at: 0)
      }
      mutating func visitDeferredDriveLetter(_ pathComponent: (UInt8, UInt8), isConfirmedDriveLetter: Bool) {
        withUnsafeBytes(of: pathComponent) { utf8.insert(contentsOf: $0, at: 0) }
        utf8.insert(ASCII.forwardSlash.codePoint, at: 0)
      }
      func visitBasePathComponent(_ pathComponent: WebURL.UTF8View.SubSequence) {
        fatalError("Not used for joining paths")
      }
    }

    return path._withContiguousUTF8 { pathUTF8 in
      var writer = StringWriter()
      writer.utf8.reserveCapacity(pathUTF8.count)
      writer.parsePathComponents(
        pathString: pathUTF8.boundsChecked,
        schemeKind: _url.schemeKind,
        hasAuthority: _url.storage.structure.hasAuthority,
        baseURL: nil,
        absolutePathsCopyWindowsDriveFromBase: false  // no baseURL
      )
      return writer.utf8
    }
  }
}

extension WebURL._SPIs {

  /// The host of this URL.
  ///
  /// This is equivalent to ``WebURL/WebURL/Host-swift.enum``, except that domains and opaque hosts are
  /// provided as slices of the URL's `UTF8View` rather than allocating a `String`.
  ///
  /// > Important:
  /// > This type, any nested types, and all of their static/member functions, are not considered
  /// > part of WebURL's supported API. Please **do not use** these APIs.
  /// > They may disappear, or their behavior may change, at any time.
  ///
  public enum _UTF8View_Host {
    case ipv4Address(IPv4Address)
    case ipv6Address(IPv6Address)
    case domain(WebURL.UTF8View.SubSequence)
    case opaque(WebURL.UTF8View.SubSequence)
    case empty
  }

  /// The host of this URL.
  ///
  /// This is equivalent to ``WebURL/WebURL/host-swift.property``, except that the returned value provides
  /// domains and opaque hostnames as slices of the URL's UTF8View, rather than allocating a `String`.
  ///
  /// > Important:
  /// > This property is not considered part of WebURL's supported API.
  /// > Please **do not use** it. It may disappear, or its behavior may change, at any time.
  ///
  public var _utf8_host: _UTF8View_Host? {
    guard let kind = _url.hostKind, let hostnameUTF8 = _url.utf8.hostname else {
      assert(
        _url.hostKind == nil && _url.utf8.hostname == nil,
        "hostKind and hostname should either both be nil, or both be non-nil!"
      )
      return nil
    }
    switch kind {
    case .ipv4Address:
      return .ipv4Address(IPv4Address(dottedDecimalUTF8: hostnameUTF8)!)
    case .ipv6Address:
      return .ipv6Address(IPv6Address(utf8: hostnameUTF8.dropFirst().dropLast())!)
    case .domain:
      return .domain(hostnameUTF8)
    case .opaque:
      return .opaque(hostnameUTF8)
    case .empty:
      return .empty
    }
  }
}
