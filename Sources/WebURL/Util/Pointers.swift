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
    var val: T = 0
    withUnsafeMutableBytes(of: &val) {
      $0.copyMemory(from: UnsafeRawBufferPointer(start: self + offset, count: MemoryLayout<T>.stride))
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


extension UnsafeRawBufferPointer {

  /// Returns a typed pointer to the memory referenced by this buffer, assuming that the memory is already bound to the specified type.
  ///
  /// This is equivalent to calling `UnsafeRawPointer.assumingMemoryBound` on this buffer's base address, and dividing this buffer's
  /// `count` by the `stride` of the given type. Be sure to do lots of research on the above method before even thinking about using this.
  ///
  @inlinable @inline(__always)
  internal func _assumingMemoryBound<T>(to: T.Type) -> UnsafeBufferPointer<T> {
    guard let base = baseAddress else {
      return .init(start: nil, count: 0)
    }
    // Question: If we 'assumingMemoryBound' the base address, can we just make a buffer with the correct 'count'
    //           and treat all of it as typed/bound?
    //
    // Answer:   Yes. Unlike 'bindMemory', which calls a Builtin function [1] with the pointer address and number of
    //           elements and communicates to the compiler the entire _region_ of memory being bound,
    //           'assumingMemoryBound' does nothing [2] - it doesn't call any Builtins, and simply constructs
    //           a typed pointer from an untyped one.
    //
    //           That's what makes it so dangerous: as it doesn't actually communicate anything to the compiler
    //           about how the memory is being accessed, incorrect use can cause type-based anti-aliasing to miscompile.
    //           As the name suggests, we assume the compiler already knows - i.e. that the entire region has already
    //           been bound.
    //
    // [1]: https://github.com/apple/swift/blob/a0098c0174199b76473636af50699e21b688110c/stdlib/public/core/UnsafeRawBufferPointer.swift.gyb#L692
    // [2]: https://github.com/apple/swift/blob/a0098c0174199b76473636af50699e21b688110c/stdlib/public/core/UnsafeRawPointer.swift#L335
    return .init(start: base.assumingMemoryBound(to: to), count: count / MemoryLayout<T>.stride)
  }
}

extension UnsafeMutableRawBufferPointer {

  /// Returns a typed pointer to the memory referenced by this buffer, assuming that the memory is already bound to the specified type.
  ///
  /// This is equivalent to calling `UnsafeMutableRawPointer.assumingMemoryBound` on this buffer's base address, and dividing this buffer's
  /// `count` by the `stride` of the given type. Be sure to do lots of research on the above method before even thinking about using this.
  ///
  @inlinable @inline(__always)
  internal func _assumingMemoryBound<T>(to: T.Type) -> UnsafeMutableBufferPointer<T> {
    guard let base = baseAddress else {
      return .init(start: nil, count: 0)
    }
    return .init(start: base.assumingMemoryBound(to: to), count: count / MemoryLayout<T>.stride)
  }
}

// Arity 4:

@inlinable @inline(__always)
internal func withUnsafeMutableBufferPointerToElements<T, Result>(
  tuple: inout (T, T, T, T), _ body: (inout UnsafeMutableBufferPointer<T>) -> Result
) -> Result {
  return withUnsafeMutableBytes(of: &tuple) {
    var ptr = $0._assumingMemoryBound(to: T.self)
    return body(&ptr)
  }
}

// Arity 8:

@inlinable @inline(__always)
internal func withUnsafeBufferPointerToElements<T, Result>(
  tuple: (T, T, T, T, T, T, T, T), _ body: (UnsafeBufferPointer<T>) -> Result
) -> Result {
  return withUnsafeBytes(of: tuple) {
    return body($0._assumingMemoryBound(to: T.self))
  }
}

@inlinable @inline(__always)
internal func withUnsafeMutableBufferPointerToElements<T, Result>(
  tuple: inout (T, T, T, T, T, T, T, T), _ body: (inout UnsafeMutableBufferPointer<T>) -> Result
) -> Result {
  return withUnsafeMutableBytes(of: &tuple) {
    var ptr = $0._assumingMemoryBound(to: T.self)
    return body(&ptr)
  }
}


// --------------------------------------------
// MARK: - Reducing arithmetic overflow traps
// --------------------------------------------
// The implementation of UnsafeBufferPointer uses arithmetic which traps on overflow in its indexing operations
// (e.g. index(after:)). This isn't a part of memory safety - UnsafeBufferPointer is, as the name suggests, unsafe.
// The thing that makes it unsafe is that it lacks bounds-checking in release mode, so you can tell it to read from
// any nonsense offset (too large, negative, whatever), and it'll just do it and think everything was fine.
//
// Collection doesn't make any guarantees about what happens when you use a Collection incorrectly;
// incrementing an invalid index could trap, or it could always return startIndex, endIndex, or anything.
// The same goes for subscripting - a Collection of Ints could trap, or return 0 or -1 if you ask for an out-of-bounds
// element. Generic Collection code has to do things like checking an index is less than endIndex before incrementing -
// otherwise it will invoke _unspecified_ behaviour (not the same as UB in C) and may give you nonsense results.
//
// The one thing a Collection should never do (or any type in Swift, Collection or not), is violate memory safety.
// --> **Even if you use it incorrectly** <--. That's the difference with C-style undefined behaviour.
// The exception to this rule is UnsafeBufferPointer - as explained above, if you ask it to read from an invalid index,
// it will happily do so. Incorrect usage _will_ invoke C-style undefined behaviour and violate memory safety.
//
// This tweaked implementation of UnsafeBufferPointer makes some changes to the stdlib's implementation,
// but is no more or less safe (you can't be "more or less safe" than something else; something is safe or it isn't):
//
// - Indexing operations do not overflow. As explained above, there is no requirement to trap.
//   UnsafeBufferPointer won't bounds-check the index anyway, so trap or not, reading from an index you incremented
//   too far will violate memory safety. Trapping on overflow doesn't make incorrect code safe.
//
//   See discussion at:
//   https://forums.swift.org/t/is-it-okay-to-ignore-overflow-when-incrementing-decrementing-collection-indexes/47416
//
// - It is self-slicing. This helps to ensure that `Slice` doesn't mess up any of the low-level performance tweaks.
//   It also allows us to implement `_copyContents` without having to create a custom iterator, which is nice.
//
// --------------------------------------------


extension UnsafeBufferPointer {

  @inlinable
  internal var withoutTrappingOnIndexOverflow: NoOverflowUnsafeBufferPointer<Element> {
    NoOverflowUnsafeBufferPointer(self)
  }
}

@usableFromInline
internal struct NoOverflowUnsafeBufferPointer<Element> {

  @usableFromInline
  internal var baseAddress: UnsafePointer<Element>?

  @usableFromInline
  internal var bounds: Range<Int>

  @inlinable
  internal init(baseAddress: UnsafePointer<Element>?, count: Int) {
    assert(count >= 0)
    assert(count == 0 || baseAddress != nil)
    self.baseAddress = baseAddress
    self.bounds = Range(uncheckedBounds: (0, count))
  }

  @inlinable
  internal init(_ buffer: UnsafeBufferPointer<Element>) {
    self.init(baseAddress: buffer.baseAddress, count: buffer.count)
  }

  @inlinable
  internal init(slicing base: Self, bounds: Range<Int>) {
    base._failEarlyRangeCheck(bounds, bounds: base.bounds)
    self.baseAddress = base.baseAddress
    self.bounds = bounds
  }
}

extension NoOverflowUnsafeBufferPointer: RandomAccessCollection {

  @inlinable
  internal var startIndex: Int {
    _assumeNonNegative(bounds.lowerBound)
  }

  @inlinable
  internal var endIndex: Int {
    _assumeNonNegative(bounds.upperBound)
  }

  @inlinable
  internal var count: Int {
    endIndex &- startIndex
  }

  @inlinable
  internal var isEmpty: Bool {
    // startIndex will never be greater than endIndex, but by writing it this way (rather than startIndex != endIndex),
    // we communicate that when 'isEmpty == false', startIndex is definitely < endIndex. This means:
    // - startIndex + 1 won't overflow
    // - The range startIndex..<endIndex is well-formed and shouldn't trap, and
    // - startIndex + 1 will at most be equal to endIndex
    //
    // This can indeed be shown to make an observable difference in smaller code snippets,
    // although most uses of 'isEmpty == false' have been changed to 'startIndex < endIndex' anyway.
    startIndex >= endIndex
  }

  @inlinable
  internal subscript(position: Int) -> Element {
    _failEarlyRangeCheck(position, bounds: bounds)
    return baseAddress.unsafelyUnwrapped[position]
  }

  @inlinable
  internal subscript(sliceBounds: Range<Int>) -> NoOverflowUnsafeBufferPointer<Element> {
    NoOverflowUnsafeBufferPointer(slicing: self, bounds: sliceBounds)
  }

  @inlinable
  internal func _failEarlyRangeCheck(_ index: Int, bounds: Range<Int>) {
    assert(index >= bounds.lowerBound)
    assert(index < bounds.upperBound)
  }

  @inlinable
  internal func _failEarlyRangeCheck(_ range: Range<Int>, bounds: Range<Int>) {
    assert(range.lowerBound >= bounds.lowerBound)
    assert(range.upperBound <= bounds.upperBound)
  }

  @inlinable
  internal func _copyContents(
    initializing destination: UnsafeMutableBufferPointer<Element>
  ) -> (Iterator, UnsafeMutableBufferPointer<Element>.Index) {
    guard !isEmpty && !destination.isEmpty else { return (makeIterator(), 0) }
    let src = self.baseAddress.unsafelyUnwrapped + bounds.lowerBound
    let dst = destination.baseAddress.unsafelyUnwrapped
    let n = Swift.min(destination.count, self.count)
    dst.initialize(from: src, count: n)
    return (self[Range(uncheckedBounds: (bounds.lowerBound &+ n, bounds.upperBound))].makeIterator(), n)
  }

  @inlinable
  internal var indices: Range<Int> {
    bounds
  }

  @inlinable @inline(__always)
  internal func index(after i: Int) -> Int {
    i &+ 1
  }

  @inlinable @inline(__always)
  internal func formIndex(after i: inout Int) {
    i &+= 1
  }

  @inlinable
  internal func index(_ i: Int, offsetBy distance: Int) -> Int {
    i &+ distance
  }

  @inlinable
  internal func formIndex(_ i: inout Int, offsetBy distance: Int) {
    i &+= distance
  }

  @inlinable
  internal func index(_ i: Int, offsetBy n: Int, limitedBy limit: Int) -> Int? {
    let l = limit &- i
    if n > 0 ? l >= 0 && l < n : l <= 0 && n < l {
      return nil
    }
    return i &+ n
  }

  @inlinable @inline(__always)
  internal func index(before i: Int) -> Int {
    i &- 1
  }

  @inlinable @inline(__always)
  internal func formIndex(before i: inout Int) {
    i &-= 1
  }

  @inlinable
  internal func distance(from start: Int, to end: Int) -> Int {
    end &- start
  }

  @inlinable
  internal func withContiguousStorageIfAvailable<R>(
    _ body: (UnsafeBufferPointer<Element>) throws -> R
  ) rethrows -> R? {
    guard let baseAddress = baseAddress else { return try body(UnsafeBufferPointer(start: nil, count: 0)) }
    return try body(UnsafeBufferPointer(start: baseAddress + startIndex, count: _assumeNonNegative(count)))
  }
}
