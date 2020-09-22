// This file contains types and functions related to parsing paths as part of URL construction.

/// An object which receives iterated path components. The components are visited in reverse order.
///
private protocol PathComponentVisitor {
  
  /// Called when the iterator yields a path component that originates from the input string.
  /// These components may not be contiguously stored and require percent-encoding when written.
  ///
  /// - parameters:
  ///   - pathComponent:                The path component yielded by the iterator.
  ///   - isLeadingWindowsDriveLetter:  If `true`, the component is a Windows drive letter in a `file:` URL.
  ///                                   It should be normalized when written (by writing the first byte followed by the ASCII character `:`).
  ///
  mutating func visitInputPathComponent<InputString>(_ pathComponent: InputString, isLeadingWindowsDriveLetter: Bool)
    where InputString: BidirectionalCollection, InputString.Element == UInt8
  
  /// Called when the iterator yields an empty path component. Note that this does not imply that other methods are always called with non-empty path components.
  /// This method exists solely as an optimisation, since empty components have no content to percent-encode/transform.
  ///
  mutating func visitEmptyPathComponent()
  
  /// Called when the iterator yields a path component that originates from the base URL's path.
  /// These components are known to be contiguously stored, properly percent-encoded, and any Windows drive letters will already have been normalized.
  /// They need no further processing, and may be written to the result as-is.
  ///
  /// - parameters:
  ///   - pathComponent: The path component yielded by the iterator.
  ///
  mutating func visitBasePathComponent(_ pathComponent: UnsafeBufferPointer<UInt8>)
}

/// A `PathComponentVisitor` which calculates the size of the buffer required to write a path.
///
struct PathBufferLengthCalculator: PathComponentVisitor {
  private var length: Int = 0
  
  static func requiredBufferLength<InputString>(
    pathString input: InputString,
    schemeKind: NewURL.Scheme,
    baseURL: NewURL?
  ) -> Int where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    var visitor = PathBufferLengthCalculator()
    visitor.walkPathComponents(
      pathString: input,
      schemeKind: schemeKind,
      baseURL: baseURL
    )
    return visitor.length
  }
  
  fileprivate mutating func visitInputPathComponent<InputString>(_ pathComponent: InputString, isLeadingWindowsDriveLetter: Bool)
  where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    length += 1
    PercentEscaping.encodeReverseIterativelyAsBuffer(
      bytes: pathComponent,
      escapeSet: .url_path,
      processChunk: { piece in length += piece.count }
    )
  }
  
  fileprivate mutating func visitEmptyPathComponent() {
    length += 1
  }
  
  fileprivate mutating func visitBasePathComponent(_ pathComponent: UnsafeBufferPointer<UInt8>) {
    length += 1 + pathComponent.count
  }
}

/// A `PathComponentVisitor` which writes a properly percent-encoded, normalised URL path string
/// in to a preallocated buffer. Use the `PathBufferLengthCalculator` to calculate the buffer's required size.
///
struct PathPreallocatedBufferWriter: PathComponentVisitor {
  private let buffer: UnsafeMutableBufferPointer<UInt8>
  private var front: Int
  
