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


// --------------------------------------------
// MARK: - Unaligned loads
// --------------------------------------------


extension UnsafeRawPointer {

  /// Returns a new instance of the given type, constructed from the raw memory at the specified offset.
  ///
  /// The memory at this pointer plus offset must be initialized to `T` or another type that is layout compatible with `T`.
  /// It does not need to be aligned for access to `T`.
  ///
  @inlinable @inline(__always)
  internal func loadUnaligned<T>(fromByteOffset offset: Int = 0, as: T.Type) -> T where T: FixedWidthInteger {
    assert(_isPOD(T.self))
    var val: T = 0
    withUnsafeMutableBytes(of: &val) {
      $0.copyMemory(from: UnsafeRawBufferPointer(start: self, count: T.bitWidth / 8))
    }
    return val
  }
}


// --------------------------------------------
// MARK: - Fast initialize
// --------------------------------------------


extension UnsafeMutableBufferPointer {

  /// Initializes the buffer’s memory with the given elements.
  ///
  /// When calling the initialize(from:) method on a buffer b, the memory referenced by b must be uninitialized or the Element type must be a trivial type.
  /// After the call, the memory referenced by this buffer up to, but not including, the returned index is initialized.
  /// The buffer must contain sufficient memory to accommodate source.underestimatedCount.
  ///
  /// The returned index is the position of the element in the buffer one past the last element written.
  /// If source contains no elements, the returned index is equal to the buffer’s startIndex.
  /// If source contains an equal or greater number of elements than the buffer can hold, the returned index is equal to the buffer’s endIndex.
  ///
  /// This is like the standard library's `initialize(from:)` method, except that it doesn't return an iterator of remaining elements from the source,
  /// and thus is able to be significantly faster for sources which implement `withContiguousStorageIfAvailable`.
  ///
  @inlinable
  internal func fastInitialize<S>(from source: S) -> Int where S: Sequence, S.Element == Element {
    // UMBP.initialize(from:) is slow with slices. https://bugs.swift.org/browse/SR-14491
    let _bytesWritten = source.withContiguousStorageIfAvailable { srcBuffer -> Int in
      guard let srcAddress = srcBuffer.baseAddress else { return 0 }
      let bytesToWrite = Swift.min(count, srcBuffer.count)
      self.baseAddress?.initialize(from: srcAddress, count: bytesToWrite)
      return bytesToWrite
    }
    if let bytesWritten = _bytesWritten {
      return bytesWritten
    }
    return initialize(from: source).1
  }
}


// --------------------------------------------
// MARK: - Pointers to tuple elements
// --------------------------------------------
// Note: because tuples do not include tail padding, we should explicitly say how many elements are in each tuple.
//       `buffer.count / MemoryLayout<T>.stride` may return fewer than expected elements.

// Arity 2:

@inlinable @inline(__always)
internal func withUnsafeBufferPointerToElements<T, Result>(
  tuple: (T, T), _ body: (UnsafeBufferPointer<T>) -> Result
) -> Result {
  return withUnsafeBytes(of: tuple) {
    let ptr = UnsafeBufferPointer(start: $0.baseAddress!.assumingMemoryBound(to: T.self), count: 2)
    return body(ptr)
  }
}

@inlinable @inline(__always)
internal func withUnsafeMutableBufferPointerToElements<T, Result>(
  tuple: inout (T, T), _ body: (inout UnsafeMutableBufferPointer<T>) -> Result
) -> Result {
  return withUnsafeMutableBytes(of: &tuple) {
    var ptr = UnsafeMutableBufferPointer(start: $0.baseAddress!.assumingMemoryBound(to: T.self), count: 2)
    return body(&ptr)
  }
}

// Arity 4:

@inlinable @inline(__always)
internal func withUnsafeMutableBufferPointerToElements<T, Result>(
  tuple: inout (T, T, T, T), _ body: (inout UnsafeMutableBufferPointer<T>) -> Result
) -> Result {
  return withUnsafeMutableBytes(of: &tuple) {
    var ptr = UnsafeMutableBufferPointer(start: $0.baseAddress!.assumingMemoryBound(to: T.self), count: 4)
    return body(&ptr)
  }
}

