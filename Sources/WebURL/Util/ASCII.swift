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

/// An ASCII character.
///
@usableFromInline
internal struct ASCII {

  /// The Unicode codepoint of this character (also the value of this character's UTF8 code-unit).
  /// This value is validated at construction to be in the range `0..<128`.
  ///
  @usableFromInline
  internal let codePoint: UInt8
}

extension ASCII {

  @inlinable @inline(__always)
  internal init(_unchecked v: UInt8) {
    assert(v & 0x7F == v, "Not an ASCII code point")
    self.codePoint = v
  }

  @inlinable @inline(__always)
  internal init?(_ v: UInt8) {
    guard v & 0x7F == v else { return nil }
    self.init(_unchecked: v)
  }

  @inlinable @inline(__always)
  internal init?(flatMap v: UInt8?) {
    guard let byte = v, byte & 0x7F == byte else { return nil }
    self.init(_unchecked: byte)
  }
}

// Standard protocols.

extension ASCII: Comparable, Equatable, CustomStringConvertible {

  @inlinable @inline(__always)
  internal static func < (lhs: ASCII, rhs: ASCII) -> Bool {
    lhs.codePoint < rhs.codePoint
  }

  @inlinable @inline(__always)
  internal static func == (lhs: ASCII, rhs: ASCII) -> Bool {
    lhs.codePoint == rhs.codePoint
  }

  @inlinable
  internal var description: String {
    String(decoding: CollectionOfOne(codePoint), as: UTF8.self)
  }
}


// --------------------------------------------
// MARK: - Character table
// --------------------------------------------


// swift-format-ignore
extension ASCII {