  static func writePath<InputString>(
    to buffer: UnsafeMutableBufferPointer<UInt8>,
    pathString input: InputString,
    schemeKind: NewURL.Scheme,
    baseURL: NewURL?
  ) -> Void where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    // Checking this now allows the implementation to use `.baseAddress.unsafelyUnwrapped`.
    precondition(buffer.baseAddress != nil)
    var visitor = PathPreallocatedBufferWriter(buffer: buffer, front: buffer.endIndex)
    visitor.walkPathComponents(
      pathString: input,
      schemeKind: schemeKind,
      baseURL: baseURL
    )
    precondition(visitor.front == buffer.startIndex, "Failed to initialise entire buffer")
  }
  
  private mutating func prependSlash() {
    front = buffer.index(before: front)
    buffer.baseAddress.unsafelyUnwrapped.advanced(by: front)
      .initialize(to: ASCII.forwardSlash.codePoint)
  }

  fileprivate mutating func visitInputPathComponent<InputString>(_ pathComponent: InputString, isLeadingWindowsDriveLetter: Bool)
  where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    guard pathComponent.isEmpty == false else {
      prependSlash()
      return
    }
    guard isLeadingWindowsDriveLetter == false else {
      assert(pathComponent.count == 2)
      front = buffer.index(front, offsetBy: -2)
      buffer.baseAddress.unsafelyUnwrapped.advanced(by: front)
        .initialize(to: pathComponent[pathComponent.startIndex])
      buffer.baseAddress.unsafelyUnwrapped.advanced(by: front &+ 1)
        .initialize(to: ASCII.colon.codePoint)
      prependSlash()
      return
    }
    PercentEscaping.encodeReverseIterativelyAsBuffer(
      bytes: pathComponent,
      escapeSet: .url_path,
      processChunk: { piece in
        let newFront = buffer.index(front, offsetBy: -1 * piece.count)
        buffer.baseAddress.unsafelyUnwrapped.advanced(by: newFront)
          .initialize(from: piece.baseAddress!, count: piece.count)
        front = newFront
    })
    prependSlash()
  }
  
  fileprivate mutating func visitEmptyPathComponent() {
    prependSlash()
  }
  
  fileprivate mutating func visitBasePathComponent(_ pathComponent: UnsafeBufferPointer<UInt8>) {
    front = buffer.index(front, offsetBy: -1 * pathComponent.count)
    buffer.baseAddress.unsafelyUnwrapped.advanced(by: front)
      .initialize(from: pathComponent.baseAddress!, count: pathComponent.count)
    prependSlash()
  }
}

/// A `PathComponentVisitor` which emits URL validation errors for non-URL code points, invalid percent encoding,
/// and use of backslashes as path separators.
///
struct PathInputStringValidator<Input, Callback>: PathComponentVisitor
where Input: BidirectionalCollection, Input.Element == UInt8, Input == Input.SubSequence, Callback: URLParserCallback {
  private var callback: Callback
  private let path: Input.SubSequence
  
  static func validatePathComponents(
    pathString input: Input,
    schemeKind: NewURL.Scheme,
    callback: inout Callback
  ) -> Void {
    var visitor = PathInputStringValidator(callback: callback, path: input)
    visitor.walkPathComponents(
      pathString: input,
      schemeKind: schemeKind,
      baseURL: nil
    )
  }
  
  fileprivate mutating func visitInputPathComponent<InputString>(_ pathComponent: InputString, isLeadingWindowsDriveLetter: Bool)
  where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    
    guard let pathComponent = pathComponent as? Input.SubSequence else {
      preconditionFailure("Unexpected slice type")
    }
    if pathComponent.endIndex != path.endIndex, ASCII(path[pathComponent.endIndex]) == .backslash {
      callback.validationError(.unexpectedReverseSolidus)
    }
    validateURLCodePointsAndPercentEncoding(pathComponent, callback: &callback)
  }
  fileprivate mutating func visitEmptyPathComponent() {
    // Nothing to do.
  }
  fileprivate mutating func visitBasePathComponent(_ pathComponent: UnsafeBufferPointer<UInt8>) {
    assertionFailure("Should never be invoked without a base URL")
  }
}

extension PathComponentVisitor {
  
