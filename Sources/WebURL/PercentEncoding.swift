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

/// A set of characters which should be transformed or substituted in order to percent-encode (or percent-escape) an ASCII string.
///
protocol PercentEncodeSet {

  /// Whether or not the given ASCII `character` should be percent-encoded.
  ///
  static func shouldEscape(character: ASCII) -> Bool

  /// An optional function which allows the encode-set to replace a non-percent-encoded character with another character.
  ///
  /// For example, the `application/x-www-form-urlencoded` encoding does not escape the space character, and instead replaces it with a "+".
  /// Conforming types must also implement the reverse substitution function, `unsubstitute(character:)`.
  ///
  /// - parameters:
  ///   - character: The source character.
  /// - returns:     The substitute character, or `nil` if the character should not be substituted.
  ///
  static func substitute(for character: ASCII) -> ASCII?

  /// An optional function which recovers a character from its substituted value.
  ///
  /// For example, the `application/x-www-form-urlencoded` encoding does not escape the space character, and instead replaces it with a "+".
  /// This function would thus return a space in place of a "+", so the original character can be recovered.
  /// Conforming types must also implement the substitution function, `substitute(for:)`.
  ///
  /// - parameters:
  ///   - character: The character from the encoded string.
  /// - returns:     The recovered original character, or `nil` if the character was not produced by this encode-set's substitution function.
  ///
  static func unsubstitute(character: ASCII) -> ASCII?
}

extension PercentEncodeSet {

  @inline(__always)
  static func substitute(for character: ASCII) -> ASCII? {
    return nil
  }

  @inline(__always)
  static func unsubstitute(character: ASCII) -> ASCII? {
    return nil
  }
}


// MARK: - Encoding.


extension LazyCollectionProtocol where Element == UInt8 {

  /// Returns a wrapper over this collection which lazily percent-encodes its contents according to the given `EncodeSet`.
  /// This collection is interpreted as UTF8-encoded text.
  ///
  /// Percent encoding transforms arbitrary strings to a limited set of ASCII characters which the `EncodeSet` permits.
  /// Non-ASCII characters and ASCII characters which are not allowed in the output, are encoded by replacing each byte with the sequence "%ZZ",
  /// where `ZZ` is the byte's value in hexadecimal.
  ///
  /// For example, the ASCII space character " " has a decimal value of 32 (0x20 hex). If the `EncodeSet` does not permit spaces in its output string,
  /// all spaces will be replaced by the sequence "%20". So the string "hello, world" becomes "hello,%20world" when percent-encoded.
  /// The character "✌️" is encoded in UTF8 as [0xE2, 0x9C, 0x8C, 0xEF, 0xB8, 0x8F] and since it is not ASCII, will be percent-encoded in every `EncodeSet`.
  /// This single-character string becomes "%E2%9C%8C%EF%B8%8F" when percent-encoded,
  ///
  /// `EncodeSet`s are also able to substitute characters. For example, the `application/x-www-form-urlencoded` encode-set percent-encodes
  /// the ASCII "+" character (0x2B), allowing that ASCII value to represent spaces. So the string "Swift is better than C++" becomes
  /// "Swift+is+better+than+C%2B%2B" in this encoding.
  ///
  /// The `LazilyPercentEncoded` wrapper is a collection-of-collections; each byte in the source collection is represented by a collection of either 1 or 3 bytes,
  /// depending on whether or not it was percent-encoded. The `.joined()` operator can be used if a one-dimensional collection is desired.
  ///
  /// -  important: Users should consider whether or not the "%" character itself should be part of their `EncodeSet`.
  /// If it is included, a string such as "%40 Polyester" would become "%2540%20Polyester", which can be decoded to exactly recover the original string.
  /// If it is _not_ included, strings such as the "%40" above would be copied to the output, where they would be indistinguishable from a percent-encoded byte
  /// and subsequently decoded as a byte value (in this case, the byte 0x40 is the ASCII commercial at, meaning the decoded string would be "@ Polyester").
  ///
  /// - parameters:
  ///     - encodeSet:    The set of ASCII characters which should be percent-encoded or substituted.
  ///
  func percentEncoded<EncodeSet>(using encodeSet: EncodeSet.Type) -> LazilyPercentEncoded<Self, EncodeSet> {
    return LazilyPercentEncoded(source: self, encodeSet: encodeSet)
  }
}

