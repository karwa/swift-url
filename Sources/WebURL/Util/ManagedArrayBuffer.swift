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


// MARK: - AltManagedBufferReference


/// A header for a managed buffer which includes `count` and `capacity` information.
/// These values are set by `ManagedArrayBuffer` and should never be modified outside of that.
///
protocol ManagedBufferHeader {

  /// The number of initialized elements that are stored in the allocation attached to this header.
  ///
  /// It is imperative that this value be kept up-to-date at all times.
  /// When `AltManagedBuffer` is deinitialized, elements in the range `0..<count` will automatically be deinitialized as well.
  ///
  var count: Int { get set }

  /// The total number of elements which may be stored in the allocation attached to this header.
  ///
  /// This value should never be mutated. Headers with the appropriate capacity values for their attached allocations are obtained by
  /// using the `withCapacity` function to copy an existing header with for use with a different allocation.
  ///
  var capacity: Int { get }

  /// Returns a copy of this header, for attaching to a buffer with a different capacity.
  ///
  /// The returned header's `capacity` must be at least as large as `minimumCapacity`, and not greater than `maximumCapacity`.
  /// If the header is unable to store values as large as `minimumCapacity`, this method must return `nil`.
  ///
  /// - Note: `maximumCapacity` is a value provided by the operating system. Even if you have taken care to ensure this
  ///         type of header is only constructed for a particular `minimumCapacity`, the `maximumCapacity` may still be larger.
  ///         The header need only be large enough to store a value of `minimumCapacity`.
  ///
  func withCapacity(minimumCapacity: Int, maximumCapacity: Int) -> Self?
}

/// An alternative `ManagedBuffer` interface, with the following differences:
///
/// - It is a `struct` with reference semantics, rather than a `class`.
/// - The initial `header` must be given as a value at initialisation time.
/// - The `header` must store the buffer's `count`and `capacity`:
///   - The `capacity` is automatically set to the correct value when attaching the header to storage.
///   - Elements in the range `0..<count` are automatically deinitialized when the buffer is destroyed.
///
struct AltManagedBufferReference<Header: ManagedBufferHeader, Element> {

  /// The private `ManagedBuffer` subclass used by all `AltManagedBufferReference`s.
  private final class _Storage: ManagedBuffer<Header, Element> {

    static func newBuffer(minimumCapacity: Int, initialHeader: Header) -> Self {
      let buffer = Self.create(minimumCapacity: minimumCapacity) { unsafeBuffer in
        let actualCapacity = unsafeBuffer.capacity
        // Create a copy of the header for the new allocation.
        guard var newHdr = initialHeader.withCapacity(minimumCapacity: minimumCapacity, maximumCapacity: actualCapacity)
        else {
          preconditionFailure("Failed to create header with required capacity")
        }
        precondition((minimumCapacity...actualCapacity).contains(newHdr.capacity), "Header stored incorrect capacity")
        // The header's `count` must be set to 0 (as the uninitialized buffer does not contain anything).
        newHdr.count = 0
        return newHdr
      }
      return unsafeDowncast(buffer, to: Self.self)
    }

    deinit {
      // Swift does not specialize generic classes (often? maybe? not sure, but it's flaky).
      // That means this deinit will never be eliminated, and everything we do here will be
      // unspecialized generic code (which is **extremely** expensive).
      // https://bugs.swift.org/browse/SR-13221
      if Swift._isPOD(Element.self) == false {
        _ = withUnsafeMutablePointers { headerPtr, elemsPtr in
          elemsPtr.deinitialize(count: headerPtr.pointee.count)
        }
      }
    }
  }

  private var wrapped: _Storage

  /// Creates a new, uninitialized buffer with the given header.
  /// Note that the header's `capacity` is automatically set to the actual, allocated capacity, and the header's `count` is set to `0`.
  ///
  init(minimumCapacity: Int, initialHeader: Header) {
    self.wrapped = _Storage.newBuffer(minimumCapacity: minimumCapacity, initialHeader: initialHeader)
  }

  /// The stored `Header` instance.
  var header: Header {
    get { return wrapped.header }
    _modify { yield &wrapped.header }
    set { wrapped.header = newValue }
  }

  /// The number of elements that have been initialized in this buffer.
  var count: Int {
    return header.count
  }

