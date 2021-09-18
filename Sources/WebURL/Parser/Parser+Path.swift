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
  ///   - pathComponent: The path component yielded by the parser.
  ///
  mutating func visitInputPathComponent(_ pathComponent: InputString.SubSequence)

  /// A callback which is invoked when the parser yields a deferred path component originating from the input string (i.e. a potential Windows drive letter).
  /// These components may require percent-encoding before writing.
  ///
  /// - parameters:
  ///   - pathComponent:         The path component yielded by the parser.
  ///   - isWindowsDriveLetter:  If `true`, the component is a Windows drive letter in a `file:` URL.
  ///                            It should be normalized when written (by writing the first byte followed by the ASCII character `:`).
  ///
  mutating func visitDeferredDriveLetter(_ pathComponent: (UInt8, UInt8), isConfirmedDriveLetter: Bool)

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
  mutating func visitEmptyPathComponents(_ n: UInt)

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
internal struct _PathParserState {

  /// Path component(s) which have been deferred for later processing.
  /// Either a potential Windows drive letter, a group of consecutive empty components, or `.none`.
  ///
  @usableFromInline
  internal var deferredComponent: Optional<_DeferredComponent>

  /// The parser's current popcount.
  ///
  /// The path parser considers path components in reverse order, in order to simplify arbitrarily long or complex paths with
  /// high performance and without allocating additional storage. To do this, it keeps track of an integer popcount, which tells it
  /// how many unpaired ".." components it has seen. When it sees a component, it first checks to see if the popcount is greater than 0 -
  /// if it is, it means the component will be popped by a ".." later in the path (but which it has already seen, due to parsing in reverse).
  ///
  /// For instance, consider the path "/p1/p2/../p3/p4/p5/../../p6":
  /// - First, the parser sees p6, and the popcount is at its initial value of 0. p6 is yielded.
  /// - Next, it sees 2 ".." components. The popcount is incremented to 2.
  /// - When it sees p5, the popcount is 2. It is not yielded, and the popcount is reduced to 1.
  /// - When it sees p4, the popcount is 1. It is not yielded, and the popcount is reduced to 0.
  /// - When it sees p3, the popcount is 0, so it is yielded.
  /// - Similarly, p2 is not yielded, p1 is.
  ///
  /// Hence the final path is "/p1/p3/p6" - only, the parser discovers that information in reverse order ("p6", "p3", "p1").
  ///
  @usableFromInline
  internal var popcount: UInt

  /// Whether or not the parser has yielded any components.
  ///
  /// A hierarchical URL requires either an authority segment or hierarchical path.
  /// Therefore, it is usually required that the path parser yields at least _something_.
  ///
  /// It is also important to track this flag when determining whether a path sigil is required.
  ///
  @usableFromInline
  internal var didYieldComponent: Bool

  @inlinable
  internal init() {
    self.deferredComponent = nil
    self.popcount = 0
    self.didYieldComponent = false
  }

  /// A component (or components) which have been deferred for later processing.
  ///
  /// - Potential Windows drive letters (file URLs only). The parser in the URL standard visits components in-order, from the root,
  ///   adding components to a stack and "shortening" the stack (popping) when it sees a ".." -- unless the pop would remove the first component,
  ///   and that component is a Windows drive letter. That means:
  ///
  ///   1. Windows drives cannot be popped (`C:/../../../foo` is simplified to `C:/foo`).
  ///   2. Other components _can_ appear before the drive, as long as they get popped-out later.
  ///     For example, when parsing the path `abc/../C:`, at some point `C:` will land at path[0],
  ///     and once it does, nothing can pop it out.
  ///   3. Components which appear before the drive must sum to nothing - i.e. they cannot result in any yielded component at all!
  ///     So `abc/C:` does not contain a drive, nor does `//C:`. This is important because Windows drives get normalized
  ///     and cannot be popped - we _need_ to know whether something is a drive or not.
  ///
  ///   So when we see a potential Windows drive letter, we defer the component and split popcount at that point (stashing it in the deferred component).
  ///   We need to work out what the left-hand side of the path component looks like before we can definitively say whether it is a drive.
  ///   - If it is (if nothing on the LHS yields a component), we discard the stashed popcount in accordance with #1, and yield it.
  ///   - If it isn't (if something on the LHS is going to yield), we flush the deferred component (popping it if its RHS popcount is > 0),
  ///     and merge the RHS and LHS popcounts.
  ///
  /// - Empty components. These are deferred in order to detect if the last yielded component was empty, and hence the resulting path string
  ///   would start with 2 slashes (e.g. "//p2"). https://github.com/whatwg/url/pull/505 introduced what we call
  ///   a "path sigil" for such paths, and tracking empty components is handy for that.
  ///
  @usableFromInline
  internal enum _DeferredComponent {
    case potentialWindowsDrive(deferredPopCount: UInt, beginsAtPathStart: Bool, bytes: (UInt8, UInt8))
    // TODO: Revist whether deferring empty components is worth it. Perhaps detect path sigils in another way.
    case empties(UInt)
  }

