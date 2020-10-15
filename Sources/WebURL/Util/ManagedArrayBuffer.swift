// This file contains utility types built atop `ManagedBuffer`, including an alternate
// interface which makes `ManagedBuffer` easier to work with (`AltManagedBufferReference`), and
// `ManagedArrayBuffer`, which is something like an Array with a user-specified header and tail-allocated contents.

/// A header for a managed buffer which includes `count` and `capacity` information.
/// These values are modified by the `ManagedBufferArray` and should never be set outside of that.
///
protocol ManagedBufferHeader {

  /// This property must be kept accurate as the buffer is mutated. It is used when the buffer is deinitialized in order to deinitialize the stored elements.
  var count: Int { get set }

  // TODO: It would be nice to make this read-only, but that would require a 'copyWithNewCapacity' method,
  //       which would have to be written by hand for every header type :(

  /// This property is set when a buffer is allocated and should not be modified.
  var capacity: Int { get set }
}

/// An alternative `ManagedBuffer` interface, with the following differences:
///
/// - Rather than allowing/requiring subclassing, the buffer object is encapsulated in a `struct`.
/// - The initial header must be given as a value at initialisation time.
/// - The buffer's capacity must be stored in the header. A protocol enforces this, and ensures that the headers of newly-allocated buffers
///   are automatically set to to the correct value.
/// - The same header protocol exposes the buffer's initialized count, allowing us to safely deinitialize those objects and implement common utility functions
///   such as for copying and moving buffers.
///
/// Essentially all uses of `ManagedBuffer` do this already. There are times when some of this information is a constant and doesn't need to be
/// stored; that can be achieved in the header's conformance to `ManagedBufferHeader`.
///
/// - important: Note that even though it is a struct, instances of this type have reference semantics.
///
struct AltManagedBufferReference<Header: ManagedBufferHeader, Element> {

  private final class _Storage: ManagedBuffer<Header, Element> {

    static func newBuffer(minimumCapacity: Int, initialHeader: Header) -> Self {
      let buffer = Self.create(minimumCapacity: minimumCapacity, makingHeaderWith: { _ in return initialHeader })
      buffer.header.capacity = buffer.capacity
      buffer.header.count = 0
      return unsafeDowncast(buffer, to: Self.self)
    }

    /// Note: If `headerConstructor` throws, it must have first uninitialized any partially-initialized portion of the buffer or `Element` must be trivial.
    static func newBuffer(
      minimumCapacity: Int,
      makingHeaderWith headerConstructor: (inout UnsafeMutableBufferPointer<Element>) throws -> Header
    ) rethrows -> Self {
      let buffer = try Self.create(
        minimumCapacity: minimumCapacity,
        makingHeaderWith: { newBuffer in
          return try newBuffer.withUnsafeMutablePointerToElements {
            var uninitializedElements = UnsafeMutableBufferPointer(start: $0, count: newBuffer.capacity)
            return try headerConstructor(&uninitializedElements)
          }
        })
      precondition(buffer.header.capacity >= minimumCapacity)
      precondition(buffer.header.count <= buffer.header.capacity)
      return unsafeDowncast(buffer, to: Self.self)
    }

