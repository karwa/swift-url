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

/// An object which parses a path string.
///
/// This protocol is an implementation detail. It defines a group of callbacks which are invoked by the `walkPathComponents` method
/// and should not be called directly. Conforming types implement these callbacks, as well as another method/initializer which invokes `walkPathComponents` to
/// compute any information the type requires about the path.
///
/// Conforming types should be aware that components are visited in reverse order. Given a path "a/b/c", the components visited would be "c", "b", and finally "a".
/// All of the visited path components are present in the simplified path string, with all pushing/popping handled internally by the `walkPathComponents` method.
///
/// Visited path components may originate from 2 sources:
///
/// - They may be slices of some string given as an input. In order to be written as a normalized path string, they must
///   be percent-encoded and adjustments must be made to Windows drive letters.
/// - They may be slices of an existing, normalized path string, coming from a URL object given as the "base URL". In this case, things are a bit easier -
///   These components require no further processing before they are incorporated in to a normalized path string, and are known to exist in contiguous storage.
///
@usableFromInline
internal protocol _PathParser {
  associatedtype InputString: BidirectionalCollection where InputString.Element == UInt8

  /// A callback which is invoked when the parser yields a path component originating from the input string.
  /// These components may not be contiguously stored and require percent-encoding before writing.
  ///
  /// - parameters:
  ///   - pathComponent:         The path component yielded by the parser.
  ///   - isWindowsDriveLetter:  If `true`, the component is a Windows drive letter in a `file:` URL.
  ///                            It should be normalized when written (by writing the first byte followed by the ASCII character `:`).
  ///
  mutating func visitInputPathComponent(_ pathComponent: InputString.SubSequence, isWindowsDriveLetter: Bool)

  /// A callback which is invoked when the parser yields a path component originating from the base URL's path.
  /// These components are known to be contiguously stored, properly percent-encoded, and any Windows drive letters will already have been normalized.
  /// They need no further processing, and may be written to the result as-is.
  ///
  /// - parameters:
  ///   - pathComponent: The path component yielded by the parser.
  ///
  mutating func visitBasePathComponent(_ pathComponent: WebURL.UTF8View.SubSequence)

  /// A callback which is invoked when the parser yields a number of consecutive empty path components.
  /// Note that this does not imply that path components yielded via other callbacks are non-empty.
  ///
  /// This method exists as an optimisation, since empty components have no content to percent-encode/transform.
  ///
  mutating func visitEmptyPathComponents(_ n: Int)

  /// A callback which is invoked when the parser yields a path sigil ("/.") in order to disambiguate a path with leading slashes from an authority.
  /// Conformers should ensure that a "/." is prepended to the path string if it is written to a URL without an authority sigil.
  ///
  /// If a sigil is yielded, it is always the very start of the path and the parser will not yield any components after this.
  ///
  mutating func visitPathSigil()

  /// An optional callback which is invoked when the parser encounters a non-fatal URL syntax oddity.
  ///
  /// The default implementation does nothing.
  ///
  mutating func visitValidationError(_ error: ValidationError)
}

extension _PathParser {

  /// A callback which is invoked when the parser yields an empty path component.
  /// Note that this does not imply that path components yielded via other callbacks are non-empty.
  ///
  /// This method exists as an optimisation, since empty components have no content to percent-encode/transform.
  ///
  @inlinable
  internal mutating func visitEmptyPathComponent() {
    visitEmptyPathComponents(1)
  }

  @inlinable
  internal mutating func visitValidationError(_ error: ValidationError) {
    // No required action.
  }
}


// --------------------------------------------
// MARK: - Parsing
// --------------------------------------------


@usableFromInline
internal enum _DeferredPathComponent<Source: Collection> {
  case potentialWindowsDrive(Source, UInt)
  case empties(Int)

  @inlinable
  internal var isPotentialWindowsDrive: Bool {
    if case .potentialWindowsDrive = self { return true }
    return false
  }

  /// Whether this component contains enough deferred empties to require a path sigil, were it to be flushed as the start of a path string.
  ///
  @inlinable
  internal func needsPathSigilWhenFlushing(_ state: _PathParserState) -> Bool {
    if state.didYieldComponent {
      if case .empties(let count) = self {
        return count != 0
      }
    } else {
      if case .empties(let count) = self {
        return count > 1
      }
    }
    return false
  }
}

@usableFromInline
internal struct _PathParserState {

  @usableFromInline
  internal var popcount: UInt

  @usableFromInline
  internal var didYieldComponent: Bool

  @inlinable
  internal init() {
    self.popcount = 0
    self.didYieldComponent = false
  }
}

extension _PathParser {

  // Note: When making these local functions inside 'walkPathComponents', the compiler fails to prove they
  // don't escape and introduces heap allocations which dominate the performance of the entire parser.

