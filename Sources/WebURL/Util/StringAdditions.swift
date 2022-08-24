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

extension String {

  /// Creates a String from the given collection of UTF-8 code-units, in a way that is optimized for discontiguous collections.
  ///
  /// The standard library's `String(decoding:as:)` initializer simply copies discontiguous collections to an `Array`, and uses
  /// the array's contiguous storage to initialize the `String`. This initializer bypasses the `Array`, copying the given code-units
  /// in to `String`'s internal storage in the most direct way available, with optimizations for small-medium length collections which avoids
  /// heap allocations.
  ///
  /// On percent-encoding/decoding benchmarks, this can improve performance by 60-75% (i.e. taking about _one quarter_ of the time).
  ///
  @inlinable
  internal init<C>(discontiguousUTF8 utf8: C) where C: Collection, C.Element == UInt8 {

    // We don't care if this overflows; it is just used to size the allocation.
    // If the collection doesn't initialize this many elements, we'll fatalError anyway.
    var _count: UInt = 0
    for _ in utf8.indices { _count &+= 1 }
    let count = Int(truncatingIfNeeded: _count)

    self = String(_unsafeUninitializedCapacity: count) { buffer in
      guard var ptr = buffer.baseAddress else { return 0 }
      let end = ptr + buffer.count
      var i = utf8.startIndex
      while i < utf8.endIndex, ptr < end {
        ptr.initialize(to: utf8[i])
        ptr += 1
        utf8.formIndex(after: &i)
      }
      precondition(i == utf8.endIndex, "Collection does not contain 'count' elements")
      return ptr - buffer.baseAddress!
    }
  }

  @inlinable
  internal init(
    _unsafeUninitializedCapacity capacity: Int,
    initializingUTF8With initializer: (UnsafeMutableBufferPointer<UInt8>) -> Int
  ) {
    if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
      self = String(unsafeUninitializedCapacity: capacity, initializingUTF8With: initializer)
      return
    }
    if capacity > 64 {
      self = String(decoding: [UInt8](unsafeUninitializedCapacity: capacity) { $1 = initializer($0) }, as: UTF8.self)
      return
    }
    var sixtyFourBytes:
      (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
      ) = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
      )
    let _ = sixtyFourBytes.63  // Check that there are 64 elements. This wouldn't compile otherwise.
    self = withUnsafeMutableBytes(of: &sixtyFourBytes) { rawBuffer in
      let ptr = UnsafeMutableBufferPointer(start: rawBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 64)
      let initializedCount = initializer(ptr)
      return String(decoding: UnsafeBufferPointer(rebasing: ptr.prefix(initializedCount)), as: UTF8.self)
    }
  }
}


// --------------------------------------------
// MARK: - Contiguous UTF-8
// --------------------------------------------
// We do low-level string processing at the UTF-8 level, with functions that work with generic Collections of UInt8.
// Those functions call withContiguousStorageIfAvailable, wrapping the provided buffer in a
// UnsafeBoundsCheckedBufferPointer and forwarding to the actual implementation.
// This is great for code-size: all contiguous data sources immediately drop down to a single generic specialization,
// which includes bounds-checking.
//
// If the collection is ^not^ contiguous, we fall back to using it directly, and the compiler will create
// a bespoke specialization. Generally, we don't expect many non-contiguous collections, so it's not a big deal.
//
// But there is one major exception: String.UTF8View. We know that, at runtime, almost all Strings will
// be native Swift Strings, with contiguous UTF-8 storage - but statically, the compiler still emits a
// specialization using String.UTF8View and storing String.Index-es, just in case it isn't.
//
// By using String.withUTF8 (not available on StringProtocol), we can use the native UTF-8 storage of a native
// Swift String/Substring, while forcing bridged Strings to become native. This means that String always uses
// the contiguous code-path, and we no longer need specializations for String.UTF8View.
// The result is a 20% (!) reduction in code-size.
// --------------------------------------------


extension StringProtocol {

  /// Calls `body` with this string's contents in a contiguous UTF-8 buffer.
  ///
  /// - If this is already a native String/Substring, its contiguous storage will be used directly.
  /// - Otherwise, it will be copied to contiguous storage.
  ///
  @inlinable @inline(__always)
  internal func _withContiguousUTF8<Result>(_ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result {
    if let resultWithExistingStorage = try utf8.withContiguousStorageIfAvailable(body) {
      return resultWithExistingStorage
    }
    var copy = String(self)
    return try copy.withUTF8(body)
  }
}

extension Optional where Wrapped: StringProtocol {

  /// Calls `body` with this string's contents in a contiguous UTF-8 buffer.
  ///
  /// - If this value is `nil`, `body` is invoked with `nil`.
  /// - If this is already a native String/Substring, its contiguous storage will be used directly.
  /// - Otherwise, it will be copied to contiguous storage.
  ///
  @inlinable @inline(__always)
  internal func _withContiguousUTF8<Result>(_ body: (UnsafeBufferPointer<UInt8>?) throws -> Result) rethrows -> Result {
    switch self {
    case .some(let string): return try string._withContiguousUTF8(body)
    case .none: return try body(nil)
    }
  }
}
