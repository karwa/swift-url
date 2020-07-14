struct ASCII {
  public let codePoint: UInt8
}

// Initialisation.

extension ASCII {

  @inlinable internal init(_unchecked v: UInt8) {
    assert(v & 0x80 == 0, "Extended ASCII is not supported")
    self.codePoint = v
  }

  @inlinable public init?(_ v: UInt8) {
    guard v & 0x80 == 0 else { return nil }
    self.init(_unchecked: v)
  }

  @inlinable public init?(_ c: Character) {
    guard let asciiVal = c.asciiValue else { return nil }
    self.init(_unchecked: asciiVal)
  }
}

// Homogeneous comparison.

extension ASCII: Comparable, Equatable, Hashable {

  @inlinable public static func < (lhs: ASCII, rhs: ASCII) -> Bool {
    lhs.codePoint < rhs.codePoint
  }
}

// Heterogeneous comparison.

extension ASCII {

  // UInt8.
  @inlinable public static func == (lhs: UInt8, rhs: ASCII) -> Bool {
    lhs == rhs.codePoint
  }
  @inlinable public static func != (lhs: UInt8, rhs: ASCII) -> Bool {
    !(lhs == rhs)
  }
  @inlinable public static func ~= (pattern: UInt8, value: ASCII) -> Bool {
    pattern == value.codePoint
  }
  @inlinable public static func ~= (pattern: ASCII, value: UInt8) -> Bool {
    value == pattern.codePoint
  }

  // UInt8?.
  @inlinable public static func == (lhs: UInt8?, rhs: ASCII) -> Bool {
    lhs == rhs.codePoint
  }
  @inlinable public static func != (lhs: UInt8?, rhs: ASCII) -> Bool {
    !(lhs == rhs)
  }
  @inlinable public static func ~= (pattern: UInt8?, value: ASCII) -> Bool {
    pattern == value.codePoint
  }
  @inlinable public static func ~= (pattern: ASCII, value: UInt8?) -> Bool {
    value == pattern.codePoint
  }

  // Character.
  @inlinable public static func == (lhs: Character, rhs: ASCII) -> Bool {
    lhs.asciiValue.map { $0 == rhs } ?? false
  }
  @inlinable public static func != (lhs: Character, rhs: ASCII) -> Bool {
    !(lhs == rhs)
  }
  @inlinable public static func ~= (pattern: Character, value: ASCII) -> Bool {
    pattern == value
  }
  @inlinable public static func ~= (pattern: ASCII, value: Character) -> Bool {
    value == pattern
  }

  // Character?.
  @inlinable public static func == (lhs: Character?, rhs: ASCII) -> Bool {
    lhs?.asciiValue.map { $0 == rhs } ?? false
  }
  @inlinable public static func != (lhs: Character?, rhs: ASCII) -> Bool {
    !(lhs == rhs)
  }
  @inlinable public static func ~= (pattern: Character?, value: ASCII) -> Bool {
    pattern == value
  }
  @inlinable public static func ~= (pattern: ASCII, value: Character?) -> Bool {
    value == pattern
  }
}

// swift-format-ignore
extension ASCII {

    // Control Characters.
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

extension ASCII {
  public struct Ranges {
    public var controlCharacters: Range<ASCII> { ASCII(_unchecked: 0x00)..<ASCII(_unchecked: 0x20) }
    public var specialCharacters: Range<ASCII> { ASCII(_unchecked: 0x20)..<ASCII(_unchecked: 0x30) }
    public var digits: Range<ASCII> { ASCII(_unchecked: 0x30)..<ASCII(_unchecked: 0x3A) }
    public var uppercaseAlpha: Range<ASCII> { ASCII(_unchecked: 0x41)..<ASCII(_unchecked: 0x5B) }
    public var lowercaseAlpha: Range<ASCII> { ASCII(_unchecked: 0x61)..<ASCII(_unchecked: 0x7B) }
  }

  public static var ranges: Ranges { Ranges() }

  public func isA(_ range: KeyPath<ASCII.Ranges, Range<ASCII>>) -> Bool {
    return ASCII.ranges[keyPath: range].contains(self)
  }

  /// Whether or not this is an alpha character (a-z, A-Z).
  ///
  public var isAlpha: Bool {
    ASCII.ranges.uppercaseAlpha.contains(self) || ASCII.ranges.lowercaseAlpha.contains(self)
  }

