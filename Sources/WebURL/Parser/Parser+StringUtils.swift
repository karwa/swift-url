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
// MARK: - URL Code Points
// --------------------------------------------


/// Detects non-URL code points in the given sequence. The sequence is assumed to contain valid UTF8 text.
///
/// - parameters:
///     - utf8: A sequence of valid UTF8-encoded text.
///     - allowPercentSign: If `true`, the ASCII percent sign (U+0025) is considered an allowed code-point.
/// - returns: `true` if the sequence contains code-points which are not URL code-points, otherwise `false`.
///
/// The URL code points are ASCII alphanumeric, U+0021 (!), U+0024 ($), U+0026 (&),
/// U+0027 ('), U+0028 LEFT PARENTHESIS, U+0029 RIGHT PARENTHESIS, U+002A (*),
/// U+002B (+), U+002C (,), U+002D (-), U+002E (.), U+002F (/), U+003A (:), U+003B (;),
/// U+003D (=), U+003F (?), U+0040 (@), U+005F (_), U+007E (~),
/// and code points in the range U+00A0 to U+10FFFD, inclusive, excluding surrogates and noncharacters.
///
/// https://url.spec.whatwg.org/#url-code-points
///
@inlinable @inline(never)
internal func hasNonURLCodePoints<UTF8Bytes>(
  utf8: UTF8Bytes, allowPercentSign: Bool = false
) -> Bool where UTF8Bytes: Sequence, UTF8Bytes.Element == UInt8 {

  // Rather than using UTF8.decode to parse the actual 21-bit unicode codepoint, we can detect
  // the handful of disallowed codepoints while they're still in UTF-8 form.
  //
  // (Note: "?" indicates a "don't care"/"match both" bit)
  //
  // - ASCII values need to be checked, but don't need any fancy decoding.
  // - (0x80 ..< 0xA0) are the patterns 0xC28? and 0xC29? when encoded, which is an easy range to detect
  //   by just ignoring the last 4 bits of the 2nd encoded codepoint.
  // - Surrogates (0xD800 ... 0xDFFF) run the range (0xD800 ... 0xDFFF) => (0xEDA080 ... 0xEDBFBF) when encoded,
  //   so we can match them with the bit-pattern 11101101_101?????_10??????.
  // - Non-characters have a relatively simple pattern when encoded:
  //     > A noncharacter is a code point that is in the range U+FDD0 to U+FDEF, inclusive,
  //       or U+FFFE, U+FFFF, U+(0x01 ... 0x10)FFFE, U+(0x01 ... 0x10)FFFF.
  //     https://infra.spec.whatwg.org/#noncharacter
  //
  // 1. 0xFDD? and 0xFDE?:
  //    - 0xFDD? => 0xEFB79? in UTF8 (11101111_10110111_1001????)
  //    - 0xFDE? => 0xEFB7A? in UTF8 (11101111_10110111_1010????)
  // 2. 0x??FFFE and 0x??FFFF:
  //    - 0xFFFE, 0xFFFF     => 0xEFBFB(E/F) in UTF8            (11101111_10111111_1011111?)
  //    - 0x??FFFE, 0x??FFFF => 0xF??FBFB(E/F) in UTF8 (11110???_10??1111_10111111_1011111?)
  //      (even though there are 2 "?" hex characters, we only have 5 "?" bits because the max codepoint is 10FFFF).

  var utf8 = utf8.makeIterator()
  while let byte1 = utf8.next() {
    switch (~byte1).leadingZeroBitCount {
    case 0:
      // ASCII.
      if byte1 == 0x25, allowPercentSign {
        continue
      }
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b01010000_00000000_00000000_00101101_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10111000_00000000_00000000_00000001_01111000_00000000_00000000_00000000
      if byte1 < 64 {
        guard lo & (1 &<< byte1) == 0 else { return true }
      } else {
        guard hi & (1 &<< (byte1 &- 64)) == 0 else { return true }
      }
    case 2:
      // 2-byte sequence.
      guard let byte2 = utf8.next() else {
        return true  // Invalid UTF8.
      }
      let encodedScalar = UInt32(byte1) << 8 | UInt32(byte2)
      // Reject 0x80-0x8F, 0x90-0x9F (non-characters)
      let masked = encodedScalar & 0b11111111_11110000
      if masked == 0b11000010_10000000 || masked == 0b11000010_10010000 {
        return true
      }
    case 3:
      // 3-byte sequence.
      guard let byte2 = utf8.next(), let byte3 = utf8.next() else {
        return true  // Invalid UTF8.
      }
      let encodedScalar = UInt32(byte1) << 16 | UInt32(byte2) << 8 | UInt32(byte3)
      // Reject 0xFDD0-0xFDEF (non-characters).
      let masked = encodedScalar & 0b11111111_11111111_11110000
      if masked == 0b11101111_10110111_10010000 || masked == 0b11101111_10110111_10100000 {
        return true
      }
      // Reject 0xFFFE, 0xFFFF (non-characters).
      if encodedScalar & 0b11111111_11111111_11111110 == 0b11101111_10111111_10111110 {
        return true
      }
      // Reject 0xD800-0xD8FF (surrogates).
      // These shouldn't appear in any valid UTF8 sequence anyway.
      if encodedScalar & 0b11111111_11100000_11000000 == 0b11101101_10100000_10000000 {
        return true
      }
    case 4:
      // 4-byte sequence.
      guard let byte2 = utf8.next(), let byte3 = utf8.next(), let byte4 = utf8.next() else {
        return true  // Invalid UTF8.
      }
      let encodedScalar = UInt32(byte1) << 24 | UInt32(byte2) << 16 | UInt32(byte3) << 8 | UInt32(byte4)
      // Reject 0x??FFFE, 0x??FFFF (non-characters).
      if encodedScalar & 0b11111000_11001111_11111111_11111110 == 0b11110000_10001111_10111111_10111110 {
        return true
      }
    default:
      return true  // Invalid UTF8.
    }
  }
  return false
}

