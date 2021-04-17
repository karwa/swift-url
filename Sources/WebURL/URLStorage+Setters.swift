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
// MARK: - Scheme
// --------------------------------------------


extension URLStorage {

  /// Attempts to set the scheme component to the given UTF8-encoded string.
  /// The new value may contain a trailing colon (e.g. `http`, `http:`). Colons are only allowed as the last character of the string.
  ///
  @inlinable
  internal mutating func setScheme<UTF8Bytes>(
    to newValue: UTF8Bytes
  ) -> (AnyURLStorage, URLSetterError?) where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    // Check that the new value is a valid scheme.
    guard let (idx, newSchemeKind) = parseScheme(newValue),
      idx == newValue.endIndex || newValue.index(after: idx) == newValue.endIndex
    else {
      return (AnyURLStorage(self), .invalidScheme)
    }

    // Check that the operation is semantically valid for the existing structure.
    let newSchemeBytes = newValue[..<idx]
    let oldStructure = header.structure

    if newSchemeKind.isSpecial != oldStructure.schemeKind.isSpecial {
      return (AnyURLStorage(self), .changeOfSchemeSpecialness)
    }
    if newSchemeKind == .file, oldStructure.hasCredentialSeparator || oldStructure.portLength != 0 {
      return (AnyURLStorage(self), .newSchemeCannotHaveCredentialsOrPort)
    }
    if oldStructure.schemeKind == .file, oldStructure.hostnameLength == 0 {
      return (AnyURLStorage(self), newSchemeKind == .file ? nil : .newSchemeCannotHaveEmptyHostname)
    }

    // The operation is valid. Calculate the new structure and replace the code-units.
    var newStructure = oldStructure
    newStructure.schemeKind = newSchemeKind
    newStructure.schemeLength = newSchemeBytes.count + 1

    var commands: [ReplaceSubrangeOperation] = [
      .replace(subrange: oldStructure.rangeForReplacingCodeUnits(of: .scheme), withCount: newStructure.schemeLength) {
        dest in
        let bytesWritten = dest.fastInitialize(from: ASCII.Lowercased(newSchemeBytes))
        dest[bytesWritten] = ASCII.colon.codePoint
        return bytesWritten + 1
      }
    ]
    // If the current port is the default for the new scheme, it must be removed.
    withUTF8(of: .port) {
      guard let portBytes = $0 else { return }
      assert(portBytes.count > 1, "invalid URLStructure: port must either be nil or >1 character")
      if newStructure.schemeKind.isDefaultPort(utf8: portBytes.dropFirst()) {
        newStructure.portLength = 0
        commands.append(.remove(subrange: oldStructure.rangeForReplacingCodeUnits(of: .port)))
      }
    }
    return (multiReplaceSubrange(commands, newStructure: newStructure), nil)
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
  @inlinable
  internal mutating func setUsername<UTF8Bytes>(
    to newValue: UTF8Bytes?
  ) -> (AnyURLStorage, URLSetterError?) where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    let oldStructure = header.structure

    // Check that the operation is semantically valid for the existing structure.
    if oldStructure.cannotHaveCredentialsOrPort {
      return (AnyURLStorage(self), .cannotHaveCredentialsOrPort)
    }

    // The operation is valid. Calculate the new structure and replace the code-units.
    var newStructure = oldStructure
    newStructure.usernameLength = 0

    guard let newValue = newValue, newValue.isEmpty == false else {
      guard let oldUsername = oldStructure.range(of: .username) else {
        return (AnyURLStorage(self), nil)
      }
      let toRemove = oldUsername.lowerBound..<(oldUsername.upperBound + (newStructure.hasCredentialSeparator ? 0 : 1))
      return (removeSubrange(toRemove, newStructure: newStructure).newStorage, nil)
    }

    let (newLength, needsEncoding) = newValue.lazy.percentEncodedGroups(as: \.userInfo).encodedLength
    newStructure.usernameLength = newLength

    let oldRange = oldStructure.rangeForReplacingCodeUnits(of: .username)
    let addSeparator = (oldStructure.hasCredentialSeparator == false)
    let bytesToWrite = newLength + (addSeparator ? 1 : 0)