  /// Defers an empty path component. If there are already empty components deferred, it will be added to them.
  ///
  /// Asserts that no potential Windows drive letters have been deferred.
  ///
  @inlinable
  internal mutating func _deferEmptyAssertNotWindowsDrive(
    _ deferred: inout _DeferredPathComponent<InputString.SubSequence>?, _ state: inout _PathParserState
  ) {

    assert(state.popcount == 0, "This component has been popped. Cannot defer empty.")
    guard case .empties(let count) = deferred else {
      assert(deferred == nil, "Windows drive already deferred! Cannot defer empty.")
      deferred = .empties(1)
      return
    }
    deferred = .empties(count &+ 1)
  }

  /// Flushes deferred empty components, if there are any, and asserts that no potential Windows drive letters have been deferred.
  ///
  @inlinable
  internal mutating func _flushEmptiesAssertNotWindowsDrive(
    _ deferred: inout _DeferredPathComponent<InputString.SubSequence>?, _ state: inout _PathParserState
  ) {

    guard case .empties(let count) = deferred else {
      assert(deferred == nil, "Windows drive deferred! Cannot flush empties")
      return
    }
    assert(count != 0, "0 is not a valid number of deferred empties")
    visitEmptyPathComponents(count)
    state.didYieldComponent = true
    deferred = .none
  }

  /// Flushes the deferred component(s).
  ///
  /// - For potential Windows drives, this means we have confirmed that the component is *not* a Windows drive.
  ///   If the `popcount` on the RHS of the candidate was 0, the candidate is yielded as a regular component.
  ///   Otherwise, the candidate is popped (like any other component would have been), and any remaining popcount from its RHS
  ///   is merged with the parser's current `popcount`.
  ///
  /// - Empty components are yielded.
  ///
  @inlinable
  internal mutating func _flushAndMergePopcount(
    _ deferred: inout _DeferredPathComponent<InputString.SubSequence>?,
    _ state: inout _PathParserState
  ) {
    guard case .potentialWindowsDrive(let componentContent, var storedPopcount) = deferred else {
      _flushEmptiesAssertNotWindowsDrive(&deferred, &state)
      return
    }
    if storedPopcount == 0 {
      visitInputPathComponent(componentContent, isWindowsDriveLetter: false)
      state.didYieldComponent = true
    } else {
      storedPopcount -= 1
    }
    state.popcount += storedPopcount
    deferred = .none
  }

  /// Flushes the deferred component(s) appropriately for the start of the path string.
  ///
  /// - For potential Windows drives, this means we have confirmed that the component *is* a Windows drive. It will be yielded with the appropriate flag.
  ///
  /// - Empty components are yielded, and if a path sigil is required, that is yielded, too.
  ///
  @inlinable
  internal mutating func _flushForFinalization(
    _ deferred: inout _DeferredPathComponent<InputString.SubSequence>?,
    _ state: inout _PathParserState, _ hasAuthority: Bool
  ) {
    switch deferred {
    case .potentialWindowsDrive(let firstComponent, _):
      visitInputPathComponent(firstComponent, isWindowsDriveLetter: true)
      return
    // If we haven't yielded anything yet, make sure we at least write an empty path.
    case .empties(let count):
      if state.didYieldComponent == false {
        assert(count != 0)
      }
    case .none:
      if state.didYieldComponent == false {
        // This should be impossible to reach. A non-empty path string which doesn't yield anything would
        // need to pop, and would need to at least end in a "..", but the parser ensures that such paths end in a "/".
        // Handle it to make *absolutely* sure we don't accidentally create a URL with 'nil' path from non-empty input.
        assertionFailure("Finalizing a path without yielding or deferring anything?!")
        deferred = .empties(1)
      }
    }
    let needsPathSigil = deferred?.needsPathSigilWhenFlushing(state) ?? false
    _flushEmptiesAssertNotWindowsDrive(&deferred, &state)
    if needsPathSigil, !hasAuthority {
      visitPathSigil()
    }
  }