struct LazilyPercentEncoded<Source, EncodeSet>: Collection, LazyCollectionProtocol
where Source: Collection, Source.Element == UInt8, EncodeSet: PercentEncodeSet {
  let source: Source

  fileprivate init(source: Source, encodeSet: EncodeSet.Type) {
    self.source = source
  }

  typealias Index = Source.Index

  var startIndex: Index {
    return source.startIndex
  }

  var endIndex: Index {
    return source.endIndex
  }

  var isEmpty: Bool {
    return source.isEmpty
  }

  var underestimatedCount: Int {
    return source.underestimatedCount
  }

  var count: Int {
    return source.count
  }

  func index(after i: Index) -> Index {
    return source.index(after: i)
  }

  func formIndex(after i: inout Index) {
    return source.formIndex(after: &i)
  }

  func index(_ i: Index, offsetBy distance: Int) -> Index {
    return source.index(i, offsetBy: distance)
  }

  func formIndex(_ i: inout Index, offsetBy distance: Int) {
    return source.formIndex(&i, offsetBy: distance)
  }

  func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    return source.index(i, offsetBy: distance, limitedBy: limit)
  }

  func formIndex(_ i: inout Index, offsetBy distance: Int, limitedBy limit: Index) -> Bool {
    return source.formIndex(&i, offsetBy: distance, limitedBy: limit)
  }

  func distance(from start: Index, to end: Index) -> Int {
    return source.distance(from: start, to: end)
  }

  subscript(position: Index) -> PercentEncodedByte {
    let sourceByte = source[position]
    if let asciiChar = ASCII(sourceByte), EncodeSet.shouldEscape(character: asciiChar) == false {
      return EncodeSet.substitute(for: asciiChar).map { .substitutedByte($0.codePoint) } ?? .sourceByte(sourceByte)
    }
    return .percentEncodedByte(sourceByte)
  }
}

enum PercentEncodedByte: RandomAccessCollection {
  case sourceByte(UInt8)
  case substitutedByte(UInt8)
  case percentEncodedByte(UInt8)

  var startIndex: Int {
    return 0
  }

  var endIndex: Int {
    switch self {
    case .sourceByte, .substitutedByte:
      return 1
    case .percentEncodedByte:
      return 3
    }
  }

  var isEmpty: Bool {
    return false
  }

  var underestimatedCount: Int {
    return endIndex
  }

  var count: Int {
    return endIndex
  }

  subscript(position: Int) -> UInt8 {
    switch self {
    case .sourceByte(let byte):
      assert(position == 0, "Invalid index")
      return byte
    case .substitutedByte(let byte):
      assert(position == 0, "Invalid index")
      return byte
    case .percentEncodedByte(let byte):
      switch position {
      case 0: return ASCII.percentSign.codePoint
      case 1: return ASCII.getHexDigit_upper(byte &>> 4).codePoint
      case 2: return ASCII.getHexDigit_upper(byte).codePoint
      default: fatalError("Invalid index")
      }
    }
  }
}

extension LazilyPercentEncoded: BidirectionalCollection where Source: BidirectionalCollection {

  func index(before i: Index) -> Index {
    return source.index(before: i)
  }

  func formIndex(before i: inout Index) {
    return source.formIndex(before: &i)
  }
}

extension LazilyPercentEncoded: RandomAccessCollection where Source: RandomAccessCollection {}

extension LazilyPercentEncoded {