    let result = replaceSubrange(oldRange, withUninitializedSpace: bytesToWrite, newStructure: newStructure) { dest in
      var bytesWritten = 0
      if needsEncoding {
        bytesWritten += dest.fastInitialize(from: newValue.lazy.percentEncoded(as: \.userInfo))
      } else {
        bytesWritten += dest.fastInitialize(from: newValue)
      }
      if addSeparator {
        dest[bytesWritten] = ASCII.commercialAt.codePoint
        bytesWritten += 1
      }
      return bytesWritten
    }
    return (result.newStorage, nil)
  }

  /// Attempts to set the password component to the given UTF8-encoded string. The value will be percent-encoded as appropriate.
  ///
  /// - Note: Usernames and Passwords are never filtered of ASCII tab or newline characters.
  ///         If the given `newValue` contains any such characters, they will be percent-encoded in to the result.
  ///
  @inlinable
  internal mutating func setPassword<UTF8Bytes>(
    to newValue: UTF8Bytes?
  ) -> (AnyURLStorage, URLSetterError?) where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    let oldStructure = header.structure

    // Check that the operation is semantically valid for the existing structure.
    if oldStructure.cannotHaveCredentialsOrPort {
      return (AnyURLStorage(self), .cannotHaveCredentialsOrPort)
    }

    // The operation is valid. Calculate the new structure and replace the code-units.
    var newStructure = oldStructure
    newStructure.passwordLength = 0

    guard let newValue = newValue, newValue.isEmpty == false else {
      guard let oldPassword = oldStructure.range(of: .password) else {
        return (AnyURLStorage(self), nil)
      }
      let toRemove = oldPassword.lowerBound..<(oldPassword.upperBound + (newStructure.hasCredentialSeparator ? 0 : 1))
      return (removeSubrange(toRemove, newStructure: newStructure).newStorage, nil)
    }

    let (newLength, needsEncoding) = newValue.lazy.percentEncodedGroups(as: \.userInfo).encodedLength
    newStructure.passwordLength = 1 /* : */ + newLength

    // Always write the trailing '@'.
    var oldRange = oldStructure.rangeForReplacingCodeUnits(of: .password)
    oldRange = oldRange.lowerBound..<oldRange.upperBound + (oldStructure.hasCredentialSeparator ? 1 : 0)
    let bytesToWrite = newStructure.passwordLength + 1 /* @ */

    let result = replaceSubrange(oldRange, withUninitializedSpace: bytesToWrite, newStructure: newStructure) { dest in
      dest[0] = ASCII.colon.codePoint
      var bytesWritten = 1
      if needsEncoding {
        bytesWritten +=
          UnsafeMutableBufferPointer(rebasing: dest.dropFirst())
          .fastInitialize(from: newValue.lazy.percentEncoded(as: \.userInfo))
      } else {
        bytesWritten +=
          UnsafeMutableBufferPointer(rebasing: dest.dropFirst())
          .fastInitialize(from: newValue.lazy.percentEncoded(as: \.userInfo))
      }
      dest[bytesWritten] = ASCII.commercialAt.codePoint
      bytesWritten += 1
      return bytesWritten
    }
    return (result.newStorage, nil)
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
  @inlinable
  internal mutating func setHostname<UTF8Bytes>(
    to newValue: UTF8Bytes?
  ) -> (AnyURLStorage, URLSetterError?) where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {

    let oldStructure = header.structure

    // Check that the operation is semantically valid for the existing structure.
    if oldStructure.cannotBeABaseURL {
      return (AnyURLStorage(self), .cannotSetHostOnCannotBeABaseURL)
    }

    guard let newHostnameBytes = newValue, newHostnameBytes.isEmpty == false else {

      if oldStructure.schemeKind.isSpecial, oldStructure.schemeKind != .file {
        return (AnyURLStorage(self), .schemeDoesNotSupportNilOrEmptyHostnames)
      }
      if oldStructure.schemeKind == .file, newValue == nil {
        return (AnyURLStorage(self), .schemeDoesNotSupportNilOrEmptyHostnames)
      }
      if oldStructure.hasCredentialsOrPort {
        return (AnyURLStorage(self), .cannotSetEmptyHostnameWithCredentialsOrPort)
      }
      if oldStructure.pathLength == 0, newValue == nil {
        return (AnyURLStorage(self), .cannotRemoveHostnameWithoutPath)
      }

      // The operation is valid. Calculate the new structure and replace the code-units.
      var newStructure = oldStructure
      newStructure.hostnameLength = 0

      switch oldStructure.range(of: .hostname) {
      case .none:
        assert(oldStructure.sigil != .authority, "URL has authority, but told us it had a nil hostname?!")

        // nil -> nil.
        guard newValue != nil else {
          return (AnyURLStorage(self), nil)
        }
        // nil -> empty string: Insert authority sigil, overwriting path sigil if present.
        newStructure.sigil = .authority
        let result = replaceSubrange(
          oldStructure.rangeForReplacingSigil,
          withUninitializedSpace: Sigil.authority.length,
          newStructure: newStructure,
          initializer: Sigil.authority.unsafeWrite
        )
        return (result.newStorage, nil)

      case .some(let hostnameRange):
        assert(oldStructure.sigil == .authority, "URL has a hostname, but apparently no authority?!")

        // hostname -> empty string: Preserve existing sigil, only remove the hostname contents.
        guard newValue == nil else {
          return (removeSubrange(hostnameRange, newStructure: newStructure).newStorage, nil)
        }
        // hostname -> nil: Remove authority sigil, replacing it with a path sigil if required.
        let needsPathSigil = withUTF8(of: .path) { pathBytes in
          pathBytes.map { PathComponentParser.doesNormalizedPathRequirePathSigil($0) } ?? false
        }
        newStructure.sigil = needsPathSigil ? .path : .none
        let commands: [ReplaceSubrangeOperation] = [
          .replace(
            subrange: oldStructure.rangeForReplacingSigil,
            withCount: needsPathSigil ? Sigil.path.length : 0,
            writer: needsPathSigil ? Sigil.path.unsafeWrite : { _ in 0 }),
          .remove(subrange: hostnameRange),
        ]
        return (multiReplaceSubrange(commands, newStructure: newStructure), nil)
      }
    }

    // Check that the new value is a valid hostname.
    var callback = IgnoreValidationErrors()
    guard let newHost = ParsedHost(newHostnameBytes, schemeKind: oldStructure.schemeKind, callback: &callback) else {
      return (AnyURLStorage(self), .invalidHostname)
    }

    // The operation is valid. Calculate the new structure and replace the code-units.
    var newStructure = oldStructure

    var newLengthCounter = HostnameLengthCounter()
    newHost.write(bytes: newHostnameBytes, using: &newLengthCounter)
    newStructure.hostnameLength = newLengthCounter.length

    // Always insert/overwrite the existing sigil.
    newStructure.sigil = .authority

    let commands: [ReplaceSubrangeOperation] = [
      .replace(
        subrange: oldStructure.rangeForReplacingSigil,
        withCount: Sigil.authority.length,
        writer: Sigil.authority.unsafeWrite),
      .replace(
        subrange: oldStructure.rangeForReplacingCodeUnits(of: .hostname),
        withCount: newStructure.hostnameLength
      ) { dest in
        var writer = UnsafeBufferHostnameWriter(buffer: dest)
        newHost.write(bytes: newHostnameBytes, using: &writer)
        return dest.baseAddress?.distance(to: writer.buffer.baseAddress!) ?? 0
      },
    ]
    return (multiReplaceSubrange(commands, newStructure: newStructure), nil)
  }
}


