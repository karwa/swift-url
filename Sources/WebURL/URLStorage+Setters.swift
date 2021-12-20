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


// Inlining:
// The setter implementations in URLStorage are all `@inlinable @inline(never)`, so they will be specialized
// but never inlined. They are accessed via generic entrypoints in UTF8View, which use `@inline(__always)`,
// so withContiguousStorageIfAvailable can be eliminated and call the correct specialization directly.


// --------------------------------------------
// MARK: - Scheme
// --------------------------------------------


extension URLStorage {

  /// Attempts to set the scheme component to the given UTF8-encoded string.
  /// The new value may contain a trailing colon (e.g. `http`, `http:`). Colons are only allowed as the last character of the string.
  ///
  @inlinable @inline(never)
  internal mutating func setScheme<UTF8Bytes>(
    to newValue: UTF8Bytes
  ) -> Result<Void, URLSetterError> where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    // Check that the new value is a valid scheme.
    guard let (idx, newSchemeKind) = parseScheme(newValue),
      idx == newValue.endIndex || newValue.index(after: idx) == newValue.endIndex
    else {
      return .failure(.invalidScheme)
    }

    // Check that the operation is semantically valid for the existing structure.
    let newSchemeBytes = newValue[..<idx]

    if newSchemeKind.isSpecial != structure.schemeKind.isSpecial {
      return .failure(.changeOfSchemeSpecialness)
    }
    if newSchemeKind == .file, structure.hasCredentialSeparator || structure.portLength != 0 {
      return .failure(.newSchemeCannotHaveCredentialsOrPort)
    }
    if structure.schemeKind == .file, structure.hostnameLength == 0 {
      return newSchemeKind == .file ? .success : .failure(.newSchemeCannotHaveEmptyHostname)
    }

    // The operation is valid. Calculate the new structure and replace the code-units.
    guard let newSchemeLength = URLStorage.SizeType(exactly: newSchemeBytes.count + 1 /* : */) else {
      return .failure(.exceedsMaximumSize)
    }
    var newStructure = structure
    newStructure.schemeKind = newSchemeKind
    newStructure.schemeLength = newSchemeLength

    return withUnsafeSmallStack_2(of: ReplaceSubrangeOperation.self) { commands in
      commands += .replace(structure.rangeForReplacingCodeUnits(of: .scheme), withCount: newSchemeLength) { dest in
        let bytesWritten = dest.fastInitialize(from: ASCII.Lowercased(newSchemeBytes))
        dest[bytesWritten] = ASCII.colon.codePoint
        return bytesWritten + 1
      }
      if let portRange = structure.range(of: .port) {
        if newStructure.schemeKind.isDefaultPort(utf8: codeUnits[portRange.dropFirst()]) {
          newStructure.portLength = 0
          commands += .remove(portRange)
        }
      }
      return multiReplaceSubrange(commands, newStructure: newStructure)
    }
  }
}


// --------------------------------------------
// MARK: - Username, Password
// --------------------------------------------


extension URLStorage {

  /// Attempts to set the username component to the given UTF8-encoded string. The value will be percent-encoded as appropriate.
  ///
  /// - Note: Usernames and Passwords are never filtered of ASCII tab or newline characters.
  ///         If the given `newValue` contains any such characters, they will be percent-encoded in to the result.
  ///
  @inlinable @inline(never)
  internal mutating func setUsername<UTF8Bytes>(
    to newValue: UTF8Bytes?
  ) -> Result<Void, URLSetterError> where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    // Check that the operation is semantically valid for the existing structure.
    if structure.cannotHaveCredentialsOrPort {
      return .failure(.cannotHaveCredentialsOrPort)
    }

    // The operation is valid. Calculate the new structure and replace the code-units.
    var newStructure = structure
    newStructure.usernameLength = 0

    guard let newValue = newValue, !newValue.isEmpty else {
      guard let oldUsername = structure.range(of: .username) else {
        return .success
      }
      removeSubrange(
        oldUsername.lowerBound..<(oldUsername.upperBound &+ (newStructure.hasCredentialSeparator ? 0 : 1)),
        newStructure: newStructure
      )
      return .success
    }

    let (_newValueLength, needsEncoding) = newValue.lazy.percentEncoded(using: .userInfoSet).unsafeEncodedLength
    guard let newValueLength = URLStorage.SizeType(exactly: _newValueLength) else {
      return .failure(.exceedsMaximumSize)
    }
    let needsSeparator = !structure.hasCredentialSeparator

    newStructure.usernameLength = newValueLength

