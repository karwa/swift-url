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
