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

/// `URLStorage` pairs the code-units of a normalized URL string with the `URLStructure` which describes them.
///
/// `URLStorage` wraps a `ManagedArrayBuffer` (and so inherits its copy-on-write value semantics),
/// and serves as a place for extensions which add URL-specific definitions and operations.
///
/// It includes familiar operations, such as `replaceSubrange`, which accept a new `URLStructure`
/// in addition to their usual parameters. This allows replacing code-units and structure in a single operation,
/// which can help ensure the two stay in sync.
///
@usableFromInline
internal struct URLStorage {

  @usableFromInline
  internal var codeUnits: ManagedArrayBuffer<Header, UInt8>

  /// The type used to represent dimensions of the URL string and its components.
  ///
  /// A larger size allows storing larger URL strings, but increases the overhead of each URL value.
  /// Similarly, the size may be adjusted down to reduce overheads, but operations which would cause
  /// the URL to exceed the maximum size will fail.
  ///
  @usableFromInline
  internal typealias SizeType = UInt32

  /// The maximum length of a URL string.
  /// If an operation would produce a URL longer than this, it fails instead.
  ///
  /// > Note:
  /// > This value must not exceed `Int.max`.
  ///
  @inlinable
  internal static var MaxSize: SizeType {
    if MemoryLayout<Int>.size == 4 {
      return SizeType(Int32.max)
    }
    return SizeType.max
  }

  /// Allocates storage with capacity to store a normalized URL string of the given size,
  /// and writes its contents using a closure.
  ///
  /// The size and structure of the URL string must be known in advance.
  /// You can write a `ParsedURLString` to a `StructureAndMetricsCollector` to obtain this information.
  ///
  /// The `initializer` closure must independently count the number of bytes it writes,
  /// and return this value as its result. This is an important safeguard against exposing uninitialized memory.
  /// Additionally, the result will be checked against the expected URL string size.
  ///
  /// - parameters:
  ///   - count:       The length of the URL string.
  ///   - structure:   The pre-calculated structure which describes the URL.
  ///   - initializer: A closure which writes the content of the URL string.
  ///
  @inlinable
  internal init(
    count: SizeType,
    structure: URLStructure<SizeType>,
    initializingCodeUnitsWith initializer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) {
    precondition(count <= URLStorage.MaxSize, "URL exceeds maximum size")

    self.codeUnits = ManagedArrayBuffer(minimumCapacity: Int(count), initialHeader: Header(emptyStorageFor: structure))
    assert(self.codeUnits.count == 0)
    assert(self.codeUnits.header.capacity >= count)

    self.codeUnits.unsafeAppend(uninitializedCapacity: Int(count), initializingWith: initializer)
    assert(self.codeUnits.header.count == count)
  }
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension URLStorage: Sendable {}
  extension URLStorage.Header: Sendable {}
#endif

extension URLStorage {

  /// The structure of this URL.
  ///
  @inlinable
  internal var structure: URLStructure<URLStorage.SizeType> {
    get { codeUnits.header.structure }
    _modify { yield &codeUnits.header.structure }
  }
}

/// A value which can be used to occupy a `URLStorage` variable,
/// allowing its previous value to be moved to a uniquely-referenced local variable.
///
/// It should not be possible to observe a URL whose storage is set to this object.
///
/// **Once Swift gains support for move operations, this value will no longer be required.**
///
@usableFromInline
internal let _tempStorage = URLStorage(
  count: 2,
  structure: URLStructure(
    schemeLength: 2, usernameLength: 0, passwordLength: 0, hostnameLength: 0,
    portLength: 0, pathLength: 0, queryLength: 0, fragmentLength: 0, firstPathComponentLength: 0,
    sigil: nil, schemeKind: .other, hostKind: nil, hasOpaquePath: true, queryIsKnownFormEncoded: true),
  initializingCodeUnitsWith: { buffer in
    buffer[0] = ASCII.a.codePoint
    buffer[1] = ASCII.colon.codePoint
    return 2
  }
)


// --------------------------------------------
// MARK: - Header
// --------------------------------------------


extension URLStorage {

  /// A `ManagedBufferHeader` for storing a `URLStructure`,
  /// with appropriately-sized `capacity` and `count` fields.
  ///
  @usableFromInline
  internal struct Header {

    @usableFromInline
    internal let _capacity: SizeType

    @usableFromInline
    internal var _count: SizeType

    @usableFromInline
    internal var structure: URLStructure<SizeType>

    @inlinable
    internal init(_count: SizeType, _capacity: SizeType, structure: URLStructure<SizeType>) {
      self._count = _count
      self._capacity = _capacity
      self.structure = structure
    }

    @inlinable
    internal init(emptyStorageFor structure: URLStructure<SizeType>) {
      self = .init(_count: 0, _capacity: 0, structure: structure)
    }
  }
}

extension URLStorage.Header: ManagedBufferHeader {

  @inlinable
  internal var capacity: Int {
    return Int(_capacity)
  }