    return replaceSubrange(
      structure.rangeForReplacingCodeUnits(of: .username),
      withUninitializedSpace: newValueLength + (needsSeparator ? 1 : 0),
      newStructure: newStructure
    ) { dest in
      var bytesWritten: Int
      if needsEncoding {
        bytesWritten = dest.fastInitialize(from: newValue.lazy.percentEncoded(using: .userInfoSet))
      } else {
        bytesWritten = dest.fastInitialize(from: newValue)
      }
      if needsSeparator {
        dest[bytesWritten] = ASCII.commercialAt.codePoint
        bytesWritten &+= 1
      }
      return bytesWritten
    }
  }

  /// Attempts to set the password component to the given UTF8-encoded string. The value will be percent-encoded as appropriate.
  ///
  /// - Note: Usernames and Passwords are never filtered of ASCII tab or newline characters.
  ///         If the given `newValue` contains any such characters, they will be percent-encoded in to the result.
  ///
  @inlinable @inline(never)
  internal mutating func setPassword<UTF8Bytes>(
    to newValue: UTF8Bytes?
  ) -> Result<Void, URLSetterError> where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    // Check that the operation is semantically valid for the existing structure.
    if structure.cannotHaveCredentialsOrPort {
      return .failure(.cannotHaveCredentialsOrPort)
    }

    // The operation is valid. Calculate the new structure and replace the code-units.
    var newStructure = structure
    newStructure.passwordLength = 0

    guard let newValue = newValue, !newValue.isEmpty else {
      guard let oldPassword = structure.range(of: .password) else {
        return .success
      }
      removeSubrange(
        oldPassword.lowerBound..<(oldPassword.upperBound &+ (newStructure.hasCredentialSeparator ? 0 : 1)),
        newStructure: newStructure
      )
      return .success
    }

    let (_newValueLength, needsEncoding) = newValue.lazy.percentEncoded(using: .userInfoSet).unsafeEncodedLength
    guard let newValueLength = URLStorage.SizeType(exactly: _newValueLength) else {
      return .failure(.exceedsMaximumSize)
    }

    newStructure.passwordLength = 1 /* : */ + newValueLength

    // Always write the trailing '@'.
    var oldPassword = structure.rangeForReplacingCodeUnits(of: .password)
    oldPassword = oldPassword.lowerBound..<oldPassword.upperBound &+ (structure.hasCredentialSeparator ? 1 : 0)
    let bytesToWrite = newStructure.passwordLength + 1 /* @ */

    return replaceSubrange(oldPassword, withUninitializedSpace: bytesToWrite, newStructure: newStructure) { dest in
      dest[0] = ASCII.colon.codePoint
      var bytesWritten = 1
      if needsEncoding {
        bytesWritten +=
          UnsafeMutableBufferPointer(rebasing: dest.dropFirst())
          .fastInitialize(from: newValue.lazy.percentEncoded(using: .userInfoSet))
      } else {
        bytesWritten +=
          UnsafeMutableBufferPointer(rebasing: dest.dropFirst())
          .fastInitialize(from: newValue)
      }
      dest[bytesWritten] = ASCII.commercialAt.codePoint
      bytesWritten &+= 1
      return bytesWritten
    }
  }
}


// --------------------------------------------
// MARK: - Hostname
// --------------------------------------------


extension URLStorage {