    // C0 Control Characters.
    @inlinable static var null                  : ASCII { ASCII(_unchecked: 0x00) }
    @inlinable static var startOfHeading        : ASCII { ASCII(_unchecked: 0x01) }
    @inlinable static var startOfText           : ASCII { ASCII(_unchecked: 0x02) }
    @inlinable static var endOfText             : ASCII { ASCII(_unchecked: 0x03) }
    @inlinable static var endOfTransmission     : ASCII { ASCII(_unchecked: 0x04) }
    @inlinable static var enquiry               : ASCII { ASCII(_unchecked: 0x05) }
    @inlinable static var acknowledge           : ASCII { ASCII(_unchecked: 0x06) }
    @inlinable static var bell                  : ASCII { ASCII(_unchecked: 0x07) }
    @inlinable static var backspace             : ASCII { ASCII(_unchecked: 0x08) }
    @inlinable static var horizontalTab         : ASCII { ASCII(_unchecked: 0x09) }
    @inlinable static var lineFeed              : ASCII { ASCII(_unchecked: 0x0A) }
    @inlinable static var verticalTab           : ASCII { ASCII(_unchecked: 0x0B) }
    @inlinable static var formFeed              : ASCII { ASCII(_unchecked: 0x0C) }
    @inlinable static var carriageReturn        : ASCII { ASCII(_unchecked: 0x0D) }
    @inlinable static var shiftOut              : ASCII { ASCII(_unchecked: 0x0E) }
    @inlinable static var shiftIn               : ASCII { ASCII(_unchecked: 0x0F) }
    @inlinable static var dataLinkEscape        : ASCII { ASCII(_unchecked: 0x10) }
    @inlinable static var deviceControl1        : ASCII { ASCII(_unchecked: 0x11) }
    @inlinable static var deviceControl2        : ASCII { ASCII(_unchecked: 0x12) }
    @inlinable static var deviceControl3        : ASCII { ASCII(_unchecked: 0x13) }
    @inlinable static var deviceControl4        : ASCII { ASCII(_unchecked: 0x14) }
    @inlinable static var negativeAcknowledge   : ASCII { ASCII(_unchecked: 0x15) }
    @inlinable static var synchronousIdle       : ASCII { ASCII(_unchecked: 0x16) }
    @inlinable static var endOfTransmissionBlock: ASCII { ASCII(_unchecked: 0x17) }
    @inlinable static var cancel                : ASCII { ASCII(_unchecked: 0x18) }
    @inlinable static var endOfMedium           : ASCII { ASCII(_unchecked: 0x19) }
    @inlinable static var substitute            : ASCII { ASCII(_unchecked: 0x1A) }
    @inlinable static var escape                : ASCII { ASCII(_unchecked: 0x1B) }
    @inlinable static var fileSeparator         : ASCII { ASCII(_unchecked: 0x1C) }
    @inlinable static var groupSeparator        : ASCII { ASCII(_unchecked: 0x1D) }
    @inlinable static var recordSeparator       : ASCII { ASCII(_unchecked: 0x1E) }
    @inlinable static var unitSeparator         : ASCII { ASCII(_unchecked: 0x1F) }
    // Special Characters.
    @inlinable static var space              : ASCII { ASCII(_unchecked: 0x20) }
    @inlinable static var exclamationMark    : ASCII { ASCII(_unchecked: 0x21) }
    @inlinable static var doubleQuotationMark: ASCII { ASCII(_unchecked: 0x22) }
    @inlinable static var numberSign         : ASCII { ASCII(_unchecked: 0x23) }
    @inlinable static var dollarSign         : ASCII { ASCII(_unchecked: 0x24) }
    @inlinable static var percentSign        : ASCII { ASCII(_unchecked: 0x25) }
    @inlinable static var ampersand          : ASCII { ASCII(_unchecked: 0x26) }
    @inlinable static var apostrophe         : ASCII { ASCII(_unchecked: 0x27) }
    @inlinable static var leftParenthesis    : ASCII { ASCII(_unchecked: 0x28) }
    @inlinable static var rightParenthesis   : ASCII { ASCII(_unchecked: 0x29) }
    @inlinable static var asterisk           : ASCII { ASCII(_unchecked: 0x2A) }
    @inlinable static var plus               : ASCII { ASCII(_unchecked: 0x2B) }
    @inlinable static var comma              : ASCII { ASCII(_unchecked: 0x2C) }
    @inlinable static var minus              : ASCII { ASCII(_unchecked: 0x2D) }
    @inlinable static var period             : ASCII { ASCII(_unchecked: 0x2E) }
    @inlinable static var forwardSlash       : ASCII { ASCII(_unchecked: 0x2F) }
    // Numbers.
    @inlinable static var n0: ASCII { ASCII(_unchecked: 0x30) }
    @inlinable static var n1: ASCII { ASCII(_unchecked: 0x31) }
    @inlinable static var n2: ASCII { ASCII(_unchecked: 0x32) }
    @inlinable static var n3: ASCII { ASCII(_unchecked: 0x33) }
    @inlinable static var n4: ASCII { ASCII(_unchecked: 0x34) }
    @inlinable static var n5: ASCII { ASCII(_unchecked: 0x35) }
    @inlinable static var n6: ASCII { ASCII(_unchecked: 0x36) }
    @inlinable static var n7: ASCII { ASCII(_unchecked: 0x37) }
    @inlinable static var n8: ASCII { ASCII(_unchecked: 0x38) }
    @inlinable static var n9: ASCII { ASCII(_unchecked: 0x39) }
    // Some punctuation.
    @inlinable static var colon          : ASCII { ASCII(_unchecked: 0x3A) }
    @inlinable static var semicolon      : ASCII { ASCII(_unchecked: 0x3B) }
    @inlinable static var lessThanSign   : ASCII { ASCII(_unchecked: 0x3C) }
    @inlinable static var equalSign      : ASCII { ASCII(_unchecked: 0x3D) }
    @inlinable static var greaterThanSign: ASCII { ASCII(_unchecked: 0x3E) }
    @inlinable static var questionMark   : ASCII { ASCII(_unchecked: 0x3F) }
    @inlinable static var commercialAt   : ASCII { ASCII(_unchecked: 0x40) }
    // Upper-case letters.
    @inlinable static var A: ASCII { ASCII(_unchecked: 0x41) }
    @inlinable static var B: ASCII { ASCII(_unchecked: 0x42) }
    @inlinable static var C: ASCII { ASCII(_unchecked: 0x43) }
    @inlinable static var D: ASCII { ASCII(_unchecked: 0x44) }
    @inlinable static var E: ASCII { ASCII(_unchecked: 0x45) }
    @inlinable static var F: ASCII { ASCII(_unchecked: 0x46) }
    @inlinable static var G: ASCII { ASCII(_unchecked: 0x47) }
    @inlinable static var H: ASCII { ASCII(_unchecked: 0x48) }
    @inlinable static var I: ASCII { ASCII(_unchecked: 0x49) }
    @inlinable static var J: ASCII { ASCII(_unchecked: 0x4A) }
    @inlinable static var K: ASCII { ASCII(_unchecked: 0x4B) }
    @inlinable static var L: ASCII { ASCII(_unchecked: 0x4C) }
    @inlinable static var M: ASCII { ASCII(_unchecked: 0x4D) }
    @inlinable static var N: ASCII { ASCII(_unchecked: 0x4E) }
    @inlinable static var O: ASCII { ASCII(_unchecked: 0x4F) }
    @inlinable static var P: ASCII { ASCII(_unchecked: 0x50) }
    @inlinable static var Q: ASCII { ASCII(_unchecked: 0x51) }
    @inlinable static var R: ASCII { ASCII(_unchecked: 0x52) }
    @inlinable static var S: ASCII { ASCII(_unchecked: 0x53) }
    @inlinable static var T: ASCII { ASCII(_unchecked: 0x54) }
    @inlinable static var U: ASCII { ASCII(_unchecked: 0x55) }
    @inlinable static var V: ASCII { ASCII(_unchecked: 0x56) }
    @inlinable static var W: ASCII { ASCII(_unchecked: 0x57) }
    @inlinable static var X: ASCII { ASCII(_unchecked: 0x58) }
    @inlinable static var Y: ASCII { ASCII(_unchecked: 0x59) }
    @inlinable static var Z: ASCII { ASCII(_unchecked: 0x5A) }
    // More special characters.
    @inlinable static var leftSquareBracket : ASCII { ASCII(_unchecked: 0x5B) }
    @inlinable static var backslash         : ASCII { ASCII(_unchecked: 0x5C) }
    @inlinable static var rightSquareBracket: ASCII { ASCII(_unchecked: 0x5D) }
    @inlinable static var circumflexAccent  : ASCII { ASCII(_unchecked: 0x5E) }
    @inlinable static var underscore        : ASCII { ASCII(_unchecked: 0x5F) }
    @inlinable static var backtick          : ASCII { ASCII(_unchecked: 0x60) }
    // Lower-case letters.
    @inlinable static var a: ASCII { ASCII(_unchecked: 0x61) }
    @inlinable static var b: ASCII { ASCII(_unchecked: 0x62) }
    @inlinable static var c: ASCII { ASCII(_unchecked: 0x63) }
    @inlinable static var d: ASCII { ASCII(_unchecked: 0x64) }
    @inlinable static var e: ASCII { ASCII(_unchecked: 0x65) }
    @inlinable static var f: ASCII { ASCII(_unchecked: 0x66) }
    @inlinable static var g: ASCII { ASCII(_unchecked: 0x67) }
    @inlinable static var h: ASCII { ASCII(_unchecked: 0x68) }
    @inlinable static var i: ASCII { ASCII(_unchecked: 0x69) }
    @inlinable static var j: ASCII { ASCII(_unchecked: 0x6A) }
    @inlinable static var k: ASCII { ASCII(_unchecked: 0x6B) }
    @inlinable static var l: ASCII { ASCII(_unchecked: 0x6C) }
    @inlinable static var m: ASCII { ASCII(_unchecked: 0x6D) }
    @inlinable static var n: ASCII { ASCII(_unchecked: 0x6E) }
    @inlinable static var o: ASCII { ASCII(_unchecked: 0x6F) }
    @inlinable static var p: ASCII { ASCII(_unchecked: 0x70) }
    @inlinable static var q: ASCII { ASCII(_unchecked: 0x71) }
    @inlinable static var r: ASCII { ASCII(_unchecked: 0x72) }
    @inlinable static var s: ASCII { ASCII(_unchecked: 0x73) }
    @inlinable static var t: ASCII { ASCII(_unchecked: 0x74) }
    @inlinable static var u: ASCII { ASCII(_unchecked: 0x75) }
    @inlinable static var v: ASCII { ASCII(_unchecked: 0x76) }
    @inlinable static var w: ASCII { ASCII(_unchecked: 0x77) }
    @inlinable static var x: ASCII { ASCII(_unchecked: 0x78) }
    @inlinable static var y: ASCII { ASCII(_unchecked: 0x79) }
    @inlinable static var z: ASCII { ASCII(_unchecked: 0x7A) }
    // More special characters.
    @inlinable static var leftCurlyBracket : ASCII { ASCII(_unchecked: 0x7B) }
    @inlinable static var verticalBar      : ASCII { ASCII(_unchecked: 0x7C) }
    @inlinable static var rightCurlyBracket: ASCII { ASCII(_unchecked: 0x7D) }
    @inlinable static var tilde            : ASCII { ASCII(_unchecked: 0x7E) }
    @inlinable static var delete           : ASCII { ASCII(_unchecked: 0x7F) }
}


