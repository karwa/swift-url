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

extension URLStorage {

  /// Attempts to set the scheme component to the given UTF8-encoded string.
  /// The new value may contain a trailing colon (e.g. `http`, `http:`). Colons are only allowed as the last character of the string.
  ///
  mutating func setScheme<Input>(
    to newValue: Input
  ) -> (AnyURLStorage, URLSetterError?) where Input: Collection, Input.Element == UInt8 {

    guard let idx = findScheme(newValue),  // Checks scheme contents.
      idx == newValue.endIndex || newValue.index(after: idx) == newValue.endIndex,  // No content after scheme.
      idx != newValue.startIndex  // Scheme cannot be empty.
    else {
      return (AnyURLStorage(self), .error(.invalidScheme))
    }
    let newSchemeBytes = newValue[..<idx]

    let oldStructure = header.structure
    var newStructure = oldStructure
    newStructure.schemeKind = WebURL.SchemeKind(parsing: newSchemeBytes)
    newStructure.schemeLength = newSchemeBytes.count + 1

    if newStructure.schemeKind.isSpecial != oldStructure.schemeKind.isSpecial {
      return (AnyURLStorage(self), .error(.changeOfSchemeSpecialness))
    }
    if newStructure.schemeKind == .file, oldStructure.hasCredentialSeparator || oldStructure.portLength != 0 {
      return (AnyURLStorage(self), .error(.newSchemeCannotHaveCredentialsOrPort))
    }
    if oldStructure.schemeKind == .file, oldStructure.hostnameLength == 0 {
      return (AnyURLStorage(self), newStructure.schemeKind == .file ? nil : .error(.newSchemeCannotHaveEmptyHostname))
    }
    // The operation is semantically valid.

    var commands: [ReplaceSubrangeOperation] = [
      .replace(subrange: oldStructure.rangeForReplacingCodeUnits(of: .scheme), withCount: newStructure.schemeLength) {
        dest in
        let bytesWritten = dest.initialize(from: ASCII.Lowercased(newSchemeBytes)).1
        dest[bytesWritten] = ASCII.colon.codePoint
        return bytesWritten + 1
      }
    ]
    // If the current port is the default for the new scheme, it must be removed.
    withComponentBytes(.port) {
      guard let portBytes = $0 else { return }
      assert(portBytes.count > 1, "invalid URLStructure: port must either be nil or >1 character")
      if newStructure.schemeKind.isDefaultPortString(portBytes.dropFirst()) {
        newStructure.portLength = 0
        commands.append(.remove(subrange: oldStructure.rangeForReplacingCodeUnits(of: .port)))
      }
    }
    return (multiReplaceSubrange(commands: commands, newStructure: newStructure), nil)
  }