  /// Parses the given path string, optionally relative to the path of a base URL object, and yields the simplified list of path components via callbacks
  /// implemented on this `_PathParser`. The path components are yielded in *reverse order*.
  ///
  /// To construct the simplified path string, start with an empty string. For each path component yielded by the parser,
  /// prepend `"/"` (ASCII forward slash) followed by the path component's contents, to that string. Note that path components from the input string may require
  /// additional adjustments such as percent-encoding or drive letter normalization as described in the documentation for `visitInputPathComponent`.
  ///
  /// For example, consider the input `"a/b/../c/"`, which normalizes to the path string `"/a/c/"`.
  /// This method yields the components `["", "c", "a"]`, and path construction by prepending proceeds as follows: `"/" -> "/c/" -> "/a/c/"`.
  ///
  /// - Note:
  /// The only case in which this function does not yield a path is when the scheme is not special and the URL has an authority.
  /// All other inputs, including empty strings, produce a non-empty path.
  ///
  /// - parameters:
  ///  - input: The path string to parse, as a collection of UTF-8 code-units.
  ///  - schemeKind: The scheme of the URL which the path will be part of.
  ///  - hasAuthority: Whether the URL this path will be part of has an authority component.
  ///  - baseURL: The URL whose path serves as the "base" for the input string, if it is a relative path.
  ///             Note that there are some edge-cases related to Windows drive letters which require
  ///             the base URL be provided (if present), even for absolute paths.
  ///  - absolutePathsCopyWindowsDriveFromBase: A flag set by the URL parser to enable special behaviours for absolute paths in path-only file
  ///                                           URLs, forcing them to be relative to the base URL's Windows drive, even if the given path contains
  ///                                           its own Windows drive. For example, the path-only URL "file:/hello" parsed against the base URL
  ///                                           "file:///C:/Windows" results in "file:///C:/hello", but the non-path-only
  ///                                           URL "file:///hello" results in "file:///hello" when parsed against the same base URL.
  ///                                           In both cases the path parser only sees the string "/hello" as its input, so the value of this flag must
  ///                                           be determined by the URL parser.
  ///
  @inlinable @inline(never)
  internal mutating func walkPathComponents(
    pathString input: InputString,
    schemeKind: WebURL.SchemeKind,
    hasAuthority: Bool,
    baseURL: WebURL?,
    absolutePathsCopyWindowsDriveFromBase: Bool
  ) {

    guard input.isEmpty == false else {
      // Special URLs have an implicit path.
      // Non-special URLs may only have an empty path if they have an authority
      // (otherwise they would be non-hierarchical URLs).
      if schemeKind.isSpecial || !hasAuthority {
        visitEmptyPathComponent()
      }
      return
    }

    let isFileScheme = (schemeKind == .file)

    // Determine if this is an absolute or relative path, as denoted by a leading path separator ("usr/lib" vs "/usr/lib").

    let input_firstComponentStart: InputString.Index
    let isInputAbsolute = PathComponentParser.isPathSeparator(input[input.startIndex], scheme: schemeKind)
    if isInputAbsolute {
      input_firstComponentStart = input.index(after: input.startIndex)
    } else {
      input_firstComponentStart = input.startIndex
    }

    guard input_firstComponentStart < input.endIndex else {
      // The input string is a single separator, i.e. an absolute root path.
      // We can fast-path this: it results in a single "/", or the drive root if baseURL has a Windows drive letter.
      assert(isInputAbsolute)
      visitEmptyPathComponent()
      if isFileScheme, let base = baseURL {
        let _baseDrive = PathComponentParser._normalizedWindowsDrive(
          in: base.utf8.path, firstCmptLength: Int(base.storage.structure.firstPathComponentLength)
        )
        if let baseDrive = _baseDrive {
          visitBasePathComponent(baseDrive)
        }
      }
      return
    }

    // Consume path components from the end.
    //
    // Consuming in reverse means that we can avoid tracking the shortened path in an dynamically-sized Array.
    // Instead, we maintain an integer `popcount`, which tells us how many components towards the front ultimately get
    // popped and removed from the traversal. For instance, consider the path "/p1/p2/../p3/p4/p5/../../p6":
    // - When we see p6, the popcount is 0. p6 is yielded.
    // - When we see p5 and p4, the popcount is 2 and 1 respectively. They are not yielded.
    // - When we see p3, the popcount is 0 again, and it is yielded. p2 is not yielded, p1 is.
    // Hence the final path is p1/p3/p6 - only, we discovered that information in reverse order (["p6", "p3", "p1"]).
    //
    // The downside is that it's harder for us to tell when something is at the start of the final path
    // or whether other components may appear before it. For this reason, some components which have different
    // behaviour get deferred until we can make that determination.
    //
    // Deferred Components
    // ===================
    //
    // - Potential Windows drive letters (file URLs only). The parser in the URL standard visits components in-order,
    //   "shortening" (popping) when it sees a "..", unless the pop would remove the first component, and that component
    //   is a Windows drive letter. That means:
    //
    //     1. Windows drives cannot be popped ("C:/../../../foo" becomes "C:/foo")
    //     2. Arbitrary stuff can appear before the drive, as long as it gets popped-out later.
    //        When parsing "abc/../C:", at some point "C:" will land at path[0], at which point nothing can pop it out.
    //
    //   So when we see a potential Windows drive letter, we stash the component and popcount at that point, and
    //   continue parsing everything left of the component. For a string like "abc/../C:", nothing on the left
    //   actually yields a component, so the candidate "C:" is confirmed as a drive letter. If something does yield
    //   ("abc/C:"), we know the candidate isn't really a drive, so we consider if it should have been popped and
    //   merge the stashed popcount from the RHS with the one from the LHS.
    //
    // - Empty components. These were originally deferred because an older version of the standard required
    //   empty components at the start of file paths to be removed (changed in https://github.com/whatwg/url/pull/544).
    //   Currently, they are used to detect if the last yielded component was empty, and the resulting path string
    //   would start with 2 slashes (e.g. "//p2"). https://github.com/whatwg/url/pull/505 introduced what we call
    //   a "path sigil" for such paths, and tracking empty components is handy for that.
    //
    // Other special components
    // ========================
    //
    // - Single dot ('.') components get skipped.
    //   - If at the end of the path, they force a trailing slash/empty component.
    //   - They cannot be independently popped; e.g. "/a/b/./../" -> "/a/", not "/a/b/".
    //
    // - Double dot ('..') components pop previous components from the path.
    //   - For file URLs, they do not pop beyond a Windows drive letter.
    //   - If at the end of the path, they force a trailing slash/empty component.
    //     (even if they have popped all other components, the result is an empty path, not a nil path)

    var remainingInput = input[...]
    var state = _PathParserState()
    var deferredComponent: _DeferredPathComponent<InputString.SubSequence>? = .none

    repeat {
      let separatorIndex = remainingInput.lastIndex { PathComponentParser.isPathSeparator($0, scheme: schemeKind) }
      let pathComponent: InputString.SubSequence
      if let separatorIdx = separatorIndex {
        pathComponent = remainingInput[remainingInput.index(after: separatorIdx)...]
        if ASCII(input[separatorIdx]) == .backslash {
          visitValidationError(.unexpectedReverseSolidus)
        }
      } else {
        pathComponent = remainingInput
      }

      switch pathComponent {
      case _ where PathComponentParser.isDoubleDotPathSegment(pathComponent):
        state.popcount &+= 1
        fallthrough

      case _ where PathComponentParser.isSingleDotPathSegment(pathComponent):
        // Don't defer this as it would have no effect due to the popcount increment.
        // Since this must be at the end of the path, 'didYieldComponent' is sufficient for calculating path sigil.
        if pathComponent.endIndex == input.endIndex {
          visitEmptyPathComponent()
          state.didYieldComponent = true
        }

      case _ where isFileScheme && PathComponentParser.isWindowsDriveLetter(pathComponent):
        _flushAndMergePopcount(&deferredComponent, &state)
        deferredComponent = .potentialWindowsDrive(pathComponent, state.popcount)
        state.popcount = 0

      case _ where state.popcount > 0:
        state.popcount -= 1

      case _ where deferredComponent?.isPotentialWindowsDrive == true:
        _flushAndMergePopcount(&deferredComponent, &state)
        continue  // Re-check this component with the new popcount.

      default:
        if pathComponent.isEmpty {
          _deferEmptyAssertNotWindowsDrive(&deferredComponent, &state)
        } else {
          _flushEmptiesAssertNotWindowsDrive(&deferredComponent, &state)
          visitInputPathComponent(pathComponent, isWindowsDriveLetter: false)
          state.didYieldComponent = true
        }
      }

      remainingInput = remainingInput[..<(separatorIndex ?? remainingInput.startIndex)]
    } while !remainingInput.isEmpty

    assert(
      deferredComponent != nil || state.didYieldComponent,
      "Since the input path was not empty, we must have either deferred or yielded something from it."
    )

    let _basePath = baseURL?.utf8.path
    var baseDrive: WebURL.UTF8View.SubSequence?

    if isFileScheme {
      if let basePath = _basePath {
        let baseURLFirstCmptLength = baseURL.unsafelyUnwrapped.storage.structure.firstPathComponentLength
        baseDrive = PathComponentParser._normalizedWindowsDrive(
          in: basePath, firstCmptLength: Int(baseURLFirstCmptLength)
        )
      }
      // If the first written component of the input string is a Windows drive letter, the path is never relative -
      // even if it normally would be. [URL Standard: "file" state, "file slash" state]
      if case .potentialWindowsDrive(let firstComponent, _) = deferredComponent,
        firstComponent.startIndex == input_firstComponentStart
      {
        visitInputPathComponent(firstComponent, isWindowsDriveLetter: true)
        return
      }
      // If the Windows drive is not the first written component of the input string, and the path is absolute,
      // we still prefer to use the drive from the base URL. [URL Standard: "file slash" state]
      if isInputAbsolute, absolutePathsCopyWindowsDriveFromBase, let baseDrive = baseDrive {
        _flushAndMergePopcount(&deferredComponent, &state)
        visitBasePathComponent(baseDrive)
        return
      }
    }

    guard isInputAbsolute == false, let basePath = _basePath, basePath.startIndex < basePath.endIndex else {
      _flushForFinalization(&deferredComponent, &state, hasAuthority)
      return  // Absolute paths, and relative paths with no base URL, are finished now.
    }
    assert(basePath.first == ASCII.forwardSlash.codePoint, "Normalized non-empty base paths must start with a /")

    // Drop the last base path component (unless it is a Windows drive, in which case flush and we're done).
    if let baseDrive = baseDrive, basePath.count == 3 {
      _flushAndMergePopcount(&deferredComponent, &state)
      visitBasePathComponent(baseDrive)
      return
    }
    var remainingBasePath = basePath[..<(basePath.lastIndex(of: ASCII.forwardSlash.codePoint) ?? basePath.startIndex)]

    while let separatorIndex = remainingBasePath.lastIndex(of: ASCII.forwardSlash.codePoint) {
      let pathComponent = remainingBasePath[
        Range(uncheckedBounds: (remainingBasePath.index(after: separatorIndex), remainingBasePath.endIndex))
      ]

      assert(PathComponentParser.isDoubleDotPathSegment(pathComponent) == false)
      assert(PathComponentParser.isSingleDotPathSegment(pathComponent) == false)

      switch pathComponent {
      // If we reached the base path's Windows drive letter, we can flush everything and end.
      case _ where separatorIndex == basePath.startIndex && baseDrive != nil:
        _flushAndMergePopcount(&deferredComponent, &state)
        visitBasePathComponent(baseDrive!)
        return

      case _ where state.popcount != 0:
        state.popcount -= 1

      case _ where deferredComponent?.isPotentialWindowsDrive == true:
        _flushAndMergePopcount(&deferredComponent, &state)
        continue  // Re-check this component with the new popcount.

      default:
        if pathComponent.isEmpty {
          _deferEmptyAssertNotWindowsDrive(&deferredComponent, &state)
        } else {
          _flushEmptiesAssertNotWindowsDrive(&deferredComponent, &state)
          visitBasePathComponent(pathComponent)
          state.didYieldComponent = true
        }
      }

      remainingBasePath = remainingBasePath[Range(uncheckedBounds: (remainingBasePath.startIndex, separatorIndex))]
    }

    assert(remainingBasePath.isEmpty, "Normalized non-empty base paths must start with a /")
    _flushForFinalization(&deferredComponent, &state, hasAuthority)
    // Finally done!
  }
}