// --------------------------------------------
// MARK: - Port
// --------------------------------------------


extension URLStorage {

  /// Attempts to set the port component to the given value. A value of `nil` removes the port.
  ///
  @inlinable
  internal mutating func setPort(
    to newValue: UInt16?
  ) -> (AnyURLStorage, URLSetterError?) {

    var newValue = newValue
    let oldStructure = header.structure

    // Check that the operation is semantically valid for the existing structure.
    guard oldStructure.cannotHaveCredentialsOrPort == false else {
      return (AnyURLStorage(self), .cannotHaveCredentialsOrPort)
    }

    // The operation is valid. Calculate the new structure and replace the code-units.
    // This is a pretty straightforward code-unit replacement, so it can go through setSimpleComponent.
    if newValue == oldStructure.schemeKind.defaultPort {
      newValue = nil
    }

    if let newPort = newValue {
      var stackBuffer = 0 as UInt64
      let result = withUnsafeMutableBytes(of: &stackBuffer) { stackBytes -> AnyURLStorage in
        let count = ASCII.writeDecimalString(for: newPort, to: stackBytes.baseAddress!)
        let utf8Bytes = UnsafeRawBufferPointer(start: stackBytes.baseAddress!, count: Int(count))
        assert(count > 0)
        return setSimpleComponent(
          .port,
          to: utf8Bytes,
          prefix: .colon,
          lengthKey: \.portLength,
          encodeSet: \.alreadyEncoded
        ).newStorage
      }
      return (result, nil)

    } else {
      let result = setSimpleComponent(
        .port,
        to: UnsafeBufferPointer?.none,
        prefix: .colon,
        lengthKey: \.portLength,
        encodeSet: \.alreadyEncoded
      ).newStorage
      return (result, nil)
    }
  }
}


