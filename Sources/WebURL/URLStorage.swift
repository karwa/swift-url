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
  /// The URL string, and any of its components, may not be larger than `SizeType.max`.
  ///
  /// A larger size allows storing larger URL strings, but increases the overhead of each URL value.
  /// Similarly, the size may be adjusted down to reduce overheads, but operations which would cause
  /// the URL to exceed the maximum size will fail.
  ///
  @usableFromInline
  internal typealias SizeType = UInt32

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
/// Once Swift gains support for move operations, this value will no longer be required.
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
