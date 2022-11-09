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


extension ASCII {

  /// Whether this character is a non-URL code point.
  ///
  /// > The URL code points are ASCII alphanumeric, U+0021 (!), U+0024 ($), U+0026 (&),
  /// > U+0027 ('), U+0028 LEFT PARENTHESIS, U+0029 RIGHT PARENTHESIS, U+002A (\*),
  /// > U+002B (+), U+002C (,), U+002D (-), U+002E (.), U+002F (/), U+003A (:), U+003B (;),
  /// > U+003D (=), U+003F (?), U+0040 (@), U+005F (\_), U+007E (~),
  /// > and code points in the range U+00A0 to U+10FFFD, inclusive, excluding surrogates and noncharacters.
  /// >
  /// > https://url.spec.whatwg.org/#url-code-points
  ///
  @inlinable
  internal var isNonURLCodePoint: Bool {
    //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
    let lo: UInt64 = 0b01010000_00000000_00000000_00101101_11111111_11111111_11111111_11111111
    let hi: UInt64 = 0b10111000_00000000_00000000_00000001_01111000_00000000_00000000_00000000
    if self.codePoint < 64 {
      return lo & (1 &<< self.codePoint) != 0
    } else {
      return hi & (1 &<< (self.codePoint &- 64)) != 0
    }
  }
}

/// Whether the given UTF-8 text contains any non-URL code points.
///
/// Note that while this function recognizes encoded non-URL code points,
/// it does not perform full UTF-8 validation, nor does it check overlong encodings.
///
/// > The URL code points are ASCII alphanumeric, U+0021 (!), U+0024 ($), U+0026 (&),
/// > U+0027 ('), U+0028 LEFT PARENTHESIS, U+0029 RIGHT PARENTHESIS, U+002A (\*),
/// > U+002B (+), U+002C (,), U+002D (-), U+002E (.), U+002F (/), U+003A (:), U+003B (;),
/// > U+003D (=), U+003F (?), U+0040 (@), U+005F (\_), U+007E (~),
/// > and code points in the range U+00A0 to U+10FFFD, inclusive, excluding surrogates and noncharacters.
/// >
/// > https://url.spec.whatwg.org/#url-code-points
///
/// - parameters:
///     - utf8:             A sequence of bytes containing UTF-8 text.
///     - allowPercentSign: Whether the ASCII percent sign (U+0025) should be allowed.
///                         Callers who set this flag should later ensure that the percent sign
///                         is only being used for percent-encoding.
///
@inlinable
internal func hasNonURLCodePoints<UTF8Bytes>(
  utf8: UTF8Bytes, allowPercentSign: Bool = false
) -> Bool where UTF8Bytes: Sequence, UTF8Bytes.Element == UInt8 {

  // We can detect surrogates and noncharacters fairly easily in raw UTF-8,
  // without needing to actually decode the code-points to a numeric value.
  //
  // - ASCII values are straightforward.
  //
  // - Codepoints U+0080..<U+00A0 encode as '0xC28?' and '0xC29?'.
  //
  // - Surrogates U+D800...U+DFFF encode as '0xEDA080'...'0xEDBFBF'.
  //   We can match them with the bit-pattern 11101101_101?????_10??????.
  //
  // - Non-characters:
  //   > A noncharacter is a code point that is in the range U+FDD0 to U+FDEF, inclusive,
  //   > or U+FFFE, U+FFFF, U+(0x01 ... 0x10)FFFE, U+(0x01 ... 0x10)FFFF.
  //   https://infra.spec.whatwg.org/#noncharacter
  //
  //   1. U+FDD? and U+FDE?:
  //      - U+FDD? encodes as '0xEFB79?' (11101111_10110111_1001????)
  //      - U+FDE? encodes as '0xEFB7A?' (11101111_10110111_1010????)
  //   2. U+??FFFE and 0x??FFFF:
  //      - U+FFFE, U+FFFF     encodes as '0xE__FBFB(E/F)' (1110_________1111_10111111_1011111?)
  //      - U+??FFFE, U+??FFFF encodes as '0xF??FBFB(E/F)' (11110???_10??1111_10111111_1011111?)
  //        (even though there are 2 "?" hex characters, we only have 5 "?" bits because the max codepoint is 10FFFF).

  var utf8 = utf8.makeIterator()
  while let byte1 = utf8.next() {

    if let asciiByte = ASCII(byte1) {
      if asciiByte.isNonURLCodePoint {
        if asciiByte == .percentSign, allowPercentSign {
          continue
        }
        return true
      }
    } else {
      switch (~byte1).leadingZeroBitCount {
      case 2:
        guard let byte2 = utf8.next() else { return true }
        let encodedScalar = UInt32(byte1) << 8 | UInt32(byte2)

        // Reject U+0080-U+008F, U+0090-U+009F (C1 controls)
        let masked = encodedScalar & 0xFFF0
        if masked == 0xC280 || masked == 0xC290 {
          return true
        }

      case 3:
        guard let byte2 = utf8.next(), let byte3 = utf8.next() else { return true }
        let encodedScalar = UInt32(byte1) << 16 | UInt32(byte2) << 8 | UInt32(byte3)

        // Reject U+FDD0-U+FDEF (non-characters).
        let masked = encodedScalar & 0xFFFFF0
        if masked == 0xEFB790 || masked == 0xEFB7A0 {
          return true
        }
        // Reject U+FFFE, U+FFFF (non-characters).
        if encodedScalar & 0xFFFFFE == 0xEFBFBE {
          return true
        }
        // Reject U+D800-U+DFFF (surrogates).
        if encodedScalar & 0xFF_E0C0 == 0xED_A080 {
          return true
        }

      case 4:
        guard let byte2 = utf8.next(), let byte3 = utf8.next(), let byte4 = utf8.next() else { return true }
        let encodedScalar = UInt32(byte1) << 24 | UInt32(byte2) << 16 | UInt32(byte3) << 8 | UInt32(byte4)

        // Reject U+??FFFE, U+??FFFF (non-characters).
        if encodedScalar & 0xF8CF_FFFE == 0xF08F_BFBE {
          return true
        }

      default:
        return true
      }
    }
  }

  return false
}