// Arity 8:

@inlinable @inline(__always)
internal func withUnsafeBufferPointerToElements<T, Result>(
  tuple: (T, T, T, T, T, T, T, T), _ body: (UnsafeBufferPointer<T>) -> Result
) -> Result {
  return withUnsafeBytes(of: tuple) {
    let ptr = UnsafeBufferPointer(start: $0.baseAddress!.assumingMemoryBound(to: T.self), count: 8)
    return body(ptr)
  }
}

@inlinable @inline(__always)
internal func withUnsafeMutableBufferPointerToElements<T, Result>(
  tuple: inout (T, T, T, T, T, T, T, T), _ body: (inout UnsafeMutableBufferPointer<T>) -> Result
) -> Result {
  return withUnsafeMutableBytes(of: &tuple) {
    var ptr = UnsafeMutableBufferPointer(start: $0.baseAddress!.assumingMemoryBound(to: T.self), count: 8)
    return body(&ptr)
  }
}


// --------------------------------------------
// MARK: - Bounds-checked unsafe buffer
// --------------------------------------------


extension UnsafeBufferPointer {

  @inlinable
  internal var boundsChecked: UnsafeBoundsCheckedBufferPointer<Element> {
    UnsafeBoundsCheckedBufferPointer(self)
  }
}