  /// Essentially, this is a `forEach` which _also_ returns whether any bytes were percent-encoded.
  @inline(__always)
  internal func write(to writer: (PercentEncodedByte) -> Void) -> Bool {
    var didEscape = false
    for byteGroup in self {
      writer(byteGroup)
      if case .percentEncodedByte = byteGroup {
        didEscape = true
      }
    }
    return didEscape
  }
}


// MARK: - Decoding.


extension LazyCollectionProtocol where Element == UInt8 {

  typealias LazilyPercentDecodedWithoutSubstitutions = LazilyPercentDecoded<Elements, PassthroughEncodeSet>

  /// Returns a view of this collection with percent-encoded byte sequences ("%ZZ") replaced by the byte 0xZZ.
  ///
  /// This view does not account for substitutions in the source collection's encode-set.
  /// If it is necessary to decode such substitutions, use `percentDecoded(using:)` instead and provide the encode-set to reverse.
  ///
  /// - seealso: `LazilyPercentDecoded`
  ///
  var percentDecoded: LazilyPercentDecodedWithoutSubstitutions {
    return LazilyPercentDecoded(source: elements)
  }

  /// Returns a view of this collection with percent-encoded byte sequences ("%ZZ") replaced by the byte 0xZZ.
  ///
  /// This view will reverse substitutions that were made by the given encode-set when encoding the source collection.
  ///
  /// - seealso: `LazilyPercentDecoded`
  ///
  func percentDecoded<EncodeSet>(using encodeSet: EncodeSet.Type) -> LazilyPercentDecoded<Elements, EncodeSet> {
    return LazilyPercentDecoded(source: elements)
  }
}

/// A collection which provides a view of its source collection with percent-encoded byte sequences ("%ZZ") replaced by the byte 0xZZ.
///
/// Some encode-sets perform substitutions as well as percent-encoding - e.g. URL form-encoding percent-encodes "+" characters but not " " (space) from the
/// source; spaces are then substituted with "+" characters so we know that every non-percent-encoded "+" represents a space. The `EncodeSet` generic
/// parameter is only used to reverse these substitutions; if such substitutions are not relevant to decoding,`PassthroughEncodeSet` may be given instead
/// of specifying a particular encode-set.
///
struct LazilyPercentDecoded<Source, EncodeSet>: Collection, LazyCollectionProtocol
where Source: Collection, Source.Element == UInt8, EncodeSet: PercentEncodeSet {
  typealias Element = UInt8

  let source: Source
  let startIndex: Index

  fileprivate init(source: Source) {
    self.source = source
    self.startIndex = Index(at: source.startIndex, in: source)
  }

  var endIndex: Index {
    return Index(endIndexOf: source)
  }

  func index(after i: Index) -> Index {
    assert(i != endIndex, "Attempt to advance endIndex")
    return Index(at: i.range.upperBound, in: source)
  }

  func formIndex(after i: inout Index) {
    assert(i != endIndex, "Attempt to advance endIndex")
    i = Index(at: i.range.upperBound, in: source)
  }

  subscript(position: Index) -> Element {
    assert(position != endIndex, "Attempt to read element at endIndex")
    return position.decodedValue
  }
}

extension LazilyPercentDecoded {

  /// A value which represents the location of a percent-encoded byte sequence in a source collection.
  ///
  /// The start index is given by `.init(at: source.startIndex, in: source)`.
  /// Each successive index is calculated by creating a new index at the previous index's `range.upperBound`, until an index is created whose
  /// `range.lowerBound` is the `endIndex` of the source collection.
  ///
  /// An index's `range` always starts at a byte which is not part of a percent-encode sequence, a percent sign, or `endIndex`, and each index
  /// represents a single decoded byte. This decoded value is stored in the index as `decodedValue`.
  ///
  struct Index: Comparable {
    let range: Range<Source.Index>
    let decodedValue: UInt8