// --------------------------------------------
// MARK: - Path
// --------------------------------------------


extension URLStorage {

  /// Attempts to set the path component to the given UTF8-encoded string.
  ///
  @inlinable
  internal mutating func setPath<UTF8Bytes>(
    to newPath: UTF8Bytes
  ) -> (AnyURLStorage, URLSetterError?) where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {

    let oldStructure = header.structure

    // Check that the operation is semantically valid for the existing structure.
    guard oldStructure.cannotBeABaseURL == false else {
      return (AnyURLStorage(self), .cannotSetPathOnCannotBeABaseURL)
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
      parsing: newPath, schemeKind: oldStructure.schemeKind, baseURL: nil,
      absolutePathsCopyWindowsDriveFromBase: false)

    var newStructure = oldStructure
    newStructure.pathLength = pathInfo.requiredCapacity
    newStructure.firstPathComponentLength = pathInfo.firstComponentLength

    var commands: [ReplaceSubrangeOperation] = []
    switch (oldStructure.sigil, pathInfo.requiresPathSigil) {
    case (.authority, _), (.path, true), (.none, false):
      break
    case (.path, false):
      newStructure.sigil = .none
      commands.append(.remove(subrange: oldStructure.rangeForReplacingSigil))
    case (.none, true):
      newStructure.sigil = .path
      commands.append(
        .replace(
          subrange: oldStructure.rangeForReplacingSigil,
          withCount: Sigil.path.length,
          writer: Sigil.path.unsafeWrite)
      )
    }
    commands.append(
      .replace(
        subrange: oldStructure.rangeForReplacingCodeUnits(of: .path),
        withCount: pathInfo.requiredCapacity,
        writer: { dest in
          dest.writeNormalizedPath(
            parsing: newPath, schemeKind: newStructure.schemeKind,
            baseURL: nil,
            absolutePathsCopyWindowsDriveFromBase: false,
            needsPercentEncoding: pathInfo.needsPercentEncoding
          )
        })
    )
    return (multiReplaceSubrange(commands, newStructure: newStructure), nil)
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
  @inlinable
  internal mutating func setQuery<UTF8Bytes>(
    to newValue: UTF8Bytes?
  ) -> AnyURLStorage where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    if self.header.structure.schemeKind.isSpecial {
      return setSimpleComponent(
        .query,
        to: newValue,
        prefix: .questionMark,
        lengthKey: \.queryLength,
        encodeSet: \.query_special,
        adjustStructure: { structure in
          // Empty and nil queries are considered form-encoded (in that they do not need to be re-encoded).
          structure.queryIsKnownFormEncoded = (structure.queryLength == 0 || structure.queryLength == 1)
        }
      ).newStorage
    } else {
      return setSimpleComponent(
        .query,
        to: newValue,
        prefix: .questionMark,
        lengthKey: \.queryLength,
        encodeSet: \.query_notSpecial,
        adjustStructure: { structure in
          structure.queryIsKnownFormEncoded = (structure.queryLength == 0 || structure.queryLength == 1)
        }
      ).newStorage
    }
  }