// --------------------------------------------
// MARK: - Character classes
// --------------------------------------------


extension ASCII {

  @usableFromInline
  internal struct ranges {

    @inlinable
    internal static var c0Control: Range<ASCII> {
      ASCII(_unchecked: 0x00)..<ASCII(_unchecked: 0x20)
    }

    @inlinable
    internal static var digits: Range<ASCII> {
      ASCII(_unchecked: 0x30)..<ASCII(_unchecked: 0x3A)
    }

    @inlinable
    internal static var uppercaseAlpha: Range<ASCII> {
      ASCII(_unchecked: 0x41)..<ASCII(_unchecked: 0x5B)
    }

    @inlinable
    internal static var lowercaseAlpha: Range<ASCII> {
      ASCII(_unchecked: 0x61)..<ASCII(_unchecked: 0x7B)
    }
  }

  /// Whether or not this is an uppercase alpha character (A-Z).
  ///
  @inlinable
  internal var isUppercaseAlpha: Bool {
    return ASCII.ranges.uppercaseAlpha.contains(self)
  }

  /// Whether or not this is an alpha character (a-z, A-Z).
  ///
  @inlinable
  internal var isAlpha: Bool {
    let uppercased = ASCII(_unchecked: codePoint & 0b11011111)
    return uppercased.isUppercaseAlpha
  }

