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

import func Foundation.memcmp
import struct WebURL.IPv4Address
import struct WebURL.IPv6Address

// --------------------------------------------
// MARK: - FastElementsEqual
// --------------------------------------------
// Optimizes to a memcmp when both sequences are contiguous. The pure-Swift version is big and slow.
// https://bugs.swift.org/browse/SR-15712


extension Sequence where Element == UInt8 {

  @inline(__always)  // wCSIA.
  internal func fastElementsEqual<Other>(_ other: Other) -> Bool where Other: Sequence, Other.Element == UInt8 {
    let contiguousResult = withContiguousStorageIfAvailable { selfBuffer in
      other.withContiguousStorageIfAvailable { otherBuffer -> Bool in
        guard selfBuffer.count == otherBuffer.count else {
          return false
        }
        guard selfBuffer.count > 0 else {
          return true
        }
        return memcmp(selfBuffer.baseAddress!, otherBuffer.baseAddress!, selfBuffer.count) == 0
      }
    }
    switch contiguousResult {
    case .some(.some(let result)):
      return result
    default:
      return elementsEqual(other)
    }
  }
}


// --------------------------------------------
// MARK: - IPAddress FastEquals
// --------------------------------------------
// Uses memcmp to compare IP addresses. The pure-Swift version is big and slow.
// Technically not a collection algorithm, but in the same spirit as fastElementsEqual above.
// https://bugs.swift.org/browse/SR-15712


internal func fastEquals(_ lhs: IPv4Address, _ rhs: IPv4Address) -> Bool {
  withUnsafeBytes(of: lhs.octets) { lhsBytes in
    withUnsafeBytes(of: rhs.octets) { rhsBytes in
      memcmp(lhsBytes.baseAddress!, rhsBytes.baseAddress!, 4) == 0
    }
  }
}

internal func fastEquals(_ lhs: IPv6Address, _ rhs: IPv6Address) -> Bool {
  withUnsafeBytes(of: lhs.octets) { lhsBytes in
    withUnsafeBytes(of: rhs.octets) { rhsBytes in
      memcmp(lhsBytes.baseAddress!, rhsBytes.baseAddress!, 16) == 0
    }
  }
}


// --------------------------------------------
// MARK: - FastContains
// --------------------------------------------
// From WebURL/Util/Pointers.swift, WebURL/Util/BitTwiddling.swift


extension Sequence where Element == UInt8 {

  /// Whether or not this sequence contains the given byte.
  ///
  /// If the sequence has contiguous storage, this optimizes to a fast, chunked search.
  ///
  @inlinable @inline(__always)
  internal func fastContains(_ element: Element) -> Bool {
    // Hoist mask calculation out of wCSIA to ensure it is constant-folded, even if wCSIA isn't inlined.
    let mask = UInt64(repeatingByte: element)
    return withContiguousStorageIfAvailable { $0.__fastContains(element: element, mask: mask) } ?? contains(element)
  }
}

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

extension UInt64 {

  /// Creates an 8-byte integer, each of which is equal to the given byte.
  ///
  @inlinable @inline(__always)
  internal init(repeatingByte byte: UInt8) {
    self = 0
    withUnsafeMutableBytes(of: &self) {
      $0[0] = byte
      $0[1] = byte
      $0[2] = byte
      $0[3] = byte
      $0[4] = byte
      $0[5] = byte
      $0[6] = byte
      $0[7] = byte
    }
  }
}

extension UnsafeBufferPointer where Element == UInt8 {

  /// Whether or not the buffer contains the given byte.
  ///
  /// This implementation compares chunks of 8 bytes at a time,
  /// using only 4 instructions per chunk of 8 bytes.
  ///
  @inlinable
  internal func __fastContains(element: UInt8, mask: UInt64) -> Bool {
    var i = startIndex
    while distance(from: i, to: endIndex) >= 8 {
      // Load 8 bytes from the source.
      var eightBytes = UnsafeRawPointer(
        self.baseAddress.unsafelyUnwrapped.advanced(by: i)
      ).loadUnaligned(as: UInt64.self)
      // XOR every byte with the element we're searching for.
      // If there are any matches, we'll get a zero byte in that position.
      eightBytes ^= mask
      // Use bit-twiddling to detect if any bytes were zero.
      // https://graphics.stanford.edu/~seander/bithacks.html#ValueInWord
      let found = (eightBytes &- 0x0101_0101_0101_0101) & (~eightBytes & 0x8080_8080_8080_8080)
      if found != 0 { return true }
      i &+= 8
    }
    while i < endIndex {
      if self[i] == element { return true }
      i &+= 1
    }
    return false
  }
}