  /// Attempts to set the hostname component to the given UTF8-encoded string. The value will be percent-encoded as appropriate.
  ///
  /// Setting the hostname to an empty or `nil` value is only possible when there are no other authority components (credentials or port).
  /// An empty hostname preserves the `//` separator after the scheme, but the authority component will be empty (e.g. `unix://oldhost/some/path` -> `unix:///some/path`).
  /// A `nil` hostname removes the `//` separator after the scheme, resulting in a so-called "path-only" URL (e.g. `unix://oldhost/some/path` -> `unix:/some/path`).
  ///
  @inlinable @inline(never)
  internal mutating func setHostname<UTF8Bytes>(
    to newValue: UTF8Bytes?
  ) -> Result<Void, URLSetterError> where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {

    // Check that the operation is semantically valid for the existing structure.
    guard !structure.hasOpaquePath else {
      return .failure(.cannotSetHostWithOpaquePath)
    }

    guard let newHostnameBytes = newValue, !newHostnameBytes.isEmpty else {

      if structure.schemeKind.isSpecial, structure.schemeKind != .file {
        return .failure(.schemeDoesNotSupportNilOrEmptyHostnames)
      }
      if structure.schemeKind == .file, newValue == nil {
        return .failure(.schemeDoesNotSupportNilOrEmptyHostnames)
      }
      if structure.hasCredentialsOrPort {
        return .failure(.cannotSetEmptyHostnameWithCredentialsOrPort)
      }
      if structure.pathLength == 0, newValue == nil {
        return .failure(.cannotRemoveHostnameWithoutPath)
      }

      // The operation is valid. Calculate the new structure and replace the code-units.
      var newStructure = structure
      newStructure.hostnameLength = 0

      switch structure.range(of: .hostname) {
      case .none:
        assert(structure.sigil != .authority, "URL has authority, but told us it had a nil hostname?!")
        switch newValue {
        // nil -> nil.
        case .none:
          return .success
        // nil -> empty string. Insert authority sigil, overwriting path sigil if present.
        case .some:
          newStructure.sigil = .authority
          newStructure.hostKind = .empty
          return replaceSubrange(
            structure.rangeForReplacingSigil,
            withUninitializedSpace: Sigil.authority.length,
            newStructure: newStructure,
            initializer: Sigil.unsafeWrite(.authority)
          )
        }

      case .some(let hostnameRange):
        assert(structure.sigil == .authority, "URL has a hostname, but apparently no authority?!")

        switch newValue {
        // hostname -> nil. Remove authority sigil, replacing it with a path sigil if required.
        case .none:
          // swift-format-ignore
          let needsPathSigil = structure.range(of: .path).map {
            PathComponentParser.doesNormalizedPathRequirePathSigil(codeUnits[$0])
          } ?? false
          newStructure.sigil = needsPathSigil ? .path : .none
          newStructure.hostKind = nil
          return withUnsafeSmallStack_2(of: ReplaceSubrangeOperation.self) { commands in
            commands += .replace(
              structure.rangeForReplacingSigil,
              withCount: needsPathSigil ? Sigil.path.length : 0,
              writer: needsPathSigil ? Sigil.unsafeWrite(.path) : { _ in 0 })
            commands += .remove(hostnameRange)
            return multiReplaceSubrange(commands, newStructure: newStructure)
          }
        // hostname -> empty string. Preserve existing sigil, only remove the hostname contents.
        case .some:
          newStructure.hostKind = .empty
          removeSubrange(hostnameRange, newStructure: newStructure)
          return .success
        }
      }
    }
    // We have a non-nil, non-empty hostname.

    var callback = IgnoreValidationErrors()
    guard let newHost = ParsedHost(newHostnameBytes, schemeKind: structure.schemeKind, callback: &callback) else {
      return .failure(.invalidHostname)
    }

    // The operation is valid. Calculate the new structure and replace the code-units.
    var newStructure = structure

    var newLengthCounter = HostnameLengthCounter()
    newHost.write(bytes: newHostnameBytes, using: &newLengthCounter)
    guard let newValueLength = URLStorage.SizeType(exactly: newLengthCounter.requiredCapacity) else {
      return .failure(.exceedsMaximumSize)
    }

    newStructure.sigil = .authority
    newStructure.hostKind = newLengthCounter.hostKind
    newStructure.hostnameLength = newValueLength

    return withUnsafeSmallStack_2(of: ReplaceSubrangeOperation.self) { commands in
      if structure.sigil != .authority {
        commands += .replace(
          structure.rangeForReplacingSigil,
          withCount: Sigil.authority.length,
          writer: Sigil.unsafeWrite(.authority)
        )
      }
      commands += .replace(
        structure.rangeForReplacingCodeUnits(of: .hostname),
        withCount: newStructure.hostnameLength
      ) { dest in
        var writer = UnsafeBufferHostnameWriter(buffer: dest)
        newHost.write(bytes: newHostnameBytes, using: &writer)
        return dest.baseAddress!.distance(to: writer.buffer.baseAddress!)
      }
      return multiReplaceSubrange(commands, newStructure: newStructure)
    }
  }
}


// --------------------------------------------
// MARK: - Port
// --------------------------------------------


extension URLStorage {