    deinit {
      // Swift does not specialize generic classes (often? maybe? not sure, but it's flaky).
      // That means this deinit will never be eliminated, and even querying `.count`
      // can be very expensive.
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

  /// Creates a new buffer which is initialized by the given closure.
  ///
  /// The closure is called with the entire allocated capacity, and must construct a header as well as initializing any contents.
  /// The header's `capacity` should be set to the `count` of the given buffer, and the header's `count` must accurately describe
  /// the number of elements that were initialized.
  ///
  /// - important: If `headerConstructor` throws, it must have first uninitialized any partially-initialized portion of the buffer,
  ///              or `Element` must be a trivial type.
  ///
  init(minimumCapacity: Int, makingHeaderWith: (inout UnsafeMutableBufferPointer<Element>) throws -> Header) rethrows {
    self.wrapped = try _Storage.newBuffer(minimumCapacity: minimumCapacity, makingHeaderWith: makingHeaderWith)
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

  /// Call `body` with an `UnsafeMutablePointer` to the stored
  /// `Header`.
  ///
  /// - Note: This pointer is valid only for the duration of the
  ///   call to `body`.
  @inlinable
  func withUnsafeMutablePointerToHeader<R>(_ body: (UnsafeMutablePointer<Header>) throws -> R) rethrows -> R {
    return try wrapped.withUnsafeMutablePointerToHeader(body)
  }

  /// Call `body` with an `UnsafeMutablePointer` to the `Element`
  /// storage.
  ///
  /// - Note: This pointer is valid only for the duration of the
  ///   call to `body`.
  @inlinable
  func withUnsafeMutablePointerToElements<R>(_ body: (UnsafeMutablePointer<Element>) throws -> R) rethrows -> R {
    return try wrapped.withUnsafeMutablePointerToElements(body)
  }

  /// Call `body` with `UnsafeMutablePointer`s to the stored `Header`
  /// and raw `Element` storage.
  ///
  /// - Note: These pointers are valid only for the duration of the
  ///   call to `body`.
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

  /// Moves the contents of this buffer to a new buffer with the given capacity. The header is copied, although its `capacity` will be adjusted to reflect the new
  /// buffer's capacity. Afterwards, this buffer's `count` will be 0.
  ///
  /// - precondition: The given capacity must be sufficient to store all of this buffer's contents.
  ///
  func moveToNewBuffer(minimumCapacity: Int) -> Self {
    let numElements = count
    precondition(minimumCapacity >= numElements)
    let newBuffer = Self.init(minimumCapacity: minimumCapacity, initialHeader: header)
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

  /// Copies the contents of this buffer to a new buffer with the given capacity. The header is copied, although its `capacity` will be adjusted to reflect the new
  /// buffer's capacity. This buffer remains unchanged.
  ///
  /// - precondition: The given capacity must be sufficient to store all of this buffer's contents.
  ///
  func copyToNewBuffer(minimumCapacity: Int) -> Self {
    let numElements = count
    precondition(minimumCapacity >= numElements)
    let newBuffer = Self.init(minimumCapacity: minimumCapacity, initialHeader: header)
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

/// A wrapper for an `AltManagedBufferReference` which provides similar convenience methods and semantics to `Array`.
///
/// For example, `ManagedArrayBuffer` provides `RandomAccessCollection` conformance using the buffer's `count`, and
/// value semantics using copy-on-write. Unfortunately, while `RangeReplaceableCollection` conformance is not possible for arbitrary `Header` types,
/// `ManagedArrayBuffer` provides an alternative which supports many of the same operations, such as inserting and removing elements in arbitrary subranges
/// and efficiently growing the storage on-demand.
///
/// `ManagedArrayBuffer` only grows its capacity to exactly fit the number of elements being inserted; it does not employ any sort
/// of predictive growth strategy (although capacity may allocated in advance using `reserveCapacity`). It also does not shrink its storage,
/// although a fresh allocation produced by copy-on-write during a no-op operation such as `reserveCapacity(0)` will occupy the smallest possible space.
///
struct ManagedArrayBuffer<Header: ManagedBufferHeader, Element> {
  var storage: AltManagedBufferReference<Header, Element>

  /// Creates a new `ManagedArrayBuffer` with the given minimum capacity and header.
  /// Note that the header's `capacity` is automatically set to the actual, allocated capacity, and the header's `count` is set to `0`.
  ///
  init(minimumCapacity: Int, initialHeader: Header) {
    self.storage = .init(minimumCapacity: minimumCapacity, initialHeader: initialHeader)
  }

  /// Creates a new `ManagedArrayBuffer` with capacity for the given number of elements, which is then initialized by the given closure.
  ///
  /// The closure is called with the buffer's entire, uninitialized capacity, and must construct a header as well as initializing any contents.
  /// The header's `capacity` should be set to the `count` of the given buffer, and the header's `count` must accurately describe
  /// the number of elements that were initialized by the closure.
  ///
  /// - important: If `headerConstructor` throws, it must have first uninitialized any partially-initialized portion of the buffer,
  ///              or `Element` must be a trivial type.
  ///
  init(
    unsafeUninitializedCapacity capacity: Int,
    initializingStorageWith headerConstructor: (inout UnsafeMutableBufferPointer<Element>) throws -> Header
  ) rethrows {
    self.storage = try .init(minimumCapacity: capacity, makingHeaderWith: headerConstructor)
  }

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
    _modify {
      let preModifyCapacity = storage.header.capacity
      ensureUnique()
      yield &storage.header
      assert(storage.header.capacity == preModifyCapacity, "Invalid change of capacity")
    }
    set {
      let preModifyCapacity = storage.header.capacity
      ensureUnique()
      storage.header = newValue
      assert(storage.header.capacity == preModifyCapacity, "Invalid change of capacity")
    }
  }
}

// Array APIs.

extension ManagedArrayBuffer {

  func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows -> R {
    return try storage.withUnsafeMutablePointerToElements {
      return try body(UnsafeBufferPointer(start: $0, count: count))
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
}

extension ManagedArrayBuffer: RandomAccessCollection {
  typealias Index = Int

  var startIndex: Int {
    return 0
  }
  var endIndex: Int {
    return storage.count
  }
  var count: Int {
    return storage.count
  }
  func index(after i: Int) -> Int {
    precondition(i < endIndex, "Cannot increment endIndex")
    return i &+ 1
  }
  func index(before i: Int) -> Int {
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

  subscript(position: Int) -> Element {
    get {
      precondition(position >= startIndex && position < endIndex, "Index out of bounds")
      return storage.withUnsafeMutablePointerToElements { $0.advanced(by: position).pointee }
    }
    set {
      precondition(position >= startIndex && position < endIndex, "Index out of bounds")
      ensureUnique()
      return storage.withUnsafeMutablePointerToElements {
        $0.advanced(by: position).assign(repeating: newValue, count: 1)
      }
    }
    _modify {
      precondition(position >= startIndex && position < endIndex, "Index out of bounds")
      ensureUnique()
      let ptr = storage.withUnsafeMutablePointerToElements { $0.advanced(by: position) }
      yield &ptr.pointee
      withExtendedLifetime(storage) {}
    }
  }
}

extension ManagedArrayBuffer: AltRangeReplaceableCollection {

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

  private struct StorageHolder: BufferContainer {
    var bufferReference: AltManagedBufferReference<Header, Element>
    func withUnsafeMutablePointerToElements<R>(_ body: (UnsafeMutablePointer<Element>) throws -> R) rethrows -> R {
      return try bufferReference.withUnsafeMutablePointerToElements(body)
    }
  }

  @discardableResult
  mutating func replaceSubrange<C>(_ subrange: Range<Int>, with newElements: C) -> Range<Int>
  where C: Collection, Self.Element == C.Element {
    return unsafeReplaceSubrange(subrange, withUninitializedCapacity: newElements.count) { buffer in
      return buffer.initialize(from: newElements).1
    }
  }

  @discardableResult
  mutating func append<S>(contentsOf newElements: S) -> Range<Self.Index> where S: Sequence, Self.Element == S.Element {
    let preAppendEnd = endIndex
    var result = unsafeAppend(uninitializedCapacity: newElements.underestimatedCount) { ptr in
      return ptr.initialize(from: newElements)
    }
    precondition(result.1 == newElements.underestimatedCount)
    while let remaining = result.0.next() {
      append(remaining)
    }
    return Range(uncheckedBounds: (preAppendEnd, endIndex))
  }
}

// Extensions.

extension ManagedArrayBuffer {

  /// Appends space for the given number of objects, but leaves the initialization of that space to the given closure.
  ///
  /// - important: The closure must initialize **exactly** `uninitializedCapacity` elements.
  ///
  mutating func unsafeAppend<T>(
    uninitializedCapacity: Int, initializingWith initializer: (UnsafeMutableBufferPointer<Element>) -> T
  ) -> T {
    let oldCount = self.count
    let newCount = oldCount + uninitializedCapacity
    reserveCapacity(newCount)
    assert(storage.isKnownUniqueReference(), "reserveCapacity should have made this unique")

    let retVal = storage.withUnsafeMutablePointerToElements { elements -> T in
      let uninitializedBuffer = UnsafeMutableBufferPointer(start: elements + oldCount, count: uninitializedCapacity)
      return initializer(uninitializedBuffer)
    }
    storage.header.count = newCount
    return retVal
  }
  
  @discardableResult
  mutating func unsafeReplaceSubrange(
    _ subrange: Range<Int>,
    withUninitializedCapacity newSubrangeCount: Int,
    initializingWith initializer: (UnsafeMutableBufferPointer<Element>) -> Int) -> Range<Int> {
    
    let isUnique = storage.isKnownUniqueReference()
    let result = storage.withUnsafeMutablePointerToElements { elems in
      return replaceElements(
        in: UnsafeMutableBufferPointer(start: elems, count: storage.capacity),
        initializedCount: storage.count,
        isUnique: isUnique,
        subrange: subrange,
        withElements: newSubrangeCount,
        initializedWith: initializer,
        storageConstructor: {
          StorageHolder(bufferReference: .init(minimumCapacity: $0, initialHeader: storage.header))
        }
      )
    }
    // Update the count of our existing storage. Its contents may have been moved out.
    self.storage.header.count = result.bufferCount
    // Adopt any new storage that was allocated.
    if var newStorage = result.newStorage?.bufferReference {
      newStorage.header.count = result.newStorageCount
      self.storage = newStorage
    }
    return subrange.lowerBound..<(subrange.lowerBound + result.insertedCount)
  }

  func withElements<T>(range: Range<Index>, _ block: (UnsafeBufferPointer<Element>) throws -> T) rethrows -> T {
    precondition(range.startIndex >= startIndex, "Invalid startIndex")
    precondition(range.endIndex <= endIndex, "Invalid endIndex")
    return try storage.withUnsafeMutablePointerToElements { elements in
      let slice = UnsafeBufferPointer(start: elements + range.startIndex, count: range.count)
      return try block(slice)
    }
  }
}