  @inlinable
  internal var hasDeferredWindowsDrive: Bool {
    if case .potentialWindowsDrive = deferredComponent { return true }
    return false
  }

  /// Defers an empty path component. If there are already empty components deferred, it will be added to them.
  ///
  /// Asserts that no potential Windows drive letters have been deferred.
  ///
  @inlinable
  internal mutating func deferAdditionalEmptyComponent() {

    assert(popcount == 0, "Shouldn't defer an empty component which has been popped!")
    if case .empties(let count) = deferredComponent {
      deferredComponent = .empties(count &+ 1)
    } else {
      assert(deferredComponent == nil, "Shouldn't defer an empty component while something else is deferred!")
      deferredComponent = .empties(1)
    }
  }

  /// Whether this component contains enough deferred empties to require a path sigil, were it to be flushed as the start of a path string.
  ///
  @inlinable
  internal var needsPathSigilWhenFlushing: Bool {
    if didYieldComponent {
      if case .empties(let count) = deferredComponent {
        return count != 0
      }
    } else {
      if case .empties(let count) = deferredComponent {
        return count > 1
      }
    }
    return false
  }
}

extension _PathParser {

  // Note: When making these local functions inside 'walkPathComponents', the compiler fails to prove they
  // don't escape and introduces heap allocations which dominate the performance of the entire parser.

  /// Flushes deferred empty components, if there are any, and asserts that no potential Windows drive letters have been deferred.
  ///
  @inlinable
  internal mutating func _flushEmptiesAssertNotWindowsDrive(
    _ state: inout _PathParserState
  ) {

    guard case .empties(let count) = state.deferredComponent else {
      assert(state.deferredComponent == nil, "Windows drive deferred! Cannot flush empties")
      return
    }
    assert(count != 0, "0 is not a valid number of deferred empties")
    visitEmptyPathComponents(count)
    state.didYieldComponent = true
    state.deferredComponent = .none
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
    _ state: inout _PathParserState
  ) {
    guard case .potentialWindowsDrive(var storedPopcount, _, let componentContent) = state.deferredComponent else {
      _flushEmptiesAssertNotWindowsDrive(&state)
      return
    }
    if storedPopcount == 0 {
      visitDeferredDriveLetter(componentContent, isConfirmedDriveLetter: false)
      state.didYieldComponent = true
    } else {
      storedPopcount -= 1
    }
    state.popcount += storedPopcount
    state.deferredComponent = .none
  }

  /// Flushes the deferred component(s) appropriately for the start of the path string.
  ///
  /// - For potential Windows drives, this means we have confirmed that the component *is* a Windows drive. It will be yielded with the appropriate flag.
  ///
  /// - Empty components are yielded, and if a path sigil is required, that is yielded, too.
  ///
  @inlinable
  internal mutating func _flushForFinalization(
    _ state: inout _PathParserState, _ hasAuthority: Bool
  ) {
    switch state.deferredComponent {
    case .potentialWindowsDrive(_, _, let firstComponent):
      visitDeferredDriveLetter(firstComponent, isConfirmedDriveLetter: true)
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
        state.deferredComponent = .empties(1)
      }
    }
    let needsPathSigil = state.needsPathSigilWhenFlushing
    _flushEmptiesAssertNotWindowsDrive(&state)
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

