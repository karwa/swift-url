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

  /// Special-purpose APIs intended for use by `WebURL*Extras` libraries or `WebURLTestSupport` only.
  /// Please **do not use** these APIs. They may disappear, or their behavior may change, at any time.
  ///
  public struct _SPIs {
    @usableFromInline
    internal var _url: WebURL

    @inlinable
    internal init(_url: WebURL) {
      self._url = _url
    }
  }

  /// Special-purpose APIs intended for use by `WebURL*Extras` libraries or `WebURLTestSupport` only.
  /// Please **do not use** these APIs. They may disappear, or their behavior may change, at any time.
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
  @inlinable
  public var _isSpecial: Bool {
    _url.schemeKind.isSpecial
  }
}

extension WebURL._SPIs {

  /// Returns a simplified path string, formed by parsing the given string in the context of this URL's `schemeKind` and authority.
  ///
  public func _simplyPathInContext(_ path: String) -> String {

    struct StringWriter: _PathParser {
      var utf8: [UInt8] = []

      typealias InputString = UnsafeBoundsCheckedBufferPointer<UInt8>
      mutating func visitEmptyPathComponents(_ n: UInt) {
        utf8.insert(contentsOf: repeatElement(ASCII.forwardSlash.codePoint, count: Int(n)), at: 0)
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
      writer.walkPathComponents(
        pathString: pathUTF8.boundsChecked,
        schemeKind: _url.schemeKind,
        hasAuthority: _url.utf8.hostname != nil,
        baseURL: nil,
        absolutePathsCopyWindowsDriveFromBase: false  // no baseURL
      )
      return String(decoding: writer.utf8, as: UTF8.self)
    }
  }
}

extension WebURL._SPIs {

  public enum _HostKind {
    case ipv4Address
    case ipv6Address
    case domain
    case opaque
    case empty
  }

  /// Returns the kind of host this URL has.
  ///
  @inlinable
  public var _hostKind: _HostKind? {
    switch _url.hostKind {
    case .ipv4Address: return .ipv4Address
    case .ipv6Address: return .ipv6Address
    case .domain: return .domain
    case .opaque: return .opaque
    case .empty: return .empty
    case .none: return .none
    }
  }
}