/// A re-imagined contiguous buffer type, which attempts to protect against buffer over-reads in release builds with a negligible performance hit, and in some
/// cases even an overall performance _improvement_ over the standard library's `UnsafeBufferPointer`.
///
/// The idea behind this type is that we start with a buffer, in the form of a base pointer and (unsigned) size, `buffer_size`.
/// The indices, which are offsets from the pointer, are also unsigned integers; meaning they can never be negative, and bounds-checking can be simplified
/// to `index < buffer_size`.
/// The type is self-slicing, and the only rule to check that a slice's bounds are safe is that the maximum addressable offset must never increase over the slice's base.
/// Since indices are unsigned, all offsets up to the maximum addressable offset are within the bounds of the original buffer, and hence safe to access.
///
/// ## What don't we need to do?
///
/// The thing to remember is that we're not under any obligation to detect misuses of the `Collection` protocol.
/// If you have a buffer of 10 elements, and you increment its `startIndex` 1000 times, it may trigger a runtime error, or it may well return a garbage result index.
/// And if you take that garbage result and pass it in to `distance(from: Index, to: Index)`, it may also trigger a runtime error - or it may not;
/// it's perfectly valid for it to return a garbage number of elements instead. And garbage means garbage - for any reason - it doesn't matter if your index is beyond
/// the bounds of the collection, or if the calculation overflows; it's all equally garbage and you shouldn't expect a meaningful result.
/// You may, by some happy accident, land at a valid index, but you also might not, and nobody is under any obligation to trigger a runtime error along the way.
///
/// It isn't just unsafe types that are free from this obligation, either; even `Array` - the paragon of safe `Collection`s in Swift - won't trigger runtime errors
/// for many misuses of the `Collection` protocol. You have a 10-element `Array`? Want to increment its `startIndex` by 1000? No problem.
/// How about decrementing it by 1000? Also not a problem. Seriously, try it. I'm not lying:
///
/// ```swift
/// let arr = Array(10..<20)
/// arr.index(arr.startIndex, offsetBy: 1000)  // Returns 1000. No runtime error.
/// arr.index(arr.startIndex, offsetBy: -1000) // Returns -1000. No runtime error.
/// ```
///
/// This is really important. It means that we can provide the bare minimum bounds-checking needed for memory safety with very few actual checks,
/// many of which can be relatively simple for the compiler to prove away, providing we express them in the right way.
///
/// ## Slicing
///
/// Bounds-checking in slices is particularly interesting, because we really want to keep the simplified `index < buffer_size` bounds check.
/// But while the first buffer starts with indices `0..<buffer_size`, slices (and slices of slices) can have a non-zero offset from the start of the buffer.
/// So just checking `index < buffer_size` is not enough to say that an index is within the _slice's_ bounds.
///
/// But we can get around this in a bit of cheeky way: by just allowing certain reads outside of the slice's bounds 😅. I know, it sounds wrong, but actually - is it?
/// Again, we're trying to do the bare minimum to guarantee we never over-read the original buffer - as long as that is true, we don't _really_ care about
/// the slice's bounds. The slice bounds are mostly only needed for `Collection` semantics, (e.g. that `startIndex` and `count` return correct values),
/// and reads from other, invalid indexes are not _required_ to always trigger a runtime error. As mentioned above, as long as we always check that slices
/// (and slices of slices) never increase the maximum addressable offset, we can guarantee not to over-read the buffer just by checking the slice's upper bound.
///
/// To illustrate: if the slice bounds are `4..<10`, and you want to read from offset `2`, that's not actually a memory-safety issue.
/// We know that offset `2` is within the buffer; we don't need to fail in that situation. But if you try to read from offset `11` - well, we don't know that the buffer
/// extends that far, so we do need to fail in order to preserve memory-safety.
///
/// A related problem is invalid `Range`s; i.e. situations where `range.lowerBound > range.upperBound`. It turns out that, again, as long as we always
/// check that successive slices never increase the `upperBound` over their base (only decrease the addressable buffer or stay the same), we don't need
/// to check that the range is properly formed, or even that `startIndex` is in-bounds (until we try to access from it, of course).
///
/// ## A delicate balance
///
/// This is a delicate balance, for sure. It definitely does **not** protect against logic bugs which can happen by invoking behaviour unspecified by `Collection`
/// (e.g. reading from an invalid index), but it does provide effective protection against reading outside the bounds of a buffer of memory,
/// and hence provides meaningful safety guarantees beyond what `UnsafeBufferPointer` provides (which is nothing; no meaningful checks whatsoever).
///
/// Moreover (and perhaps most importantly), it does so with a negligible impact on performance. In the "AverageURLs" benchmark, I've seen the performance
/// difference when switching from UBP to this type range from about -5% (~ 32.2ms to 33.8ms) to about +8% (~32.2ms vs 29.7ms). My guess is that the use of
/// unsigned integers helps the compiler avoid some runtime checks when constructing `Range` literals, which are frequently used in generic `Collection` code.
///
/// But overall it's kind of margin-of-error-ish stuff, which is a great result considering the added memory-safety. By comparison, a type which adds
/// naive bounds-checking (including being strict about slice lower bounds) on an unsafe buffer with `Int` indexes, comes with a 20-25% performance hit.
///
/// ## Great! So, why is this still called 'Unsafe'?
///
/// Bounds-checking alone isn't enough for memory safety. In particular, this type:
///
/// 1. Doesn't guarantee the lifetime of the underlying memory. It's still a pointer underneath, after all.
/// 2. Doesn't guarantee that the buffer has been fully initialized. You're supposed to do that before you create this view over the buffer.
///
/// So it's still unsafe, but the situations where unsafe, undefined behaviour could be invoked are easier to spot, even in complex `Collection` algorithms.
///
@usableFromInline
internal struct UnsafeBoundsCheckedBufferPointer<Element> {

  @usableFromInline
  internal var baseAddress: Optional<UnsafePointer<Element>>

  @usableFromInline
  internal var bounds: Range<UInt>

  /// Convenience initializer for creating a bounds-checked view of the given `UnsafeBufferPointer`.
  ///
  @inlinable
  internal init(_ buffer: UnsafeBufferPointer<Element>) {
    // We trust UnsafeBufferPointer to meet our conditions:
    // - 'count' is within 0..<Int.max
    // - if 'baseAddress' is nil, 'count' is 0
    self.baseAddress = buffer.baseAddress
    self.bounds = 0..<UInt(bitPattern: buffer.count)
  }

