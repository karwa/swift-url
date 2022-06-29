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

  /// Whether this URL's scheme is considered "special".
  ///
  /// > Important:
  /// > This property is not considered part of WebURL's supported API.
  /// > Please **do not use** it. It may disappear, or its behavior may change, at any time.
  ///
  @inlinable
  public var _isSpecial: Bool {
    _url.schemeKind.isSpecial
  }

  /// Whether this URL contains a path sigil.
  ///
  /// > Important:
  /// > This property is not considered part of WebURL's supported API.
  /// > Please **do not use** it. It may disappear, or its behavior may change, at any time.
  ///
  @inlinable
  public var _hasPathSigil: Bool {
    _url.storage.structure.hasPathSigil
  }
}


// --------------------------------------------
// MARK: - URLStructure equality
// --------------------------------------------


extension WebURL._SPIs {

  /// Whether this URL's internal URLStructure is equivalent to `other`'s URLStructure.
  ///
  /// If two URLs have the same code-units, they should have identical URLStructures.
  /// This function is used by tests and fuzzers to check the URL's internal state,
  /// and ensure this is the case.
  ///
  /// > Important:
  /// > This function is not considered part of WebURL's supported API.
  /// > Please **do not use** it. It may disappear, or its behavior may change, at any time.
  ///
  public func _describesSameStructure(as other: WebURL) -> Bool {
    _url.storage.structure.describesSameStructure(as: other.storage.structure)
  }
}


// --------------------------------------------
// MARK: - Path Parsing
// --------------------------------------------


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


// --------------------------------------------
// MARK: - Hosts
// --------------------------------------------


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
    case .domain, .domainWithIDN:
      return .domain(hostnameUTF8)
    case .opaque:
      return .opaque(hostnameUTF8)
    case .empty:
      return .empty
    }
  }

  /// Whether this URL's host is an IPv6 address.
  ///
  /// > Important:
  /// > This property is not considered part of WebURL's supported API.
  /// > Please **do not use** it. It may disappear, or its behavior may change, at any time.
  ///
  @inlinable
  public var _isIPv6: Bool {
    if case .some(.ipv6Address) = _url.hostKind {
      return true
    }
    return false
  }
}


// --------------------------------------------
// MARK: - Percent-Encoding
// --------------------------------------------


extension WebURL._SPIs {

  /// The result of an operation which adds percent-encoding to URL components in-place.
  ///
  /// > Important:
  /// > This type, any nested types, and all of their static/member functions, are not considered
  /// > part of WebURL's supported API. Please **do not use** these APIs.
  /// > They may disappear, or their behavior may change, at any time.
  ///
  public enum _AddPercentEncodingResult {

    /// No components required additional percent-encoding; the URL is unchanged.
    ///
    /// > Important:
    /// > This enum case is not considered part of WebURL's supported API.
    /// > Please **do not use** it. It may disappear, or its behavior may change, at any time.
    ///
    case doesNotNeedEncoding

    /// Percent-encoding was added to one or more components of the URL.
    ///
    /// > Important:
    /// > This enum case is not considered part of WebURL's supported API.
    /// > Please **do not use** it. It may disappear, or its behavior may change, at any time.
    ///
    case encodingAdded

    /// The URL contains characters which _should_ be encoded, but cannot be. The operation has failed.
    ///
    /// For example, percent-encoding may take the URL beyond its maximum capacity,
    /// or may be required in a component which does not allow percent-encoding (e.g. in a domain).
    ///
    /// If the operation fails, some components may be encoded and others may not be,
    /// but the result is still a proper WebURL with correct structure, etc.
    ///
    /// > Important:
    /// > This enum case is not considered part of WebURL's supported API.
    /// > Please **do not use** it. It may disappear, or its behavior may change, at any time.
    ///
    case unableToEncode

    @inlinable
    internal static func += (lhs: inout Self, rhs: Self) {
      switch (lhs, rhs) {
      case (.unableToEncode, _):
        assertionFailure("Operation has already failed, nothing more should be combined")
      case (_, .unableToEncode):
        lhs = .unableToEncode
      case (.doesNotNeedEncoding, .encodingAdded):
        lhs = .encodingAdded
      case (.encodingAdded, .encodingAdded),
        (.doesNotNeedEncoding, .doesNotNeedEncoding),
        (.encodingAdded, .doesNotNeedEncoding):
        break
      }
    }
  }