    /// Creates an index referencing the given source collection's `endIndex`.
    /// This index's `decodedValue` is meaningless.
    ///
    init(endIndexOf source: Source) {
      self.range = Range(uncheckedBounds: (source.endIndex, source.endIndex))
      self.decodedValue = 0
    }

    /// Creates an index referencing the decoded byte starting at the given source index.
    ///
    /// The newly-created index's successor may be obtained by creating another index starting at `range.upperBound`.
    /// The index which starts at `source.endIndex` is given by `.init(endIndexOf:)`.
    ///
    init(at i: Source.Index, in source: Source) {
      guard i != source.endIndex else {
        self = .init(endIndexOf: source)
        return
      }
      let byte0 = source[i]
      let byte1Index = source.index(after: i)
      guard _slowPath(byte0 == ASCII.percentSign.codePoint) else {
        self.decodedValue = ASCII(byte0).flatMap { EncodeSet.unsubstitute(character: $0)?.codePoint } ?? byte0
        self.range = Range(uncheckedBounds: (i, byte1Index))
        return
      }
      var tail = source.suffix(from: byte1Index)
      guard let byte1 = tail.popFirst(),
        let decodedByte1 = ASCII(byte1).map(ASCII.parseHexDigit(ascii:)), decodedByte1 != ASCII.parse_NotFound,
        let byte2 = tail.popFirst(),
        let decodedByte2 = ASCII(byte2).map(ASCII.parseHexDigit(ascii:)), decodedByte2 != ASCII.parse_NotFound
      else {
        self.decodedValue = EncodeSet.unsubstitute(character: .percentSign)?.codePoint ?? ASCII.percentSign.codePoint
        self.range = Range(uncheckedBounds: (i, byte1Index))
        return
      }
      // decodedByte{1/2} are parsed from hex digits (i.e. in the range 0...15), so this will never overflow.
      self.decodedValue = (decodedByte1 &* 16) &+ (decodedByte2)
      self.range = Range(uncheckedBounds: (i, tail.startIndex))
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
      return lhs.range.lowerBound == rhs.range.lowerBound
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
      return lhs.range.lowerBound < rhs.range.lowerBound
    }
  }
}


// MARK: - URL encode sets.


/// An encode-set which does not escape or substitute any characters.
///
/// This is useful for decoding percent-encoded strings when we don't expect any characters to have been substituted, or when
/// the `PercentEncodeSet` used to encode the string is not known.
///
struct PassthroughEncodeSet: PercentEncodeSet {
  @inline(__always)
  static func shouldEscape(character: ASCII) -> Bool {
    return false
  }
}

// ARM and x86 seem to have wildly different performance characteristics.
// The lookup table seems to be about 8-12% better than bitshifting on x86, but can be 90% slower on ARM.

protocol DualImplementedPercentEncodeSet: PercentEncodeSet {
  static func shouldEscape_binary(character: ASCII) -> Bool
  static func shouldEscape_table(character: ASCII) -> Bool
}

extension DualImplementedPercentEncodeSet {
  @inline(__always)
  static func shouldEscape(character: ASCII) -> Bool {
    #if arch(x86_64)
      return shouldEscape_table(character: character)
    #else
      return shouldEscape_binary(character: character)
    #endif
  }
}

enum URLEncodeSet {