    guard input.startIndex < input.endIndex else {
      // Special URLs have an implicit path.
      // Non-special URLs may only have an empty path if they have an authority
      // (otherwise they would be non-hierarchical URLs).
      if schemeKind.isSpecial || !hasAuthority {
        visitEmptyPathComponent()
      }
      return
    }

    var startOfFirstInputComponent = input.startIndex
    let inputIsAbsolute = PathComponentParser.isPathSeparator(input[startOfFirstInputComponent], scheme: schemeKind)
    if inputIsAbsolute {
      input.formIndex(after: &startOfFirstInputComponent)
    }

    guard startOfFirstInputComponent < input.endIndex else {
      // Fast path: the input string is a single separator, i.e. an absolute root path.
      // The result is always a single "/", or the drive root if baseURL has a Windows drive letter.
      visitEmptyPathComponent()
      if case .file = schemeKind, let base = baseURL {
        let firstComponentFromBase = base.utf8.pathComponent(base.storage.pathComponentsStartIndex)
        if PathComponentParser.isNormalizedWindowsDriveLetter(firstComponentFromBase) {
          visitBasePathComponent(firstComponentFromBase)
        }
      }
      return
    }

    // =======================================
    // Parse components from the input string.
    // =======================================

    var state = _PathParserState()
    var remainingInput = input[Range(uncheckedBounds: (input.startIndex, input.endIndex))]

    repeat {

      let separatorIndex = remainingInput.fastLastIndex { PathComponentParser.isPathSeparator($0, scheme: schemeKind) }
      // swift-format-ignore
      let pathComponent = separatorIndex.map {
        if ASCII(input[$0]) == .backslash { visitValidationError(.unexpectedReverseSolidus) }
        return remainingInput[Range(uncheckedBounds: (remainingInput.index(after: $0), remainingInput.endIndex))]
      } ?? remainingInput

      if let dotComponent = PathComponentParser.parseDotPathComponent(pathComponent) {
        switch dotComponent {
        case .singleDot:
          break  // Single-dot components cannot be popped; e.g. "/a/b/./../" -> "/a/", not "/a/b/".
        case .doubleDot:
          state.popcount &+= 1
        }
        if pathComponent.endIndex == input.endIndex {
          // Don't defer this as it would have no effect due to the popcount increment.
          // Since this is at the end of the path, 'didYieldComponent' is sufficient for calculating path sigil.
          visitEmptyPathComponent()
          state.didYieldComponent = true
        }

      } else if case .file = schemeKind, let drive = PathComponentParser.parseWindowsDriveLetter(pathComponent) {
        _flushAndMergePopcount(&state)
        state.deferredComponent = .potentialWindowsDrive(
          deferredPopCount: state.popcount,
          beginsAtPathStart: pathComponent.startIndex == startOfFirstInputComponent,
          bytes: drive
        )
        state.popcount = 0

      } else if state.popcount > 0 {
        state.popcount -= 1

      } else if state.hasDeferredWindowsDrive {
        _flushAndMergePopcount(&state)
        continue  // Re-check this component with the new popcount.

      } else {
        assert(!state.hasDeferredWindowsDrive)
        if pathComponent.isEmpty {
          state.deferAdditionalEmptyComponent()
        } else {
          _flushEmptiesAssertNotWindowsDrive(&state)
          visitInputPathComponent(pathComponent)
          state.didYieldComponent = true
        }
      }

      // swift-format-ignore
      remainingInput = remainingInput[
        Range(uncheckedBounds: (remainingInput.startIndex, separatorIndex ?? remainingInput.startIndex))
      ]

    } while remainingInput.startIndex < remainingInput.endIndex

    assert(
      state.deferredComponent != nil || state.didYieldComponent,
      "Since the input path was not empty, we must have either deferred or yielded something from it."
    )

    // ==========================
    // Input/Base Path interface.
    // ==========================

    var baseDrive: WebURL.UTF8View.SubSequence? = nil