// --------------------------------------------
// MARK: - Parsers
// --------------------------------------------


/// A summary of statistics about a of the lexically-normalized, percent-encoded path string.
///
@usableFromInline
internal struct PathMetrics {

  /// The precise length of the path string, in bytes.
  @usableFromInline
  internal private(set) var requiredCapacity: Int

  /// The length of the first path component, in bytes, including its leading "/".
  @usableFromInline
  internal private(set) var firstComponentLength: Int

  /// The number of components in the path.
  @usableFromInline
  internal private(set) var numberOfComponents: Int

  /// Whether or not the path must be prefixed with a path sigil when it is written to a URL which does not have an authority sigil.
  @usableFromInline
  internal private(set) var requiresPathSigil: Bool

  /// Whether there is at least one component in the path which needs percent-encoding.
  @usableFromInline
  internal private(set) var needsPercentEncoding: Bool
}

extension PathMetrics {

  /// Creates a `PathMetrics` object containing information about the shape of the given path-string if it were written in its simplified, normalized form.
  ///
  /// The metrics may also contain information about simplification/normalization steps which can be skipped when writing the path-string.
  ///
  @inlinable
  internal init<UTF8Bytes>(
    parsing utf8: UTF8Bytes,
    schemeKind: WebURL.SchemeKind,
    hasAuthority: Bool,
    baseURL: WebURL?,
    absolutePathsCopyWindowsDriveFromBase: Bool
  ) where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {

    self.requiredCapacity = 0
    self.firstComponentLength = 0
    self.numberOfComponents = 0
    self.needsPercentEncoding = false
    self.requiresPathSigil = false

    var parser = _Parser<UTF8Bytes>(_emptyMetrics: self)
    parser.walkPathComponents(
      pathString: utf8, schemeKind: schemeKind, hasAuthority: hasAuthority, baseURL: baseURL,
      absolutePathsCopyWindowsDriveFromBase: absolutePathsCopyWindowsDriveFromBase)

    self = parser.metrics
  }