  struct C0: DualImplementedPercentEncodeSet {
    @inline(__always)
    static func shouldEscape_binary(character: ASCII) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b00000000_00000000_00000000_00000000_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000
      if character.codePoint < 64 {
        return lo & (1 &<< character.codePoint) != 0
      } else {
        return hi & (1 &<< (character.codePoint &- 64)) != 0
      }
    }
    @inline(__always)
    static func shouldEscape_table(character: ASCII) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(character.codePoint)] }.contains(.c0)
    }
  }

  struct Fragment: DualImplementedPercentEncodeSet {
    @inline(__always)
    static func shouldEscape_binary(character: ASCII) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b01010000_00000000_00000000_00000101_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10000000_00000000_00000000_00000001_00000000_00000000_00000000_00000000
      if character.codePoint < 64 {
        return lo & (1 &<< character.codePoint) != 0
      } else {
        return hi & (1 &<< (character.codePoint &- 64)) != 0
      }
    }
    @inline(__always)
    static func shouldEscape_table(character: ASCII) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(character.codePoint)] }.contains(.fragment)
    }
  }

  struct Query_NotSpecial: DualImplementedPercentEncodeSet {
    @inline(__always)
    static func shouldEscape_binary(character: ASCII) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b01010000_00000000_00000000_00001101_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000
      if character.codePoint < 64 {
        return lo & (1 &<< character.codePoint) != 0
      } else {
        return hi & (1 &<< (character.codePoint &- 64)) != 0
      }
    }
    @inline(__always)
    static func shouldEscape_table(character: ASCII) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(character.codePoint)] }.contains(.query)
    }
  }

  struct Query_Special: DualImplementedPercentEncodeSet {
    @inline(__always)
    static func shouldEscape_binary(character: ASCII) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b01010000_00000000_00000000_10001101_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000
      if character.codePoint < 64 {
        return lo & (1 &<< character.codePoint) != 0
      } else {
        return hi & (1 &<< (character.codePoint &- 64)) != 0
      }
    }
    @inline(__always)
    static func shouldEscape_table(character: ASCII) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(character.codePoint)] }.contains(.specialQuery)
    }
  }

  struct Path: DualImplementedPercentEncodeSet {
    @inline(__always)
    static func shouldEscape_binary(character: ASCII) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b11010000_00000000_00000000_00001101_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10101000_00000000_00000000_00000001_00000000_00000000_00000000_00000000
      if character.codePoint < 64 {
        return lo & (1 &<< character.codePoint) != 0
      } else {
        return hi & (1 &<< (character.codePoint &- 64)) != 0
      }
    }
    @inline(__always)
    static func shouldEscape_table(character: ASCII) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(character.codePoint)] }.contains(.path)
    }
  }

  struct UserInfo: DualImplementedPercentEncodeSet {
    @inline(__always)
    static func shouldEscape_binary(character: ASCII) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b11111100_00000000_10000000_00001101_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10111000_00000000_00000000_00000001_01111000_00000000_00000000_00000001
      if character.codePoint < 64 {
        return lo & (1 &<< character.codePoint) != 0
      } else {
        return hi & (1 &<< (character.codePoint &- 64)) != 0
      }
    }
    @inline(__always)
    static func shouldEscape_table(character: ASCII) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(character.codePoint)] }.contains(.userInfo)
    }
  }

  /// This encode-set is not used for any particular component, but can be used to encode data which is compatible with the escaping for
  /// the path, query, and fragment. It should give the same results as Javascript's `.encodeURIComponent()` method.
  ///
  struct Component: DualImplementedPercentEncodeSet {
    @inline(__always)
    static func shouldEscape_binary(character: ASCII) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b11111100_00000000_10011000_01111101_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10111000_00000000_00000000_00000001_01111000_00000000_00000000_00000001
      if character.codePoint < 64 {
        return lo & (1 &<< character.codePoint) != 0
      } else {
        return hi & (1 &<< (character.codePoint &- 64)) != 0
      }
    }
    @inline(__always)
    static func shouldEscape_table(character: ASCII) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(character.codePoint)] }.contains(.component)
    }
  }

  struct FormEncoded: DualImplementedPercentEncodeSet {
    @inline(__always)
    static func shouldEscape_binary(character: ASCII) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b11111100_00000000_10011011_11111110_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b11111000_00000000_00000000_00000001_01111000_00000000_00000000_00000001
      if character.codePoint < 64 {
        return lo & (1 &<< character.codePoint) != 0
      } else {
        return hi & (1 &<< (character.codePoint &- 64)) != 0
      }
    }
    @inline(__always)
    static func shouldEscape_table(character: ASCII) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(character.codePoint)] }.contains(.form)
    }
    @inline(__always)
    static func substitute(for character: ASCII) -> ASCII? {
      return character == .space ? .plus : nil
    }
    @inline(__always)
    static func unsubstitute(character: ASCII) -> ASCII? {
      return character == .plus ? .space : nil
    }
  }
}

