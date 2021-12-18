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

extension UnsafeBufferPointer where Element == UInt8 {

  /// Whether or not the buffer contains the given byte.
  ///
  /// This implementation compares chunks of 8 bytes at a time,
  /// using only 4 instructions per chunk of 8 bytes.
  ///
  @inlinable @inline(__always)  // mask must be constant-folded.
  internal func _fastContains(_ element: UInt8) -> Bool {
    let mask = UInt64(repeatingByte: element)
    return __fastContains(element: element, mask: mask)
  }

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
