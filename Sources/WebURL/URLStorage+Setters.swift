extension URLStorage {

  /// Attempts to set the scheme component to the given UTF8-encoded string.
  /// The new value may contain a trailing colon (e.g. `http`, `http:`). Colons are only allowed as the last character of the string.
  ///
  /// - Note: Filtering ASCII tab and newline characters is not needed as those characters cannot be included in a scheme, and schemes cannot
  ///         contain percent encoding.
  ///
  mutating func setScheme<Input>(
    to newValue: Input
  ) -> (Bool, AnyURLStorage) where Input: Collection, Input.Element == UInt8 {

    guard let idx = findScheme(newValue),  // Checks scheme contents.
      idx == newValue.endIndex || newValue.index(after: idx) == newValue.endIndex,  // No content after scheme.
      idx != newValue.startIndex  // Scheme cannot be empty.
    else {
      return (false, AnyURLStorage(self))
    }
    let newSchemeBytes = newValue[..<idx]

    let oldStructure = header.structure
    var newStructure = oldStructure
    newStructure.schemeKind = WebURL.SchemeKind(parsing: newSchemeBytes)
    newStructure.schemeLength = newSchemeBytes.count + 1

    if newStructure.schemeKind.isSpecial != oldStructure.schemeKind.isSpecial {
      return (false, AnyURLStorage(self))
    }
    if newStructure.schemeKind == .file, oldStructure.hasCredentialSeparator || oldStructure.portLength != 0 {
      return (false, AnyURLStorage(self))
    }
    if oldStructure.schemeKind == .file, oldStructure.hostnameLength == 0 {
      return (false, AnyURLStorage(self))
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
    return (true, multiReplaceSubrange(commands: commands, newStructure: newStructure))
  }

  /// Attempts to set the username component to the given UTF8-encoded string. The value will be percent-encoded as appropriate.
  ///
  /// - Note: Usernames and Passwords are never filtered of ASCII tab or newline characters.
  ///         If the given `newValue` contains any such characters, they will be percent-encoded in to the result.
  ///
  mutating func setUsername<Input>(
    to newValue: Input
  ) -> (Bool, AnyURLStorage) where Input: Collection, Input.Element == UInt8 {

    let oldStructure = header.structure
    guard oldStructure.cannotHaveCredentialsOrPort == false else {
      return (false, AnyURLStorage(self))
    }
    // The operation is semantically valid.

    guard newValue.isEmpty == false else {
      guard let oldUsername = oldStructure.range(of: .username) else {
        return (true, AnyURLStorage(self))
      }
      var newStructure = oldStructure
      newStructure.usernameLength = 0
      let toRemove = oldUsername.lowerBound..<(oldUsername.upperBound + (newStructure.hasCredentialSeparator ? 0 : 1))
      return (true, removeSubrange(toRemove, newStructure: newStructure))
    }

    var newStructure = oldStructure
    newStructure.usernameLength = 0
    let needsEncoding = newValue.lazy.percentEncoded(using: URLEncodeSet.UserInfo.self).writeBuffered {
      newStructure.usernameLength += $0.count
    }
    let shouldAddSeparator = (oldStructure.hasCredentialSeparator == false)
    let bytesToWrite = newStructure.usernameLength + (shouldAddSeparator ? 1 : 0)
    let toReplace = oldStructure.rangeForReplacingCodeUnits(of: .username)
    let result = replaceSubrange(toReplace, withUninitializedSpace: bytesToWrite, newStructure: newStructure) { dest in
      guard var ptr = dest.baseAddress else { return 0 }
      if needsEncoding {
        newValue.lazy.percentEncoded(using: URLEncodeSet.UserInfo.self).writeBuffered { piece in
          ptr.initialize(from: piece.baseAddress.unsafelyUnwrapped, count: piece.count)
          ptr += piece.count
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
    return (true, result)
  }

  /// Attempts to set the password component to the given UTF8-encoded string. The value will be percent-encoded as appropriate.
  ///
  /// - Note: Usernames and Passwords are never filtered of ASCII tab or newline characters.
  ///         If the given `newValue` contains any such characters, they will be percent-encoded in to the result.
  ///
  mutating func setPassword<Input>(
    to newValue: Input
  ) -> (Bool, AnyURLStorage) where Input: Collection, Input.Element == UInt8 {

    let oldStructure = header.structure
    guard oldStructure.cannotHaveCredentialsOrPort == false else {
      return (false, AnyURLStorage(self))
    }
    // The operation is semantically valid.

    guard newValue.isEmpty == false else {
      guard let oldPassword = oldStructure.range(of: .password) else {
        return (true, AnyURLStorage(self))
      }
      var newStructure = oldStructure
      newStructure.passwordLength = 0
      let toRemove = oldPassword.lowerBound..<(oldPassword.upperBound + (newStructure.hasCredentialSeparator ? 0 : 1))
      return (true, removeSubrange(toRemove, newStructure: newStructure))
    }

    var newStructure = oldStructure
    newStructure.passwordLength = 1  // leading ":"
    let needsEncoding = newValue.lazy.percentEncoded(using: URLEncodeSet.UserInfo.self).writeBuffered {
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
        newValue.lazy.percentEncoded(using: URLEncodeSet.UserInfo.self).writeBuffered { piece in
          ptr.initialize(from: piece.baseAddress.unsafelyUnwrapped, count: piece.count)
          ptr += piece.count
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
    return (true, result)
  }

  /// Attempts to set the hostname component to the given UTF8-encoded string. The value will be percent-encoded as appropriate.
  ///
  /// Setting the hostname to an empty or `nil` value is only possible when there are no other authority components (credentials or port).
  /// An empty hostname preserves the `//` separator after the scheme, but the authority component will be empty (e.g. `unix://oldhost/some/path` -> `unix:///some/path`).
  /// A `nil` hostname removes the `//` separator after the scheme, resulting in a so-called "path-only" URL (e.g. `unix://oldhost/some/path` -> `unix:/some/path`).
  ///
  mutating func setHostname<Input>(
    to newValue: Input?,
    filter: Bool = false
  ) -> (Bool, AnyURLStorage) where Input: BidirectionalCollection, Input.Element == UInt8 {

    guard filter == false || newValue == nil else {
      return setHostname(to: newValue.map { ASCII.NewlineAndTabFiltered($0) }, filter: false)
    }

    let oldStructure = header.structure
    guard oldStructure.cannotBeABaseURL == false else {
      return (newValue == nil, AnyURLStorage(self))
    }
    // Excluding 'cannotBeABaseURL' URLs doesn't mean we always have an authority sigil.
    // Path-only URLs (e.g. "hello:/some/path") can be base URLs.
    let hasCredentialsOrPort =
      oldStructure.usernameLength != 0 || oldStructure.passwordLength != 0 || oldStructure.portLength != 0

    guard let newHostnameBytes = newValue, newHostnameBytes.isEmpty == false else {
      if oldStructure.schemeKind.isSpecial, oldStructure.schemeKind != .file {
        return (false, AnyURLStorage(self))
      }
      guard hasCredentialsOrPort == false else {
        return (false, AnyURLStorage(self))
      }
      switch oldStructure.range(of: .hostname) {
      case .none:
        // 'nil' -> 'nil'.
        guard newValue != nil else {
          return (true, AnyURLStorage(self))
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
        return (true, result)

      case .some(let hostnameRange):
        precondition(oldStructure.sigil == .authority, "A URL with a hostname must have an authority sigil")
        var newStructure = oldStructure
        newStructure.hostnameLength = 0

        var commands: [ReplaceSubrangeOperation] = []
        // hostname -> 'nil'.
        // Remove authority sigil, replacing it with a path sigil if necessary.
        if newValue == nil {
          let needsPathSigil = withComponentBytes(.path) { pathBytes -> Bool in
            return pathBytes.map { URLStringUtils.doesNormalizedPathRequirePathSigil($0) } ?? false
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
        return (true, multiReplaceSubrange(commands: commands, newStructure: newStructure))
      }
    }

    var callback = IgnoreValidationErrors()
    guard let newHost = ParsedHost(newHostnameBytes, schemeKind: oldStructure.schemeKind, callback: &callback) else {
      return (false, AnyURLStorage(self))
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

    return (true, multiReplaceSubrange(commands: commands, newStructure: newStructure))
  }

  /// Attempts to set the port component to the given value. A value of `nil` removes the port.
  ///
  mutating func setPort(
    to newValue: UInt16?
  ) -> (Bool, AnyURLStorage) {

    let oldStructure = header.structure
    guard oldStructure.cannotHaveCredentialsOrPort == false else {
      return (false, AnyURLStorage(self))
    }

    var newValue = newValue
    if newValue == oldStructure.schemeKind.defaultPort {
      newValue = nil
    }

    guard let newPort = newValue else {
      return setSimpleComponent(
        .port,
        to: UnsafeBufferPointer?.none,
        prefix: .colon,
        lengthKey: \.portLength,
        encoder: { _, _, _ in preconditionFailure("Cannot encode 'nil' contents") }
      )
    }
    // TODO: More efficient UInt16 serialisation.
    var serialized = String(newPort)
    return serialized.withUTF8 { ptr in
      assert(ptr.isEmpty == false)
      return setSimpleComponent(
        .port,
        to: ptr,
        prefix: .colon,
        lengthKey: \.portLength,
        encoder: { bytes, _, callback in
          callback(bytes)
          return false
        }
      )
    }
  }

  /// Attempts to set the path component to the given UTF8-encoded string.
  ///
  /// A value of `nil` removes the path.
  /// If `filter` is `true`, ASCII tab and newline characters in the given value will be ignored.
  ///
  mutating func setPath<Input>(
    to newValue: Input?,
    filter: Bool = false
  ) -> (Bool, AnyURLStorage) where Input: BidirectionalCollection, Input.Element == UInt8 {

    guard filter == false || newValue == nil else {
      return setPath(to: newValue.map { ASCII.NewlineAndTabFiltered($0) }, filter: false)
    }

    let oldStructure = header.structure
    guard oldStructure.cannotBeABaseURL == false else {
      return (false, AnyURLStorage(self))
    }

    guard let newPath = newValue else {
      // URLs with special schemes must always have a path. Possibly replace this with an empty path?
      guard oldStructure.schemeKind.isSpecial == false else {
        return (false, AnyURLStorage(self))
      }
      guard let existingPath = oldStructure.range(of: .path) else {
        precondition(oldStructure.hasPathSigil == false, "Cannot have a path sigil without a path")
        return (true, AnyURLStorage(self))
      }
      var commands: [ReplaceSubrangeOperation] = []
      var newStructure = oldStructure
      if oldStructure.hasPathSigil {
        commands.append(.remove(subrange: oldStructure.rangeForReplacingSigil))
        newStructure.sigil = .none
      }
      commands.append(.remove(subrange: existingPath))
      newStructure.pathLength = 0
      return (true, multiReplaceSubrange(commands: commands, newStructure: newStructure))
    }

    let pathInfo = PathMetrics(parsing: newPath, schemeKind: oldStructure.schemeKind, baseURL: nil)
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
            baseURL: nil, needsEscaping: pathInfo.needsEscaping
          )
        }))
    return (true, multiReplaceSubrange(commands: commands, newStructure: newStructure))
  }

  /// Attempts to set the query component to the given UTF8-encoded string.
  ///
  /// A value of `nil` removes the query. If `filter` is `true`, ASCII tab and newline characters will be removed from the given string.
  ///
  mutating func setQuery<Input>(
    to newValue: Input?,
    filter: Bool = false
  ) -> (Bool, AnyURLStorage) where Input: Collection, Input.Element == UInt8 {

    guard filter == false || newValue == nil else {
      return setQuery(to: newValue.map { ASCII.NewlineAndTabFiltered($0) }, filter: false)
    }
    return setSimpleComponent(
      .query,
      to: newValue,
      prefix: .questionMark,
      lengthKey: \.queryLength,
      encoder: { writeBufferedPercentEncodedQuery($0, isSpecial: $1.isSpecial, $2) }
    )
  }

  /// Attempts to set the query component to the given UTF8-encoded string.
  ///
  /// A value of `nil` removes the query. If `filter` is `true`, ASCII tab and newline characters will be removed from the given string.
  ///
  mutating func setFragment<Input>(
    to newValue: Input?,
    filter: Bool = false
  ) -> (Bool, AnyURLStorage) where Input: Collection, Input.Element == UInt8 {

    guard filter == false || newValue == nil else {
      return setFragment(to: newValue.map { ASCII.NewlineAndTabFiltered($0) }, filter: false)
    }
    return setSimpleComponent(
      .fragment,
      to: newValue,
      prefix: .numberSign,
      lengthKey: \.fragmentLength,
      encoder: { $0.lazy.percentEncoded(using: URLEncodeSet.Fragment.self).writeBuffered($2) }
    )
  }
}