  /// Iterates the simplified components of a given path string, optionally applied relative to a base URL's path.
  /// The components are iterated in reverse order, and yielded via 3 callbacks.
  ///
  /// A path string, such as `"a/b/c/.././d/e/../f/"`, describes a traversal through a tree of nodes.
  /// In order to resolve which nodes are present in the final path without allocating dynamic storage to represent the stack of visited nodes,
  /// the components must be iterated in reverse.
  ///
  /// To construct a simplified path string, repeatedly prepend `"/"` (forward slash) followed by the component, to a resulting string.
  /// For example, the input `"a/b/"` yields the components `["", "b", "a"]`, and the construction proceeds as follows:
  /// `"/" -> "/b/" -> "/a/b/"`. The components are yielded by 3 callbacks, all of which build a single result:
  ///
  ///  - `visitInputPathComponent` yields a component from the input string.
  ///     These components may be expensive to iterate and must be percent-encoded when written.
  ///     In some circumstances, Windows drive letter components require normalisation. If the boolean flag is `true`, handlers should
  ///     check if the component is a Windows drive letter and normalize it if it is.
  ///  - `visitEmptyPathComponent` yields an empty component. Not all empty components are guaranteed to be called via this method,
  ///     but it can be more efficient when we know the component is empty and doesn't need escaping or other checks.
  ///  - `visitBasePathComponent` yields a component from the base URL's path.
  ///     These components are known to be contiguously stored, properly percent-encoded, and any Windows drive letters will already have been normalized.
  ///     They can essentially need no further processing, and may be written to the result as-is.
  ///
  /// If the input string is empty, no callbacks will be called unless the scheme is special, in which case there is always an implicit empty path.
  /// If the input string is not empty, this function will always yield something.
  ///
  fileprivate mutating func walkPathComponents<InputString>(
    pathString input: InputString,
    schemeKind: NewURL.Scheme,
    baseURL: NewURL?
  ) where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    
    let schemeIsSpecial = schemeKind.isSpecial
    let isFileScheme = (schemeKind == .file)
    
    // Special URLs have an implicit, empty path.
    guard input.isEmpty == false else {
      if schemeIsSpecial {
        visitEmptyPathComponent()
      }
      return
    }
    
    let isPathComponentTerminator: (_ byte: UInt8) -> Bool
    if schemeIsSpecial {
      isPathComponentTerminator = { byte in ASCII(byte) == .forwardSlash || ASCII(byte) == .backslash }
    } else {
      isPathComponentTerminator = { byte in ASCII(byte) == .forwardSlash }
    }
    
    var contentStartIdx = input.startIndex
    
    // Trim leading slash if present.
    if isPathComponentTerminator(input[contentStartIdx]) {
      contentStartIdx = input.index(after: contentStartIdx)
    }
    // File paths trim _all_ leading slashes, single- and double-dot path components.
    if isFileScheme {
      while contentStartIdx != input.endIndex, isPathComponentTerminator(input[contentStartIdx]) {
        // callback.validationError(.unexpectedEmptyPath)
        contentStartIdx = input.index(after: contentStartIdx)
      }
      while let terminator = input[contentStartIdx...].firstIndex(where: isPathComponentTerminator) {
        let component = input[contentStartIdx..<terminator]
        guard URLStringUtils.isSingleDotPathSegment(component) || URLStringUtils.isDoubleDotPathSegment(component) || component.isEmpty else {
          break
        }
        contentStartIdx = input.index(after: terminator)
      }
    }
    
    // If the input is now empty after trimming, it is either a lone slash (non-file) or string of slashes and dots (file).
    // All of these possible inputs get shortened down to "/", and are not relative to the base path.
    // With one exception: if this is a file URL and the base path starts with a Windows drive letter (X), the result is just "X:/"
    guard contentStartIdx != input.endIndex else {
      var didYield = false
      if isFileScheme {
        baseURL?.withComponentBytes(.path) {
          guard let basePath = $0?.dropFirst() else { return } // dropFirst() due to the leading slash.
          if URLStringUtils.hasWindowsDriveLetterPrefix(basePath) {
            visitEmptyPathComponent()
            visitBasePathComponent(UnsafeBufferPointer(rebasing: basePath.prefix(2)))
            didYield = true
          }
        }
      }
      if !didYield {
        visitEmptyPathComponent()
      }
      return
    }
    