  @usableFromInline
  internal struct _Parser<UTF8Bytes>: _PathParser
  where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {

    @usableFromInline
    internal var metrics: PathMetrics

    @inlinable
    internal init(_emptyMetrics: PathMetrics) {
      self.metrics = _emptyMetrics
    }

    @usableFromInline
    internal typealias InputString = UTF8Bytes

    @inlinable
    internal mutating func visitInputPathComponent(
      _ pathComponent: UTF8Bytes.SubSequence, isWindowsDriveLetter: Bool
    ) {
      metrics.numberOfComponents += 1
      let (encodedLength, needsEncoding) = pathComponent.lazy.percentEncodedGroups(as: \.path).encodedLength
      metrics.needsPercentEncoding = metrics.needsPercentEncoding || needsEncoding
      metrics.firstComponentLength = 1 /* "/" */ + encodedLength
      metrics.requiredCapacity += metrics.firstComponentLength
    }

    @inlinable
    internal mutating func visitEmptyPathComponents(_ n: Int) {
      metrics.numberOfComponents += n
      metrics.requiredCapacity += n
      metrics.firstComponentLength = 1
    }

    @inlinable
    internal mutating func visitPathSigil() {
      metrics.requiresPathSigil = true
    }

    @inlinable
    internal mutating func visitBasePathComponent(_ pathComponent: WebURL.UTF8View.SubSequence) {
      metrics.numberOfComponents += 1
      metrics.firstComponentLength = 1 /* "/" */ + pathComponent.count
      metrics.requiredCapacity += metrics.firstComponentLength
    }
  }
}