  /// Attempts to set the port component to the given value. A value of `nil` removes the port.
  ///
  @inlinable @inline(never)
  internal mutating func setPort(
    to newValue: UInt16?
  ) -> Result<Void, URLSetterError> {

    var newValue = newValue

    // Check that the operation is semantically valid for the existing structure.
    guard !structure.cannotHaveCredentialsOrPort else {
      return .failure(.cannotHaveCredentialsOrPort)
    }

    // The operation is valid. Calculate the new structure and replace the code-units.
    // This is a straightforward code-unit replacement, so it can go through setSimpleComponent.
    if newValue == structure.schemeKind.defaultPort {
      newValue = nil
    }

    var stackBuffer = 0 as UInt64
    return withUnsafeMutableBytes(of: &stackBuffer) { stackBytes in
      var stringPointer: UnsafeRawBufferPointer? = nil
      if let newPort = newValue {
        let count = ASCII.writeDecimalString(for: newPort, to: stackBytes.baseAddress!)
        stringPointer = UnsafeRawBufferPointer(start: stackBytes.baseAddress!, count: Int(count))
        assert(count > 0)
      }
      return setSimpleComponent(
        .port,
        to: stringPointer,
        prefix: .colon,
        lengthKey: \.portLength,
        encodeSet: Optional<_StaticMember<URLEncodeSet.SpecialQuery>>.none
      )
    }
  }
}


// --------------------------------------------
// MARK: - Path
// --------------------------------------------


extension URLStorage {

  /// Attempts to set the path component to the given UTF8-encoded string.
  ///
  @inlinable @inline(never)
  internal mutating func setPath<UTF8Bytes>(
    to newPath: UTF8Bytes
  ) -> Result<Void, URLSetterError> where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {

    // Check that the operation is semantically valid for the existing structure.
    guard !structure.hasOpaquePath else {
      return .failure(.cannotModifyOpaquePath)
    }

    // The operation is valid. Calculate the new structure and replace the code-units.

    // Note: absolutePathsCopyWindowsDriveFromBase models a quirk from the URL Standard's "file slash" state,
    //       whereby parsing a "relative URL string" which turns out to be an absolute path copies the Windows drive
    //       from its base URL (so parsing "/usr/bin" against "file:///C:/Windows" returns "file:///C:/usr/bin",
    //       not "file:///usr/bin", even though "/usr/bin" is absolute).
    //
    //       The 'pathname' setter defined in the standard always goes through the "path start" state,
    //       which never reaches "file slash" and does not include this quirk. Therefore APCWDFB should be 'false'.
    let pathInfo = PathMetrics(
      parsing: newPath, schemeKind: structure.schemeKind, hasAuthority: structure.hasAuthority, baseURL: nil,
      absolutePathsCopyWindowsDriveFromBase: false
    )

    guard let newLength = URLStorage.SizeType(exactly: pathInfo.requiredCapacity),
      let newFirstComponentLength = URLStorage.SizeType(exactly: pathInfo.firstComponentLength)
    else {
      return .failure(.exceedsMaximumSize)
    }

    var newStructure = structure
    newStructure.pathLength = newLength
    newStructure.firstPathComponentLength = newFirstComponentLength

    return withUnsafeSmallStack_2(of: ReplaceSubrangeOperation.self) { commands in
      switch (structure.sigil, pathInfo.requiresPathSigil) {
      case (.authority, _), (.path, true), (.none, false):
        break
      case (.path, false):
        newStructure.sigil = .none
        commands += .remove(structure.rangeForReplacingSigil)
      case (.none, true):
        newStructure.sigil = .path
        commands += .replace(
          structure.rangeForReplacingSigil,
          withCount: Sigil.path.length,
          writer: Sigil.unsafeWrite(.path)
        )
      }
      commands += .replace(
        structure.rangeForReplacingCodeUnits(of: .path),
        withCount: newStructure.pathLength
      ) { dest in
        dest.writeNormalizedPath(
          parsing: newPath, schemeKind: newStructure.schemeKind,
          hasAuthority: newStructure.hasAuthority, baseURL: nil,
          absolutePathsCopyWindowsDriveFromBase: false,
          needsPercentEncoding: pathInfo.needsPercentEncoding
        )
      }
      return multiReplaceSubrange(commands, newStructure: newStructure)
    }
  }
}


// --------------------------------------------
// MARK: - Query, Fragment.
// --------------------------------------------


extension URLStorage {