  /// Creates a bounds-checked buffer view covering the memory from `baseAddress` and spanning `size` elements.
  ///
  /// - precondition: `size` must not be greater than `Int.max`.
  /// - precondition: If `size` is greater than 0, `baseAddress` must not be `nil`.
  ///                 If `size` is 0, `baseAddress` may be `nil`, but doesn't have to be.
  ///
  @inlinable
  internal init(baseAddress: UnsafePointer<Element>?, size: UInt) {
    // By limiting the size to `Int.max`, and bounds-checking every slice's (upperBound <= base.endIndex),
    // we ensure that every valid index, and every distance between valid indices, fits in a signed integer.
    //
    // This allows us to use `Int(bitPattern:)` to convert valid indexes without range/overflow checks.
    // We don't care about invalid indices; they are garbage values and will be rejected by bounds-checking if
    // they point outside of the buffer's known safe bounds.
    precondition(size <= UInt(Int.max), "buffer size is greater than Int.max!")
    precondition(size == 0 || baseAddress != nil, "buffer size > 0, but baseAddress is nil!")
    self.baseAddress = baseAddress
    self.bounds = 0..<size
  }

  /// Do not use. `internal` for inline purposes only.
  ///
  @inlinable
  internal init(_doNotUse_precheckedSliceOf base: Self, bounds: Range<UInt>) {
    // When slicing, we don't actually check that `bounds.lowerBound` (i.e. our new `startIndex`) is actually in-bounds,
    // only that the new `endIndex` is not greater than the parent's `endIndex`.
    //
    // For subscript accesses, that's fine, bounds-checking will handle it.
    // For other operations (like wCSIA, _copyContents) which bypass the subscript, extra checks are needed.
    self.baseAddress = base.baseAddress
    self.bounds = bounds
  }

  @inlinable @inline(__always)
  internal func boundsCheckForRead(_ index: UInt) {
    assert(index >= startIndex, "UnsafeBoundsCheckedBufferPointer: Invalid read. index < startIndex")
    precondition(index < endIndex, "UnsafeBoundsCheckedBufferPointer: Invalid read. index >= endIndex")
  }

  @inlinable @inline(__always)
  internal func boundsCheckForSlice(_ range: Range<UInt>) {
    assert(range.lowerBound >= startIndex, "UnsafeBoundsCheckedBufferPointer: Invalid slice. lowerBound < startIndex")
    precondition(range.upperBound <= endIndex, "UnsafeBoundsCheckedBufferPointer: Invalid slice. upperBound > endIndex")
  }
}

extension UnsafeBoundsCheckedBufferPointer: RandomAccessCollection {

  @inlinable
  internal var startIndex: UInt {
    bounds.lowerBound
  }

  @inlinable
  internal var endIndex: UInt {
    bounds.upperBound
  }

  @inlinable
  internal var count: Int {
    Int(bitPattern: endIndex &- startIndex)
  }

  @inlinable
  internal var isEmpty: Bool {
    // We don't expect startIndex to regularly be greater than endIndex, but by writing it this way
    // (rather than startIndex != endIndex), we communicate that !isEmpty is a synonym for startIndex < endIndex.
    // This can help eliminate some bounds checks.
    startIndex >= endIndex
  }

  @inlinable @inline(__always)
  internal subscript(position: UInt) -> Element {
    boundsCheckForRead(position)
    return baseAddress.unsafelyUnwrapped[Int(bitPattern: position)]
  }

  @inlinable @inline(__always)
  internal subscript(sliceBounds: Range<UInt>) -> UnsafeBoundsCheckedBufferPointer<Element> {
    boundsCheckForSlice(sliceBounds)
    return UnsafeBoundsCheckedBufferPointer(_doNotUse_precheckedSliceOf: self, bounds: sliceBounds)
  }

  @inlinable
  internal var indices: Range<UInt> {
    bounds
  }

  // All of these indexing methods return essentially junk values (albeit deterministic junk) if you use them
  // in a way that Collection does not specify.
  //
  // It's no different to a 10-element Array giving you an Index of 1000 if you call 'index(after:)' enough times.
  // The important thing for memory safety is that we bounds-check the actual read from the pointer.