  /// Set the query component to the given UTF8-encoded string, assuming that the string is already `application/x-www-form-urlencoded`.
  ///
  @inlinable
  internal mutating func setQuery<UTF8Bytes>(
    toKnownFormEncoded newValue: UTF8Bytes?
  ) -> AnyURLStorage where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    return setSimpleComponent(
      .query,
      to: newValue,
      prefix: .questionMark,
      lengthKey: \.queryLength,
      encodeSet: \.alreadyEncoded,
      adjustStructure: { structure in
        structure.queryIsKnownFormEncoded = true
      }
    ).newStorage
  }

  /// Attempts to set the query component to the given UTF8-encoded string.
  ///
  /// A value of `nil` removes the query.
  ///
  @inlinable
  internal mutating func setFragment<UTF8Bytes>(
    to newValue: UTF8Bytes?
  ) -> AnyURLStorage where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    return setSimpleComponent(
      .fragment,
      to: newValue,
      prefix: .numberSign,
      lengthKey: \.fragmentLength,
      encodeSet: \.fragment
    ).newStorage
  }
}


// --------------------------------------------
// MARK: - Errors
// --------------------------------------------


/// An error which may be returned when a `URLStorage` setter operation fails.
///
@usableFromInline
internal enum URLSetterError: Error, Equatable {

  // scheme.
  case invalidScheme
  case changeOfSchemeSpecialness
  case newSchemeCannotHaveCredentialsOrPort
  case newSchemeCannotHaveEmptyHostname
  // credentials and port.
  case cannotHaveCredentialsOrPort
  case portValueOutOfBounds
  // hostname.
  case cannotSetHostOnCannotBeABaseURL
  case schemeDoesNotSupportNilOrEmptyHostnames
  case cannotSetEmptyHostnameWithCredentialsOrPort
  case invalidHostname
  case cannotRemoveHostnameWithoutPath
  // path.
  case cannotSetPathOnCannotBeABaseURL
}

extension URLSetterError: CustomStringConvertible {