  /// Attempts to set the query component to the given UTF8-encoded string.
  ///
  /// A value of `nil` removes the query.
  ///
  @inlinable @inline(never)
  internal mutating func setQuery<UTF8Bytes>(
    to newValue: UTF8Bytes?
  ) -> Result<Void, URLSetterError> where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    if structure.schemeKind.isSpecial {
      return setSimpleComponent(
        .query,
        to: newValue,
        prefix: .questionMark,
        lengthKey: \.queryLength,
        encodeSet: .specialQuerySet,
        adjustStructure: { newStructure in
          // Empty and nil queries are considered form-encoded (in that they do not need to be re-encoded).
          newStructure.queryIsKnownFormEncoded = (newStructure.queryLength == 0 || newStructure.queryLength == 1)
        }
      )
    } else {
      return setSimpleComponent(
        .query,
        to: newValue,
        prefix: .questionMark,
        lengthKey: \.queryLength,
        encodeSet: .querySet,
        adjustStructure: { newStructure in
          newStructure.queryIsKnownFormEncoded = (newStructure.queryLength == 0 || newStructure.queryLength == 1)
        }
      )
    }
  }

  /// Set the query component to the given UTF8-encoded string, assuming that the string is already `application/x-www-form-urlencoded`.
  ///
  @inlinable @inline(never)
  internal mutating func setQuery<UTF8Bytes>(
    toKnownFormEncoded newValue: UTF8Bytes?
  ) -> Result<Void, URLSetterError> where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    setSimpleComponent(
      .query,
      to: newValue,
      prefix: .questionMark,
      lengthKey: \.queryLength,
      encodeSet: Optional<_StaticMember<URLEncodeSet.SpecialQuery>>.none,
      adjustStructure: { newStructure in
        newStructure.queryIsKnownFormEncoded = true
      }
    )
  }

  /// Attempts to set the query component to the given UTF8-encoded string.
  ///
  /// A value of `nil` removes the query.
  ///
  @inlinable @inline(never)
  internal mutating func setFragment<UTF8Bytes>(
    to newValue: UTF8Bytes?
  ) -> Result<Void, URLSetterError> where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    setSimpleComponent(
      .fragment,
      to: newValue,
      prefix: .numberSign,
      lengthKey: \.fragmentLength,
      encodeSet: .fragmentSet
    )
  }
}


// --------------------------------------------
// MARK: - Errors
// --------------------------------------------


/// An error which may be returned when a `URLStorage` setter operation fails.
///
@usableFromInline
internal enum URLSetterError: Error, Equatable {

  case exceedsMaximumSize
  // scheme.
  case invalidScheme
  case changeOfSchemeSpecialness
  case newSchemeCannotHaveCredentialsOrPort
  case newSchemeCannotHaveEmptyHostname
  // credentials and port.
  case cannotHaveCredentialsOrPort
  case portValueOutOfBounds
  // hostname.
  case cannotSetHostWithOpaquePath
  case schemeDoesNotSupportNilOrEmptyHostnames
  case cannotSetEmptyHostnameWithCredentialsOrPort
  case invalidHostname
  case cannotRemoveHostnameWithoutPath
  // path.
  case cannotModifyOpaquePath
}

extension URLSetterError: CustomStringConvertible {