extension UnsafeMutableBufferPointer where Element == UInt8 {

  /// Initializes this buffer to the simplified, normalized path parsed from `utf8`.
  ///
  /// The buffer must have precisely the correct capacity to store the path string, or a runtime error will be triggered.  This implies that its address may not be `nil`.
  /// The fact that the exact capacity is known is taken as proof that `PathMetrics` have been calculated, and that the number of bytes written will not overflow
  /// an `Int`.
  ///
  /// - returns; The number of bytes written. This will be equal to `self.count`, but is calculated independently as an additional check.
  ///
  @inlinable
  internal func writeNormalizedPath<UTF8Bytes>(
    parsing utf8: UTF8Bytes,
    schemeKind: WebURL.SchemeKind,
    hasAuthority: Bool,
    baseURL: WebURL?,
    absolutePathsCopyWindowsDriveFromBase: Bool,
    needsPercentEncoding: Bool = true
  ) -> Int where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {
    return _PathWriter.writePath(
      to: self, pathString: utf8, schemeKind: schemeKind, hasAuthority: hasAuthority, baseURL: baseURL,
      absolutePathsCopyWindowsDriveFromBase: absolutePathsCopyWindowsDriveFromBase,
      needsPercentEncoding: needsPercentEncoding
    )
  }

  /// A path parser which writes a properly percent-encoded, normalised URL path string
  /// in to a correctly-sized, uninitialized buffer. Use `PathMetrics` to calculate the buffer's required size.
  ///
  @usableFromInline
  internal struct _PathWriter<UTF8Bytes>: _PathParser
  where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {

    @usableFromInline
    internal let buffer: UnsafeMutableBufferPointer<UInt8>

    @usableFromInline
    internal private(set) var front: Int

    @usableFromInline
    internal let needsEscaping: Bool

    @inlinable
    internal static func writePath(
      to buffer: UnsafeMutableBufferPointer<UInt8>,
      pathString input: UTF8Bytes,
      schemeKind: WebURL.SchemeKind,
      hasAuthority: Bool,
      baseURL: WebURL?,
      absolutePathsCopyWindowsDriveFromBase: Bool,
      needsPercentEncoding: Bool = true
    ) -> Int {
      // Checking this now allows the implementation to safely use `.baseAddress.unsafelyUnwrapped`.
      precondition(buffer.baseAddress != nil)
      var writer = _PathWriter(_doNotUse: buffer, front: buffer.endIndex, needsPercentEncoding: needsPercentEncoding)
      writer.walkPathComponents(
        pathString: input,
        schemeKind: schemeKind,
        hasAuthority: hasAuthority,
        baseURL: baseURL,
        absolutePathsCopyWindowsDriveFromBase: absolutePathsCopyWindowsDriveFromBase
      )
      // Checking this now allows the implementation to be safe when omitting bounds checks.
      precondition(writer.front == 0, "Buffer was incorrectly sized")
      return buffer.count - writer.front
    }

    /// **Do not use**. Use the `_PathWriter.writePath(...)` static method instead.
    ///
    @inlinable
    internal init(_doNotUse buffer: UnsafeMutableBufferPointer<UInt8>, front: Int, needsPercentEncoding: Bool) {
      self.buffer = buffer
      self.front = front
      self.needsEscaping = needsPercentEncoding
    }

    @usableFromInline
    internal typealias InputString = UTF8Bytes

    @inlinable
    internal mutating func prependSlash(_ n: Int = 1) {
      front &-= n
      buffer.baseAddress.unsafelyUnwrapped.advanced(by: front)
        .initialize(repeating: ASCII.forwardSlash.codePoint, count: n)
    }

    @inlinable
    internal mutating func visitInputPathComponent(
      _ pathComponent: UTF8Bytes.SubSequence, isWindowsDriveLetter: Bool
    ) {
      guard pathComponent.isEmpty == false else {
        prependSlash()
        return
      }
      guard isWindowsDriveLetter == false else {
        assert(pathComponent.count == 2)
        front &-= 2
        buffer.baseAddress.unsafelyUnwrapped.advanced(by: front).initialize(to: pathComponent[pathComponent.startIndex])
        buffer.baseAddress.unsafelyUnwrapped.advanced(by: front &+ 1).initialize(to: ASCII.colon.codePoint)
        prependSlash()
        return
      }
      if needsEscaping {
        for byteGroup in pathComponent.reversed().lazy.percentEncodedGroups(as: \.path) {
          switch byteGroup.encoding {
          case .percentEncoded:
            (buffer.baseAddress.unsafelyUnwrapped + front - 3).initialize(to: byteGroup[0])
            (buffer.baseAddress.unsafelyUnwrapped + front - 2).initialize(to: byteGroup[1])
            (buffer.baseAddress.unsafelyUnwrapped + front - 1).initialize(to: byteGroup[2])
            front &-= 3
          case .unencoded, .substituted:
            (buffer.baseAddress.unsafelyUnwrapped + front - 1).initialize(to: byteGroup[0])
            front &-= 1
          }
        }
      } else {
        let count = pathComponent.count
        let newFront = front &- count
        _ = UnsafeMutableBufferPointer(
          start: buffer.baseAddress.unsafelyUnwrapped.advanced(by: newFront),
          count: count
        ).fastInitialize(from: pathComponent)
        front = newFront
      }
      prependSlash()
    }

    @inlinable
    internal mutating func visitEmptyPathComponents(_ n: Int) {
      prependSlash(n)
    }

    @inlinable
    internal func visitPathSigil() {
      // URLWriter is reponsible for writing its own path sigil.
    }

    @inlinable
    internal mutating func visitBasePathComponent(_ pathComponent: WebURL.UTF8View.SubSequence) {
      let count = pathComponent.count
      let newFront = front &- count
      _ = UnsafeMutableBufferPointer(
        start: buffer.baseAddress.unsafelyUnwrapped.advanced(by: newFront),
        count: count
      ).fastInitialize(from: pathComponent)
      front = newFront
      prependSlash()
    }
  }
}

