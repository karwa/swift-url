
// - URL-related String utilities.

/// Detects non-URL code points in the given sequence. The sequence is assumed to contain valid UTF8 text.
///
/// - parameters:
///     - input:            A sequence of valid UTF8-encoded text.
///     - allowPercentSign: If `true`, the ASCII percent sign (U+0025) is considered an allowed code-point. 
/// - returns:      `true` if the sequence contains code-points which are not URL code-points, otherwise `false`.
///
/// From the [spec](https://url.spec.whatwg.org/#url-code-points):
/// 
/// The URL code points are ASCII alphanumeric, U+0021 (!), U+0024 ($), U+0026 (&),
/// U+0027 ('), U+0028 LEFT PARENTHESIS, U+0029 RIGHT PARENTHESIS, U+002A (*), 
/// U+002B (+), U+002C (,), U+002D (-), U+002E (.), U+002F (/), U+003A (:), U+003B (;),
/// U+003D (=), U+003F (?), U+0040 (@), U+005F (_), U+007E (~), 
/// and code points in the range U+00A0 to U+10FFFD, inclusive, excluding surrogates and noncharacters.
///
func hasNonURLCodePoints<S>(_ input: S, allowPercentSign: Bool = false) -> Bool where S: Sequence, S.Element == UInt8 {

    // Rather than using UTF8.decode to parse the actual scalar value, we can detect
    // the handful of disallowed code-points in their raw, encoded form.
    //
    // - ASCII values need to be checked, but don't need any fancy decoding.
    // - Surrogates (0xD800 ... 0xDFFF) are not valid in UTF8 anyway.
    //      If we wanted to, we could detect the bit-pattern 11101011_101?????_10??????.
    //
    // Leaving only code-points in the range 0x80 ..< 0xA0 and non-characters to detect.
    // - (0x80 ..< 0xA0) are the patterns 0xC28? and 0xC29? when encoded, so just 1.5 bytes to match.
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
    //      (even though there are 2 hex characters, the prefix is only 5 bits because the max code-point is 10FFFF).

    var input = input.makeIterator()
    while let byte1 = input.next() {
        switch (~byte1).leadingZeroBitCount { // a.k.a leadingNonZeroBitCount.
        case 0:
            // ASCII.
            if byte1 == 0x25, allowPercentSign { 
                continue
            }
            let low:  UInt64 = 0b1010_1111_1111_1111_1111_1111_1101_0010____0000_0000_0000_0000_0000_0000_0000_0000
            let high: UInt64 = 0b0100_0111_1111_1111_1111_1111_1111_1110____1000_0111_1111_1111_1111_1111_1111_1111
            let (lowHigh, index) = byte1.quotientAndRemainder(dividingBy: 64)
            if lowHigh == 0 {
                guard (low &>> index) & 0x01 == 1 else { return true }
            } else {
                guard (high &>> index) & 0x01 == 1 else { return true }
            }
        case 1:
            // Unexpected continuation byte. Invalid UTF8.
            return true 
        case 2:
            // 2-byte sequence.
            guard let byte2 = input.next() else { 
                return true // Invalid UTF8.
            }
            let encodedScalar = UInt32(byte1) << 8 | UInt32(byte2)
            // Reject 0x80-0x8F (encoded: 0xC28?), 0x90-0x9F (encoded: 0xC29?)
            let masked = encodedScalar & 0b11111111_11110000
            if masked == 0b11000010_10000000 || masked == 0b11000010_10010000 {
                return true
            }
        case 3:
            // 3-byte sequence.
            guard let byte2 = input.next(), let byte3 = input.next() else { 
                return true // Invalid UTF8.
            }
            let encodedScalar = UInt32(byte1) << 16 | UInt32(byte2) << 8 | UInt32(byte3)
            // Reject 0xFDD0-0xFDEF.
            let masked = encodedScalar & 0b11111111_11111111_11110000 
            if masked == 0b11101111_10110111_10010000 || masked == 0b11101111_10110111_10100000 {
                return true
            }
            // Reject 0xFFFE, 0xFFFF.
            if encodedScalar & 0b11111111_11111111_11111110 == 0b11101111_10111111_10111110 {
                return true
            }
        case 4:
            // 4-byte sequence.
            guard let byte2 = input.next(), let byte3 = input.next(), let byte4 = input.next() else { 
                return true // Invalid UTF8.
            }
            let encodedScalar = UInt32(byte1) << 24 | UInt32(byte2) << 16 | UInt32(byte3) << 8 | UInt32(byte4)
            // Reject 0x??FFFE, 0x??FFFF.
            if encodedScalar & 0b11111000_11001111_11111111_11111110 == 0b11110000_10001111_10111111_10111110 {
                return true
            }            
        default:
            return true // Invalid UTF8.
        }
    }
    return false
}

extension ASCII {

    /// Returns `true` if this character is a forbidden host code point, otherwise `false`.
    ///
    /// From the [spec](https://url.spec.whatwg.org/#host-miscellaneous):
    ///
    /// A forbidden host code point is U+0000 NULL, U+0009 TAB, U+000A LF, U+000D CR,
    /// U+0020 SPACE, U+0023 (#), U+0025 (%), U+002F (/), U+003A (:), U+003F (?),
    /// U+0040 (@), U+005B ([), U+005C (\), or U+005D (]).
    ///
    var isForbiddenHostCodePoint: Bool {
        let low:  UInt64 = 0b1000_0100_0000_0000_1000_0000_0010_1001____0000_0000_0000_0000_0010_0110_0000_0001
        let high: UInt64 = 0b0000_0000_0000_0000_0000_0000_0000_0000____0011_1000_0000_0000_0000_0000_0000_0001
        let (lowHigh, index) = codePoint.quotientAndRemainder(dividingBy: 64)
        if lowHigh == 0 {
            return (low &>> index) & 0x01 == 1
        } else {
            return (high &>> index) & 0x01 == 1
        }
    }
}