  /// Attempts to set the username component to the given UTF8-encoded string. The value will be percent-encoded as appropriate.
  ///
  /// - Note: Usernames and Passwords are never filtered of ASCII tab or newline characters.
  ///         If the given `newValue` contains any such characters, they will be percent-encoded in to the result.
  ///
  mutating func setUsername<Input>(
    to newValue: Input?
  ) -> (AnyURLStorage, URLSetterError?) where Input: Collection, Input.Element == UInt8 {

    let oldStructure = header.structure
    guard oldStructure.cannotHaveCredentialsOrPort == false else {
      return (AnyURLStorage(self), .error(.cannotHaveCredentialsOrPort))
    }
    // The operation is semantically valid.

    guard let newValue = newValue, newValue.isEmpty == false else {
      guard let oldUsername = oldStructure.range(of: .username) else {
        return (AnyURLStorage(self), nil)
      }
      var newStructure = oldStructure
      newStructure.usernameLength = 0
      let toRemove = oldUsername.lowerBound..<(oldUsername.upperBound + (newStructure.hasCredentialSeparator ? 0 : 1))
      return (removeSubrange(toRemove, newStructure: newStructure), nil)
    }

    var newStructure = oldStructure
    newStructure.usernameLength = 0
    let needsEncoding = newValue.lazy.percentEncoded(using: URLEncodeSet.UserInfo.self).write {
      newStructure.usernameLength += $0.count
    }
    let shouldAddSeparator = (oldStructure.hasCredentialSeparator == false)
    let bytesToWrite = newStructure.usernameLength + (shouldAddSeparator ? 1 : 0)
    let toReplace = oldStructure.rangeForReplacingCodeUnits(of: .username)
    let result = replaceSubrange(toReplace, withUninitializedSpace: bytesToWrite, newStructure: newStructure) { dest in
      guard var ptr = dest.baseAddress else { return 0 }
      if needsEncoding {
        _ = newValue.lazy.percentEncoded(using: URLEncodeSet.UserInfo.self).write { group in
          switch group {
          case .percentEncodedByte:
            ptr[0] = group[0]
            ptr[1] = group[1]
            ptr[2] = group[2]
            ptr += 3
          case .sourceByte, .substitutedByte:
            ptr[0] = group[0]
            ptr += 1
          }
        }
      } else {
        ptr += UnsafeMutableBufferPointer(start: ptr, count: newStructure.usernameLength).initialize(from: newValue).1
      }
      if shouldAddSeparator {
        ptr.pointee = ASCII.commercialAt.codePoint
        ptr += 1
      }
      return dest.baseAddress.unsafelyUnwrapped.distance(to: ptr)
    }
    return (result, nil)
  }

  /// Attempts to set the password component to the given UTF8-encoded string. The value will be percent-encoded as appropriate.
  ///
  /// - Note: Usernames and Passwords are never filtered of ASCII tab or newline characters.
  ///         If the given `newValue` contains any such characters, they will be percent-encoded in to the result.
  ///
  mutating func setPassword<Input>(
    to newValue: Input?
  ) -> (AnyURLStorage, URLSetterError?) where Input: Collection, Input.Element == UInt8 {

    let oldStructure = header.structure
    guard oldStructure.cannotHaveCredentialsOrPort == false else {
      return (AnyURLStorage(self), .error(.cannotHaveCredentialsOrPort))
    }
    // The operation is semantically valid.

    guard let newValue = newValue, newValue.isEmpty == false else {
      guard let oldPassword = oldStructure.range(of: .password) else {
        return (AnyURLStorage(self), nil)
      }
      var newStructure = oldStructure
      newStructure.passwordLength = 0
      let toRemove = oldPassword.lowerBound..<(oldPassword.upperBound + (newStructure.hasCredentialSeparator ? 0 : 1))
      return (removeSubrange(toRemove, newStructure: newStructure), nil)
    }

    var newStructure = oldStructure
    newStructure.passwordLength = 1  // leading ":"
    let needsEncoding = newValue.lazy.percentEncoded(using: URLEncodeSet.UserInfo.self).write {
      newStructure.passwordLength += $0.count
    }
    let bytesToWrite = newStructure.passwordLength + 1  // Always write the trailing "@".
    var toReplace = oldStructure.rangeForReplacingCodeUnits(of: .password)
    toReplace = toReplace.lowerBound..<toReplace.upperBound + (oldStructure.hasCredentialSeparator ? 1 : 0)

    let result = replaceSubrange(toReplace, withUninitializedSpace: bytesToWrite, newStructure: newStructure) { dest in
      guard var ptr = dest.baseAddress else { return 0 }
      ptr.pointee = ASCII.colon.codePoint
      ptr += 1
      if needsEncoding {
        _ = newValue.lazy.percentEncoded(using: URLEncodeSet.UserInfo.self).write { group in
          switch group {
          case .percentEncodedByte:
            ptr[0] = group[0]
            ptr[1] = group[1]
            ptr[2] = group[2]
            ptr += 3
          case .sourceByte, .substitutedByte:
            ptr[0] = group[0]
            ptr += 1
          }
        }
      } else {
        // swift-format-ignore
        ptr += UnsafeMutableBufferPointer(start: ptr, count: newStructure.passwordLength - 1)
          .initialize(from: newValue).1
      }
      ptr.pointee = ASCII.commercialAt.codePoint
      ptr += 1
      return dest.baseAddress.unsafelyUnwrapped.distance(to: ptr)
    }
    return (result, nil)
  }