/// An objects which checks for URL validation errors in a path string.
///
/// Validation errors are communicated to the given `URLParserCallback` if the path-string contains:
/// - Non-URL code points
/// - Invalid percent encoding (e.g. "%ZZ"), or
/// - Backslashes as path separators
///
/// This type must not be initialized directly. To validate a path string, use the static `.validate` method.
///
@usableFromInline
internal struct PathStringValidator<UTF8Bytes, Callback>: _PathParser
where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8, Callback: URLParserCallback {

  @usableFromInline
  internal let path: UTF8Bytes

  @usableFromInline
  internal let callback: UnsafeMutablePointer<Callback>

  @inlinable
  internal init(_doNotUse path: UTF8Bytes, callback: UnsafeMutablePointer<Callback>) {
    self.path = path
    self.callback = callback
  }

  /// Checks for non-fatal syntax oddities in the given path string.
  ///
  /// See the URL standard's "path state" or the type-level documentation for `PathStringValidator` for more information.
  ///
  @inlinable
  internal static func validate(
    pathString input: UTF8Bytes,
    schemeKind: WebURL.SchemeKind,
    hasAuthority: Bool,
    callback: inout Callback
  ) {
    // The compiler has a tough time optimizing this function away when we ignore validation errors.
    guard Callback.self != IgnoreValidationErrors.self else {
      return
    }
    var visitor = PathStringValidator(_doNotUse: input, callback: &callback)
    visitor.walkPathComponents(
      pathString: input, schemeKind: schemeKind, hasAuthority: hasAuthority, baseURL: nil,
      absolutePathsCopyWindowsDriveFromBase: false)
  }

  @usableFromInline
  internal typealias InputString = UTF8Bytes

  @usableFromInline
  internal mutating func visitInputPathComponent(
    _ pathComponent: UTF8Bytes.SubSequence, isWindowsDriveLetter: Bool
  ) {
    validateURLCodePointsAndPercentEncoding(utf8: pathComponent, callback: &callback.pointee)
  }

  @usableFromInline
  internal mutating func visitEmptyPathComponents(_ n: Int) {
    // Nothing to do.
  }

  @usableFromInline
  internal func visitPathSigil() {
    // Nothing to do.
  }

  @usableFromInline
  internal mutating func visitBasePathComponent(_ pathComponent: WebURL.UTF8View.SubSequence) {
    assertionFailure("Should never be invoked without a base URL")
  }

  @usableFromInline
  internal mutating func visitValidationError(_ error: ValidationError) {
    callback.pointee.validationError(error)
  }
}


// --------------------------------------------
// MARK: - Path Utilities
// --------------------------------------------


/// A namespace for functions relating to parsing of path components.
///
@usableFromInline
internal enum PathComponentParser<T> {}

extension PathComponentParser where T == Never {

  /// Whether the given UTF-8 code-unit is a path separator character for the given `scheme`.
  ///
  @inlinable @inline(__always)
  internal static func isPathSeparator(_ codeUnit: UInt8, scheme: WebURL.SchemeKind) -> Bool {
    ASCII(codeUnit) == .forwardSlash || (scheme.isSpecial && ASCII(codeUnit) == .backslash)
  }
}