  @inlinable
  internal var count: Int {
    get { Int(_count) }
    set { _count = URLStorage.SizeType(truncatingIfNeeded: newValue) }
  }

  @inlinable
  internal func withCapacity(minimumCapacity: Int, maximumCapacity: Int) -> Self? {
    let newCapacity = URLStorage.SizeType(clamping: maximumCapacity)
    guard newCapacity >= minimumCapacity else {
      return nil
    }
    return Self(_count: _count, _capacity: newCapacity, structure: structure)
  }
}


// --------------------------------------------
// MARK: - Index conversion
// --------------------------------------------


extension Range where Bound == URLStorage.SizeType {

  @inlinable
  internal func toCodeUnitsIndices() -> Range<Int> {
    Range<Int>(uncheckedBounds: (Int(lowerBound), Int(upperBound)))
  }
}

extension Range where Bound == Int {

  @inlinable
  internal func toURLStorageIndices() -> Range<URLStorage.SizeType> {
    // This should, in theory, only produce one trap. Actual results may vary.
    // https://github.com/apple/swift/issues/62262
    guard
      let lower = URLStorage.SizeType(exactly: lowerBound),
      let upper = URLStorage.SizeType(exactly: upperBound)
    else {
      preconditionFailure("Indexes cannot be represented by URLStorage.SizeType")
    }
    return Range<URLStorage.SizeType>(uncheckedBounds: (lower, upper))
  }
}

extension ManagedArrayBuffer where Header == URLStorage.Header {

  @inlinable
  internal subscript(position: URLStorage.SizeType) -> Element {
    self[Index(position)]
  }

  @inlinable
  internal subscript(bounds: Range<URLStorage.SizeType>) -> Slice<Self> {
    Slice(base: self, bounds: bounds.toCodeUnitsIndices())
  }
}


// --------------------------------------------
// MARK: - Combined Modifications
// --------------------------------------------


extension URLStorage {

  /// Replaces the given code-units and updates the URL structure.
  ///
  /// This function replaces the given subrange with uninitialized space,
  /// which must then be entirely initialized by the given closure.
  /// The closure must independently count the number of bytes it writes,
  /// and return this value as its result.
  ///
  /// If the closure fails to initialize all of the space it is given, a runtime error is triggered.
  /// This is an important safeguard against exposing uninitialized memory.
  ///
  /// - parameters:
  ///   - subrange:        The code-units to replace.
  ///   - newElementCount: The number of code-units to insert in place of `subrange`.
  ///   - newStructure:    The pre-calculated structure of the URL string after replacement.
  ///   - initializer:     A closure which writes the new code-units.
  ///
  /// - returns: A `Result` object, indicating whether or not the operation was a success.
  ///            Since this is a code-unit replacement and does not validate semantics,
  ///            this operation only fails if the resulting URL would exceed `URLStorage.MaxSize`.
  ///
  @inlinable
  internal mutating func replaceSubrange(
    _ subrange: Range<SizeType>,
    withUninitializedSpace newElementCount: SizeType,
    newStructure: URLStructure<SizeType>,
    initializer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) -> Result<Void, URLSetterError> {

    newStructure.checkInvariants()

    let newElementCount = Int(newElementCount)

    // Heterogeneous comparison produces suboptimal code unless widened to Int.
    // https://github.com/apple/swift/issues/62260
    guard
      let newTotalCount = codeUnits.count.subtracting(subrange.count, adding: newElementCount),
      newTotalCount <= Int(URLStorage.MaxSize)
    else {
      return .failure(.exceedsMaximumSize)
    }

    codeUnits.unsafeReplaceSubrange(
      subrange.toCodeUnitsIndices(),
      withUninitializedCapacity: newElementCount,
      initializingWith: initializer
    )
    assert(codeUnits.header.count == newTotalCount)
    structure = newStructure

    return .success
  }

  /// Removes the given code-units and updates the URL structure.
  ///
  /// - parameters:
  ///   - subrange:     The code-units to remove
  ///   - newStructure: The pre-calculated structure of the URL string after removing the code-units.
  ///
  @inlinable
  internal mutating func removeSubrange(
    _ subrange: Range<URLStorage.SizeType>,
    newStructure: URLStructure<URLStorage.SizeType>
  ) {

    newStructure.checkInvariants()

    codeUnits.removeSubrange(subrange.toCodeUnitsIndices())
    structure = newStructure
  }
}

extension URLStorage {

  /// A command object for replacing URL code-units.
  /// For use with `URLStorage.multiReplaceSubrange`.
  ///
  @usableFromInline
  internal struct ReplaceSubrangeOperation {

    @usableFromInline
    internal var range: Range<Int>

    @usableFromInline
    internal var replacementCount: Int

    // Unfortunately, because we store these closures, they must be @escaping.
    // It would be much nicer if we could keep then non-escaping,
    // and make the enclosing struct (and collection of structs) all be non-escaping too.
    // Rust can express that kind of lifetime dependency, but Swift cannot (yet?).