  /// Whether or not this is a decimal digit (0-9).
  ///
  @inlinable
  internal var isDigit: Bool {
    ASCII.ranges.digits.contains(self)
  }

  /// Whether or not this is an alphanumeric character (a-z, A-Z, 0-9).
  ///
  @inlinable
  internal var isAlphaNumeric: Bool {
    isAlpha || isDigit
  }

  /// Whether or not this is a hex digit (a-f, A-F, 0-9).
  ///
  @inlinable
  internal var isHexDigit: Bool {
    hexNumberValue != nil
  }
}


// --------------------------------------------
// MARK: - Parsing and printing
// --------------------------------------------


@usableFromInline internal let DC: Int8 = -1
// swift-format-ignore
@usableFromInline internal let _parseHex_table: [Int8] = [
    DC, DC, DC, DC, DC, DC, DC, DC, DC, DC, // 48 invalid chars.
    DC, DC, DC, DC, DC, DC, DC, DC, DC, DC,
    DC, DC, DC, DC, DC, DC, DC, DC, DC, DC,
    DC, DC, DC, DC, DC, DC, DC, DC, DC, DC,
    DC, DC, DC, DC, DC, DC, DC, DC,
    00, 01, 02, 03, 04, 05, 06, 07, 08, 09, // numbers 0-9
    DC, DC, DC, DC, DC, DC, DC,             // 7 invalid chars from ':' to '@'
    10, 11, 12, 13, 14, 15,                 // uppercase A-F
    DC, DC, DC, DC, DC, DC, DC, DC, DC, DC, // 20 invalid chars G-Z
    DC, DC, DC, DC, DC, DC, DC, DC, DC, DC,
    DC, DC, DC, DC, DC, DC,                 // 6 invalid chars from '[' to '`'
    10, 11, 12, 13, 14, 15,                 // lowercase a-f
    DC, DC, DC, DC, DC, DC, DC, DC, DC, DC, // 20 invalid chars g-z
    DC, DC, DC, DC, DC, DC, DC, DC, DC, DC,
    DC, DC, DC, DC, DC,                     // 5 invalid chars from '{' to '(delete)'
]