  /// Attempts to set the hostname component to the given UTF8-encoded string. The value will be percent-encoded as appropriate.
  ///
  /// Setting the hostname to an empty or `nil` value is only possible when there are no other authority components (credentials or port).
  /// An empty hostname preserves the `//` separator after the scheme, but the authority component will be empty (e.g. `unix://oldhost/some/path` -> `unix:///some/path`).
  /// A `nil` hostname removes the `//` separator after the scheme, resulting in a so-called "path-only" URL (e.g. `unix://oldhost/some/path` -> `unix:/some/path`).
  ///
  mutating func setHostname<Input>(
    to newValue: Input?
  ) -> (AnyURLStorage, URLSetterError?) where Input: BidirectionalCollection, Input.Element == UInt8 {

    let oldStructure = header.structure
    guard oldStructure.cannotBeABaseURL == false else {
      return (AnyURLStorage(self), .error(.cannotSetHostOnCannotBeABaseURL))
    }
    // Excluding 'cannotBeABaseURL' URLs doesn't mean we always have an authority sigil.
    // Path-only URLs (e.g. "hello:/some/path") can be base URLs.
    let hasCredentialsOrPort =
      oldStructure.usernameLength != 0 || oldStructure.passwordLength != 0 || oldStructure.portLength != 0

    guard let newHostnameBytes = newValue, newHostnameBytes.isEmpty == false else {
      // Special schemes (except file) do not support nil/empty hostnames.
      if oldStructure.schemeKind.isSpecial, oldStructure.schemeKind != .file {
        return (AnyURLStorage(self), .error(.schemeDoesNotSupportNilOrEmptyHostnames))
      }
      // File does not support nil hostnames, only empty.
      if oldStructure.schemeKind == .file, newValue == nil {
        return (AnyURLStorage(self), .error(.schemeDoesNotSupportNilOrEmptyHostnames))
      }
      // Cannot set empty/nil hostname if there are credentials or a port number.
      guard hasCredentialsOrPort == false else {
        return (AnyURLStorage(self), .error(.cannotSetEmptyHostnameWithCredentialsOrPort))
      }
      // Can only set a nil hostname if there is a path.
      guard !(oldStructure.pathLength == 0 && newValue == nil) else {
        return (AnyURLStorage(self), .error(.cannotRemoveHostnameWithoutPath))
      }
      switch oldStructure.range(of: .hostname) {
      case .none:
        // 'nil' -> 'nil'.
        guard newValue != nil else {
          return (AnyURLStorage(self), nil)
        }
        // 'nil' -> empty host.
        // Insert authority sigil, overwriting path sigil if present.
        var newStructure = oldStructure
        newStructure.sigil = .authority
        newStructure.hostnameLength = 0
        assert(oldStructure.sigil != .authority, "A URL without a hostname cannot have an authority sigil")
        let result = replaceSubrange(
          oldStructure.rangeForReplacingSigil,
          withUninitializedSpace: Sigil.authority.length,
          newStructure: newStructure,
          initializer: { return Sigil.authority.unsafeWrite(to: $0) }
        )
        return (result, nil)

      case .some(let hostnameRange):
        precondition(oldStructure.sigil == .authority, "A URL with a hostname must have an authority sigil")
        var newStructure = oldStructure
        newStructure.hostnameLength = 0

        var commands: [ReplaceSubrangeOperation] = []
        // hostname -> 'nil'.
        // Remove authority sigil, replacing it with a path sigil if necessary.
        if newValue == nil {
          let needsPathSigil = withComponentBytes(.path) { pathBytes -> Bool in
            return pathBytes.map { PathComponentParser.doesNormalizedPathRequirePathSigil($0) } ?? false
          }
          if needsPathSigil {
            commands.append(
              .replace(subrange: oldStructure.rangeForReplacingSigil, withCount: Sigil.path.length) {
                return Sigil.path.unsafeWrite(to: $0)
              })
            newStructure.sigil = .path
          } else {
            commands.append(.remove(subrange: oldStructure.rangeForReplacingSigil))
            newStructure.sigil = .none
          }
        }
        // hostname -> empty hostname.
        // Preserve authority sigil, only remove the hostname contents.
        commands.append(.remove(subrange: hostnameRange))
        return (multiReplaceSubrange(commands: commands, newStructure: newStructure), nil)
      }
    }

    var callback = IgnoreValidationErrors()
    guard let newHost = ParsedHost(newHostnameBytes, schemeKind: oldStructure.schemeKind, callback: &callback) else {
      return (AnyURLStorage(self), .error(.invalidHostname))
    }

    var counter = HostnameLengthCounter()
    newHost.write(bytes: newHostnameBytes, using: &counter)

    // * -> valid, non-nil host.
    // Always write authority sigil, overwriting path sigil if present.

    var newStructure = oldStructure
    newStructure.hostnameLength = counter.length
    newStructure.sigil = .authority

    let commands: [ReplaceSubrangeOperation] = [
      .replace(subrange: oldStructure.rangeForReplacingSigil, withCount: Sigil.authority.length) {
        return Sigil.authority.unsafeWrite(to: $0)
      },
      .replace(subrange: oldStructure.rangeForReplacingCodeUnits(of: .hostname), withCount: newStructure.hostnameLength)
      { dest in
        guard var ptr = dest.baseAddress else { return 0 }
        var writer = UnsafeBufferHostnameWriter(buffer: UnsafeMutableBufferPointer(start: ptr, count: counter.length))
        newHost.write(bytes: newHostnameBytes, using: &writer)
        ptr = writer.buffer.baseAddress.unsafelyUnwrapped
        return dest.baseAddress.unsafelyUnwrapped.distance(to: ptr)
      },
    ]

    return (multiReplaceSubrange(commands: commands, newStructure: newStructure), nil)
  }