/// Checks if `utf8`, which is a collection of UTF-8 code-units, contains any non-URL code-points
/// or invalid percent encoding (e.g. "%XY"). If it does, `callback` is informed with an appropriate `ValidationError`.
///
/// - Note: This method considers the percent sign ("%") to be a valid URL code-point.
/// - Note: This method is a no-op if `callback` is an instance of `IgnoreValidationErrors`.
///
@inlinable
internal func _validateURLCodePointsAndPercentEncoding<UTF8Bytes, Callback>(
  utf8: @autoclosure () -> UTF8Bytes, callback: inout Callback
) where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8, Callback: URLParserCallback {

  // The compiler has a tough time optimising this function away when we ignore validation errors.
  guard Callback.self != IgnoreValidationErrors.self else {
    return
  }
  let utf8 = utf8()
  if hasNonURLCodePoints(utf8: utf8, allowPercentSign: true) {
    callback.validationError(.invalidURLCodePoint)
  }
  var percentSignSearchIdx = utf8.startIndex
  while let percentSignIdx = utf8[percentSignSearchIdx...].fastFirstIndex(where: { ASCII($0) == .percentSign }) {
    percentSignSearchIdx = utf8.index(after: percentSignIdx)
    let nextTwo = utf8[percentSignIdx...].prefix(2)
    if nextTwo.count != 2 || !nextTwo.allSatisfy({ ASCII($0)?.isHexDigit ?? false }) {
      callback.validationError(.unescapedPercentSign)
    }
  }
}


// --------------------------------------------
// MARK: - Other Utilities
// --------------------------------------------


/// Returns `true` if `utf8` begins with two U+002F (/) codepoints.
/// Otherwise, `false`.
///
@inlinable
internal func indexAfterDoubleSolidusPrefix<UTF8Bytes>(
  utf8: UTF8Bytes
) -> UTF8Bytes.Index? where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
  var idx = utf8.startIndex
  guard idx < utf8.endIndex, utf8[idx] == ASCII.forwardSlash.codePoint else { return nil }
  utf8.formIndex(after: &idx)
  guard idx < utf8.endIndex, utf8[idx] == ASCII.forwardSlash.codePoint else { return nil }
  utf8.formIndex(after: &idx)
  return idx
}

