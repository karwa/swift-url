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

extension UnsafeBufferPointer {

  @inlinable
  internal var withUncheckedIndexArithmetic: UnsafeUncheckedMathBufferPointer<Element> {
    UnsafeUncheckedMathBufferPointer(self)
  }
}

/// An UnsafeBufferPointer with unsigned indexes and using unchecked math for index calculations.
///
/// This type is similar in spirit to the merged PR <https://github.com/apple/swift/pull/37424>,
/// but ported to all systems and with unsigned indexes. Like the standard library's `UnsafeBufferPointer`,
/// this type does **not** perform any bounds-checking in release builds.
///
@usableFromInline
internal struct UnsafeUncheckedMathBufferPointer<Element> {

  @usableFromInline
  internal var baseAddress: Optional<UnsafePointer<Element>>

  @usableFromInline
  internal var bounds: Range<UInt>

  @inlinable
  internal init(_ buffer: UnsafeBufferPointer<Element>) {
    // We trust UnsafeBufferPointer to meet our conditions:
    // - 'count' is within 0..<Int.max
    // - if 'baseAddress' is nil, 'count' is 0
    self.baseAddress = buffer.baseAddress
    self.bounds = 0..<UInt(bitPattern: buffer.count)
  }

  /// Do not use. `internal` for inline purposes only.
  ///
  @inlinable
  internal init(_doNotUse_precheckedSliceOf base: Self, bounds: Range<UInt>) {
    self.baseAddress = base.baseAddress
    self.bounds = bounds
  }

  @inlinable @inline(__always)
  internal func boundsCheckForRead(_ index: UInt) {
    assert(index >= startIndex, "UnsafeUncheckedMathBufferPointer: Invalid read. index < startIndex")
    assert(index < endIndex, "UnsafeUncheckedMathBufferPointer: Invalid read. index >= endIndex")
  }

  @inlinable @inline(__always)
  internal func boundsCheckForSlice(_ range: Range<UInt>) {
    assert(range.lowerBound >= startIndex, "UnsafeUncheckedMathBufferPointer: Invalid slice. lowerBound < startIndex")
    assert(range.upperBound <= endIndex, "UnsafeUncheckedMathBufferPointer: Invalid slice. upperBound > endIndex")
  }
}

extension UnsafeUncheckedMathBufferPointer: RandomAccessCollection {

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
    startIndex >= endIndex
  }

  @inlinable @inline(__always)
  internal subscript(position: UInt) -> Element {
    boundsCheckForRead(position)
    return baseAddress.unsafelyUnwrapped[Int(bitPattern: position)]
  }

  @inlinable @inline(__always)
  internal subscript(sliceBounds: Range<UInt>) -> UnsafeUncheckedMathBufferPointer<Element> {
    boundsCheckForSlice(sliceBounds)
    return UnsafeUncheckedMathBufferPointer(_doNotUse_precheckedSliceOf: self, bounds: sliceBounds)
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

extension UnsafeUncheckedMathBufferPointer {

  @inlinable
  internal func makeIterator() -> Iterator {
    Iterator(pointer: self, idx: startIndex)
  }

  @usableFromInline
  internal struct Iterator: IteratorProtocol {

    @usableFromInline
    internal var pointer: UnsafeUncheckedMathBufferPointer

    @usableFromInline
    internal var idx: UInt

    @inlinable
    internal init(pointer: UnsafeUncheckedMathBufferPointer<Element>, idx: UInt) {
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