  /// Attempts to set the port component to the given value. A value of `nil` removes the port.
  ///
  mutating func setPort(
    to newValue: UInt16?
  ) -> (AnyURLStorage, URLSetterError?) {

    let oldStructure = header.structure
    guard oldStructure.cannotHaveCredentialsOrPort == false else {
      return (AnyURLStorage(self), .error(.cannotHaveCredentialsOrPort))
    }

    var newValue = newValue
    if newValue == oldStructure.schemeKind.defaultPort {
      newValue = nil
    }

    guard let newPort = newValue else {
      let result = setSimpleComponent(
        .port,
        to: UnsafeBufferPointer?.none,
        prefix: .colon,
        lengthKey: \.portLength,
        encoder: PassthroughEncodeSet.self
      )
      return (result, nil)
    }
    // TODO: More efficient UInt16 serialisation.
    var serialized = String(newPort)
    let result = serialized.withUTF8 { ptr -> AnyURLStorage in
      assert(ptr.isEmpty == false)
      return setSimpleComponent(
        .port,
        to: ptr,
        prefix: .colon,
        lengthKey: \.portLength,
        encoder: PassthroughEncodeSet.self
      )
    }
    return (result, nil)
  }

  /// Attempts to set the path component to the given UTF8-encoded string.
  ///
  mutating func setPath<Input>(
    to newPath: Input
  ) -> (AnyURLStorage, URLSetterError?) where Input: BidirectionalCollection, Input.Element == UInt8 {

    let oldStructure = header.structure
    guard oldStructure.cannotBeABaseURL == false else {
      return (AnyURLStorage(self), .error(.cannotSetPathOnCannotBeABaseURL))
    }

    // Note: absolutePathsCopyWindowsDriveFromBase models a quirk from the URL Standard's "file slash" state,
    //       and the setter goes through the "path start" state, which never reaches "file slash",
    //       so the setter doesn't expose the quirk and APCWDFB should be 'false'.
    let pathInfo = PathMetrics(
      parsing: newPath, schemeKind: oldStructure.schemeKind, baseURL: nil,
      absolutePathsCopyWindowsDriveFromBase: false)
    var newStructure = oldStructure
    newStructure.pathLength = pathInfo.requiredCapacity

    var commands: [ReplaceSubrangeOperation] = []
    switch (oldStructure.sigil, pathInfo.requiresSigil) {
    case (.authority, _), (.path, true), (.none, false):
      break
    case (.path, false):
      newStructure.sigil = .none
      commands.append(.remove(subrange: oldStructure.rangeForReplacingSigil))
    case (.none, true):
      newStructure.sigil = .path
      commands.append(
        .replace(subrange: oldStructure.rangeForReplacingSigil, withCount: Sigil.path.length) {
          return Sigil.path.unsafeWrite(to: $0)
        })
    }
    commands.append(
      .replace(
        subrange: oldStructure.rangeForReplacingCodeUnits(of: .path),
        withCount: pathInfo.requiredCapacity,
        writer: { dest in
          return dest.writeNormalizedPath(
            parsing: newPath, schemeKind: newStructure.schemeKind,
            baseURL: nil,
            absolutePathsCopyWindowsDriveFromBase: false,
            needsEscaping: pathInfo.needsEscaping
          )
        }))
    return (multiReplaceSubrange(commands: commands, newStructure: newStructure), nil)
  }

