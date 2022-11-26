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

/// A `ManagedBufferHeader` containing a complete `URLStructure` and size-appropriate `count` and `capacity` fields.
///
@usableFromInline
internal struct URLHeader<SizeType> where SizeType: FixedWidthInteger & UnsignedInteger {

  @usableFromInline
  internal var _count: SizeType

  @usableFromInline
  internal var _capacity: SizeType

  @usableFromInline
  internal var _structure: URLStructure<SizeType>

  @inlinable
  internal init(_count: SizeType, _capacity: SizeType, _structure: URLStructure<SizeType>) {
    self._count = _count
    self._capacity = _capacity
    self._structure = _structure
  }

  @inlinable
  internal init(structure: URLStructure<SizeType>) {
    self = .init(_count: 0, _capacity: 0, _structure: structure)
  }
}

extension URLHeader: ManagedBufferHeader {

  @inlinable
  internal var count: Int {
    get { return Int(_count) }
    set { _count = SizeType(newValue) }
  }

  @inlinable
  internal var capacity: Int {
    return Int(_capacity)
  }

  @inlinable
  internal func withCapacity(minimumCapacity: Int, maximumCapacity: Int) -> Self? {
    let newCapacity = SizeType(clamping: maximumCapacity)
    guard newCapacity >= minimumCapacity else {
      return nil
    }
    return Self(_count: _count, _capacity: newCapacity, _structure: _structure)
  }
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension URLHeader: Sendable where SizeType: Sendable {}
#endif


// --------------------------------------------
// MARK: - URLStorage
// --------------------------------------------


/// The primary type responsible for URL storage.
///
/// An `URLStorage` object wraps a `ManagedArrayBuffer`, containing the normalized URL string's contiguous code-units, together
/// with a header describing the structure of the URL components within those code-units. `URLStorage` has value semantics
/// via `ManagedArrayBuffer`, with modifications to multiply-referenced storage copying on write.
///
@usableFromInline
internal struct URLStorage {

  /// The type used to represent dimensions of the URL string and its components.
  ///
  /// The URL string, and any of its components, may not be larger than `SizeType.max`.
  ///
  @usableFromInline
  internal typealias SizeType = UInt32

  @usableFromInline
  internal var codeUnits: ManagedArrayBuffer<URLHeader<SizeType>, UInt8>

  @inlinable
  internal var header: URLHeader<SizeType> {
    get { return codeUnits.header }
    _modify { yield &codeUnits.header }
  }

  /// Allocates new storage with sufficient capacity to store `count` code-units, and a header describing the given `structure`.
  /// The `initializer` closure is invoked to write the code-units, and must return the number of code-units initialized.
  ///
  /// If the header cannot exactly reproduce the given `structure`, a runtime error is triggered.
  /// Use `AnyURLStorage` to allocate storage with the appropriate header for a given structure.
  ///
  /// - parameters:
  ///   - count:       The number of UTF8 code-units contained in the normalized URL string that `initializer` will write to the new storage.
  ///   - structure:   The structure of the normalized URL string that `initializer` will write to the new storage.
  ///   - initializer: A closure which must initialize exactly `count` code-units in the buffer pointer it is given, matching the normalized URL string
  ///                  described by `structure`. The closure returns the number of bytes actually written to storage, which should be
  ///                  calculated by the closure independently as it writes the contents, which serves as a safety check to avoid exposing uninitialized storage.
  ///
  @inlinable
  internal init(
    count: SizeType,
    structure: URLStructure<SizeType>,
    initializingCodeUnitsWith initializer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) {
    self.codeUnits = ManagedArrayBuffer(minimumCapacity: Int(count), initialHeader: URLHeader(structure: structure))
    assert(self.codeUnits.count == 0)
    assert(self.codeUnits.header.capacity >= count)
    self.codeUnits.unsafeAppend(uninitializedCapacity: Int(count)) { buffer in initializer(&buffer) }
    assert(self.codeUnits.header.count == count)
  }
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension URLStorage: Sendable {}
#endif

extension URLStorage {

  @inlinable
  internal var structure: URLStructure<URLStorage.SizeType> {
    get {
      header._structure
    }
    _modify {
      yield &header._structure
    }
    set {
      header._structure = newValue
    }
  }

  @inlinable
  internal func withUTF8OfAllAuthorityComponents<T>(
    _ body: (
      _ authorityString: UnsafeBufferPointer<UInt8>?,
      _ hostKind: WebURL.HostKind?,
      _ usernameLength: Int,
      _ passwordLength: Int,
      _ hostnameLength: Int,
      _ portLength: Int
    ) -> T
  ) -> T {

    guard structure.hasAuthority else { return body(nil, nil, 0, 0, 0, 0) }
    let range = Range(uncheckedBounds: (structure.usernameStart, structure.pathStart))
    return codeUnits.withUnsafeBufferPointer(range: range.toCodeUnitsIndices()) { buffer in
      body(
        buffer, structure.hostKind,
        Int(structure.usernameLength), Int(structure.passwordLength),
        Int(structure.hostnameLength), Int(structure.portLength)
      )
    }
  }
}

/// The URL `a:` - essentially the smallest valid URL string. This is a used to temporarily occupy a `URLStorage` variable,
/// so its previous value can be moved to a uniquely-referenced local variable.
///
/// It should not be possible to observe a URL whose storage is set to this object.
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
// MARK: - Index conversion utilities
// --------------------------------------------


extension Range where Bound == URLStorage.SizeType {

  @inlinable
  internal func toCodeUnitsIndices() -> Range<Int> {
    Range<Int>(uncheckedBounds: (Int(lowerBound), Int(upperBound)))
  }
}

extension Range where Bound == ManagedArrayBuffer<URLHeader<URLStorage.SizeType>, UInt8>.Index {

  @inlinable
  internal func toURLStorageIndices() -> Range<URLStorage.SizeType> {
    Range<URLStorage.SizeType>(uncheckedBounds: (URLStorage.SizeType(lowerBound), URLStorage.SizeType(upperBound)))
  }
}

extension ManagedArrayBuffer where Header == URLHeader<URLStorage.SizeType> {

  @inlinable
  internal subscript(position: URLStorage.SizeType) -> Element {
    self[Index(position)]
  }

  @inlinable
  internal subscript(bounds: Range<URLStorage.SizeType>) -> Slice<Self> {
    Slice(base: self, bounds: bounds.toCodeUnitsIndices())
  }
}