  /// Adds percent-encoding to the specified characters in all URL components.
  ///
  /// Note that this is not the same as straight percent-encoding each component;
  /// this function only adds encoding for characters that are _not already_ part of a percent-encoded byte sequence.
  /// This mean that it does **not** introduce nested percent-encoding. A single round of decoding produces
  /// the same result before and after this operation.
  ///
  /// The nested vs. flat distinction really all comes down to how the `"%"` sign itself is handled;
  /// if we see one being used for percent-encoding (e.g. `"%AB"`), it remains as it is. However,
  /// if the percent-sign is not being used for percent-encoding (e.g. `"%hello"`), it will be encoded
  /// and become `"%25hello"`.
  ///
  /// Also be aware of the following limitations:
  ///
  /// - Encoding is only added to list-style paths.
  ///   If an opaque path requires encoding, the operation fails and returns `.unableToEncode`.
  ///
  /// - Encoding cannot be added to domains, since they do not support percent-encoding.
  ///   If a domain requires encoding, the operation fails and returns `.unableToEncode`.
  ///
  /// - IP Addresses are ignored by this function.
  ///   Even if the encode-set says they should be encoded, they will not be encoded, and the operation will not fail.
  ///
  /// - The given encode-set must not contain:
  ///   - the ASCII forward slash (`"/"`, 0x2F),
  ///   - ampersand (`"&"`, 0x26),
  ///   - plus sign (`"+"`, 0x2B), or
  ///   - equals-sign (`"="`, 0x3D) code-points.
  ///
  /// > Important:
  /// > This function is not considered part of WebURL's supported API.
  /// > Please **do not use** it. It may disappear, or its behavior may change, at any time.
  ///
  @inlinable @inline(never)
  public mutating func _addPercentEncodingToAllComponents<EncodeSet>(
    _ encodeSet: EncodeSet
  ) -> _AddPercentEncodingResult where EncodeSet: PercentEncodeSet {

    // Since we're only _adding_ percent-encoding to the contents of each component (not including its delimiters),
    // and we exclude internal subdelimiters for the path and query params, we can just encode the code-units directly
    // rather than going through the setter functions.
    precondition(!encodeSet.shouldPercentEncode(ascii: ASCII.forwardSlash.codePoint), "'/' must not be encoded")
    precondition(!encodeSet.shouldPercentEncode(ascii: ASCII.plus.codePoint), "'+' must not be encoded")
    precondition(!encodeSet.shouldPercentEncode(ascii: ASCII.equalSign.codePoint), "'=' must not be encoded")
    precondition(!encodeSet.shouldPercentEncode(ascii: ASCII.ampersand.codePoint), "'&' must not be encoded")

    var result = _AddPercentEncodingResult.doesNotNeedEncoding
    var buffer = [UInt8]()

    // Username and Password.
    result += _addPercentEncodingInPlace(_url.utf8.username, encodeSet: encodeSet, buffer: &buffer) {
      structure, newLength in structure.usernameLength = newLength
    }
    if case .unableToEncode = result { return result }

    result += _addPercentEncodingInPlace(_url.utf8.password, encodeSet: encodeSet, buffer: &buffer) {
      structure, newLength in structure.passwordLength = newLength + 1
    }
    if case .unableToEncode = result { return result }

    // Hostname.
    switch _url.storage.structure.hostKind {
    case .some(.domain), .some(.domainWithIDN):
      guard _url.utf8.hostname?.contains(where: { encodeSet.shouldPercentEncode(ascii: $0) }) == false else {
        // Domains are not allowed to contain percent-encoding.
        return .unableToEncode
      }
    case .some(.opaque):
      result += _addPercentEncodingInPlace(_url.utf8.hostname, encodeSet: encodeSet, buffer: &buffer) {
        structure, newLength in structure.hostnameLength = newLength
      }
    case .empty?, .ipv4Address?, .ipv6Address?, .none:
      break
    }
    if case .unableToEncode = result { return result }

    // Path.
    if _url.hasOpaquePath {
      let opqPath = _url.utf8.path
      switch _addPercentEncoding(opqPath, encodeSet: encodeSet, buffer: &buffer) {
      case .doesNotNeedEncoding:
        break
      case .encodingAdded, .unableToEncode:
        result = .unableToEncode  // This operation chooses not to encode opaque paths; fail instead.
      }
    } else {
      let pathResult = _addPercentEncodingInPlace(_url.utf8.path, encodeSet: encodeSet, buffer: &buffer) {
        structure, newLength in structure.pathLength = newLength
      }
      if case .encodingAdded = pathResult {
        let newPath = _url.utf8.path
        _url.storage.structure.firstPathComponentLength = URLStorage.SizeType(
          _url.storage.endOfPathComponent(startingAt: newPath.startIndex)! - newPath.startIndex
        )
      }
      result += pathResult
    }
    if case .unableToEncode = result { return result }

    // Query.
    result += _addPercentEncodingInPlace(_url.utf8.query, encodeSet: encodeSet, buffer: &buffer) {
      structure, newLength in
      structure.queryLength = newLength + 1
      structure.queryIsKnownFormEncoded = false
    }
    if case .unableToEncode = result { return result }

    // Fragment.
    result += _addPercentEncodingInPlace(_url.utf8.fragment, encodeSet: encodeSet, buffer: &buffer) {
      structure, newLength in structure.fragmentLength = newLength + 1
    }

    return result
  }

