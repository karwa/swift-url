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
          processChunk(UnsafeBufferPointer(start: chunkBuffer.baseAddress, count: i))
          i = 0
        }
        if let asciiChar = ASCII(byte), encodeSet.shouldEscape(character: asciiChar) == false {
          chunkBuffer[i] = encodeSet.substitute(for: asciiChar).codePoint
          i &+= 1
          continue
        }
        _escape(
          byte: byte,
          into: UnsafeMutableBufferPointer(start: chunkBuffer.baseAddress.unsafelyUnwrapped.advanced(by: i), count: 3)
        )
        i &+= 3
        didEncode = true
      }
      // Flush the buffer.
      processChunk(UnsafeBufferPointer(start: chunkBuffer.baseAddress, count: i))
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
            UnsafeBufferPointer(start: chunkBuffer.baseAddress.unsafelyUnwrapped.advanced(by: i), count: chunkSize &- i)
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
          into: UnsafeMutableBufferPointer(start: chunkBuffer.baseAddress.unsafelyUnwrapped.advanced(by: i), count: 3)
        )
        didEncode = true
      }
      // Flush the buffer.
      processChunk(
        UnsafeBufferPointer(start: chunkBuffer.baseAddress.unsafelyUnwrapped.advanced(by: i), count: chunkSize &- i)
      )
      return didEncode
    }
  }

  @inline(__always)
  private static func _escape(byte: UInt8, into output: UnsafeMutableBufferPointer<UInt8>) {
    assert(output.count >= 3)
    output[0] = ASCII.percentSign.codePoint
    output[1] = ASCII.getHexDigit_upper(byte >> 4).codePoint
    output[2] = ASCII.getHexDigit_upper(byte).codePoint
  }
}

// MARK: - Decoding.

extension LazyCollectionProtocol where Element == UInt8 {

  /// Returns a `Collection` which lazily decodes ASCII byte sequences of the form "%ZZ", where `ZZ` are 2 hex digits, in to bytes with the value `0xZZ`.
  /// Non-ASCII bytes and those which do not match the percent-escaping pattern are left unchanged.
  ///
  /// This is a `PercentEncodeSet`-neutral decoder. If the byte sequence's encoding set may have substitutions, use `percentDecoded(using:)` instead.
  ///
  var percentDecoded: LazilyPercentDecoded<Self> {
    return LazilyPercentDecoded(base: self)
  }

  typealias LazilyPercentDecodedWithSubstitutions = LazilyPercentDecoded<
    LazyMapSequence<LazySequence<Self.Elements>.Elements, UInt8>
  >

  /// Returns a `Collection` which lazily decodes ASCII byte sequences of the form "%ZZ", where `ZZ` are 2 hex digits, in to bytes with the value `0xZZ`.
  /// Non-ASCII bytes and those which do not match the percent-escaping pattern are left unchanged.
  ///
  /// This decoder is suitable to use if the encode-set may include substitutions.
  ///
  func percentDecoded<EncodeSet: PercentEncodeSet>(
    using encodeSet: EncodeSet.Type
  ) -> LazilyPercentDecodedWithSubstitutions {
    return self.lazy.map { byte in
      return ASCII(byte).map(encodeSet.unsubstitute)?.codePoint ?? byte
    }.percentDecoded
  }
}

struct LazilyPercentDecoded<Base: Collection>: Collection, LazyCollectionProtocol where Base.Element == UInt8 {
  typealias Element = UInt8

  let base: Base
  let startIndex: Index

  fileprivate init(base: Base) {
    self.base = base
    var start = Index(withoutReadingValue: base.startIndex)
    start.advance(in: base)
    self.startIndex = start
  }

  struct Index: Comparable {
    var range: Range<Base.Index>
    var decodedValue: UInt8

    init(withoutReadingValue position: Base.Index) {
      self.range = Range(uncheckedBounds: (position, position))
      self.decodedValue = 0
    }

    mutating func advance(in base: Base) {

      // If the current value is or ends at endIndex, the next index _is_ endIndex.
      guard range.upperBound != base.endIndex else {
        self.range = Range(uncheckedBounds: (range.upperBound, range.upperBound))
        self.decodedValue = 0
        return
      }
      // Read the next byte. If it is a % sign, attempt to consume the next two bytes and decode the value.
      let byte0 = base[range.upperBound]
      let byte1Index = base.index(after: range.upperBound)
      guard _slowPath(byte0 == ASCII.percentSign.codePoint) else {
        self.decodedValue = byte0
        self.range = Range(uncheckedBounds: (range.upperBound, byte1Index))
        return
      }
      var tail = base.suffix(from: byte1Index)
      guard let byte1 = tail.popFirst(), let decodedByte1 = ASCII(byte1).map(ASCII.parseHexDigit(ascii:)),
        decodedByte1 != ASCII.parse_NotFound,
        let byte2 = tail.popFirst(), let decodedByte2 = ASCII(byte2).map(ASCII.parseHexDigit(ascii:)),
        decodedByte2 != ASCII.parse_NotFound
      else {
        self.decodedValue = byte0
        self.range = Range(uncheckedBounds: (range.upperBound, byte1Index))
        return
      }
      self.decodedValue = (decodedByte1 &* 16) &+ (decodedByte2)
      self.range = Range(uncheckedBounds: (range.upperBound, tail.startIndex))
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
      return lhs.range.lowerBound == rhs.range.lowerBound
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
      return lhs.range.lowerBound < rhs.range.lowerBound
    }
  }

  var endIndex: Index {
    return Index(withoutReadingValue: base.endIndex)
  }

  func index(after i: Index) -> Index {
    var tmp = i
    formIndex(after: &tmp)
    return tmp
  }

  func formIndex(after i: inout Index) {
    i.advance(in: base)
  }

  subscript(position: Index) -> Element {
    return position.decodedValue
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