    @usableFromInline
    internal var writer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int

    @inlinable
    internal init(
      subrange: Range<SizeType>,
      replacementCount: SizeType,
      writer: @escaping (inout UnsafeMutableBufferPointer<UInt8>) -> Int
    ) {
      self.range = subrange.toCodeUnitsIndices()
      self.replacementCount = Int(replacementCount)
      self.writer = writer
    }

    /// See `URLStorage.replaceSubrange`
    ///
    @inlinable
    internal static func replace(
      _ subrange: Range<SizeType>,
      withCount replacementCount: SizeType,
      writer: @escaping (inout UnsafeMutableBufferPointer<UInt8>) -> Int
    ) -> Self {

      ReplaceSubrangeOperation(
        subrange: subrange,
        replacementCount: replacementCount,
        writer: writer
      )
    }

    /// See `URLStorage.removeSubrange`
    ///
    @inlinable
    internal static func remove(
      _ subrange: Range<SizeType>
    ) -> Self {

      ReplaceSubrangeOperation(
        subrange: subrange,
        replacementCount: 0,
        writer: { _ in return 0 }
      )
    }
  }

  /// Performs a series of code-unit replacements for a URL structure replacement.
  ///
  /// The list of operations must be sorted by range, and not contain any overlapping ranges,
  /// otherwise a runtime error will be triggered.
  ///
  /// - parameters:
  ///   - commands:     The list of replacement operations to perform.
  ///   - newStructure: The pre-calculated structure of the URL string after all replacements have been performed.
  ///
  /// - returns: A `Result` object, indicating whether or not the operation was a success.
  ///            Since this is a code-unit replacement and does not validate semantics,
  ///            this operation only fails if the resulting URL would exceed `URLStorage.MaxSize`.
  ///
  @inlinable
  internal mutating func multiReplaceSubrange<Operations>(
    _ operations: Operations,
    newStructure: URLStructure<SizeType>
  ) -> Result<Void, URLSetterError>
  where Operations: BidirectionalCollection, Operations.Element == ReplaceSubrangeOperation {

    newStructure.checkInvariants()

    // Simulate the operations as we would perform them in-place.
    // That means: in reverse order, to avoid clobbering.

    let currentCapacity = codeUnits.header.capacity
    var exceedsCapacity = false
    var cursor = codeUnits.endIndex
    var newCount = codeUnits.count

    for op in operations.reversed() {

      precondition(op.range.upperBound <= cursor && op.range.upperBound >= op.range.lowerBound, "Invalid range")
      cursor = op.range.lowerBound

      guard
        let countAfterReplacement = newCount.subtracting(op.range.count, adding: op.replacementCount),
        countAfterReplacement <= Int(URLStorage.MaxSize)
      else {
        return .failure(.exceedsMaximumSize)
      }
      precondition(countAfterReplacement >= 0, "count may never go negative")

      if countAfterReplacement > currentCapacity {
        exceedsCapacity = true
      }

      newCount = countAfterReplacement
    }

    // Perform the operations in-place, if we can do it without copying.

    if !exceedsCapacity, codeUnits._storage.isKnownUniqueReference() {

      for operation in operations.reversed() {

        if operation.replacementCount == 0 {
          codeUnits.removeSubrange(operation.range)
        } else {
          codeUnits.unsafeReplaceSubrange(
            operation.range,
            withUninitializedCapacity: operation.replacementCount,
            initializingWith: operation.writer
          )
        }
      }

      structure = newStructure
      return .success
    }

    // Otherwise, write the new string in a fresh allocation.

    self = URLStorage(count: SizeType(newCount), structure: newStructure) { destination in

      let baseAddress = destination.baseAddress!
      var destination = destination
      var sourceIndex = codeUnits.startIndex

      for operation in operations {

        // Copy from source until start of operation range.

        var written = destination.fastInitialize(
          from: codeUnits[Range(uncheckedBounds: (sourceIndex, operation.range.lowerBound))]
        )
        destination = UnsafeMutableBufferPointer(
          start: destination.baseAddress! + written,
          count: destination.count &- written
        )

        // Initialize space using operation.

        if operation.replacementCount > 0 {
          var replacementRegion = UnsafeMutableBufferPointer(
            start: destination.baseAddress!,
            count: operation.replacementCount
          )
          written = operation.writer(&replacementRegion)
          precondition(
            written == operation.replacementCount,
            "Operation did not initialize the expected number of elements"
          )
          destination = UnsafeMutableBufferPointer(
            start: destination.baseAddress! + written,
            count: destination.count &- written
          )
        }

        // Advance source cursor to operation end.

        sourceIndex = operation.range.upperBound
      }

      // Copy remaining contents from the source.

      let written = destination.fastInitialize(
        from: codeUnits[Range(uncheckedBounds: (sourceIndex, codeUnits.endIndex))]
      )
      return baseAddress.distance(to: destination.baseAddress!) &+ written
    }

    return .success
  }
}