  /// The number of elements that can be stored in this buffer.
  var capacity: Int {
    return header.capacity
  }

  /// Call `body` with an `UnsafeMutablePointer` to the stored `Header`.
  ///
  /// - Note: This pointer is valid only for the duration of the call to `body`.
  ///
  @inlinable
  func withUnsafeMutablePointerToHeader<R>(_ body: (UnsafeMutablePointer<Header>) throws -> R) rethrows -> R {
    return try wrapped.withUnsafeMutablePointerToHeader(body)
  }

  /// Call `body` with an `UnsafeMutablePointer` to the `Element` storage.
  ///
  /// - Note: This pointer is valid only for the duration of the call to `body`.
  ///
  @inlinable
  func withUnsafeMutablePointerToElements<R>(_ body: (UnsafeMutablePointer<Element>) throws -> R) rethrows -> R {
    return try wrapped.withUnsafeMutablePointerToElements(body)
  }

  /// Call `body` with `UnsafeMutablePointer`s to the stored `Header` and raw `Element` storage.
  ///
  /// - Note: These pointers are valid only for the duration of the call to `body`.
  ///
  @inlinable
  func withUnsafeMutablePointers<R>(
    _ body: (UnsafeMutablePointer<Header>, UnsafeMutablePointer<Element>) throws -> R
  ) rethrows -> R {
    return try wrapped.withUnsafeMutablePointers(body)
  }

  /// Whether or not this buffer is known to be uniquely-referenced.
  ///
  mutating func isKnownUniqueReference() -> Bool {
    return isKnownUniquelyReferenced(&wrapped)
  }

  /// Moves the contents of this buffer to a new buffer with the given capacity.
  ///
  /// The header is copied, although its `capacity` will be adjusted to reflect the new buffer's capacity. Afterwards, this buffer's `count` will be 0.
  ///
  /// - precondition: The given capacity must be sufficient to store all of this buffer's contents.
  ///
  func moveToNewBuffer(minimumCapacity: Int) -> Self {
    let numElements = count
    precondition(minimumCapacity >= numElements)
    let newBuffer = Self.init(minimumCapacity: minimumCapacity, initialHeader: header)
    assert(newBuffer.count == 0)
    newBuffer.withUnsafeMutablePointers { destHeader, destElems in
      self.withUnsafeMutablePointers { srcHeader, srcElems in
        destElems.moveInitialize(from: srcElems, count: numElements)
        srcHeader.pointee.count = 0
      }
      destHeader.pointee.count = numElements
    }
    assert(newBuffer.count == numElements)
    assert(count == 0)
    return newBuffer
  }

  /// Copies the contents of this buffer to a new buffer with the given capacity.
  ///
  /// The header is copied, although its `capacity` will be adjusted to reflect the new buffer's capacity. This buffer remains unchanged.
  ///
  /// - precondition: The given capacity must be sufficient to store all of this buffer's contents.
  ///
  func copyToNewBuffer(minimumCapacity: Int) -> Self {
    let numElements = count
    precondition(minimumCapacity >= numElements)
    let newBuffer = Self.init(minimumCapacity: minimumCapacity, initialHeader: header)
    assert(newBuffer.count == 0)
    newBuffer.withUnsafeMutablePointers { destHeader, destElemens in
      self.withUnsafeMutablePointerToElements { srcElems in
        destElemens.initialize(from: srcElems, count: numElements)
      }
      destHeader.pointee.count = numElements
    }
    assert(newBuffer.count == numElements)
    assert(count == numElements)
    return newBuffer
  }
}


// MARK: - ManagedArrayBuffer


/// A wrapper for an `AltManagedBufferReference` which aims to provide similar convenience methods and semantics to `Array`.
///
/// In particular:
/// - This is a Copy-on-Write value type.
/// - The buffer's header is exposed as a property, mutations to which will trigger the buffer to copy to new storage if not a unique reference.
/// - The buffer's elements are exposed as a `RandomAccessCollection` for reading and a `MutableCollection` for writing. Again, mutations
///   will trigger a copy if not a unique reference.
/// - Indicies are bounds-checked.
///
/// Some features of `Array` are not supported:
/// - No `RangeReplaceableCollection` conformance. However, this type does provide the `replaceSubrange` and `append` methods.
/// - No predictive growth strategy (although capacity may allocated in advance using `reserveCapacity`).
/// - No shrinking of storage, although a fresh allocation produced by copy-on-write during a no-op operation such as `reserveCapacity(0)`
///   will occupy the smallest possible space.
///
struct ManagedArrayBuffer<Header: ManagedBufferHeader, Element> {
  private var storage: AltManagedBufferReference<Header, Element>