    // Path component special cases:
    //
    // - Single dot ('.') components get skipped.
    //   - If at the end of the path, they force a trailing slash/empty component.
    // - Double dot ('..') components pop previous components from the path.
    //   - For file URLs, they do not pop the last component if it is a Windows drive letter.
    //   - If at the end of the path, they force a trailing slash/empty component.
    //     (even if they have popped all other components, the result is an empty path, not a nil path)
    // - Consecutive empty components at the start of a file URL get collapsed.
    
    // Iterate the path components in reverse, so we can skip components which later get popped.
    var path = input[contentStartIdx...]
    var popcount = 0
    var trailingEmptyCount = 0
    var didYieldComponent = false
    
    func flushTrailingEmpties() {
      if trailingEmptyCount != 0 {
        for _ in 0 ..< trailingEmptyCount {
          visitEmptyPathComponent()
        }
        didYieldComponent = true
        trailingEmptyCount = 0
      }
    }
    
    // Consume components separated by terminators.
    // Since we stripped the initial slash, this loop never sees the initial path component
    // unless it is empty and the scheme is not file.
    while let componentTerminatorIndex = path.lastIndex(where: isPathComponentTerminator) {
      
      let pathComponent = input[path.index(after: componentTerminatorIndex)..<path.endIndex]
      defer { path = path.prefix(upTo: componentTerminatorIndex) }
      
      if ASCII(input[componentTerminatorIndex]) == .backslash {
        //callback.validationError(.unexpectedReverseSolidus)
      }
      
      // '..' -> skip it and increase the popcount.
      // If at the end of the path, mark it as a trailing empty.
      guard URLStringUtils.isDoubleDotPathSegment(pathComponent) == false else {
        popcount += 1
        if pathComponent.endIndex == input.endIndex {
          trailingEmptyCount += 1
        }
        continue
      }
      // Every other component (incl. '.', empty components) can be popped.
      guard popcount == 0 else {
        popcount -= 1
        continue
      }
      // '.' -> skip it.
      // If at the end of the path, mark it as a trailing empty.
      if URLStringUtils.isSingleDotPathSegment(pathComponent) {
        if pathComponent.endIndex == input.endIndex {
          trailingEmptyCount += 1
        }
        continue
      }
      // '' (empty) -> defer processing.
      if pathComponent.isEmpty {
        trailingEmptyCount += 1
        continue
      }
      flushTrailingEmpties()
      visitInputPathComponent(pathComponent, isLeadingWindowsDriveLetter: false)
      didYieldComponent = true
    }
    
    // If the remainder (first component) is empty, if means the path begins with a '//'.
    // This can't be a file URL, because we would have stripped that.
    assert(path.isEmpty ? isFileScheme == false : true)
    
    switch path {
    case _ where URLStringUtils.isDoubleDotPathSegment(path):
      popcount += 1
      fallthrough
    case _ where URLStringUtils.isSingleDotPathSegment(path):
      // Ensure we have a trailing slash.
      if !didYieldComponent {
        trailingEmptyCount = max(trailingEmptyCount, 1)
      }
      
    case _ where URLStringUtils.isWindowsDriveLetter(path) && isFileScheme:
      flushTrailingEmpties()
      visitInputPathComponent(path, isLeadingWindowsDriveLetter: true)
      return // Never appended to base URL.
    
    case _ where popcount == 0:
      flushTrailingEmpties()
      visitInputPathComponent(path, isLeadingWindowsDriveLetter: false)
      didYieldComponent = true
      
    default:
      popcount -= 1
      break // Popped out.
    }
    
    // The leading component has now been processed.
    // If there is no base URL to carry state forward to, we need to flush anything that was deferred.
    path = path.prefix(0)
    guard let baseURL = baseURL else {
      if didYieldComponent == false {
        // If we haven't yielded anything yet, it's because the leading component was popped-out or skipped.
        // Make sure we have at least (or for files, exactly) 1 trailing empty to yield when we flush.
        trailingEmptyCount = isFileScheme ? 1 : max(trailingEmptyCount, 1)
      }
      flushTrailingEmpties()
      return
    }
    
