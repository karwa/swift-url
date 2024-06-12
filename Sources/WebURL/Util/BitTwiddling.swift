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

extension UInt64 {

  /// Creates an 8-byte integer, each of which is equal to the given byte.
  ///
  @inlinable @inline(__always)
  internal init(repeatingByte byte: UInt8) {
    self = 0x01010101_01010101 &* UInt64(byte)
  }
}

extension UnsafeBoundsCheckedBufferPointer where Element == UInt8 {

  /// Whether or not the buffer contains the given byte.
  ///
  @inlinable
  internal func fastContains(_ element: UInt8) -> Bool {

    var i = startIndex

    // - UnsafeBoundsCheckedBufferPointer does not enforce that its startIndex is in-bounds
    //   by construction; it only checks indexes which are actually read from.
    //   We need to check it here since we'll be reading using 'loadUnaligned'.
    //
    // - Since our index type is UInt, 'i <= endIndex' and 'endIndex <= Int.max' SHOULD be enough
    //   for the compiler to know that (i + 8) cannot overflow. Unfortunately it doesn't,
    //   so the precondition is only for the benefit of humans. https://github.com/apple/swift/issues/71919
    precondition(i <= endIndex && endIndex <= Int.max)

    while i &+ 8 <= endIndex {
      // Load 8 bytes from the source.
      var eightBytes = self.loadUnaligned_unchecked(fromByteOffset: i, as: UInt64.self)
      // XOR every byte with the element we're searching for.
      // If there are any matches, we'll get a zero byte in that position.
      eightBytes ^= UInt64(repeatingByte: element)
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

extension UnsafeBoundsCheckedBufferPointer where Element == UInt8 {

  /// Whether or not the buffer contains an ASCII horizontal tab (0x09), line feed (0x0A),
  /// or carriage return (0x0D) code-unit.
  ///
  @inlinable
  internal func fastContainsTabOrCROrLF() -> Bool {

    var i = startIndex

    // - UnsafeBoundsCheckedBufferPointer does not enforce that its startIndex is in-bounds
    //   by construction; it only checks indexes which are actually read from.
    //   We need to check it here since we'll be reading using 'loadUnaligned'.
    //
    // - Since our index type is UInt, 'i <= endIndex' and 'endIndex <= Int.max' SHOULD be enough
    //   for the compiler to know that (i + 8) cannot overflow. Unfortunately it doesn't,
    //   so the precondition is only for the benefit of humans. https://github.com/apple/swift/issues/71919
    precondition(i <= endIndex && endIndex <= Int.max)

    while i &+ 8 <= endIndex {
      // Load 8 bytes from the source.
      var eightBytes = self.loadUnaligned_unchecked(fromByteOffset: i, as: UInt64.self)

      // Check for line feeds first; we're more likely to find one than a tab or carriage return.
      var bytesForLF = eightBytes
      bytesForLF ^= UInt64(repeatingByte: ASCII.lineFeed.codePoint)
      var found = (bytesForLF &- 0x0101_0101_0101_0101) & (~bytesForLF & 0x8080_8080_8080_8080)
      if found != 0 { return true }

      // Check for tabs (0x09, 0b0000_1001) and carriage returns (0x0D, 0b0000_1101).
      // These differ by one bit, so mask it out (turns carriage returns in to tabs), then look for tabs.
      eightBytes &= UInt64(repeatingByte: 0b1111_1011)
      eightBytes ^= UInt64(repeatingByte: 0b0000_1001)
      found = (eightBytes &- 0x0101_0101_0101_0101) & (~eightBytes & 0x8080_8080_8080_8080)
      if found != 0 { return true }

      i &+= 8
    }
    while i < endIndex {
      let byte = self[i]
      if byte == ASCII.lineFeed.codePoint || (byte & 0b1111_1011) == 0b0000_1001 { return true }
      i &+= 1
    }
    return false
  }
}