  /// Creates a new `ManagedArrayBuffer` with the given minimum capacity and header.
  ///
  /// The new header's `count` is automatically set to `0`, and its `capacity` is set appropriately for the allocated storage.
  ///
  init(minimumCapacity: Int, initialHeader: Header) {
    self.storage = .init(minimumCapacity: minimumCapacity, initialHeader: initialHeader)
  }

  @inline(__always)
  mutating func ensureUnique() {
    if !storage.isKnownUniqueReference() {
      storage = storage.copyToNewBuffer(minimumCapacity: count)
    }
    assert(storage.isKnownUniqueReference())
  }

  /// The stored `Header` instance.
  var header: Header {
    get {
      return storage.header
    }
    @inline(__always) _modify {
      ensureUnique()
      let preModifyCapacity = storage.header.capacity
      yield &storage.header
      assert(storage.header.capacity == preModifyCapacity, "Invalid change of capacity")
    }
    @inline(__always) set {
      ensureUnique()
      let preModifyCapacity = storage.header.capacity
      storage.header = newValue
      assert(storage.header.capacity == preModifyCapacity, "Invalid change of capacity")
    }
  }
}

extension ManagedArrayBuffer {

  /// Ensures that this buffer's has sufficient capacity to store at least the specified number of elements.
  ///
  /// If the buffer already has sufficient capacity, calling this function will also ensure that it has a unique reference to its storage.
  ///
  mutating func reserveCapacity(_ minimumCapacity: Int) {
    let isUnique = storage.isKnownUniqueReference()
    if _slowPath(!isUnique || storage.capacity < minimumCapacity) {
      let newCapacity = Swift.max(minimumCapacity, storage.count)
      if isUnique {
        storage = storage.moveToNewBuffer(minimumCapacity: newCapacity)
      } else {
        storage = storage.copyToNewBuffer(minimumCapacity: newCapacity)
      }
    }
    precondition(storage.capacity >= minimumCapacity)
    precondition(storage.isKnownUniqueReference())
  }

  /// Appends space for the given number of objects, but leaves the initialization of that space to the given closure.
  ///
  /// - important: The closure must initialize **exactly** `uninitializedCapacity` elements, else a runtime error will be triggered.
  /// - returns:   The collection's new `endIndex`.
  ///
  @discardableResult
  mutating func unsafeAppend(
    uninitializedCapacity: Int, initializingWith initializer: (inout UnsafeMutableBufferPointer<Element>) -> Int
  ) -> Index {

    let oldCount = self.count
    let newCount = oldCount + uninitializedCapacity
    reserveCapacity(newCount)
    assert(storage.isKnownUniqueReference(), "reserveCapacity should have made this unique")

    storage.withUnsafeMutablePointerToElements { elements in
      var uninitializedBuffer = UnsafeMutableBufferPointer(start: elements + oldCount, count: uninitializedCapacity)
      let n = initializer(&uninitializedBuffer)
      precondition(n == uninitializedCapacity)
    }
    storage.header.count = newCount
    return newCount
  }

  private struct StorageHolder: BufferContainer {
    var bufferRef: AltManagedBufferReference<Header, Element>
    func withUnsafeMutablePointerToElements<R>(_ body: (UnsafeMutablePointer<Element>) throws -> R) rethrows -> R {
      return try bufferRef.withUnsafeMutablePointerToElements(body)
    }
  }

