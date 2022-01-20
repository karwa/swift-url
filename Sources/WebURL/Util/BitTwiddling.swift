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

extension UnsafeBoundsCheckedBufferPointer where Element == UInt8 {

  /// Whether or not the buffer contains the given byte.
  ///
  /// This implementation is able to search chunks of 8 bytes at a time, using only 5 instructions per chunk.
  ///
  /// > Important:
  /// > This function is **not** bounds-checked (since 8-byte chunks are loaded directly from the `baseAddress`,
  /// > rather than via the Collection interface), although of course it only reads data within the buffer's bounds.
  /// > The reason it lives on `UnsafeBoundsCheckedBufferPointer` is because unsigned indexes allow for
  /// > better performance and code-size.
  ///
  @inlinable @inline(__always)  // mask must be constant-folded.
  internal func uncheckedFastContains(_ element: UInt8) -> Bool {
    let mask = UInt64(repeatingByte: element)
    return _uncheckedFastContains(element: element, mask: mask)
  }

  @inlinable
  internal func _uncheckedFastContains(element: UInt8, mask: UInt64) -> Bool {
    var i = startIndex
    while distance(from: i, to: endIndex) >= 8 {
      // Load 8 bytes from the source.
      var eightBytes = UnsafeRawPointer(
        self.baseAddress.unsafelyUnwrapped.advanced(by: Int(bitPattern: i))
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

extension UnsafeBoundsCheckedBufferPointer where Element == UInt8 {

  /// Whether or not the buffer contains an ASCII horizontal tab (0x09), line feed (0x0A),
  /// or carriage return (0x0D) code-unit.
  ///
  /// This implementation is able to search chunks of 8 bytes at a time, using only 5 instructions per chunk.
  ///
  /// > Important:
  /// > This function is **not** bounds-checked (since 8-byte chunks are loaded directly from the `baseAddress`,
  /// > rather than via the Collection interface), although of course it only reads data within the buffer's bounds.
  /// > The reason it lives on `UnsafeBoundsCheckedBufferPointer` is because unsigned indexes allow for
  /// > better performance and code-size.
  ///
  @inlinable
  internal func uncheckedFastContainsTabOrCROrLF() -> Bool {
    var i = startIndex
    while distance(from: i, to: endIndex) >= 8 {
      // Load 8 bytes from the source.
      let eightBytes = UnsafeRawPointer(
        self.baseAddress.unsafelyUnwrapped.advanced(by: Int(bitPattern: i))
      ).loadUnaligned(as: UInt64.self)

      // Check for line feeds first; we're more likely to find one than a tab or carriage return.
      var bytesForLF = eightBytes
      bytesForLF ^= UInt64(repeatingByte: ASCII.lineFeed.codePoint)
      var found = (bytesForLF &- 0x0101_0101_0101_0101) & (~bytesForLF & 0x8080_8080_8080_8080)
      if found != 0 { return true }

      // Check for tabs (0x09, 0b0000_1001) and carriage returns (0x0D, 0b0000_1101).
      // These differ by one bit, so mask it out (turns carriage returns in to tabs), then look for tabs.
      var bytesForTCR = eightBytes
      bytesForTCR &= UInt64(repeatingByte: 0b1111_1011)
      bytesForTCR ^= UInt64(repeatingByte: 0b0000_1001)
      found = (bytesForTCR &- 0x0101_0101_0101_0101) & (~bytesForTCR & 0x8080_8080_8080_8080)
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