extension ASCII {

  /// If this character is a hex digit, returns the digit's numeric value.
  ///
  @inlinable
  internal var hexNumberValue: UInt8? {
    let numericValue = _parseHex_table.withUnsafeBufferPointer { $0[Int(codePoint)] }
    return numericValue < 0 ? nil : UInt8(bitPattern: numericValue)
  }

  /// If this character is a decimal digit, returns the digit's numeric value.
  ///
  @inlinable
  internal var decimalNumberValue: UInt8? {
    hexNumberValue.flatMap { $0 < 10 ? $0 : nil }
  }
}

extension ASCII {

  /// Returns the uppercase hex digit corresponding to the low nibble of `number`.
  ///
  @inlinable
  internal static func uppercaseHexDigit(of number: UInt8) -> ASCII {
    let table: StaticString = "0123456789ABCDEF"
    return table.withUTF8Buffer { table in
      ASCII(_unchecked: table[Int(number & 0x0F)])
    }
  }

  /// Returns the lowercase hex digit corresponding to the low nibble of `number`.
  ///
  @inlinable
  internal static func lowercaseHexDigit(of number: UInt8) -> ASCII {
    let table: StaticString = "0123456789abcdef"
    return table.withUTF8Buffer { table in
      ASCII(_unchecked: table[Int(number & 0x0F)])
    }
  }

  /// If `number` is in the range `0..<10`, returns the decimal digit corresponding to the value of `number`.
  ///
  @inlinable
  internal static func decimalDigit(of number: UInt8) -> ASCII? {
    return number < 10 ? uppercaseHexDigit(of: number) : nil
  }

  /// Prints the decimal representation of `number` to the memory location given by `stringBuffer`.
  /// A maximum of 3 bytes will be written.
  ///
  /// - returns:  The number of bytes written to `stringBuffer`.
  ///
  @usableFromInline
  internal static func writeDecimalString(for number: UInt8, to stringBuffer: UnsafeMutableRawPointer) -> UInt8 {

    var count: UInt8 = 0
    var remaining = number
    do {
      let digit: UInt8
      (digit, remaining) = remaining.quotientAndRemainder(dividingBy: 100)
      if digit != 0 {
        stringBuffer.storeBytes(
          of: ASCII.decimalDigit(of: UInt8(truncatingIfNeeded: digit))!.codePoint,
          toByteOffset: 0,
          as: UInt8.self
        )
        count += 1
      }
    }
    do {
      let digit: UInt8
      (digit, remaining) = remaining.quotientAndRemainder(dividingBy: 10)
      if count != 0 || digit != 0 {
        stringBuffer.storeBytes(
          of: ASCII.decimalDigit(of: UInt8(truncatingIfNeeded: digit))!.codePoint,
          toByteOffset: Int(count),
          as: UInt8.self
        )
        count += 1
      }
    }
    stringBuffer.storeBytes(
      of: ASCII.decimalDigit(of: UInt8(truncatingIfNeeded: remaining))!.codePoint,
      toByteOffset: Int(count),
      as: UInt8.self
    )
    count += 1
    return count
  }