  /// Whether or not this is an alphanumeric character (a-z, A-Z, 0-9).
  ///
  public var isAlphaNumeric: Bool {
    isAlpha || ASCII.ranges.digits.contains(self)
  }

  /// Whether or not this is a hex digit (a-f, A-F, 0-9).
  ///
  public var isHexDigit: Bool {
    ASCII.parseHexDigit(ascii: self) != ASCII.parse_NotFound
  }
}

// Parsing/Printing utilities.

// TODO: Clean these up.

private let DC: UInt8 = 99
// swift-format-ignore
private let _parseHex_table: [UInt8] = [
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

  /// Returns the ASCII character corresponding to the low nibble of `number`, in hex.
  static func getHexDigit_upper(_ number: UInt8) -> ASCII {
    let table: StaticString = "0123456789ABCDEF"
    return table.withUTF8Buffer { table in
      ASCII(_unchecked: table[Int(number & 0x0F)])
    }
  }

  static func getHexDigit_lower(_ number: UInt8) -> ASCII {
    let table: StaticString = "0123456789abcdef"
    return table.withUTF8Buffer { table in
      ASCII(_unchecked: table[Int(number & 0x0F)])
    }
  }

  /// Returns the ASCII character corresponding to the value of `number`.
  /// If `number` is >= 10, returns `ASCII.null`.
  ///
  static func getDecimalDigit(_ number: UInt8) -> ASCII {
    return number < 10 ? getHexDigit_upper(number) : .null
  }

  static var parse_NotFound: UInt8 { DC }

  /// Returns the numerical value of a hex digit.
  static func parseHexDigit(ascii: ASCII) -> UInt8 {
    assert(_parseHex_table.count == 128)
    return _parseHex_table.withUnsafeBufferPointer { $0[Int(ascii.codePoint)] }
  }

  static func parseDecimalDigit(ascii: ASCII) -> UInt8 {
    let hexValue = parseHexDigit(ascii: ascii)
    // Yes, there's a branch, but I didn't fancy a second lookup table.
    return hexValue < 10 ? hexValue : DC
  }
}

extension ASCII {

  /// Prints the decimal representation of `number` in to `stringBuffer`.
  /// `stringBuffer` requires at least 3 bytes worth of space.
  ///
  /// - returns:  The index one-past-the-end of the resulting text.
  ///
  static func insertDecimalString(for number: UInt8, into stringBuffer: UnsafeMutableBufferPointer<UInt8>) -> Int {
    var idx = stringBuffer.startIndex
    guard _fastPath(stringBuffer.count >= 3) else { return idx }

    guard number != 0 else {
      stringBuffer[idx] = ASCII.n0.codePoint
      idx &+= 1
      return idx
    }
    var number = number
    let pieceStart = idx
    while number != 0 {
      let digit: UInt8
      (number, digit) = number.quotientAndRemainder(dividingBy: 10)
      stringBuffer[idx] = ASCII.getDecimalDigit(UInt8(truncatingIfNeeded: digit)).codePoint
      idx &+= 1
    }
    stringBuffer[pieceStart..<idx].reverse()
    return idx
  }

  /// Prints the decimal representation of `number` in to `stringBuffer`.
  /// `stringBuffer` requires at least `B.bitWidth / 4` bytes of space.
  ///
  /// - returns:  The index one-past-the-end of the resulting text.
  ///
  static func insertHexString<B>(for number: B, into stringBuffer: UnsafeMutableBufferPointer<UInt8>) -> Int
  where B: BinaryInteger {
    var idx = stringBuffer.startIndex
    assert(stringBuffer.count >= number.bitWidth / 4)

    guard number != 0 else {
      stringBuffer[idx] = ASCII.n0.codePoint
      idx &+= 1
      return idx
    }
    var number = number
    let pieceStart = idx
    while number != 0 {
      let digit: B
      (number, digit) = number.quotientAndRemainder(dividingBy: 16)
      stringBuffer[idx] = ASCII.getHexDigit_lower(UInt8(truncatingIfNeeded: digit)).codePoint
      idx &+= 1
    }
    stringBuffer[Range(uncheckedBounds: (pieceStart, idx))].reverse()
    return idx
  }
}

extension ASCII {
  var lowercased: ASCII {
    guard ASCII.ranges.uppercaseAlpha.contains(self) else { return self }
    return ASCII(_unchecked: ASCII.a.codePoint + (self.codePoint - ASCII.A.codePoint))
  }
}