/// Checks whether the given UTF-8 text contains non-URL code points or uses the percent-sign
/// for things other than percent encoding. Infractions are reported to the given `URLParserCallback`.
///
@inlinable @inline(never)
internal func _validateURLCodePointsAndPercentEncoding<UTF8Bytes, Callback>(
  utf8: UTF8Bytes, callback: inout Callback
) where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8, Callback: URLParserCallback {

  if hasNonURLCodePoints(utf8: utf8, allowPercentSign: true) {
    callback.validationError(.invalidURLCodePoint)
  }

  var cursor = utf8.startIndex
  while let percentSignIdx = utf8[cursor...].fastFirstIndex(where: { ASCII($0) == .percentSign }) {
    cursor = utf8.index(after: percentSignIdx)
    guard cursor < utf8.endIndex, ASCII(utf8[cursor])?.isHexDigit == true else {
      callback.validationError(.unescapedPercentSign)
      break
    }
    utf8.formIndex(after: &cursor)
    guard cursor < utf8.endIndex, ASCII(utf8[cursor])?.isHexDigit == true else {
      callback.validationError(.unescapedPercentSign)
      break
    }
    utf8.formIndex(after: &cursor)
  }
}


// --------------------------------------------
// MARK: - Host and Domain Code Points
// --------------------------------------------


extension ASCII {

  /// Whether this character is a forbidden host code point.
  ///
  /// > A forbidden host code point is U+0000 NULL, U+0009 TAB, U+000A LF, U+000D CR,
  /// > U+0020 SPACE, U+0023 (#), U+002F (/), U+003A (:), U+003C (<), U+003E (>), U+003F (?),
  /// > U+0040 (@), U+005B ([), U+005C (\), U+005D (]), U+005E (^), or U+007C (|).
  /// >
  /// > https://url.spec.whatwg.org/#host-miscellaneous
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

  /// Whether this character is a forbidden domain code point.
  ///
  /// > A forbidden domain code point is a forbiden host code point, a C0 control, U+0025 (%),
  /// > or U+007F DELETE.
  /// >
  /// > https://url.spec.whatwg.org/#host-miscellaneous
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


// --------------------------------------------
// MARK: - Other Utilities
// --------------------------------------------


/// If `utf8` begins with two U+002F (`/`) code points, returns the index after them.
/// Otherwise, returns `nil`.
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

/// Whether `utf8` begins with the ASCII string "xn--" (case-insensitive).
///
@inlinable
internal func hasIDNAPrefix<UTF8Bytes>(
  utf8: UTF8Bytes
) -> Bool where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

  var prefix: UInt32 = 0
  let copied = withUnsafeMutableBytes(of: &prefix) { destination -> Bool in
    // swift-format-ignore
    utf8.withContiguousStorageIfAvailable { source -> Bool in
      guard let sourceAddress = source.baseAddress, source.count >= 4 else { return false }
      destination.baseAddress!.copyMemory(from: .init(sourceAddress), byteCount: 4)
      return true
    } ?? {
      var i = utf8.startIndex
      for offset in 0..<4 {
        guard i < utf8.endIndex else { return false }
        destination[offset] = utf8[i]
        utf8.formIndex(after: &i)
      }
      return true
    }()
  }
  guard copied else { return false }

  // Uppercase the first 2 characters.
  prefix &= (0b11011111_11011111_11111111_11111111 as UInt32).bigEndian

  // swift-format-ignore
  let idnaPrefix = UInt32(
    bigEndian: UInt32(ASCII.X.codePoint) &<< 24    | UInt32(ASCII.N.codePoint) &<< 16
             | UInt32(ASCII.minus.codePoint) &<< 8 | UInt32(ASCII.minus.codePoint)
  )
  return prefix == idnaPrefix
}

/// Whether `utf8` is equal to the ASCII string "localhost" (case-insensitive).
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