  /// Prints the decimal representation of `number` to the memory location given by `stringBuffer`.
  /// A maximum of 5 bytes will be written.
  ///
  /// - returns:  The number of bytes written to `stringBuffer`.
  ///
  @usableFromInline
  internal static func writeDecimalString(for number: UInt16, to stringBuffer: UnsafeMutableRawPointer) -> UInt8 {

    var count: UInt8 = 0
    var remaining = number
    do {
      let digit: UInt16
      (digit, remaining) = remaining.quotientAndRemainder(dividingBy: 10000)
      if digit != 0 {
        stringBuffer.storeBytes(
          of: ASCII.decimalDigit(of: UInt8(truncatingIfNeeded: digit))!.codePoint,
          toByteOffset: 0,
          as: UInt8.self
        )
        count += 1
      }
    }
    do {
      let digit: UInt16
      (digit, remaining) = remaining.quotientAndRemainder(dividingBy: 1000)
      if count != 0 || digit != 0 {
        stringBuffer.storeBytes(
          of: ASCII.decimalDigit(of: UInt8(truncatingIfNeeded: digit))!.codePoint,
          toByteOffset: Int(count),
          as: UInt8.self
        )
        count += 1
      }
    }
    do {
      let digit: UInt16
      (digit, remaining) = remaining.quotientAndRemainder(dividingBy: 100)
      if count != 0 || digit != 0 {
        stringBuffer.storeBytes(
          of: ASCII.decimalDigit(of: UInt8(truncatingIfNeeded: digit))!.codePoint,
          toByteOffset: Int(count),
          as: UInt8.self
        )
        count += 1
      }
    }
    do {
      let digit: UInt16
      (digit, remaining) = remaining.quotientAndRemainder(dividingBy: 10)
      if count != 0 || digit != 0 {
        stringBuffer.storeBytes(
          of: ASCII.decimalDigit(of: UInt8(truncatingIfNeeded: digit))!.codePoint,
          toByteOffset: Int(count),
          as: UInt8.self
        )
        count += 1
      }
    }
    stringBuffer.storeBytes(
      of: ASCII.decimalDigit(of: UInt8(truncatingIfNeeded: remaining))!.codePoint,
      toByteOffset: Int(count),
      as: UInt8.self
    )
    count += 1
    return count
  }

  /// Parses a 16-bit unsigned integer from a decimal representation contained in the given UTF-8 code-units.
  ///
  /// If parsing fails, it means the code-units contained a character which was not a decimal digit, or that the number overflows a 16-bit integer.
  ///
  @inlinable @inline(never)
  internal static func parseDecimalU16<UTF8Bytes>(
    from utf8: UTF8Bytes
  ) -> UInt16? where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    var value: UInt16 = 0
    var idx = utf8.startIndex
    while idx < utf8.endIndex, let digit = ASCII(utf8[idx])?.decimalNumberValue {
      var (overflowM, overflowA) = (false, false)
      (value, overflowM) = value.multipliedReportingOverflow(by: 10)
      (value, overflowA) = value.addingReportingOverflow(UInt16(digit))
      if overflowM || overflowA {
        return nil
      }
      utf8.formIndex(after: &idx)
    }
    return idx < utf8.endIndex ? nil : value
  }

  /// Prints the hex representation of `number` to the memory location given by `stringBuffer`.
  /// A maximum of `B.bitWidth / 4` bytes will be written (e.g. 2 bytes for an 8-bit integer, 4 bytes for a 16-bit integer, etc).
  ///
  /// The hex representation is written without any leading zeroes, and in lowercase.
  ///
  /// - returns:  The number of bytes written to `stringBuffer`.
  ///
  @inlinable
  internal static func writeHexString<B>(
    for number: B, to stringBuffer: UnsafeMutableRawPointer
  ) -> UInt8 where B: FixedWidthInteger & UnsignedInteger {

    var count: UInt8 = 0
    for nibbleIdx in 1..<(B.bitWidth / 4) {
      let digit = number &>> (B.bitWidth - (nibbleIdx * 4))
      if count != 0 || digit != 0 {
        stringBuffer.storeBytes(
          of: ASCII.lowercaseHexDigit(of: UInt8(truncatingIfNeeded: digit)).codePoint,
          toByteOffset: Int(count),
          as: UInt8.self
        )
        count += 1
      }
    }
    stringBuffer.storeBytes(
      of: ASCII.lowercaseHexDigit(of: UInt8(truncatingIfNeeded: number)).codePoint,
      toByteOffset: Int(count),
      as: UInt8.self
    )
    count += 1
    return count
  }
}


// --------------------------------------------
// MARK: - Misc
// --------------------------------------------


extension ASCII {

  /// If this is an uppercase alpha character, returns its lowercase counterpart. Otherwise, returns `self`.
  ///
  @inlinable
  internal var lowercased: ASCII {
    guard ASCII.ranges.uppercaseAlpha.contains(self) else { return self }
    return ASCII(_unchecked: codePoint | 0b00100000)
  }

  /// A sequence of all possible ASCII characters.
  ///
  internal static var allCharacters: AnySequence<ASCII> {
    AnySequence(
      sequence(first: ASCII(_unchecked: 0x00)) { character in
        ASCII(character.codePoint + 1)
      }
    )
  }
}
