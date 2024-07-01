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


#if swift(<5.9)
  extension UnsafeRawPointer {

    /// Returns a new instance of the given type, constructed from the raw memory at the specified offset.
    ///
    /// The memory at this pointer plus offset must be initialized to `T` or another type
    /// that is layout compatible with `T`. It does not need to be aligned for access to `T`.
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
#endif


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

// Note: This documentation is intended to be very thorough, because I assume that anybody who sees a library
//       which includes its own buffer-pointer type is (rightly) going to be sceptical.
//       I would be sceptical, too.

/// A re-imagined contiguous buffer type, which introduces bounds-checking to protect against buffer over-reads
/// even in release builds. The implementation is carefully tuned to allow the compiler to eliminate bounds checks
/// and other overheads more easily.
///
/// The idea behind this type is that we represent a buffer as a base pointer and (unsigned) size.
/// The indexes are also unsigned integers, although the buffer's size is limited to `Int.max`.
/// This gives us a couple of benefits:
///
/// 1. It is impossible to address locations before the base pointer.
///    In order to bounds-check a read at some index `i`, we only need to check that `i < endIndex`.
///
/// 2. We can easily convert between signed and unsigned integers for arithmetic using `(U)Int(bitPattern:)`.
///    The bit-pattern of a negative `Int` will be interpreted as a `UInt` whose magnitude is `> Int.max`,
///    so it will automatically be an invalid index.
///
/// The type is also self-slicing (for code size in both respects - to limit the amount of code that needs to be audited
/// by humans, and the number of generic specialisations that get generated by the compiler).
///
/// Slices are really interesting because they are used _a lot_ in complex Collection algorithms,
/// and could complicate our approach to bounds-checking. There's a whole sub-section about this, but essentially:
///
/// 1. Slices keep the same base pointer as the parent.
///
/// 2. Since only the upper-bound (the slice's `endIndex`) is used to ensure memory safety,
///    that's the only part we check in release builds. It must always be `<=` to the parent's `endIndex`,
///    so the maximum addressable offset from the base pointer can only go down (or stay the same).
///
/// 3. This means that we can keep our simplified `i < endIndex` bounds-check, even for slices.
///
///
/// ## What don't we need to do?
///
///
/// This type is designed to provide speed _and_ safety, so it's useful to know what we can get away with
/// without violating memory safety.
///
/// The most important thing is that we're not obliged to detect _misuses_ of the `Collection` protocol.
/// For instance, let's say you have a buffer of 10 elements, and you increment its `startIndex` 1000 times,
/// what is the result?
///
/// Actually, it's not specified: it _may_ trigger a `fatalError` at runtime, or it _may_ return a garbage index,
/// or it _may_ automatically limit itself to `endIndex`, or wrap around to `startIndex` again.
/// And if you take that unspecified result and pass it in to, say, `distance(from: Index, to: Index)`,
/// it's also not specified what that will do, either - it might `fatalError`, or it might not; it might return a garbage
/// value, or maybe it always returns 0, etc. It's not specified, is the point.
///
/// And it's worth pointing out explicitly that "garbage" means garbage for any reason.
/// It's perfectly fine if `distance(from: Index, to: Index)` overflows with invalid indexes, for instance.
/// There is no obligation to `fatalError`.
///
/// None of this is at odds with the idea of memory safety because, crucially, these operations _do not access memory_.
///
/// This isn't just a property of unsafe types, either; even `Array` - the paragon of safe `Collection`s in Swift -
/// won't trigger runtime errors for many misuses of the `Collection` protocol, and will happily return "garbage"
/// indexes outside the bounds of the array.
///
/// You have a 10-element `Array`? Want to increment its `startIndex` by 1000? No problem.
/// How about decrementing `startIndex` by 1000? Also fine.
///
/// ```swift
/// let arr = Array(10..<20)
/// arr.index(arr.startIndex, offsetBy: 1000)  // Returns 1000. No runtime error.
/// arr.index(arr.startIndex, offsetBy: -1000) // Returns -1000. No runtime error.
/// ```
///
/// Again, there's no problem with any of that (from a memory safety perspective),
/// because these operations _do not access memory_.
///
///
/// ## Slicing
///
///
/// Bounds-checking in slices is interesting, because we want to keep the simple `i < endIndex` bounds check.
///
/// But while the original buffer starts with indexes `0..<size`, slices can have a non-zero offset
/// from the start of their parent, so just checking `i < size` is not enough to say that an index
/// is within the slice's bounds.
///
/// But we can get around this in a bit of cheeky way: by just allowing certain reads outside of the slice's bounds 😅.
/// Remember what we said about Collection semantics -- we don't _strictly_ care that you only access indexes
/// within the slice's bounds, we only care that you only access locations within the original buffer's bounds.
/// As it turns out, slice bounds are a Collection concept, and enforcing them is not necessary for memory safety.
///
/// So what we do is:
///
/// 1. We keep the base pointer of the original buffer.
///
/// 2. We store the range of the slice -- we still need to _know_ its bounds for it to, y'know, be a slice.
///
/// 3. When creating a slice, it turns out that we only need to check the `upperBound` of the slice,
///    to ensure the maximum addressable offset never grows - only shrinks or stays the same.
///    This is true even if the range is invalid (i.e. `lowerBound > upperBound`).
///
/// 4. This means we can keep our simple `i < endIndex` bounds check in release mode.
///    We allow reads outside of the slice, but never outside of the buffer it belongs to.
///
/// Here's that visually:
///
/// ```
/// ┌────────────────────────────┐
/// │                            │ - original buffer
/// └────────────────────────────┘
/// 0    |                  |    x
///      |                  |
///      ┌──────────────────┐
///      │                  │ - bounds of the slice
///      └──────────────────┘
/// ┌───────────────────────┐
/// │░░░░░░░░░░░░░░░░░░░░░░░│ - will not trap for accesses in this region
/// └───────────────────────┘
/// 0                       y
/// ```
///
/// To give a concrete example: let's say the original buffer has a length of `20`, and the slice bounds are `4..<10`,
/// there will not be a `fatalError` in release builds if you try to access index `2`, because we still know
/// it is within bounds of the original buffer, so it is not a memory-safety issue.
///
/// That doesn't mean it isn't a bug - it is, and we _will_ still trap in debug builds
/// because you're doing something incorrect, but it's not undefined behaviour.
///
/// A related problem is an invalid `Range` - i.e. situations where `range.lowerBound > range.upperBound`.
/// As long as we always check that successive slices never increase their `upperBound` over their base,
/// it will always be valid, and so for the most part we don't need to check that the range is properly formed,
/// or even that `lowerBound` is in-bounds (!).
///
/// That's because, again, it doesn't actually access memory. So long as that bounds check on actual accesses holds,
/// nothing else really matters. It's important for `upperBound` to be valid to ensure that, but that's all.
///
/// I said "for the most part", because there are two exceptions:
///
/// - `withContiguousStorageIfAvailable`
/// - `_copyContents(initializing:)`
///
/// In both of these cases, we perform "bulk access" to the entire slice or return an unchecked UBP pointer over it,
/// so we need to check both ends of its bounds.
///
///
/// ## A delicate balance
///
///
/// This is a delicate balance, for sure. It's important to remember the goal of this type -
/// to do the utter bare minimum required for memory safety (in release builds).
///
/// It does **not** protect against logic bugs which can happen if you misuse the `Collection` protocol
/// (e.g. invalid indexing operations, and sometimes even reading from an invalid location),
/// so if you get a problem in a release build, it may be more difficult to debug.
/// But those kinds of bugs should at least be deterministic.
///
/// In debug builds, more thorough checks are enabled, so you can more easily spot where the unexpected behaviour
/// happened.
///
///
/// ## Great! So, why is this still called 'Unsafe'?
///
///
/// Bounds-checking alone isn't enough for memory safety. In particular, this type:
///
/// 1. Doesn't guarantee the lifetime of the underlying memory.
///    It's still a pointer underneath, after all.
///
/// 2. Doesn't guarantee that the buffer has been fully initialized.
///    You're supposed to do that before you create this view over the buffer.
///
/// So it's still unsafe, but the situations where unsafe, undefined behaviour could be invoked are easier to spot,
/// even in complex `Collection` algorithms.
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
    // We don't actually expect startIndex to be greater than endIndex, but by writing it this way
    // rather than `startIndex != endIndex`, we communicate that `!isEmpty` means `startIndex < endIndex`.
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
    // - 'startIndex < endIndex' is effectively a bounds-check for 'startIndex'.
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