  /// Attempts to set the query component to the given UTF8-encoded string.
  ///
  /// A value of `nil` removes the query.
  ///
  mutating func setQuery<Input>(
    to newValue: Input?
  ) -> AnyURLStorage where Input: Collection, Input.Element == UInt8 {

    if self.header.structure.schemeKind.isSpecial {
      return setSimpleComponent(
        .query,
        to: newValue,
        prefix: .questionMark,
        lengthKey: \.queryLength,
        encoder: URLEncodeSet.Query_Special.self
      )
    } else {
      return setSimpleComponent(
        .query,
        to: newValue,
        prefix: .questionMark,
        lengthKey: \.queryLength,
        encoder: URLEncodeSet.Query_NotSpecial.self
      )
    }
  }

  /// Set the query component to the given UTF8-encoded string, assuming that the string is already `application/x-www-form-urlencoded`.
  ///
  mutating func setQuery<Input>(
    toKnownFormEncoded newValue: Input
  ) -> AnyURLStorage where Input: Collection, Input.Element == UInt8 {
    return setSimpleComponent(
      .query,
      to: newValue,
      prefix: .questionMark,
      lengthKey: \.queryLength,
      encoder: PassthroughEncodeSet.self
    )
  }

  /// Attempts to set the query component to the given UTF8-encoded string.
  ///
  /// A value of `nil` removes the query.
  ///
  mutating func setFragment<Input>(
    to newValue: Input?
  ) -> AnyURLStorage where Input: Collection, Input.Element == UInt8 {

    return setSimpleComponent(
      .fragment,
      to: newValue,
      prefix: .numberSign,
      lengthKey: \.fragmentLength,
      encoder: URLEncodeSet.Fragment.self
    )
  }
}


// MARK: - Errors.


/// An error which may be returned when a `URLStorage` setter operation fails.
///
struct URLSetterError: Error, Equatable {

  enum Value: Equatable {
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
  private var _value: Value

  static func error(_ v: Value) -> Self {
    return .init(_value: v)
  }
}

extension URLSetterError: CustomStringConvertible {

  public var description: String {
    switch _value {
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