extension PathComponentParser where T: Collection, T.Element == UInt8 {

  /// A Windows drive letter is two code points, of which the first is an ASCII alpha and the second is either U+003A (:) or U+007C (|).
  ///
  /// https://url.spec.whatwg.org/#url-miscellaneous
  ///
  @inlinable
  internal static func isWindowsDriveLetter(_ bytes: T) -> Bool {
    var it = bytes.makeIterator()
    guard let byte1 = it.next(), ASCII(byte1)?.isAlpha == true else { return false }
    guard let byte2 = it.next(), ASCII(byte2) == .colon || ASCII(byte2) == .verticalBar else { return false }
    guard it.next() == nil else { return false }
    return true
  }

  /// A normalized Windows drive letter is a Windows drive letter of which the second code point is U+003A (:).
  ///
  /// https://url.spec.whatwg.org/#url-miscellaneous
  ///
  @inlinable
  internal static func isNormalizedWindowsDriveLetter(_ bytes: T) -> Bool {
    isWindowsDriveLetter(bytes) && (bytes.dropFirst().first.map { ASCII($0) == .colon } ?? false)
  }

  /// A string starts with a Windows drive letter if all of the following are true:
  ///
  /// - its length is greater than or equal to 2
  /// - its first two code points are a Windows drive letter
  /// - its length is 2 or its third code point is U+002F (/), U+005C (\), U+003F (?), or U+0023 (#).
  ///
  /// https://url.spec.whatwg.org/#url-miscellaneous
  ///
  @inlinable
  internal static func hasWindowsDriveLetterPrefix(_ bytes: T) -> Bool {
    var it = bytes.makeIterator()
    guard let byte1 = it.next(), ASCII(byte1)?.isAlpha == true else { return false }
    guard let byte2 = it.next(), ASCII(byte2) == .colon || ASCII(byte2) == .verticalBar else { return false }
    guard let byte3 = it.next() else { return true }
    switch ASCII(byte3) {
    case .forwardSlash?, .backslash?, .questionMark?, .numberSign?: return true
    default: return false
    }
  }

  /// Interprets the given collection as a URL's normalized path whose first component length is `firstCmptLength`, and returns a slice
  /// covering the path's normalized Windows drive letter, if it has one.
  ///
  /// Windows drive letters only have meaning for `file` URLs.
  ///
  @inlinable
  internal static func _normalizedWindowsDrive(
    in path: T, firstCmptLength: Int
  ) -> T.SubSequence? {

    if firstCmptLength == 3 {
      let firstComponentContent = path.dropFirst().prefix(2)
      if PathComponentParser<T.SubSequence>.isNormalizedWindowsDriveLetter(firstComponentContent) {
        return firstComponentContent
      }
    }
    return nil
  }

  /// Returns `true` if the next contents of `iterator` are either the ASCII byte U+002E (.), the string "%2e", or "%2E".
  /// Otherwise, `false`.
  ///
  @inlinable
  internal static func _checkForDotOrCaseInsensitivePercentEncodedDot(in iterator: inout T.Iterator) -> Bool {
    guard let byte1 = iterator.next(), let ascii1 = ASCII(byte1) else { return false }
    if ascii1 == .period { return true }
    guard ascii1 == .percentSign,
      let byte2 = iterator.next(), ASCII(byte2) == .n2,
      let byte3 = iterator.next(), ASCII(byte3 & 0b11011111) == .E  // bitmask uppercases ASCII alphas.
    else {
      return false
    }
    return true
  }

  /// Returns `true` if `bytes` contains a single U+002E (.), the ASCII string "%2e" or "%2E" only.
  /// Otherwise, `false`.
  ///
  @inlinable
  internal static func isSingleDotPathSegment(_ bytes: T) -> Bool {
    var it = bytes.makeIterator()
    guard _checkForDotOrCaseInsensitivePercentEncodedDot(in: &it) else { return false }
    guard it.next() == nil else { return false }
    return true
  }

  /// Returns `true` if `bytes` contains two of either U+002E (.), the ASCII string "%2e" or "%2E" only.
  /// Otherwise, `false`.
  ///
  @inlinable
  internal static func isDoubleDotPathSegment(_ bytes: T) -> Bool {
    var it = bytes.makeIterator()
    guard _checkForDotOrCaseInsensitivePercentEncodedDot(in: &it) else { return false }
    guard _checkForDotOrCaseInsensitivePercentEncodedDot(in: &it) else { return false }
    guard it.next() == nil else { return false }
    return true
  }

  /// Returns `true` if the given normalized path requires a path sigil when written to a URL that does not have an authority sigil.
  ///
  @inlinable
  internal static func doesNormalizedPathRequirePathSigil(_ path: T) -> Bool {
    var iter = path.makeIterator()
    guard iter.next() == ASCII.forwardSlash.codePoint, iter.next() == ASCII.forwardSlash.codePoint else {
      return false
    }
    return true
  }
}