    if case .file = schemeKind {
      if let base = baseURL {
        let firstComponentFromBase = base.utf8.pathComponent(base.storage.pathComponentsStartIndex)
        if PathComponentParser.isNormalizedWindowsDriveLetter(firstComponentFromBase) {
          baseDrive = firstComponentFromBase
        }
      }
      // If the first written component of the input string is a Windows drive letter, the path is never relative -
      // even if it normally would be. [URL Standard: "file" state, "file slash" state]
      if case .potentialWindowsDrive(_, beginsAtPathStart: true, let firstComponent) = state.deferredComponent {
        visitDeferredDriveLetter(firstComponent, isConfirmedDriveLetter: true)
        return
      }
      // If the Windows drive is not the first written component of the input string, and the path is absolute,
      // we still prefer to use the drive from the base URL. [URL Standard: "file slash" state]
      if inputIsAbsolute, absolutePathsCopyWindowsDriveFromBase, let baseDrive = baseDrive {
        _flushAndMergePopcount(&state)
        visitBasePathComponent(baseDrive)
        return
      }
    }

    guard !inputIsAbsolute, let baseURL = baseURL, baseURL.storage.structure.pathLength > 0 else {
      _flushForFinalization(&state, hasAuthority)
      return  // Absolute paths, and relative paths with no base URL, are finished now.
    }

    // ==================================
    // Add components from the Base Path.
    // ==================================

    let basePath = baseURL.utf8.path

    // If the last component is the Windows drive at the start of the path, don't drop it - yield it and exit.
    if let baseDrive = baseDrive, baseDrive.endIndex == basePath.endIndex {
      _flushAndMergePopcount(&state)
      visitBasePathComponent(baseDrive)
      return
    }

    // Drop the last base path component.
    // Normalized non-empty base paths always have at least one component.
    var remainingBasePath = basePath[
      Range(uncheckedBounds: (basePath.startIndex, basePath.lastIndex(of: ASCII.forwardSlash.codePoint)!))
    ]

    while let separatorIndex = remainingBasePath.lastIndex(of: ASCII.forwardSlash.codePoint) {
      let pathComponent = remainingBasePath[
        Range(uncheckedBounds: (remainingBasePath.index(after: separatorIndex), remainingBasePath.endIndex))
      ]

      assert(PathComponentParser.parseDotPathComponent(pathComponent) == nil)

      switch pathComponent {
      // If we reached the base path's Windows drive letter, we can flush everything and end.
      case _ where separatorIndex == basePath.startIndex && baseDrive != nil:
        _flushAndMergePopcount(&state)
        visitBasePathComponent(baseDrive!)
        return

      case _ where state.popcount != 0:
        state.popcount -= 1

      case _ where state.hasDeferredWindowsDrive:
        _flushAndMergePopcount(&state)
        continue  // Re-check this component with the new popcount.

      default:
        assert(!state.hasDeferredWindowsDrive)
        if pathComponent.isEmpty {
          state.deferAdditionalEmptyComponent()
        } else {
          _flushEmptiesAssertNotWindowsDrive(&state)
          visitBasePathComponent(pathComponent)
          state.didYieldComponent = true
        }
      }

      remainingBasePath = remainingBasePath[Range(uncheckedBounds: (remainingBasePath.startIndex, separatorIndex))]
    }

    assert(remainingBasePath.isEmpty, "Normalized non-empty base paths must start with a /")
    _flushForFinalization(&state, hasAuthority)
    // Finally done!
  }
}


// --------------------------------------------
// MARK: - Parsers
// --------------------------------------------


/// A summary of statistics about a lexically-normalized, percent-encoded path string.
///
/// Note that the information collected by this object is calculated without regards to overflow,
/// or invalid collections which return a negative `count`. The measured capacity is sufficient to predict
/// the size of the allocation required, although actually writing to that allocation must employ bounds-checking
/// to ensure memory safety.
///
/// Assuming the path string is able to be written in the measured capacity, the other metrics may also be assumed to be accurate.
///
@usableFromInline
internal struct PathMetrics {

  /// The size of the allocation required to write the URL string.
  ///
  @usableFromInline
  internal private(set) var requiredCapacity: UInt

