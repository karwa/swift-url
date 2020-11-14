enum PercentEncoding {}

/// A set of characters which should be transformed or substituted during a percent-encoding transformation.
///
/// - seealso: `PercentEncoding`
///
protocol PercentEncodeSet {

  /// Whether or not the given ASCII `character` should be percent-encoded.
  ///
  static func shouldEscape(character: ASCII) -> Bool

  /// An optional function which allows the encode-set to replace a non-percent-encoded character with another character.
  ///
  /// For example, the `application/x-www-form-urlencoded` encoding does not escape the space character, and instead replaces it with a "+".
  /// Conformers must also implement the reverse substitution function, `unsubstitute(character:)`.
  ///
  static func substitute(for character: ASCII) -> ASCII

  /// An optional function which recovers a character from its substituted value.
  ///
  /// For example, the `application/x-www-form-urlencoded` encoding does not escape the space character, and instead replaces it with a "+".
  /// This function would thus return a space in place of a "+", so the original character can be recovered.
  /// Conformers must also implement the substitution function, `substitute(for:)`.
  ///
  static func unsubstitute(character: ASCII) -> ASCII
}

extension PercentEncodeSet {

  static func substitute(for character: ASCII) -> ASCII {
    return character
  }
  static func unsubstitute(character: ASCII) -> ASCII {
    return character
  }
}


// MARK: - Encoding.


// TODO: Investigate a lazy collection, whose Element is an enum containing either 1 or 3 UInt8s.

extension PercentEncoding {

  /// Encodes the given byte sequence as an ASCII string, by means of the "percent-encoding" transformation.
  /// The bytes are encoded in to a small buffer which is given to the provided closure to process.
  ///
  /// - Bytes which are not valid ASCII characters are _always_ encoded as the sequence "%ZZ",
  ///   where ZZ is the byte's numerical value as a hexadecimal string.
  /// - Bytes which are valid ASCII characters are also encoded if included in the given `EncodeSet`.
  /// - Otherwise, the `EncodeSet` is also able to substitute ASCII characters.
  ///
  /// -  important:	If the "%" character is not in the encode-set, this function will not automatically percent-encode it. This means that existing
  ///             	percent-encoded sequences will be passed-through, rather than being double-encoded. If the byte string is truly an arbitrary
  ///             	sequence of bytes which may by coincidence contain the same bytes as a percent-encoded sequence, the "%" character
  ///               must be in the encode-set to preserve the original contents.
  ///
  /// - parameters:
  ///     - bytes:        The sequence of bytes to encode.
  ///     - encodeSet:    The predicate which decides if a particular ASCII character should be escaped or not.
  ///     - processChunk: A callback which processes a chunk of encoded data. Each chunk is guaranteed to be a valid ASCII String, containing
  ///                     only the % character, upper-case ASCII hex digits, and characters allowed by the encode set. The given pointer, and any
  ///                     derived pointers to the same region of memory, must not escape the closure.
  ///
  /// - returns: `true` if any bytes from the given sequence required percent-encoding, otherwise `false`.
  ///             Note that `false` is also returned if bytes were substituted, as long as no percent-encoding was required.
  ///
  @discardableResult
  static func encode<Bytes, EncodeSet: PercentEncodeSet>(
    bytes: Bytes,
    using encodeSet: EncodeSet.Type,
    _ processChunk: (UnsafeBufferPointer<UInt8>) -> Void
  ) -> Bool where Bytes: Sequence, Bytes.Element == UInt8 {

    return withSmallStringSizedStackBuffer { chunkBuffer -> Bool in
      var didEncode = false
      let chunkSize = chunkBuffer.count
      var i = 0
      for byte in bytes {
        // Ensure the buffer has at least enough space for an escaped byte (%XX).
        if i &+ 3 > chunkSize {
          processChunk(UnsafeBufferPointer(start: chunkBuffer.baseAddress.unsafelyUnwrapped, count: i))
          i = 0
        }
        if let asciiChar = ASCII(byte), encodeSet.shouldEscape(character: asciiChar) == false {
          chunkBuffer[i] = encodeSet.substitute(for: asciiChar).codePoint
          i &+= 1
          continue
        }
        _escape(
          byte: byte,
          into: UnsafeMutableBufferPointer(start: chunkBuffer.baseAddress.unsafelyUnwrapped + i, count: 3)
        )
        i &+= 3
        didEncode = true
      }
      // Flush the buffer.
      processChunk(UnsafeBufferPointer(start: chunkBuffer.baseAddress.unsafelyUnwrapped, count: i))
      return didEncode
    }
  }

