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
      let buffer = rawBuffer._assumingMemoryBound(to: UInt8.self)
      let initializedCount = initializer(buffer)
      return String(decoding: UnsafeBufferPointer(rebasing: buffer.prefix(initializedCount)), as: UTF8.self)
    }
  }
}