  /// The length of the first path component, in bytes, including its leading "/".
  ///
  @usableFromInline
  internal private(set) var firstComponentLength: UInt

  /// The number of components in the path.
  ///
  @usableFromInline
  internal private(set) var numberOfComponents: UInt

  /// Whether or not the path must be prefixed with a path sigil when it is written to a URL which does not have an authority sigil.
  ///
  @usableFromInline
  internal private(set) var requiresPathSigil: Bool

  /// Whether there is at least one component in the path which needs percent-encoding.
  ///
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
    internal typealias InputString = UTF8Bytes

    @usableFromInline
    internal var metrics: PathMetrics

    @inlinable
    internal init(_emptyMetrics: PathMetrics) {
      self.metrics = _emptyMetrics
    }

    @inlinable
    internal mutating func visitInputPathComponent(_ pathComponent: InputString.SubSequence) {
      metrics.numberOfComponents &+= 1
      let (encodedLength, needsEncoding) = pathComponent.lazy.percentEncoded(as: \.path).unsafeEncodedLength
      metrics.needsPercentEncoding = metrics.needsPercentEncoding || needsEncoding
      metrics.firstComponentLength = 1 /* "/" */ &+ encodedLength
      metrics.requiredCapacity &+= metrics.firstComponentLength
    }

    @inlinable
    internal mutating func visitDeferredDriveLetter(_ pathComponent: (UInt8, UInt8), isConfirmedDriveLetter: Bool) {
      // We know that this was a Windows drive candidate, so
      // the first byte is an ASCII alpha, and the second is ":" or "|". Neither are percent-encoded.
      assert(ASCII(pathComponent.0)!.isAlpha)
      assert(pathComponent.1 == ASCII.colon.codePoint || pathComponent.1 == ASCII.verticalBar.codePoint)
      assert(!PercentEncodeSet.Path.shouldPercentEncode(ascii: pathComponent.0))
      assert(!PercentEncodeSet.Path.shouldPercentEncode(ascii: pathComponent.1))

      metrics.numberOfComponents &+= 1
      metrics.firstComponentLength = 1 /* "/" */ &+ 2 /* encodedLength */
      metrics.requiredCapacity &+= metrics.firstComponentLength
    }

    @inlinable
    internal mutating func visitEmptyPathComponents(_ n: UInt) {
      metrics.numberOfComponents &+= n
      metrics.requiredCapacity &+= n
      metrics.firstComponentLength = 1
    }

    @inlinable
    internal mutating func visitPathSigil() {
      metrics.requiresPathSigil = true
    }

    @inlinable
    internal mutating func visitBasePathComponent(_ pathComponent: WebURL.UTF8View.SubSequence) {
      metrics.numberOfComponents &+= 1
      metrics.firstComponentLength = 1 /* "/" */ &+ UInt(bitPattern: pathComponent.count)
      metrics.requiredCapacity &+= metrics.firstComponentLength
    }
  }
}

extension UnsafeMutableBufferPointer where Element == UInt8 {

  /// Initializes this buffer to the simplified, normalized path parsed from `utf8`.
  ///
  /// The buffer is written with bounds-checking; a runtime error will be triggered if an attempt is made to write beyond its bounds.
  /// Additionally, a runtime error will be triggered if the buffer is not precisely sized to store the path string (i.e. with excess capacity).
  /// The buffer's address may not be `nil`.
  ///
  /// - returns: The number of bytes written. This will be equal to `self.count`.
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
    internal typealias InputString = UTF8Bytes

    @usableFromInline
    internal let buffer: UnsafeMutableBufferPointer<UInt8>

    @usableFromInline
    internal private(set) var front: Int

    @usableFromInline
    internal let needsEscaping: Bool