  /// Encodes the given byte sequence as an ASCII string, by means of the "percent-encoding" transformation.
  /// The bytes are encoded in to a small buffer which is given to the provided closure to process.
  ///
  /// Unlike the regular `encode` function, this function processes the input sequence in reverse. The buffers given to the `processChunk` closure
  /// are correctly-ordered, but represent a sliding window which begins at the last chunk of the input sequence and moves towards the beginning. Each
  /// buffer of bytes may be _prepended_, so that its contents occur before all chunks yielded so far, in order to obtain the same result as calling the regular
  /// `encode` function and _appening_ the contents of each buffer.
  ///
  /// - seealso: `encode(bytes:using:_:)`
  ///
  /// -  important:  If the "%" character is not in the encode-set, this function will not automatically percent-encode it. This means that existing
  ///               percent-encoded sequences will be passed-through, rather than being double-encoded. If the byte string is truly an arbitrary
  ///               sequence of bytes which may by coincidence contain the same bytes as a percent-encoded sequence, the "%" character
  ///               must be in the encode-set to preserve the original contents.
  ///
  /// - parameters:
  ///     - bytes:        The sequence of bytes to encode.
  ///     - encodeSet:    The predicate which decides if a particular ASCII character should be escaped or not.
  ///     - processChunk: A callback which processes a chunk of encoded data. Each chunk is guaranteed to be a valid ASCII String, containing
  ///                     only the % character, upper-case ASCII hex digits, and characters allowed by the encode set. The given pointer, and any
  ///                     derived pointers to the same region of memory, must not escape the closure.
  ///
  /// - returns: `true` if any bytes from the given sequence required percent-encoding, otherwise `false`.
  ///             Note that `false` is also returned if bytes were substituted, as long as no percent-encoding was required.
  ///
  @discardableResult
  static func encodeFromBack<Bytes, EncodeSet: PercentEncodeSet>(
    bytes: Bytes,
    using encodeSet: EncodeSet.Type,
    _ processChunk: (UnsafeBufferPointer<UInt8>) -> Void
  ) -> Bool where Bytes: BidirectionalCollection, Bytes.Element == UInt8 {

    return withSmallStringSizedStackBuffer { chunkBuffer -> Bool in
      var didEncode = false
      let chunkSize = chunkBuffer.count
      var i = chunkBuffer.endIndex
      for byte in bytes.reversed() {
        // Ensure the buffer has at least enough space for an escaped byte (%XX).
        if i < 3 {
          processChunk(
            UnsafeBufferPointer(start: chunkBuffer.baseAddress.unsafelyUnwrapped + i, count: chunkSize &- i)
          )
          i = chunkBuffer.endIndex
        }
        if let asciiChar = ASCII(byte), encodeSet.shouldEscape(character: asciiChar) == false {
          i &-= 1
          chunkBuffer[i] = encodeSet.substitute(for: asciiChar).codePoint
          continue
        }
        i &-= 3
        _escape(
          byte: byte,
          into: UnsafeMutableBufferPointer(start: chunkBuffer.baseAddress.unsafelyUnwrapped + i, count: 3)
        )
        didEncode = true
      }
      // Flush the buffer.
      processChunk(
        UnsafeBufferPointer(start: chunkBuffer.baseAddress.unsafelyUnwrapped + i, count: chunkSize &- i)
      )
      return didEncode
    }
  }

  @inline(__always)
  private static func _escape(byte: UInt8, into output: UnsafeMutableBufferPointer<UInt8>) {
    assert(output.count >= 3)
    output[0] = ASCII.percentSign.codePoint
    output[1] = ASCII.getHexDigit_upper(byte &>> 4).codePoint
    output[2] = ASCII.getHexDigit_upper(byte).codePoint
  }
}


// MARK: - Decoding.


extension LazyCollectionProtocol where Element == UInt8 {

  typealias LazilyPercentDecodedWithoutSubstitutions = LazilyPercentDecoded<Self, PassthroughEncodeSet>

  /// Returns a view of this collection with percent-encoded byte sequences ("%ZZ") replaced by the byte 0xZZ.
  ///
  /// This view does not account for substitutions in the source collection's encode-set.
  /// If it is necessary to decode such substitutions, use `percentDecoded(using:)` instead and provide the encode-set to reverse.
  ///
  /// - seealso: `LazilyPercentDecoded`
  ///
  var percentDecoded: LazilyPercentDecodedWithoutSubstitutions {
    return LazilyPercentDecoded(source: self)
  }