  /// Adds percent-encoding to the given range of code-units in-place.
  ///
  /// Note that this is not the same as straight percent-encoding the component;
  /// this function only adds encoding for characters that are not already part of a percent-encoded byte sequence.
  /// This ensures that a single round of decoding produces the same result before and after this operation,
  /// rather than introducing nested percent-encoding.
  ///
  /// For example, if the encode-set includes the `"%"` sign itself, `"%hello"` would be encoded to `"%25hello"`,
  /// but `"%AB"` would remain as `"%AB"`.
  ///
  @inlinable
  internal mutating func _addPercentEncodingInPlace<EncodeSet: PercentEncodeSet>(
    _ codeUnits: WebURL.UTF8View.SubSequence?,
    encodeSet: EncodeSet,
    buffer: inout [UInt8],
    adjustStructure: (inout URLStructure<URLStorage.SizeType>, _ newLength: URLStorage.SizeType) -> Void
  ) -> _AddPercentEncodingResult {
    guard
      let component = codeUnits, !component.isEmpty,
      case .encodingAdded = _addPercentEncoding(component, encodeSet: encodeSet, buffer: &buffer)
    else {
      return .doesNotNeedEncoding
    }
    // Ensure the URL string's new total length won't overflow the maximum total length.
    let oldComponent = Range(uncheckedBounds: (component.startIndex, component.endIndex))
    let newTotalLength = _url.storage.codeUnits.count - oldComponent.count + buffer.count
    guard
      let _ = URLStorage.SizeType(exactly: newTotalLength),
      let newComponentLength = URLStorage.SizeType(exactly: buffer.count)
    else {
      return .unableToEncode
    }
    // Replace the code-units, then adjust the structure.
    _url.storage.codeUnits.replaceSubrange(oldComponent, with: buffer)
    adjustStructure(&_url.storage.structure, newComponentLength)
    return .encodingAdded
  }
}

/// Adds percent-encoding to the given range of code-units.
///
/// Note that this is not the same as straight percent-encoding the code-units;
/// this function only adds encoding for characters that are not already part of a percent-encoded byte sequence.
/// This ensures that a single round of decoding either the source or encoded result produces the same end result,
/// rather than introducing nested percent-encoding.
///
/// For example, if the encode-set includes the `"%"` sign itself, `"%hello"` would be encoded to `"%25hello"`,
/// but `"%AB"` would remain as `"%AB"`.
///
/// - parameters:
///   - source:    The code-units to add percent-encoding to.
///   - encodeSet: The set of characters to encode.
///   - buffer:    A pre-allocated buffer to store the result in to.
///
/// - returns: Whether or not percent-encoding was added to `source`. If the result is `encodingAdded`,
///            the percent-encoded string will be contained in `buffer`. If the result is `doesNotNeedEncoding`,
///            the contents of `buffer` are unspecified.
///
@inlinable
internal func _addPercentEncoding<Source, EncodeSet>(
  _ source: Source,
  encodeSet: EncodeSet,
  buffer: inout [UInt8]
) -> WebURL._SPIs._AddPercentEncodingResult
where Source: Collection, Source.Element == UInt8, EncodeSet: PercentEncodeSet {

  buffer.removeAll(keepingCapacity: true)

  let decoded = source.lazy.percentDecoded()

  var startOfContiguousRange = source.startIndex

  var i = decoded.startIndex
  while i < decoded.endIndex {
    if !decoded.isByteDecodedOrUnsubstituted(at: i), encodeSet.shouldPercentEncode(ascii: decoded[i]) {
      // We need to encode something. Copy contiguous source bytes until this point.
      let contiguousRange = Range(uncheckedBounds: (startOfContiguousRange, decoded.sourceIndices(at: i).lowerBound))
      // But first - if the buffer is an empty array, give it some actual capacity.
      if buffer.capacity < 512 {
        let capacity = max(source.distance(from: contiguousRange.lowerBound, to: contiguousRange.upperBound) * 2, 512)
        buffer.reserveCapacity(capacity)
      }
      if !contiguousRange.isEmpty {
        buffer += source[contiguousRange]
      }
      // Append the encoded byte.
      withPercentEncodedString(decoded[i]) { utf8 in
        buffer += utf8
      }
      // Start a new contiguous range following this byte.
      decoded.formIndex(after: &i)
      startOfContiguousRange = decoded.sourceIndices(at: i).lowerBound

    } else {
      // The byte is already encoded, or doesn't need to be encoded. Keep the contiguous range going.
      decoded.formIndex(after: &i)
    }
  }

  if startOfContiguousRange == source.startIndex {
    return .doesNotNeedEncoding
  } else {
    buffer += source[startOfContiguousRange...]
    return .encodingAdded
  }
}