    @inlinable
    internal init(_doNotUse buffer: UnsafeMutableBufferPointer<UInt8>, front: Int, needsPercentEncoding: Bool) {
      self.buffer = buffer
      self.front = front
      self.needsEscaping = needsPercentEncoding
    }

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
      precondition(writer.front == 0, "Buffer was incorrectly sized")
      return buffer.count
    }

    @inlinable
    internal mutating func prependSlash(_ n: UInt = 1) {
      precondition(front >= n)
      // Since front >= n, the compiler can prove that Int(n) will not trap.
      // However, it can't prove that 'front - n' won't underflow (even though it can't, as n >= 0 due to unsigned).
      front &-= Int(n)
      buffer.baseAddress.unsafelyUnwrapped.advanced(by: front)
        .initialize(repeating: ASCII.forwardSlash.codePoint, count: Int(n))
    }

    @inlinable
    internal mutating func visitInputPathComponent(_ pathComponent: UTF8Bytes.SubSequence) {

      guard !pathComponent.isEmpty else {
        prependSlash()
        return
      }
      guard !needsEscaping else {
        for byte in pathComponent.lazy.percentEncoded(as: \.path).reversed() {
          precondition(front > 1)
          front &-= 1
          (buffer.baseAddress.unsafelyUnwrapped + front).initialize(to: byte)
        }
        prependSlash()
        return
      }
      // swift-format-ignore
      pathComponent.withContiguousStorageIfAvailable { componentContent in
        let count = componentContent.count
        precondition(front > count && count >= 0)
        let newFront = front &- count
        _ = UnsafeMutableBufferPointer(
          start: buffer.baseAddress.unsafelyUnwrapped.advanced(by: newFront),
          count: count
        ).fastInitialize(from: componentContent)
        front = newFront
      } ?? {
        for byte in pathComponent.reversed() {
          precondition(front > 1)
          front &-= 1
          (buffer.baseAddress.unsafelyUnwrapped + front).initialize(to: byte)
        }
      }()
      prependSlash()
    }

    @inlinable
    internal mutating func visitDeferredDriveLetter(_ pathComponent: (UInt8, UInt8), isConfirmedDriveLetter: Bool) {
      // We know that this was a Windows drive candidate, so
      // the first byte is an ASCII alpha, and the second is ":" or "|". Neither are percent-encoded.
      assert(ASCII(pathComponent.0)!.isAlpha)
      assert(pathComponent.1 == ASCII.colon.codePoint || pathComponent.1 == ASCII.verticalBar.codePoint)
      assert(!PercentEncodeSet.Path.shouldPercentEncode(ascii: pathComponent.0))
      assert(!PercentEncodeSet.Path.shouldPercentEncode(ascii: pathComponent.1))

      precondition(front > 2)
      front &-= 2
      buffer.baseAddress.unsafelyUnwrapped.advanced(by: front).initialize(to: pathComponent.0)
      buffer.baseAddress.unsafelyUnwrapped.advanced(by: front &+ 1).initialize(
        to: isConfirmedDriveLetter ? ASCII.colon.codePoint : pathComponent.1
      )
      prependSlash()
    }

    @inlinable
    internal mutating func visitEmptyPathComponents(_ n: UInt) {
      prependSlash(n)
    }

    @inlinable
    internal func visitPathSigil() {
      // URLWriter is reponsible for writing its own path sigil.
    }

    @inlinable
    internal mutating func visitBasePathComponent(_ pathComponent: WebURL.UTF8View.SubSequence) {
      let count = pathComponent.count
      precondition(front > count && count >= 0)
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
  internal mutating func visitInputPathComponent(_ pathComponent: UTF8Bytes.SubSequence) {
    validateURLCodePointsAndPercentEncoding(utf8: pathComponent, callback: &callback.pointee)
  }

  @usableFromInline
  internal mutating func visitDeferredDriveLetter(_ pathComponent: (UInt8, UInt8), isConfirmedDriveLetter: Bool) {
    withUnsafeBufferPointerToElements(tuple: pathComponent) {
      validateURLCodePointsAndPercentEncoding(utf8: $0, callback: &callback.pointee)
    }
  }

  @usableFromInline
  internal mutating func visitEmptyPathComponents(_ n: UInt) {
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

// Windows drive letters.

extension PathComponentParser where T: Collection, T.Element == UInt8 {

  /// A Windows drive letter is two code points, of which the first is an ASCII alpha and the second is either U+003A (:) or U+007C (|).
  ///
  /// https://url.spec.whatwg.org/#url-miscellaneous
  ///
  @inlinable
  internal static func parseWindowsDriveLetter(_ bytes: T) -> (UInt8, UInt8)? {
    var it = bytes.makeIterator()
    guard let byte0 = it.next(), ASCII(byte0)?.isAlpha == true else { return nil }
    guard let byte1 = it.next(), byte1 == ASCII.colon.codePoint || byte1 == ASCII.verticalBar.codePoint else {
      return nil
    }
    guard it.next() == nil else { return nil }
    return (byte0, byte1)
  }

  /// A Windows drive letter is two code points, of which the first is an ASCII alpha and the second is either U+003A (:) or U+007C (|).
  ///
  /// https://url.spec.whatwg.org/#url-miscellaneous
  ///
  @inlinable
  internal static func isWindowsDriveLetter(_ bytes: T) -> Bool {
    parseWindowsDriveLetter(bytes) != nil
  }

  /// A normalized Windows drive letter is a Windows drive letter of which the second code point is U+003A (:).
  ///
  /// https://url.spec.whatwg.org/#url-miscellaneous
  ///
  @inlinable
  internal static func isNormalizedWindowsDriveLetter(_ bytes: T) -> Bool {
    if let drive = parseWindowsDriveLetter(bytes), drive.1 == ASCII.colon.codePoint {
      return true
    }
    return false
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
    var i = bytes.startIndex
    guard i < bytes.endIndex else { return false }
    bytes.formIndex(after: &i)
    guard i < bytes.endIndex else { return false }
    bytes.formIndex(after: &i)
    guard PathComponentParser<T.SubSequence>.isWindowsDriveLetter(bytes[Range(uncheckedBounds: (bytes.startIndex, i))])
    else {
      return false
    }
    guard i < bytes.endIndex else { return true }
    switch ASCII(bytes[i]) {
    case .forwardSlash?, .backslash?, .questionMark?, .numberSign?: return true
    default: return false
    }
  }
}

// Dot components.

@usableFromInline
internal enum DotPathComponent {
  case singleDot
  case doubleDot
}

extension PathComponentParser where T: Collection, T.Element == UInt8 {

  @inlinable
  internal static func _checkForDotOrCaseInsensitivePercentEncodedDot2(in iterator: inout T.Iterator) -> Bool? {
    guard let byte0 = iterator.next() else { return nil }
    // The most likely spelling is a plain '.'
    if byte0 == ASCII.period.codePoint { return true }
    // Copy 3 bytes in to a UInt32 and match them as one unit.
    var buffer = 0 as UInt32
    let hasThreeBytes = withUnsafeMutableBytes(of: &buffer) { buffer -> Bool in
      guard let byte1 = iterator.next(), let byte2 = iterator.next() else { return false }
      buffer[0] = byte0
      buffer[1] = byte1
      buffer[2] = byte2 & 0b11011111
      return true
    }
    // swift-format-ignore
    let _percentTwoE = UInt32(bigEndian:
      UInt32(ASCII.percentSign.codePoint) &<< 24 | UInt32(ASCII.n2.codePoint) &<< 16 | UInt32(ASCII.E.codePoint) &<< 8
    )
    return hasThreeBytes && buffer == _percentTwoE
  }

  /// Returns a `DotPathComponent` if the given bytes contain one or two ASCII periods (including percent-encoded ASCII periods).
  /// For example, "." and "%2e" return `.singleDot`. "..", ".%2E", and "%2e%2E" return `.doubleDot`.
  ///
  @inlinable
  internal static func parseDotPathComponent(_ bytes: T) -> DotPathComponent? {
    var iter = bytes.makeIterator()
    guard _checkForDotOrCaseInsensitivePercentEncodedDot2(in: &iter) == true else { return nil }
    guard let second = _checkForDotOrCaseInsensitivePercentEncodedDot2(in: &iter) else { return .singleDot }
    guard second, iter.next() == nil else { return nil }
    return .doubleDot
  }
}

// Path sigils.

extension PathComponentParser where T: Collection, T.Element == UInt8 {

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