  @usableFromInline
  internal var description: String {
    switch self {
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
    case .cannotSetHostOnCannotBeABaseURL:
      return #"""
        Attempt to set the hostname on a 'cannot be a base' URL.
        URLs without hostnames, and whose path does not begin with '/', are considered invalid base URLs and
        cannot be made valid by adding a hostname or changing their path.

        Examples include: 'mailto:somebody@example.com', 'javascript:alert("hi")', 'data:image/png;base64,iVBOR...'
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
    case .cannotSetPathOnCannotBeABaseURL:
      return #"""
        Attempt to set the path on a 'cannot be a base' URL.
        URLs without hostnames, and whose path does not begin with '/', are considered invalid base URLs and
        cannot be made valid by adding a hostname or changing their path.

        Examples include: 'mailto:somebody@example.com', 'javascript:alert("hi")', 'data:image/png;base64,iVBOR...'
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
    subrange: Range<Int>, withCount: Int, writer: @escaping (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) -> Self {
    ReplaceSubrangeOperation(subrange: subrange, newElementCount: withCount, writer: writer)
  }

  /// - seealso: `URLStorage.removeSubrange`
  @inlinable
  internal static func remove(subrange: Range<Int>) -> Self {
    ReplaceSubrangeOperation(subrange: subrange, newElementCount: 0, writer: { _ in return 0 })
  }
}

extension URLStorage {

  /// Performs a code-unit and URL structure replacement, copying to new storage with a different header type if necessary.
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
  /// - returns: A tuple consisting of:
  ///   - An `AnyURLStorage` with the given range of code-units replaced and with the new structure. If the existing storage was already capable
  ///     of supporting the new structure, this will wrap `self`. Otherwise, it will wrap a new storage object.
  ///   - The range of the replaced code-units in the new storage object.
  ///
  @inlinable
  internal mutating func replaceSubrange(
    _ subrange: Range<Int>,
    withUninitializedSpace newElementCount: Int,
    newStructure: URLStructure<Int>,
    initializer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) -> (newStorage: AnyURLStorage, newSubrange: Range<Int>) {

    newStructure.checkInvariants()
    let newCount = codeUnits.count - subrange.count + newElementCount

    if AnyURLStorage.isOptimalStorageType(Self.self, requiredCapacity: newCount, structure: newStructure) {
      let newSubrange = codeUnits.unsafeReplaceSubrange(
        subrange, withUninitializedCapacity: newElementCount, initializingWith: initializer
      )
      header.copyStructure(from: newStructure)
      return (AnyURLStorage(self), newSubrange)
    }
    let newSubrange = subrange.lowerBound..<(subrange.lowerBound + newElementCount)
    let newStorage = AnyURLStorage(optimalStorageForCapacity: newCount, structure: newStructure) { dest in
      return codeUnits.withUnsafeBufferPointer { src in
        dest.initialize(from: src, replacingSubrange: subrange, withElements: newElementCount) { rgnStart, count in
          var rgnPtr = UnsafeMutableBufferPointer(start: rgnStart, count: count)
          let written = initializer(&rgnPtr)
          precondition(written == count, "Subrange initializer did not initialize the expected number of code-units")
        }
      }
    }
    return (newStorage, newSubrange)
  }

  /// Removes the given code-units and replaces the URL structure, copying to new storage with a different header type if necessary.
  ///
  /// - parameters:
  ///   - subrange:     The range of code-units to remove
  ///   - newStructure: The structure of the normalized URL string after removing the specified code-units.
  ///
  /// - returns: A tuple consisting of:
  ///   - An `AnyURLStorage` with the given range of code-units replaced and with the new structure. If the existing storage was already capable
  ///     of supporting the new structure, this will wrap `self`. Otherwise, it will wrap a new storage object.
  ///   - The range of the replaced code-units in the new storage object.
  ///
  @inlinable
  internal mutating func removeSubrange(
    _ subrange: Range<Int>, newStructure: URLStructure<Int>
  ) -> (newStorage: AnyURLStorage, newSubrange: Range<Int>) {
    return replaceSubrange(subrange, withUninitializedSpace: 0, newStructure: newStructure) { _ in 0 }
  }

  /// Performs a series of code-unit replacements and a URL structure replacement, allocating and writing to new storage if a different header type is necessary.
  ///
  /// - parameters:
  ///   - commands:      The list of code-unit replacement operations to perform.
  ///                    This list must be sorted by the operations' subrange, and operations may not work on overlapping subranges.
  ///   - newStructure:  The new structure of the URL after all replacement operations have been performed.
  ///
  /// - returns: An `AnyURLStorage` with the new code-units and structure. If the existing storage was already capable
  ///            of supporting the new structure, this will wrap `self`. Otherwise, it will wrap a new storage object.
  ///
  @inlinable
  internal mutating func multiReplaceSubrange(
    _ operations: [ReplaceSubrangeOperation],
    newStructure: URLStructure<Int>
  ) -> AnyURLStorage {

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

    let newCount = operations.reduce(into: codeUnits.count) { count, op in
      count += (op.newElementCount - op.subrange.count)
      assert(count > 0, "count became negative")
    }

    if AnyURLStorage.isOptimalStorageType(Self.self, requiredCapacity: newCount, structure: newStructure) {
      // Perform the operations in reverse order to avoid clobbering.
      for operation in operations.reversed() {
        codeUnits.unsafeReplaceSubrange(
          operation.subrange,
          withUninitializedCapacity: operation.newElementCount,
          initializingWith: operation.writer
        )
      }
      header.copyStructure(from: newStructure)
      return AnyURLStorage(self)
    }

    let newStorage = AnyURLStorage(optimalStorageForCapacity: newCount, structure: newStructure) { dest in
      return codeUnits.withUnsafeBufferPointer { src in
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
    return newStorage
  }

  /// A general setter which works for some URL components which do not have component-specific normalization logic.
  ///
  /// If the new value is `nil`, the component's code-units (as given by `URLStructure.range(of: Component)`) are removed,
  /// and the structure's `lengthKey` is set to 0.
  ///
  /// Otherwise, the component's code-units are replaced with `[prefix][encoded-content]`, where `prefix` is a given ASCII character and
  /// `encoded-content` is the result of percent-encoding the new value with `encodeSet`. The structure's `lengthKey` is set to the length
  /// of the new code-units, including the single-character prefix.
  ///
  /// This simple strategy is sufficient for components which do not modify other components when they are modified.
  /// For example, the query, fragment and port components may be changed without modifying any other parts of the URL.
  /// However, components such as scheme, hostname, username and password require more complex logic to produce a normalized URL string --
  /// when changing the scheme, the port may also need to be modified; the hostname setter needs to deal with authority sigils,
  /// and credentials have special logic for the credential separators.
  /// This setter is sufficient for the former kind of components, but **does not include the necessary component-specific logic for the latter**.
  ///
  /// - parameters:
  ///   - component: The component to modify.
  ///   - newValue:  The new value of the component.
  ///   - prefix:    A single ASCII character to write before the new value. If `newValue` is not `nil`, this is _always_ written.
  ///   - lengthKey: The `URLStructure` field to update with the component's new length. Said length will include the single-character prefix.
  ///   - encodeSet: The `PercentEncodeSet` which should be used to encode the new value.
  ///   - adjustStructure: A closure which allows setting additional properties of the structure to be tweaked before writing.
  ///                      This closure is invoked after the structure's `lengthKey` has been updated with the component's new length.
  ///
  @inlinable
  internal mutating func setSimpleComponent<UTF8Bytes, EncodeSet>(
    _ component: WebURL.Component,
    to newValue: UTF8Bytes?,
    prefix: ASCII,
    lengthKey: WritableKeyPath<URLStructure<Int>, Int>,
    encodeSet: KeyPath<PercentEncodeSet, EncodeSet.Type>,
    adjustStructure: (inout URLStructure<Int>) -> Void = { _ in }
  ) -> (newStorage: AnyURLStorage, newSubrange: Range<Int>)
  where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8, EncodeSet: PercentEncodeSetProtocol {

    let oldStructure = header.structure

    guard let newBytes = newValue else {
      guard let existingFragment = oldStructure.range(of: component) else {
        return (AnyURLStorage(self), oldStructure.rangeForReplacingCodeUnits(of: component))
      }
      var newStructure = oldStructure
      newStructure[keyPath: lengthKey] = 0
      adjustStructure(&newStructure)
      return removeSubrange(existingFragment, newStructure: newStructure)
    }

    let (newLength, needsEncoding) = newBytes.lazy.percentEncodedGroups(as: encodeSet).encodedLength

    let bytesToWrite = 1 /* prefix char */ + newLength
    let oldRange = oldStructure.rangeForReplacingCodeUnits(of: component)

    var newStructure = oldStructure
    newStructure[keyPath: lengthKey] = bytesToWrite
    adjustStructure(&newStructure)

    return replaceSubrange(oldRange, withUninitializedSpace: bytesToWrite, newStructure: newStructure) { dest in
      dest[0] = prefix.codePoint
      var bytesWritten = 1
      if needsEncoding {
        bytesWritten +=
          UnsafeMutableBufferPointer(rebasing: dest.dropFirst())
          .fastInitialize(from: newBytes.lazy.percentEncoded(as: encodeSet))
      } else {
        bytesWritten +=
          UnsafeMutableBufferPointer(rebasing: dest.dropFirst())
          .fastInitialize(from: newBytes.lazy.percentEncoded(as: encodeSet))
      }
      return bytesWritten
    }
  }
}