  @usableFromInline
  internal var description: String {
    switch self {
    case .exceedsMaximumSize:
      return #"""
        The operation would exceed the maximum supported size of a URL string (\#(URLStorage.SizeType.self).max).
        """#
    case .invalidScheme:
      return #"""
        The new scheme is not valid. Valid schemes consist of ASCII alphanumerics, '+', '-' and '.', and the
        first character must be an ASCII alpha. If setting a scheme, you may include its trailing ':' separator.

        Valid schemes: 'http', 'file', 'ftp:', 'http+unix:'
        Invalid schemes: '  http', 'http$', '👹', 'ftp://example.com'
        """#
    case .changeOfSchemeSpecialness:
      return #"""
        The new scheme is special/not-special, but the URL's existing scheme is not-special/special.
        URLs with special schemes are encoded in a significantly different way from those with non-special schemes,
        and switching from one style to the other via the 'scheme' property is not supported.

        The special schemes are: 'http', 'https', 'file', 'ftp', 'ws', 'wss'.
        Gopher was considered a special scheme by previous standards, but no longer is.
        """#
    case .newSchemeCannotHaveCredentialsOrPort:
      return #"""
        The URL contains credentials or a port number, which is unsupported by the new scheme.
        The only scheme which does not support credentials or a port number is 'file'.
        """#
    case .newSchemeCannotHaveEmptyHostname:
      return #"""
        The URL has an empty hostname, which is unsupported by the new scheme.
        The schemes which do not support empty hostnames are 'http', 'https', 'ftp', 'ws', and 'wss'.
        """#
    case .cannotHaveCredentialsOrPort:
      return #"""
        Attempt to set credentials or a port number, but the URL's scheme does not support them.
        The only scheme which does not support credentials or a port number is 'file'.
        """#
    case .portValueOutOfBounds:
      return #"""
        Attempt to set the port number to an invalid value. Valid port numbers are in the range 0 ..< 65536.
        """#
    case .cannotSetHostWithOpaquePath:
      return #"""
        URLs with opaque paths do not support authority components; modifying the hostname is an invalid operation.

        Examples of URLs with opaque paths include:
          'mailto:bob@example.com', 'javascript:alert("hi")', 'data:image/png;base64,iVBOR...'
        """#
    case .schemeDoesNotSupportNilOrEmptyHostnames:
      return #"""
        Attempt to set the hostname to 'nil' or the empty string, but the URL's scheme requires a non-empty hostname.
        The schemes which do not support empty hostnames are 'http', 'https', 'ftp', 'ws', and 'wss'.
        The schemes which do not support 'nil' hostnames are as above, plus 'file'.
        """#
    case .cannotSetEmptyHostnameWithCredentialsOrPort:
      return #"""
        Attempt to set the hostname to 'nil' or the empty string, but the URL contains credentials or a port number.
        Credentials and port numbers require a non-empty hostname to be present.
        """#
    case .invalidHostname:
      return #"""
        Attempt to set the hostname to an invalid value. Invalid values include invalid IPv4/v6 addresses
        (e.g. "10.0.0.999" or "[:::]"), as well as strings containing forbidden host code points.

        A forbidden host code point is U+0000 NULL, U+0009 TAB, U+000A LF, U+000D CR,
        U+0020 SPACE, U+0023 (#), U+0025 (%), U+002F (/), U+003A (:), U+003C (<), U+003E (>),
        U+003F (?), U+0040 (@), U+005B ([), U+005C (\), U+005D (]), or U+005E (^).

        These code points are forbidden (even if percent-encoded) in 'http', 'https', 'file', 'ftp', 'ws', and 'wss' URLs.
        They may only be present in hostnames of other schemes if they are percent-encoded.
        """#
    case .cannotRemoveHostnameWithoutPath:
      return #"""
        Attempt to set the hostname to 'nil' on a URL which also does not have a path.
        This is not allowed, as the result would be an invalid base URL (for example, "foo://examplehost?aQuery" would become "foo:?aQuery").
        """#
    case .cannotModifyOpaquePath:
      return #"""
        Modifying a URL's opaque path is not supported.

        Examples of URLs with opaque paths include:
          'mailto:bob@example.com', 'javascript:alert("hi")', 'data:image/png;base64,iVBOR...'
        """#
    }
  }
}


// --------------------------------------------
// MARK: - Utilities
// --------------------------------------------


/// A command object which represents a replacement operation on some URL code-units. For use with `URLStorage.multiReplaceSubrange`.
///
@usableFromInline
internal struct ReplaceSubrangeOperation {

  // Note: These are stored as Int because they are passed directly to ManagedArrayBuffer, which uses Int indices.
  @usableFromInline
  internal var subrange: Range<Int>

  @usableFromInline
  internal var newElementCount: Int

  @usableFromInline
  internal var writer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int

  @inlinable
  internal init(
    subrange: Range<Int>, newElementCount: Int, writer: @escaping (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) {
    self.subrange = subrange
    self.newElementCount = newElementCount
    self.writer = writer
  }

  /// - seealso: `URLStorage.replaceSubrange`
  @inlinable
  internal static func replace(
    _ subrange: Range<URLStorage.SizeType>, withCount: URLStorage.SizeType,
    writer: @escaping (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) -> Self {
    ReplaceSubrangeOperation(
      subrange: subrange.toCodeUnitsIndices(), newElementCount: Int(withCount), writer: writer
    )
  }

  /// - seealso: `URLStorage.removeSubrange`
  @inlinable
  internal static func remove(_ subrange: Range<URLStorage.SizeType>) -> Self {
    ReplaceSubrangeOperation(
      subrange: subrange.toCodeUnitsIndices(), newElementCount: 0, writer: { _ in return 0 }
    )
  }
}

extension URLStorage {

  /// Performs a combined code-unit and URL structure replacement.
  ///
  /// The `initializer` closure is invoked to write the new code-units, and must return the number of code-units initialized.
  ///
  /// - parameters:
  ///   - subrange:        The range of code-units to replace
  ///   - newElementCount: The number of UTF8 code-units that `initializer` will write to replace the indicated code-units.
  ///   - newStructure:    The structure of the normalized URL string after replacement.
  ///   - initializer:     A closure which must initialize exactly `newElementCount` code-units in the buffer pointer it is given.
  ///                      The closure returns the number of bytes actually written to storage, which should be calculated by the closure independently
  ///                      as it writes the contents, which serves as a safety and correctness check.
  ///
  /// - returns: A `Result` object, indicating whether or not the operation was a success.
  ///            Since this is a code-unit replacement and does not validate semantics, the operation only fails if the resulting URL string would
  ///            exceed `URLStorage`'s maximum addressable capacity.
  ///
  @inlinable
  internal mutating func replaceSubrange(
    _ subrange: Range<URLStorage.SizeType>,
    withUninitializedSpace newElementCount: URLStorage.SizeType,
    newStructure: URLStructure<URLStorage.SizeType>,
    initializer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) -> Result<Void, URLSetterError> {

    let newElementCount = Int(newElementCount)
    guard codeUnits.count - subrange.count + newElementCount <= URLStorage.SizeType.max else {
      return .failure(.exceedsMaximumSize)
    }
    newStructure.checkInvariants()
    codeUnits.unsafeReplaceSubrange(
      subrange.toCodeUnitsIndices(), withUninitializedCapacity: newElementCount, initializingWith: initializer
    )
    structure = newStructure
    return .success
  }

  /// Performs a combined code-unit removal and URL structure replacement.
  ///
  /// - parameters:
  ///   - subrange:     The range of code-units to remove
  ///   - newStructure: The structure of the normalized URL string after removing the specified code-units.
  ///
  @inlinable
  internal mutating func removeSubrange(
    _ subrange: Range<URLStorage.SizeType>, newStructure: URLStructure<URLStorage.SizeType>
  ) {
    newStructure.checkInvariants()
    codeUnits.removeSubrange(subrange.toCodeUnitsIndices())
    structure = newStructure
  }

  /// Performs a series of code-unit replacements and a URL structure replacement.
  ///
  /// - parameters:
  ///   - commands:      The list of code-unit replacement operations to perform.
  ///                    This list must be sorted by the operations' subrange, and operations may not work on overlapping subranges.
  ///   - newStructure:  The new structure of the URL after all replacement operations have been performed.
  ///
  /// - returns: A `Result` object, indicating whether or not the operation was a success.
  ///            Since this is a code-unit replacement and does not validate semantics, the operation only fails if the resulting URL string would
  ///            exceed `URLStorage`'s maximum addressable capacity.
  ///
  @inlinable
  internal mutating func multiReplaceSubrange<Operations>(
    _ operations: __shared /* caller-owned */ Operations,
    newStructure: URLStructure<URLStorage.SizeType>
  ) -> Result<Void, URLSetterError>
  where Operations: BidirectionalCollection, Operations.Element == ReplaceSubrangeOperation {

    #if DEBUG
      do {
        newStructure.checkInvariants()
        var cursor = 0
        for operation in operations {
          assert(operation.subrange.lowerBound >= cursor, "Overlapping commands")
          cursor = operation.subrange.upperBound
        }
      }
    #endif

    let _newCount = operations.reduce(into: codeUnits.count) { count, op in
      count += (op.newElementCount - op.subrange.count)
      assert(count > 0, "count became negative")
    }
    guard let newCount = URLStorage.SizeType(exactly: _newCount) else {
      return .failure(.exceedsMaximumSize)
    }

    if header._capacity >= newCount, codeUnits._storage.isKnownUniqueReference() {
      // Perform the operations in reverse order to avoid clobbering.
      for operation in operations.reversed() {
        if operation.newElementCount == 0 {
          codeUnits.removeSubrange(operation.subrange)
        } else {
          codeUnits.unsafeReplaceSubrange(
            operation.subrange,
            withUninitializedCapacity: operation.newElementCount,
            initializingWith: operation.writer
          )
        }
      }
      structure = newStructure
    } else {
      self = URLStorage(count: newCount, structure: newStructure) { dest in
        codeUnits.withUnsafeBufferPointer { src in
          var destHead = dest.baseAddress.unsafelyUnwrapped
          let sourceAddr = src.baseAddress.unsafelyUnwrapped
          var sourceOffset = 0
          for operation in operations {
            // Copy from source until command range.
            let bytesToCopyFromSource = operation.subrange.lowerBound - sourceOffset
            destHead.initialize(from: sourceAddr + sourceOffset, count: bytesToCopyFromSource)
            destHead += bytesToCopyFromSource
            sourceOffset += bytesToCopyFromSource
            // Initialize space using command.
            var buffer = UnsafeMutableBufferPointer(start: destHead, count: operation.newElementCount)
            let actualBytesWritten = operation.writer(&buffer)
            precondition(
              actualBytesWritten == operation.newElementCount,
              "Subrange initializer did not initialize the expected number of code-units"
            )
            destHead += actualBytesWritten
            // Advance source to command end.
            sourceOffset = operation.subrange.upperBound
          }
          // Copy from end of last command until end of source.
          let bytesToCopyFromSource = src.count - sourceOffset
          destHead.initialize(from: sourceAddr + sourceOffset, count: bytesToCopyFromSource)
          destHead += bytesToCopyFromSource
          return dest.baseAddress.unsafelyUnwrapped.distance(to: destHead)
        }
      }
    }
    return .success
  }

  /// A general setter for some URL components which do not have component-specific normalization logic.
  ///
  /// - If the new value is `nil`, the component's code-units (as given by `URLStructure.range(of: Component)`) are removed,
  ///   and the structure's `lengthKey` is set to 0.
  /// - Otherwise, the component's code-units are replaced with `[prefix][encoded-content]`, where `prefix` is a given ASCII character and
  ///   `encoded-content` is the result of percent-encoding the new value with the given `encodeSet`.
  ///   The structure's `lengthKey` is set to the length of the inserted content, including the single-character prefix.
  ///
  /// This strategy is sufficient for several components which do not require complex parsing/validation, or alter other components when they are modified
  /// (such as `port`, `query` and `fragment`).
  ///
  /// - parameters:
  ///   - component: The component to modify.
  ///   - newValue:  The new value of the component.
  ///   - prefix:    A single ASCII character to write before the new value. If `newValue` is not `nil`, this is _always_ written.
  ///   - lengthKey: The `URLStructure` field to update with the component's new length. Said length will include the single-character prefix.
  ///   - encodeSet: The `URLEncodeSet` which should be used to encode the new value.
  ///   - adjustStructure: A closure which allows setting additional properties of the structure to be tweaked before writing.
  ///                      This closure is invoked after the structure's `lengthKey` has been updated with the component's new length.
  ///
  /// - returns: A `Result` object, indicating whether or not the operation was a success.
  ///            Since this is a code-unit replacement and does not validate semantics, the operation only fails if the resulting URL string would
  ///            exceed `URLStorage`'s maximum addressable capacity.
  ///
  @inlinable
  internal mutating func setSimpleComponent<UTF8Bytes, EncodeSet>(
    _ component: WebURL.Component,
    to newValue: UTF8Bytes?,
    prefix: ASCII,
    lengthKey: WritableKeyPath<URLStructure<URLStorage.SizeType>, URLStorage.SizeType>,
    encodeSet: EncodeSet._Member?,
    adjustStructure: (inout URLStructure<URLStorage.SizeType>) -> Void = { _ in }
  ) -> Result<Void, URLSetterError>
  where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8, EncodeSet: PercentEncodeSet {

    let oldStructure = structure

    guard let newBytes = newValue else {
      guard let existingFragment = oldStructure.range(of: component) else {
        return .success
      }
      var newStructure = oldStructure
      newStructure[keyPath: lengthKey] = 0
      adjustStructure(&newStructure)
      removeSubrange(existingFragment, newStructure: newStructure)
      return .success
    }

    let (_newValueLength, needsEncoding) =
      encodeSet.map {
        newBytes.lazy.percentEncoded(using: $0).unsafeEncodedLength
      } ?? (UInt(bitPattern: newBytes.count), false)
    guard let newValueLength = URLStorage.SizeType(exactly: _newValueLength) else {
      return .failure(.exceedsMaximumSize)
    }

    let bytesToWrite = 1 /* prefix char */ + newValueLength
    let oldRange = oldStructure.rangeForReplacingCodeUnits(of: component)

    var newStructure = oldStructure
    newStructure[keyPath: lengthKey] = bytesToWrite
    adjustStructure(&newStructure)

    return replaceSubrange(oldRange, withUninitializedSpace: bytesToWrite, newStructure: newStructure) { dest in
      dest[0] = prefix.codePoint
      var bytesWritten = 1
      if let encodeSet = encodeSet, needsEncoding {
        bytesWritten +=
          UnsafeMutableBufferPointer(rebasing: dest.dropFirst())
          .fastInitialize(from: newBytes.lazy.percentEncoded(using: encodeSet))
      } else {
        bytesWritten +=
          UnsafeMutableBufferPointer(rebasing: dest.dropFirst())
          .fastInitialize(from: newBytes)
      }
      return bytesWritten
    }
  }
}