  @inlinable @inline(__always)
  internal func index(after i: UInt) -> UInt {
    i &+ 1
  }

  @inlinable @inline(__always)
  internal func formIndex(after i: inout UInt) {
    i &+= 1
  }

  @inlinable @inline(__always)
  internal func index(before i: UInt) -> UInt {
    i &- 1
  }

  @inlinable @inline(__always)
  internal func formIndex(before i: inout UInt) {
    i &-= 1
  }

  @inlinable
  internal func index(_ i: UInt, offsetBy distance: Int) -> UInt {
    UInt(bitPattern: Int(bitPattern: i) &+ distance)
  }

  @inlinable
  internal func formIndex(_ i: inout UInt, offsetBy distance: Int) {
    i = UInt(bitPattern: Int(bitPattern: i) &+ distance)
  }

  @inlinable
  internal func index(_ i: UInt, offsetBy n: Int, limitedBy limit: UInt) -> UInt? {
    let l = distance(from: i, to: limit)
    if n > 0 ? l >= 0 && l < n : l <= 0 && n < l {
      return nil
    }
    return UInt(bitPattern: Int(bitPattern: i) &+ n)
  }

  @inlinable
  internal func distance(from start: UInt, to end: UInt) -> Int {
    Int(bitPattern: end) &- Int(bitPattern: start)
  }

  @inlinable @inline(__always)
  internal func withContiguousStorageIfAvailable<R>(
    _ body: (UnsafeBufferPointer<Element>) throws -> R
  ) rethrows -> R? {
    // Watch out!
    // - 'guard startIndex < endIndex' is effectively a bounds-check for 'startIndex'.
    //   We otherwise don't check the collection's lower bound.
    // - This must be a single statement, otherwise the compiler may not recognize that this
    //   never returns 'nil', and might not eliminate the non-contiguous branch in generic algorithms.
    return try body(
      UnsafeBufferPointer(
        start: baseAddress.map { $0 + Int(bitPattern: startIndex) },
        count: baseAddress != nil && startIndex < endIndex ? count : 0
      )
    )
  }

  @inlinable @inline(__always)
  internal func _failEarlyRangeCheck(_ index: UInt, bounds: Range<UInt>) {}

  @inlinable @inline(__always)
  internal func _failEarlyRangeCheck(_ range: Range<UInt>, bounds: Range<UInt>) {}

  @inlinable
  internal func _copyContents(
    initializing destination: UnsafeMutableBufferPointer<Element>
  ) -> (Iterator, UnsafeMutableBufferPointer<Element>.Index) {
    // Watch out!
    // 'startIndex < endIndex' is effectively a bounds-check for 'startIndex', as well as checking for an empty buffer.
    // We otherwise don't check the collection's lower bound.
    guard startIndex < endIndex, !destination.isEmpty else { return (makeIterator(), 0) }
    let src = baseAddress.unsafelyUnwrapped + Int(bitPattern: bounds.lowerBound)
    let dst = destination.baseAddress.unsafelyUnwrapped
    let n = Swift.min(destination.count, count)
    dst.initialize(from: src, count: n)
    return (Iterator(pointer: self, idx: bounds.lowerBound &+ UInt(bitPattern: n)), n)
  }
}

extension UnsafeBoundsCheckedBufferPointer {

  @inlinable
  internal func makeIterator() -> Iterator {
    Iterator(pointer: self, idx: startIndex)
  }

  @usableFromInline
  internal struct Iterator: IteratorProtocol {

    @usableFromInline
    internal var pointer: UnsafeBoundsCheckedBufferPointer

    @usableFromInline
    internal var idx: UInt

    @inlinable
    internal init(pointer: UnsafeBoundsCheckedBufferPointer<Element>, idx: UInt) {
      self.pointer = pointer
      self.idx = idx
    }

    @inlinable @inline(__always)
    internal mutating func next() -> Element? {
      guard idx < pointer.endIndex else { return nil }
      let i = idx
      pointer.formIndex(after: &idx)
      return pointer[i]
    }
  }
}