  /// Replaces the given subrange with uninitialized space for a given number of objects, but leaves the initialization of that space to the given closure.
  ///
  /// - important: The closure must initialize **exactly** `uninitializedCapacity` elements, else a runtime error will be triggered.
  /// - returns:   The indices of the initialized elements.
  ///
  @discardableResult
  mutating func unsafeReplaceSubrange(
    _ subrange: Range<Index>,
    withUninitializedCapacity newSubrangeCount: Int,
    initializingWith initializer: (inout UnsafeMutableBufferPointer<Element>) -> Int
  ) -> Range<Index> {

    let isUnique = storage.isKnownUniqueReference()
    let result = storage.withUnsafeMutablePointerToElements { elems in
      return replaceElements(
        in: UnsafeMutableBufferPointer(start: elems, count: storage.capacity),
        initializedCount: storage.count,
        isUnique: isUnique,
        subrange: subrange,
        withElements: newSubrangeCount,
        initializedWith: initializer,
        storageConstructor: { StorageHolder(bufferRef: .init(minimumCapacity: $0, initialHeader: storage.header)) }
      )
    }
    // Update the count of our existing storage. Its contents may have been moved out.
    self.storage.header.count = result.bufferCount
    // Adopt any new storage that was allocated.
    if var newStorage = result.newStorage?.bufferRef {
      newStorage.header.count = result.newStorageCount
      self.storage = newStorage
    }
    return subrange.lowerBound..<(subrange.lowerBound + result.insertedCount)
  }
}

// Collection protocols.

extension ManagedArrayBuffer: RandomAccessCollection {
  typealias Index = Int

  var startIndex: Index {
    return 0
  }
  var endIndex: Index {
    return storage.count
  }
  var count: Index {
    return storage.count
  }
  func index(after i: Index) -> Index {
    precondition(i < endIndex, "Cannot increment endIndex")
    return i &+ 1
  }
  func index(before i: Index) -> Index {
    precondition(i > startIndex, "Cannot decrement startIndex")
    return i &- 1
  }
  func withContiguousStorageIfAvailable<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows -> R? {
    return try withUnsafeBufferPointer(body)
  }
  mutating func withContiguousMutableStorageIfAvailable<R>(
    _ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R
  ) rethrows -> R? {
    return try withUnsafeMutableBufferPointer(body)
  }
}

extension ManagedArrayBuffer: MutableCollection {

  subscript(position: Index) -> Element {
    get {
      precondition(position >= startIndex && position < endIndex, "Index out of bounds")
      return storage.withUnsafeMutablePointerToElements { $0.advanced(by: position).pointee }
    }
    set {
      precondition(position >= startIndex && position < endIndex, "Index out of bounds")
      ensureUnique()
      return storage.withUnsafeMutablePointerToElements {
        $0.advanced(by: position).pointee = newValue
      }
    }
  }
}

// RRC-lite.

extension ManagedArrayBuffer {

  @discardableResult
  mutating func replaceSubrange<C>(_ subrange: Range<Index>, with newElements: C) -> Range<Index>
  where C: Collection, Self.Element == C.Element {
    return unsafeReplaceSubrange(subrange, withUninitializedCapacity: newElements.count) { buffer in
      return buffer.initialize(from: newElements).1
    }
  }

  @discardableResult
  mutating func append<S>(contentsOf newElements: S) -> Range<Index> where S: Sequence, Self.Element == S.Element {
    let preAppendEnd = endIndex

    var result: (S.Iterator, Int)?
    unsafeAppend(uninitializedCapacity: newElements.underestimatedCount) { ptr in
      result = ptr.initialize(from: newElements)
      return result.unsafelyUnwrapped.1
    }
    while let remaining = result?.0.next() {
      append(remaining)
    }
    return Range(uncheckedBounds: (preAppendEnd, endIndex))
  }

  @discardableResult
  mutating func append(_ element: Element) -> Index {
    append(contentsOf: CollectionOfOne(element)).lowerBound
  }
}

// Extensions.

extension ManagedArrayBuffer {

  func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows -> R {
    try storage.withUnsafeMutablePointerToElements {
      try body(UnsafeBufferPointer(start: $0, count: count))
    }
  }

  mutating func withUnsafeMutableBufferPointer<R>(
    _ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R
  ) rethrows -> R {
    ensureUnique()
    return try storage.withUnsafeMutablePointerToElements {
      var ptr = UnsafeMutableBufferPointer(start: $0, count: count)
      return try body(&ptr)
    }
  }

  func withUnsafeBufferPointer<R>(
    range: Range<Index>, _ block: (UnsafeBufferPointer<Element>) throws -> R
  ) rethrows -> R {
    precondition(range.startIndex >= startIndex && range.endIndex <= endIndex, "Range is out of bounds")
    return try storage.withUnsafeMutablePointerToElements { elements in
      let slice = UnsafeBufferPointer(start: elements + range.startIndex, count: range.count)
      return try block(slice)
    }
  }
}