  /// Returns a view of this collection with percent-encoded byte sequences ("%ZZ") replaced by the byte 0xZZ.
  ///
  /// This view will reverse substitutions that were made by the given encode-set when encoding the source collection.
  ///
  /// - seealso: `LazilyPercentDecoded`
  ///
  func percentDecoded<EncodeSet>(using encodeSet: EncodeSet.Type) -> LazilyPercentDecoded<Self, EncodeSet> {
    return LazilyPercentDecoded(source: self)
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
        self.decodedValue = ASCII(byte0).map { EncodeSet.unsubstitute(character: $0).codePoint } ?? byte0
        self.range = Range(uncheckedBounds: (i, byte1Index))
        return
      }
      var tail = source.suffix(from: byte1Index)
      guard let byte1 = tail.popFirst(),
        let decodedByte1 = ASCII(byte1).map(ASCII.parseHexDigit(ascii:)), decodedByte1 != ASCII.parse_NotFound,
        let byte2 = tail.popFirst(),
        let decodedByte2 = ASCII(byte2).map(ASCII.parseHexDigit(ascii:)), decodedByte2 != ASCII.parse_NotFound
      else {
        self.decodedValue = EncodeSet.unsubstitute(character: .percentSign).codePoint
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


// MARK: - String APIs.


extension Sequence where Element == UInt8 {

  func percentEncodedString<EncodeSet: PercentEncodeSet>(encodeSet: EncodeSet.Type) -> String {
    var result = ""
    PercentEncoding.encode(bytes: self, using: encodeSet) { chunk in
      result.append(String(decoding: chunk, as: UTF8.self))
    }
    return result
  }
}


// MARK: - URL encode sets.


/// An encode-set which does not escape or substitute any characters.
///
struct PassthroughEncodeSet: PercentEncodeSet {
  static func shouldEscape(character: ASCII) -> Bool {
    return false
  }
}

extension PercentEncoding {

  @discardableResult
  static func encodeQuery<Bytes>(
    bytes: Bytes,
    isSpecial: Bool,
    _ processChunk: (UnsafeBufferPointer<UInt8>) -> Void
  ) -> Bool where Bytes: Sequence, Bytes.Element == UInt8 {

    if isSpecial {
      return encode(bytes: bytes, using: URLEncodeSet.Query_Special.self, processChunk)
    } else {
      return encode(bytes: bytes, using: URLEncodeSet.Query_NotSpecial.self, processChunk)
    }
  }
}

enum URLEncodeSet {

  struct C0: PercentEncodeSet {
    @inline(__always)
    static func shouldEscape(character: ASCII) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b00000000_00000000_00000000_00000000_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000
      if character.codePoint < 64 {
        return lo & (1 &<< character.codePoint) != 0
      } else {
        return hi & (1 &<< (character.codePoint &- 64)) != 0
      }
    }
  }

  struct Fragment: PercentEncodeSet {
    @inline(__always)
    static func shouldEscape(character: ASCII) -> Bool {
      if C0.shouldEscape(character: character) { return true }
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b01010000_00000000_00000000_00000101_00000000_00000000_00000000_00000000
      let hi: UInt64 = 0b00000000_00000000_00000000_00000001_00000000_00000000_00000000_00000000
      if character.codePoint < 64 {
        return lo & (1 &<< character.codePoint) != 0
      } else {
        return hi & (1 &<< (character.codePoint &- 64)) != 0
      }
    }
  }

  struct Query_NotSpecial: PercentEncodeSet {
    @inline(__always)
    static func shouldEscape(character: ASCII) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b01010000_00000000_00000000_00001101_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000
      if character.codePoint < 64 {
        return lo & (1 &<< character.codePoint) != 0
      } else {
        return hi & (1 &<< (character.codePoint &- 64)) != 0
      }
    }
  }

  struct Query_Special: PercentEncodeSet {
    @inline(__always)
    static func shouldEscape(character: ASCII) -> Bool {
      if Query_NotSpecial.shouldEscape(character: character) { return true }
      return character == .apostrophe
    }
  }

  struct Path: PercentEncodeSet {
    @inline(__always)
    static func shouldEscape(character: ASCII) -> Bool {
      if Fragment.shouldEscape(character: character) { return true }
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b10000000_00000000_00000000_00001000_00000000_00000000_00000000_00000000
      let hi: UInt64 = 0b00101000_00000000_00000000_00000000_00000000_00000000_00000000_00000000
      if character.codePoint < 64 {
        return lo & (1 &<< character.codePoint) != 0
      } else {
        return hi & (1 &<< (character.codePoint &- 64)) != 0
      }
    }
  }

  struct UserInfo: PercentEncodeSet {
    @inline(__always)
    static func shouldEscape(character: ASCII) -> Bool {
      if Path.shouldEscape(character: character) { return true }
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b00101100_00000000_10000000_00000000_00000000_00000000_00000000_00000000
      let hi: UInt64 = 0b00010000_00000000_00000000_00000000_01111000_00000000_00000000_00000001
      if character.codePoint < 64 {
        return lo & (1 &<< character.codePoint) != 0
      } else {
        return hi & (1 &<< (character.codePoint &- 64)) != 0
      }
    }
  }

  struct FormEncoded: PercentEncodeSet {
    static func shouldEscape(character: ASCII) -> Bool {
      // Do not percent-escape spaces because we 'plus-escape' them instead.
      if character == .space { return false }
      switch character {
      case _ where character.isAlphaNumeric: return false
      case .asterisk, .minus, .period, .underscore: return false
      default: return true
      }
    }
    static func substitute(for character: ASCII) -> ASCII {
      return character == .space ? .plus : character
    }
    static func unsubstitute(character: ASCII) -> ASCII {
      return character == .plus ? .space : character
    }
  }
}