    baseURL.withComponentBytes(.path) {
      guard var basePath = $0?[...] else {
        // No base path. Flush state from input string, as above.
        assert(baseURL.schemeKind.isSpecial == false, "Special URLs always have a path")
        if didYieldComponent == false {
          trailingEmptyCount = isFileScheme ? 1 : max(trailingEmptyCount, 1)
        }
        flushTrailingEmpties()
        return
      }
      // Trim the leading slash.
      if basePath.first == ASCII.forwardSlash.codePoint {
        basePath = basePath.dropFirst()
      }
      // Drop the last path component.
      if basePath.last == ASCII.forwardSlash.codePoint {
        basePath = basePath.dropLast()
      } else if isFileScheme {
        // file URLs don't drop leading Windows drive letters.
        let lastPathComponent: Slice<UnsafeBufferPointer<UInt8>>
        let trimmedBasePath: Slice<UnsafeBufferPointer<UInt8>>
        if let terminatorBeforeLastPathComponent = basePath.lastIndex(of: ASCII.forwardSlash.codePoint) {
          trimmedBasePath   = basePath[..<terminatorBeforeLastPathComponent]
          lastPathComponent = basePath[terminatorBeforeLastPathComponent...].dropFirst()
        } else {
          trimmedBasePath   = basePath.prefix(0)
          lastPathComponent = basePath
        }
        if !(lastPathComponent.startIndex == basePath.startIndex && URLStringUtils.isWindowsDriveLetter(lastPathComponent)) {
          basePath = trimmedBasePath
        }
      } else {
        basePath = basePath[..<(basePath.lastIndex(of: ASCII.forwardSlash.codePoint) ?? basePath.startIndex)]
      }
      
      // Consume remaining components. Continue to observe popcount and trailing empties.
      while let componentTerminatorIndex = basePath.lastIndex(of: ASCII.forwardSlash.codePoint) {
        let pathComponent = basePath[basePath.index(after: componentTerminatorIndex)..<basePath.endIndex]
        defer { basePath = basePath.prefix(upTo: componentTerminatorIndex) }
        
        assert(URLStringUtils.isDoubleDotPathSegment(pathComponent) == false)
        assert(URLStringUtils.isSingleDotPathSegment(pathComponent) == false)
        guard popcount == 0 else {
          popcount -= 1
          continue
        }
        if pathComponent.isEmpty {
          trailingEmptyCount += 1
          continue
        }
        flushTrailingEmpties()
        visitBasePathComponent(UnsafeBufferPointer(rebasing: pathComponent))
        didYieldComponent = true
      }
      // We're left with the leading path component from the base URL (i.e. the very start of the resulting path).
      
      guard popcount == 0 else {
        // Leading Windows drive letters cannot be popped-out.
        if isFileScheme, URLStringUtils.isWindowsDriveLetter(basePath) {
          trailingEmptyCount = max(1, trailingEmptyCount)
          flushTrailingEmpties()
          visitBasePathComponent(UnsafeBufferPointer(rebasing: basePath))
          return
        }
        if !isFileScheme {
          flushTrailingEmpties()
        }
        if didYieldComponent == false {
          visitEmptyPathComponent()
        }
        return
      }
      
      assert(URLStringUtils.isDoubleDotPathSegment(basePath) == false)
      assert(URLStringUtils.isSingleDotPathSegment(basePath) == false)
      
      if basePath.isEmpty {
        // We are at the very start of the path. File URLs discard empties.
        if !isFileScheme {
          flushTrailingEmpties()
        }
        if didYieldComponent == false {
          // If we still didn't yield anything and basePath is empty, any components have been popped to a net zero result.
          // Yield an empty path.
          visitEmptyPathComponent()
        }
        return
      }
      flushTrailingEmpties()
      visitBasePathComponent(UnsafeBufferPointer(rebasing: basePath))
    }
  }
}