//swift-format-ignore
/// A set of `URLEncodeSet`s.
struct URLEncodeSetSet: OptionSet {
  var rawValue: UInt8
  init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  static var none: Self         { Self(rawValue: 0) }
  static var c0: Self           { Self(rawValue: 1 << 0) }
  static var fragment: Self     { Self(rawValue: 1 << 1) }
  static var query: Self        { Self(rawValue: 1 << 2) }
  static var specialQuery: Self { Self(rawValue: 1 << 3) }
  static var path: Self         { Self(rawValue: 1 << 4) }
  static var userInfo: Self     { Self(rawValue: 1 << 5) }
  static var form: Self         { Self(rawValue: 1 << 6) }
  static var component: Self    { Self(rawValue: 1 << 7) }
}

// swift-format-ignore
let percent_encoding_table: [URLEncodeSetSet] = [
  // Control Characters                ---------------------------------------------------------------------
  /*  0x00 null */                     [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x01 startOfHeading */           [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x02 startOfText */              [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x03 endOfText */                [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x04 endOfTransmission */        [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x05 enquiry */                  [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x06 acknowledge */              [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x07 bell */                     [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x08 backspace */                [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x09 horizontalTab */            [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x0A lineFeed */                 [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x0B verticalTab */              [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x0C formFeed */                 [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x0D carriageReturn */           [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x0E shiftOut */                 [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x0F shiftIn */                  [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x10 dataLinkEscape */           [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x11 deviceControl1 */           [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x12 deviceControl2 */           [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x13 deviceControl3 */           [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x14 deviceControl4 */           [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x15 negativeAcknowledge */      [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x16 synchronousIdle */          [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x17 endOfTransmissionBlock */   [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x18 cancel */                   [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x19 endOfMedium */              [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x1A substitute */               [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x1B escape */                   [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x1C fileSeparator */            [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x1D groupSeparator */           [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x1E recordSeparator */          [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x1F unitSeparator */            [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  // Special Characters                ---------------------------------------------------------------------
  /* 0x20 space */                     [.fragment, .query, .specialQuery, .path, .userInfo, .component], // form substitutes instead.
  /* 0x21 exclamationMark */           .form,
  /* 0x22 doubleQuotationMark */       [.fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /* 0x23 numberSign */                [.query, .specialQuery, .path, .userInfo, .form, .component],
  /* 0x24 dollarSign */                [.form, .component],
  /* 0x25 percentSign */               [.form, .component],
  /* 0x26 ampersand */                 [.form, .component],
  /* 0x27 apostrophe */                [.specialQuery, .form],
  /* 0x28 leftParenthesis */           .form,
  /* 0x29 rightParenthesis */          .form,
  /* 0x2A asterisk */                  .none,
  /* 0x2B plus */                      [.form, .component],
  /* 0x2C comma */                     [.form, .component],
  /* 0x2D minus */                     .none,
  /* 0x2E period */                    .none,
  /* 0x2F forwardSlash */              [.userInfo, .form, .component],
  // Numbers                           ----------------------------------------------------------------------
  /*  0x30 digit 0 */                  .none,
  /*  0x31 digit 1 */                  .none,
  /*  0x32 digit 2 */                  .none,
  /*  0x33 digit 3 */                  .none,
  /*  0x34 digit 4 */                  .none,
  /*  0x35 digit 5 */                  .none,
  /*  0x36 digit 6 */                  .none,
  /*  0x37 digit 7 */                  .none,
  /*  0x38 digit 8 */                  .none,
  /*  0x39 digit 9 */                  .none,
  // Punctuation                       ----------------------------------------------------------------------
  /*  0x3A colon */                    [.userInfo, .form, .component],
  /*  0x3B semicolon */                [.userInfo, .form, .component],
  /*  0x3C lessThanSign */             [.fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x3D equalSign */                [.userInfo, .form, .component],
  /*  0x3E greaterThanSign */          [.fragment, .query, .specialQuery, .path, .userInfo, .form, .component],
  /*  0x3F questionMark */             [.path, .userInfo, .form, .component],
  /*  0x40 commercialAt */             [.userInfo, .form, .component],
  // Uppercase letters                 ----------------------------------------------------------------------
  /*  0x41 A */                        .none,
  /*  0x42 B */                        .none,
  /*  0x43 C */                        .none,
  /*  0x44 D */                        .none,
  /*  0x45 E */                        .none,
  /*  0x46 F */                        .none,
  /*  0x47 G */                        .none,
  /*  0x48 H */                        .none,
  /*  0x49 I */                        .none,
  /*  0x4A J */                        .none,
  /*  0x4B K */                        .none,
  /*  0x4C L */                        .none,
  /*  0x4D M */                        .none,
  /*  0x4E N */                        .none,
  /*  0x4F O */                        .none,
  /*  0x50 P */                        .none,
  /*  0x51 Q */                        .none,
  /*  0x52 R */                        .none,
  /*  0x53 S */                        .none,
  /*  0x54 T */                        .none,
  /*  0x55 U */                        .none,
  /*  0x56 V */                        .none,
  /*  0x57 W */                        .none,
  /*  0x58 X */                        .none,
  /*  0x59 Y */                        .none,
  /*  0x5A Z */                        .none,
  // More special characters           ---------------------------------------------------------------------
  /*  0x5B leftSquareBracket */        [.userInfo, .form, .component],
  /*  0x5C backslash */                [.userInfo, .form, .component],
  /*  0x5D rightSquareBracket */       [.userInfo, .form, .component],
  /*  0x5E circumflexAccent */         [.userInfo, .form, .component],
  /*  0x5F underscore */               .none,
  /*  0x60 backtick */                 [.fragment, .path, .userInfo, .form, .component],
  // Lowercase letters                 ---------------------------------------------------------------------
  /*  0x61 a */                        .none,
  /*  0x62 b */                        .none,
  /*  0x63 c */                        .none,
  /*  0x64 d */                        .none,
  /*  0x65 e */                        .none,
  /*  0x66 f */                        .none,
  /*  0x67 g */                        .none,
  /*  0x68 h */                        .none,
  /*  0x69 i */                        .none,
  /*  0x6A j */                        .none,
  /*  0x6B k */                        .none,
  /*  0x6C l */                        .none,
  /*  0x6D m */                        .none,
  /*  0x6E n */                        .none,
  /*  0x6F o */                        .none,
  /*  0x70 p */                        .none,
  /*  0x71 q */                        .none,
  /*  0x72 r */                        .none,
  /*  0x73 s */                        .none,
  /*  0x74 t */                        .none,
  /*  0x75 u */                        .none,
  /*  0x76 v */                        .none,
  /*  0x77 w */                        .none,
  /*  0x78 x */                        .none,
  /*  0x79 y */                        .none,
  /*  0x7A z */                        .none,
  // More special characters           ---------------------------------------------------------------------
  /*  0x7B leftCurlyBracket */         [.path, .userInfo, .form, .component],
  /*  0x7C verticalBar */              [.userInfo, .form, .component],
  /*  0x7D rightCurlyBracket */        [.path, .userInfo, .form, .component],
  /*  0x7E tilde */                    .form,
  /*  0x7F delete */                   [.c0, .fragment, .query, .specialQuery, .path, .userInfo, .form, .component]
  // The End.                          ---------------------------------------------------------------------
]