@inlinable
internal func isForwardSlashOrBackSlash(_ codeUnit: UInt8) -> Bool {
  codeUnit == ASCII.forwardSlash.codePoint || codeUnit == ASCII.backslash.codePoint
}

@inlinable @inline(__always)
internal var _idnaPrefix: UInt32 {
  UInt32(
    bigEndian: UInt32(ASCII.X.codePoint) &<< 24 | UInt32(ASCII.N.codePoint) &<< 16
      | UInt32(ASCII.minus.codePoint) &<< 8 | UInt32(ASCII.minus.codePoint)
  )
}

/// Whether or not `utf8` begins with the ASCII string "xn--" (case-insensitive),
/// indicating that it is a domain label is encoded by IDNA.
///
@inlinable
internal func hasIDNAPrefix<UTF8Bytes>(
  utf8: UTF8Bytes
) -> Bool where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
  let contiguousResult = utf8.withContiguousStorageIfAvailable { utf8 -> Bool in
    guard let ptr = utf8.baseAddress, utf8.count >= 4 else { return false }
    var prefix = UnsafeRawPointer(ptr).loadUnaligned(as: UInt32.self)
    prefix &= (0b11011111_11011111_11111111_11111111 as UInt32).bigEndian  // Make first 2 chars uppercase
    return prefix == _idnaPrefix
  }
  if let contiguousResult = contiguousResult {
    return contiguousResult
  }
  return ("xn--" as StaticString).withUTF8Buffer { ASCII.Lowercased(utf8).starts(with: $0) }
}

/// Whether or not `utf8` is equal to the ASCII string "localhost" (case-insensitive).
///
@inlinable
internal func isLocalhost<UTF8Bytes>(
  utf8: UTF8Bytes
) -> Bool where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
  // This function is used by file URLs, which generally have an empty hostname.
  // It isn't worth doing anything fancy here.
  guard !utf8.isEmpty else { return false }
  return ("localhost" as StaticString).withUTF8Buffer { ASCII.Lowercased(utf8).elementsEqual($0) }
}

extension ASCII {

  /// Returns `true` if this character is a forbidden host code point, otherwise `false`.
  ///
  /// A forbidden host code point is U+0000 NULL, U+0009 TAB, U+000A LF, U+000D CR,
  /// U+0020 SPACE, U+0023 (#), U+002F (/), U+003A (:), U+003C (<), U+003E (>), U+003F (?),
  /// U+0040 (@), U+005B ([), U+005C (\), U+005D (]), U+005E (^), or U+007C (|).
  ///
  /// https://url.spec.whatwg.org/#host-miscellaneous
  ///
  @inlinable
  internal var isForbiddenHostCodePoint: Bool {
    //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
    let lo: UInt64 = 0b11010100_00000000_10000000_00001001_00000000_00000000_00100110_00000001
    let hi: UInt64 = 0b00010000_00000000_00000000_00000000_01111000_00000000_00000000_00000001
    if self.codePoint < 64 {
      return lo & (1 &<< self.codePoint) != 0
    } else {
      return hi & (1 &<< (self.codePoint &- 64)) != 0
    }
  }

  /// Returns `true` if this character is a forbidden host code point, otherwise `false`.
  ///
  /// A forbidden domain code point is a forbiden host code point, a C0 control, U+0025 (%),
  /// or U+007F DELETE.
  ///
  /// https://url.spec.whatwg.org/#host-miscellaneous
  ///
  @inlinable
  internal var isForbiddenDomainCodePoint: Bool {
    //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
    let lo: UInt64 = 0b11010100_00000000_10000000_00101001_11111111_11111111_11111111_11111111
    let hi: UInt64 = 0b10010000_00000000_00000000_00000000_01111000_00000000_00000000_00000001
    if self.codePoint < 64 {
      return lo & (1 &<< self.codePoint) != 0
    } else {
      return hi & (1 &<< (self.codePoint &- 64)) != 0
    }
  }
}
