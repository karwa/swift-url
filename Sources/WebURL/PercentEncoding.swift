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
/// Conforming types should be exposed as computed properties of `PercentEncodeSet`, and encode-sets which substitute characters
/// should additionally be added to `PercentDecodeSet`. These properties are never called, and only used to create a concise,
/// `KeyPath`-based generic interface.
///
/// ```swift
/// struct MyEncodeSet: PercentEncodeSetProtocol {
///   // ...
/// }
///
/// extension PercentEncodeSet {
///   var myEncodeSet: MyEncodeSet.Type { fatalError("Do not call") }
/// }
///
/// "a string".percentEncoded(as: \.myEncodeSet)
/// "a%20string".percentDecoded(from: \.percentEncodedOnly)
/// ```
///
public protocol PercentEncodeSetProtocol {

  /// Whether or not the given ASCII `codePoint` should be percent-encoded.
  ///
  static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool

  /// An optional function which allows the encode-set to replace a non-percent-encoded source codepoint with another codepoint.
  ///
  /// For example, the `application/x-www-form-urlencoded` encoding does not percent-encode ASCII spaces (`0x20`) as "%20",
  /// instead replacing them with a "+" (`0x2B`). An implementation of this encoding would look like this:
  ///
  /// ```swift
  /// struct FormEncodeSet: PercentEncodeSetProtocol {
  ///
  ///   static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
  ///     if codePoint == 0x20 { return false } // do not percent-encode spaces, substitute instead.
  ///     if codePoint == 0x2B { return true } // percent-encode "+"s in the source.
  ///     // other codepoints...
  ///   }
  ///
  ///   static func substitute(ascii codePoint: UInt8) -> UInt8? {
  ///     if codePoint == 0x20 { return 0x2B } // Substitute spaces with "+".
  ///     return nil
  ///   }
  ///
  ///   static func unsubstitute(ascii codePoint: UInt8) -> UInt8? {
  ///     if codePoint == 0x2B { return 0x20 } // Unsubstitute "+" to space.
  ///     return nil
  ///   }
  /// }
  /// ```
  ///
  /// The ASCII percent sign (`0x25`) and upper- and lowercase alpha characters (`0x41...0x5A` and `0x61...0x7A`) must not be substituted.
  /// Conforming types must also implement the reverse substitution function, `unsubstitute(ascii:)`, and should ensure that any codepoints emitted
  /// as substitutes are percent-encoded by `shouldPercentEncode`.
  ///
  /// - parameters:
  ///   - codePoint: The ASCII codepoint from the source. Always in the range `0...127`.
  /// - returns: The codepoint to emit instead of `codePoint`, or `nil` if the codepoint should not be substituted.
  ///            If not `nil`, must always be in the range `0...127`
  ///
  static func substitute(ascii codePoint: UInt8) -> UInt8?

  /// An optional function which recovers a non-percent-decoded codepoint from its substituted value.
  ///
  /// For example, the `application/x-www-form-urlencoded` encoding does not percent-encode ASCII spaces (`0x20`) as "%20",
  /// instead replacing them with a "+" (`0x2B`). An implementation of this encoding would look like this:
  ///
  /// ```swift
  /// struct FormEncodeSet: PercentEncodeSetProtocol {
  ///
  ///   static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
  ///     if codePoint == 0x20 { return false } // do not percent-encode spaces, substitute instead.
  ///     if codePoint == 0x2B { return true } // percent-encode "+"s in the source.
  ///     // other codepoints...
  ///   }
  ///
  ///   static func substitute(ascii codePoint: UInt8) -> UInt8? {
  ///     if codePoint == 0x20 { return 0x2B } // Substitute spaces with "+".
  ///     return nil
  ///   }
  ///
  ///   static func unsubstitute(ascii codePoint: UInt8) -> UInt8? {
  ///     if codePoint == 0x2B { return 0x20 } // Unsubstitute "+" to space.
  ///     return nil
  ///   }
  /// }
  /// ```
  ///
  /// The ASCII percent sign (`0x25`) and upper- and lowercase alpha characters (`0x41...0x5A` and `0x61...0x7A`) must not be substituted.
  /// Conforming types must also implement the substitution function, `substitute(ascii:)`, and should ensure that any codepoints emitted
  /// as substitutes are percent-encoded by `shouldPercentEncode`.
  ///
  /// Codepoints emitted by this function are not recognised as being part of a percent-encoded byte sequence, and values decoded from percent-encoded
  /// byte sequences are assumed not to have been substituted.
  ///
  /// - parameters:
  ///   - codePoint: The possibly-substituted ASCII codepoint from an encoded string. Always in the range `0...127`.
  /// - returns: The codepoint to emit instead of `codePoint`, or `nil` if the codepoint was not substituted by this encode-set.
  ///            If not `nil`, must always be in the range `0...127`
  ///
  static func unsubstitute(ascii codePoint: UInt8) -> UInt8?
}

extension PercentEncodeSetProtocol {

  @inlinable @inline(__always)
  public static func substitute(ascii codePoint: UInt8) -> UInt8? {
    nil
  }

  @inlinable @inline(__always)
  public static func unsubstitute(ascii codePoint: UInt8) -> UInt8? {
    nil
  }
}


// --------------------------------------------
// MARK: - Encoding
// --------------------------------------------


extension LazyCollectionProtocol where Element == UInt8 {

  /// Returns a collection of ASCII codepoints formed by percent-encoding this collection's elements using the given `EncodeSet`.
  /// For instance, the byte 200 (0xC8) becomes the 3-byte ASCII string "%C8" (0x25, 0x43, 0x38).
  ///
  @inlinable @inline(__always)
  public func percentEncoded<EncodeSet>(
    as: KeyPath<PercentEncodeSet, EncodeSet.Type>
  ) -> LazilyPercentEncodedUTF8<Elements, EncodeSet> {
    LazilyPercentEncodedUTF8(source: elements, encodeSet: EncodeSet.self)
  }
}

/// A `Collection` which percent-encodes elements from its `Source` on-demand using a given `EncodeSet`.
///
/// This collection only _adds_ percent-encoding or substitutions; it does not decode any pre-existing encoded or substituted bytes.
/// Only encode-sets which include the percent character (0x25) will preserve their source contents exactly when decoded.
///
/// Percent encoding is used to escape arbitrary bytes using a limited set of ASCII code-points permitted by the encode-set.
/// Some encode-sets perform additional substitutions (e.g. replacing spaces with "+"), so users should take care to decode
/// these sequences using the same encode-set.
///
/// The elements of this collection are guaranteed to be ASCII code-units, and hence valid UTF-8.
///
public struct LazilyPercentEncodedUTF8<Source, EncodeSet>: Collection, LazyCollectionProtocol
where Source: Collection, Source.Element == UInt8, EncodeSet: PercentEncodeSetProtocol {

  @usableFromInline
  internal let source: Source

  public let startIndex: Index

  @inlinable
  internal init(source: Source, encodeSet: EncodeSet.Type) {
    self.source = source
    let sourceStartIndex = source.startIndex
    if sourceStartIndex < source.endIndex {
      self.startIndex = Index(sourceIndex: sourceStartIndex, sourceByte: source[sourceStartIndex])
    } else {
      self.startIndex = Index(endIndex: sourceStartIndex)
    }
  }

  public struct Index: Equatable, Comparable {

    @usableFromInline
    internal var sourceIndex: Source.Index

    @usableFromInline
    internal var encodedByteOffset: UInt8

    @usableFromInline
    internal var encodedByte: _EncodedByte

    @inlinable
    internal init(sourceIndex: Source.Index, sourceByte: UInt8) {
      self.sourceIndex = sourceIndex
      self.encodedByteOffset = 0
      self.encodedByte = _EncodedByte(byte: sourceByte, encodeSet: EncodeSet.self)
    }

    @inlinable
    internal init(endIndex: Source.Index) {
      self.sourceIndex = endIndex
      self.encodedByteOffset = 0
      self.encodedByte = _EncodedByte(_null: ())
    }

    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
      // This uses 3 comparisons rather than 2, but generates smaller, faster code,
      // because most of the time we're testing that an index is < endIndex.
      if lhs.sourceIndex < rhs.sourceIndex {
        return true
      }
      return lhs.sourceIndex == rhs.sourceIndex && lhs.encodedByteOffset < rhs.encodedByteOffset
    }

    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.sourceIndex == rhs.sourceIndex && lhs.encodedByteOffset == rhs.encodedByteOffset
    }
  }

  @inlinable
  public var endIndex: Index {
    Index(endIndex: source.endIndex)
  }

  @inlinable
  public var isEmpty: Bool {
    source.isEmpty
  }

  @inlinable
  public var underestimatedCount: Int {
    source.underestimatedCount
  }

  @inlinable
  public subscript(position: Index) -> UInt8 {
    position.encodedByte[position.encodedByteOffset]
  }

  @inlinable
  public func index(after i: Index) -> Index {
    var copy = i
    formIndex(after: &copy)
    return copy
  }

  @inlinable
  public func formIndex(after i: inout Index) {
    i.encodedByteOffset &+= 1
    if i.encodedByteOffset < i.encodedByte.count {
      return
    }
    i.encodedByteOffset = 0
    guard i.sourceIndex < source.endIndex else {
      return
    }
    source.formIndex(after: &i.sourceIndex)
    guard i.sourceIndex < source.endIndex else {
      return
    }
    i.encodedByte = _EncodedByte(byte: source[i.sourceIndex], encodeSet: EncodeSet.self)
  }
}

extension LazilyPercentEncodedUTF8: BidirectionalCollection where Source: BidirectionalCollection {

  @inlinable
  public func index(before i: Index) -> Index {
    var copy = i
    formIndex(before: &copy)
    return copy
  }

  @inlinable
  public func formIndex(before i: inout Index) {
    guard i.encodedByteOffset == 0 else {
      i.encodedByteOffset &-= 1
      return
    }
    guard i.sourceIndex > startIndex.sourceIndex else {
      return
    }
    source.formIndex(before: &i.sourceIndex)
    i.encodedByte = _EncodedByte(byte: source[i.sourceIndex], encodeSet: EncodeSet.self)
    i.encodedByteOffset = i.encodedByte.count &- 1
  }
}

/// A byte which has been encoded by a `PercentEncodeSet`.
///
@usableFromInline
internal struct _EncodedByte {

  @usableFromInline
  internal let byte: UInt8

  @usableFromInline
  internal let count: UInt8

  @usableFromInline
  internal let isEncodedOrSubstituted: Bool

  @inlinable
  internal init<EncodeSet>(byte: UInt8, encodeSet: EncodeSet.Type) where EncodeSet: PercentEncodeSetProtocol {
    if let asciiChar = ASCII(byte), EncodeSet.shouldPercentEncode(ascii: asciiChar.codePoint) == false {
      self.count = 1
      if let substitute = EncodeSet.substitute(ascii: asciiChar.codePoint) {
        self.byte = substitute & 0b01111_1111  // Ensure the substitute is ASCII.
        self.isEncodedOrSubstituted = true
      } else {
        self.byte = byte
        self.isEncodedOrSubstituted = false
      }
    } else {
      self.byte = byte
      self.count = 3
      self.isEncodedOrSubstituted = true
    }
  }

  @inlinable
  internal init(_null: Void) {
    self.byte = 0
    self.count = 1
    self.isEncodedOrSubstituted = false
  }

  @inlinable
  internal subscript(position: UInt8) -> UInt8 {
    if count == 1 {
      assert(position == 0, "Invalid index")
      return byte
    } else {
      assert((0..<3).contains(position), "Invalid index")
      return percentEncodedCharacter(byte, offset: position)
    }
  }
}

extension LazilyPercentEncodedUTF8 {

  /// Calls `writer` for every byte in the source collection, providing it with a pointer
  /// from which it may copy entire percent-encoded characters (1 or 3 bytes), and returning
  /// whether or not any bytes were actually encoded or substituted.
  ///
  /// This is used when writing a URL string, as we want to not only write the percent-encoded contents,
  /// but determine whether or not percent-encoding was even necessary, in a single pass.
  ///
  @inlinable
  internal func write(to writer: (UnsafeBufferPointer<UInt8>) -> Void) -> Bool {
    var didEncode = false
    var i = startIndex
    while i.sourceIndex < source.endIndex {
      i.encodedByte = _EncodedByte(byte: source[i.sourceIndex], encodeSet: EncodeSet.self)
      if i.encodedByte.count == 1 {
        withUnsafePointer(to: i.encodedByte.byte) {
          writer(UnsafeBufferPointer(start: $0, count: 1))
        }
        didEncode = didEncode || i.encodedByte.isEncodedOrSubstituted
      } else {
        withPercentEncodedString(i.encodedByte.byte) { writer($0) }
        didEncode = true
      }
      source.formIndex(after: &i.sourceIndex)
    }
    return didEncode
  }

  /// Returns the total length of the encoded UTF-8 bytes, calculated without considering overflow,
  /// and whether or not any code-units were altered by the `EncodeSet`.
  ///
  /// This is useful for determining the expected allocation size required to hold the contents,
  /// but since it does not consider overflow, it will be inaccurate in the case that the collection yields more than `Int.max` elements.
  ///
  /// If not exact, this value should always be an underestimate; never negative,
  /// and (assuming the source collection yields the same sequence of elements), never an overestimate.
  /// The latter point means that writers should still be wary - even an invalid collection which yields different values every time must
  /// never cause memory safety to be violated.
  ///
  @inlinable @inline(never)
  internal var unsafeEncodedLength: (count: UInt, needsEncoding: Bool) {
    var count: UInt = 0
    let needsEncoding = write { count &+= UInt($0.count) }
    return (count, needsEncoding)
  }
}

// Eager encoding to String.

extension Collection where Element == UInt8 {

  /// Interpets this collection's elements as UTF-8 code-units, and returns a `String` formed by encoding them using the given `EncodeSet`.
  ///
  /// - seealso: `StringProtocol.percentEncoded(as:)`
  ///
  @inlinable @inline(__always)
  public func percentEncodedString<EncodeSet: PercentEncodeSetProtocol>(
    as encodeSet: KeyPath<PercentEncodeSet, EncodeSet.Type>
  ) -> String {
    withContiguousStorageIfAvailable {
      String(discontiguousUTF8: $0.boundsChecked.lazy.percentEncoded(as: encodeSet))
    } ?? String(discontiguousUTF8: self.lazy.percentEncoded(as: encodeSet))
  }

  /// Interpets this collection's elements as UTF-8 code-units, and returns a `String` formed by encoding them using the `\.component` encoding-set.
  ///
  /// - seealso: `StringProtocol.urlComponentEncoded`
  ///
  @inlinable
  public var urlComponentEncodedString: String {
    percentEncodedString(as: \.component)
  }

  /// Interpets this collection's elements as UTF-8 code-units, and returns a `String` formed by encoding them using the
  /// `application/x-www-form-urlencoded` (`\.form`) encoding-set.
  ///
  /// - seealso: `StringProtocol.urlFormEncoded`
  ///
  @inlinable
  public var urlFormEncodedString: String {
    percentEncodedString(as: \.form)
  }
}

extension StringProtocol {

  /// Returns a copy of this string, encoded using the given `EncodeSet`.
  ///
  /// This function only _adds_ percent-encoding or substitutions as required by `EncodeSet`; it does not decode any percent-encoded or substituted characters
  /// already contained in the string.
  ///
  /// Percent-encoding transforms strings containing arbitrary Unicode characters to ones containing a limited set of ASCII code-points permitted by
  /// the `EncodeSet`. If the `EncodeSet` performs substitutions, users should take care to decode the contents using the same `EncodeSet`.
  ///
  /// ```swift
  /// "hello, world!".percentEncoded(as: \.userInfo) // hello,%20world!
  /// "/usr/bin/swift".percentEncoded(as: \.component) // %2Fusr%2Fbin%2Fswift
  /// "got en%63oders?".percentEncoded(as: \.userInfo) // got%20en%63oders%3F
  /// "king of the 🦆s".percentEncoded(as: \.form) // king+of+the+%F0%9F%A6%86s
  /// ```
  ///
  @inlinable @inline(__always)
  public func percentEncoded<EncodeSet: PercentEncodeSetProtocol>(
    as encodeSet: KeyPath<PercentEncodeSet, EncodeSet.Type>
  ) -> String {
    utf8.percentEncodedString(as: encodeSet)
  }

  /// Returns a copy of this string, encoded using the `\.component` encoding-set.
  ///
  /// The `\.component` encoding-set is suitable for encoding strings so they may be embedded in a URL's `path`, `query`, `fragment`,
  /// or in the names of opaque `host`s. It does not perform substitutions.
  ///
  /// The URL standard confirms that encoding a string using the `\.component` set gives identical results
  /// to JavaScript's `encodeURIComponent()` function.
  ///
  /// ```swift
  /// "hello, world!".urlComponentEncoded // hello%2C%20world!
  /// "/usr/bin/swift".urlComponentEncoded // %2Fusr%2Fbin%2Fswift
  /// "😎".urlComponentEncoded // %F0%9F%98%8E
  /// ```
  ///
  @inlinable
  public var urlComponentEncoded: String {
    utf8.urlComponentEncodedString
  }

  /// Returns a copy of this string, encoded using the `application/x-www-form-urlencoded` (`\.form`) encoding-set.
  ///
  /// To create an `application/x-www-form-urlencoded` key-value pair string from a collection of keys and values, encode each key and value, and join
  /// the results using the format: `encoded-key-1=encoded-value-1&encoded-key-2=encoded-value-2...`. For example:
  ///
  /// ```swift
  /// let myKVPs: KeyValuePairs = ["favourite pet": "🦆, of course", "favourite foods": "🍎 & 🍦" ]
  /// let form = myKVPs.map { key, value in "\(key.urlFormEncoded)=\(value.urlFormEncoded)" }
  ///                  .joined(separator: "&")
  /// print(form) // favourite+pet=%F0%9F%A6%86%2C+of+course&favourite+foods=%F0%9F%8D%8E+%26+%F0%9F%8D%A6
  /// ```
  ///
  /// This encoding-set performs substitutions. Users should take care to also decode the resulting strings using the `application/x-www-form-urlencoded`
  /// decoding-set.
  ///
  @inlinable
  public var urlFormEncoded: String {
    utf8.urlFormEncodedString
  }
}


// --------------------------------------------
// MARK: - Decoding
// --------------------------------------------


extension LazyCollectionProtocol where Element == UInt8 {

  /// Interprets this collection's elements as UTF-8 code-units, and returns a collection of bytes whose elements are computed lazily
  /// by decoding all percent-encoded code-unit sequences and using `EncodeSet` to restore substituted code-units.
  ///
  /// If no code-points were substituted when this collection's contents were encoded, `\.percentEncodedOnly` may be used to only remove percent-encoding.
  ///
  /// - important: Users should beware that percent-encoding has frequently been used by attackers to smuggle malicious inputs
  ///              (e.g. extra path components which lead to sensitive data when used as a relative path, ASCII NULL bytes, or SQL injection),
  ///              sometimes under multiple layers of encoding. Users to be careful not to over-decode their strings, and every time a string
  ///              is percent-decoded, the result must be considered to be **entirely unvalidated**, even if the source contents were previously validated.
  ///
  @inlinable @inline(__always)
  public func percentDecodedUTF8<EncodeSet>(
    from: KeyPath<PercentDecodeSet, EncodeSet.Type>
  ) -> LazilyPercentDecodedUTF8<Elements, EncodeSet> {
    LazilyPercentDecodedUTF8(source: elements)
  }

  /// Interprets this collection's elements as UTF-8 code-units, and returns a collection of bytes whose elements are computed lazily
  /// by decoding all percent-encoded code-unit sequences.
  ///
  /// This is equivalent to calling `percentDecodedUTF8(from: \.percentEncodedOnly)`. If this collection's contents were encoded
  /// with substitutions (e.g. using form-encoding), use `percentDecodedUTF8(from:)` instead, providing a `PercentDecodeSet` which is able
  /// to reverse those substitutions.
  ///
  /// - important: Users should beware that percent-encoding has frequently been used by attackers to smuggle malicious inputs
  ///              (e.g. extra path components which lead to sensitive data when used as a relative path, ASCII NULL bytes, or SQL injection),
  ///              sometimes under multiple layers of encoding. Users to be careful not to over-decode their strings, and every time a string
  ///              is percent-decoded, the result must be considered to be **entirely unvalidated**, even if the source contents were previously validated.
  ///
  @inlinable
  public var percentDecodedUTF8: LazilyPercentDecodedUTF8WithoutSubstitutions<Elements> {
    percentDecodedUTF8(from: \.percentEncodedOnly)
  }
}

/// A `Collection` which lazily replaces all percent-encoded UTF8 code-units from its `Source` with their decoded code-units.
/// It does not reverse any substitutions that may be a part of how `Source` is encoded.
///
/// Percent decoding transforms certain sequences of ASCII code-points to arbitrary byte values ("%AB" to the byte 0xAB).
///
/// - important: Users should beware that percent-encoding has frequently been used by attackers to smuggle malicious inputs
///              (e.g. extra path components which lead to sensitive data when used as a relative path, ASCII NULL bytes, or SQL injection),
///              sometimes under multiple layers of encoding. Users to be careful not to over-decode their strings, and every time a string
///              is percent-decoded, the result must be considered to be **entirely unvalidated**, even if the source contents were previously validated.
///
public typealias LazilyPercentDecodedUTF8WithoutSubstitutions<Source> =
  LazilyPercentDecodedUTF8<Source, PercentEncodeSet._Passthrough> where Source: Collection, Source.Element == UInt8

/// A `Collection` which lazily replaces all percent-encoded UTF8 code-units from its `Source` with their decoded code-units,
/// and reverses substitutions of other code-units performed by `EncodeSet`.
///
/// If the encode-set does not perform substitutions, `PercentEncodeSet._Passthrough` can be used to only remove percent-encoding.
///
/// - important: Users should beware that percent-encoding has frequently been used by attackers to smuggle malicious inputs
///              (e.g. extra path components which lead to sensitive data when used as a relative path, ASCII NULL bytes, or SQL injection),
///              sometimes under multiple layers of encoding. Users to be careful not to over-decode their strings, and every time a string
///              is percent-decoded, the result must be considered to be **entirely unvalidated**, even if the source contents were previously validated.
///
public struct LazilyPercentDecodedUTF8<Source, EncodeSet>: Collection, LazyCollectionProtocol
where Source: Collection, Source.Element == UInt8, EncodeSet: PercentEncodeSetProtocol {

  @usableFromInline
  internal let source: Source

  public let startIndex: Index

  @inlinable
  internal init(source: Source) {
    self.source = source
    self.startIndex = Index(at: source.startIndex, in: source)
  }

  public typealias Element = UInt8

  @inlinable
  public var endIndex: Index {
    Index(_endIndex: source.endIndex)
  }

  @inlinable
  public var isEmpty: Bool {
    source.isEmpty
  }

  @inlinable
  public subscript(position: Index) -> Element {
    assert(position != endIndex, "Attempt to read element at endIndex")
    return position.decodedValue
  }

  @inlinable
  public func index(after i: Index) -> Index {
    assert(i != endIndex, "Attempt to advance endIndex")
    // Does not trap in release mode - just keeps returning 'endIndex'.
    return Index(at: i.range.upperBound, in: source)
  }

  @inlinable
  public func formIndex(after i: inout Index) {
    assert(i != endIndex, "Attempt to advance endIndex")
    // Does not trap in release mode - just keeps returning 'endIndex'.
    i = Index(at: i.range.upperBound, in: source)
  }

  public struct Index: Comparable {

    /// Always either 0, 1, or 3 bytes from the source:
    /// - 0 bytes: `endIndex` only.
    /// - 1 byte: non-encoded or substituted byte.
    /// - 3 bytes: percent-encoded byte.
    ///
    @usableFromInline
    internal let range: Range<Source.Index>

    @usableFromInline
    internal let decodedValue: UInt8

    @usableFromInline
    internal let isDecoded: Bool

    /// Creates an index referencing the given source collection's `endIndex`.
    /// This index's `decodedValue` is always 0. It is meaningless and should not be read.
    ///
    @inlinable
    internal init(_endIndex i: Source.Index) {
      self.range = Range(uncheckedBounds: (i, i))
      self.decodedValue = 0
      self.isDecoded = false
    }

    @inlinable @inline(__always)
    internal init(_unsubstituting value: UInt8, range: Range<Source.Index>) {
      self.range = range
      if let unsub = ASCII(value).flatMap({ EncodeSet.unsubstitute(ascii: $0.codePoint) }) {
        self.decodedValue = unsub
        self.isDecoded = true
      } else {
        self.decodedValue = value
        self.isDecoded = false
      }
    }

    /// Decodes the octet starting at the given index in the given `source` collection.
    /// The index's successor may be obtained by creating another index starting at the index's `range.upperBound`.
    ///
    /// The index which starts at `source.endIndex` is also given by `Index(endIndexOf:)`.
    ///
    @inlinable
    internal init(at i: Source.Index, in source: Source) {
      // The successor of endIndex is endIndex.
      guard i < source.endIndex else {
        self = .init(_endIndex: i)
        return
      }

      let byte0 = source[i]
      let byte1Index = source.index(after: i)
      guard byte0 == ASCII.percentSign.codePoint else {
        self = Self(_unsubstituting: byte0, range: Range(uncheckedBounds: (i, byte1Index)))
        return
      }
      var cursor = byte1Index
      guard cursor < source.endIndex, let decodedByte1 = ASCII(source[cursor])?.hexNumberValue else {
        self.range = Range(uncheckedBounds: (i, byte1Index))
        self.decodedValue = byte0  // Percent-sign, should never be substituted.
        self.isDecoded = false
        return
      }
      source.formIndex(after: &cursor)
      guard cursor < source.endIndex, let decodedByte2 = ASCII(source[cursor])?.hexNumberValue else {
        self.range = Range(uncheckedBounds: (i, byte1Index))
        self.decodedValue = byte0  // Percent-sign, should never be substituted.
        self.isDecoded = false
        return
      }
      source.formIndex(after: &cursor)

      self.range = Range(uncheckedBounds: (i, cursor))
      self.decodedValue = (decodedByte1 &* 16) &+ (decodedByte2)
      self.isDecoded = true
    }

    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.range.lowerBound == rhs.range.lowerBound
    }

    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.range.lowerBound < rhs.range.lowerBound
    }

    @inlinable
    public static func > (lhs: Self, rhs: Self) -> Bool {
      lhs.range.lowerBound > rhs.range.lowerBound
    }
  }
}

extension LazilyPercentDecodedUTF8.Index where Source: BidirectionalCollection {

  /// Decodes the octet whose final code-unit precedes the given index in the given `source` collection.
  /// The index's predeccessor may be obtained by creating another index ending at the index's `range.lowerBound`.
  ///
  @inlinable
  internal init(endingAt i: Source.Index, in source: Source, startIndex: Self) {
    // The predecessor of startIndex is startIndex.
    guard i > source.startIndex else {
      self = startIndex
      return
    }

    let byte2Index = source.index(before: i)
    let byte2 = source[byte2Index]

    guard
      let byte0Index = source.index(byte2Index, offsetBy: -2, limitedBy: source.startIndex),
      source[byte0Index] == ASCII.percentSign.codePoint
    else {
      self = Self(_unsubstituting: byte2, range: Range(uncheckedBounds: (byte2Index, i)))
      return
    }
    guard
      let decodedByte1 = ASCII(source[source.index(before: byte2Index)])?.hexNumberValue,
      let decodedByte2 = ASCII(byte2)?.hexNumberValue
    else {
      self = Self(_unsubstituting: byte2, range: Range(uncheckedBounds: (byte2Index, i)))
      return
    }
    self.range = Range(uncheckedBounds: (byte0Index, i))
    self.decodedValue = (decodedByte1 &* 16) &+ (decodedByte2)
    self.isDecoded = true
  }
}

extension LazilyPercentDecodedUTF8: BidirectionalCollection where Source: BidirectionalCollection {

  @inlinable
  public func index(before i: Index) -> Index {
    assert(i != startIndex, "Cannot decrement startIndex")
    // Does not trap in release mode - just keeps returning 'startIndex'.
    return Index(endingAt: i.range.lowerBound, in: source, startIndex: startIndex)
  }

  @inlinable
  public func formIndex(before i: inout Index) {
    assert(i != startIndex, "Cannot decrement startIndex")
    // Does not trap in release mode - just keeps returning 'startIndex'.
    i = Index(endingAt: i.range.lowerBound, in: source, startIndex: startIndex)
  }
}

// Eager decoding to String.

extension Collection where Element == UInt8 {

  /// Interprets this collection's elements as UTF-8 code-units, and returns a string formed by decoding all percent-encoded code-unit sequences and
  /// using `EncodeSet` to restore substituted code-units.
  ///
  /// If no code-points were substituted when this collection's contents were encoded, `\.percentEncodedOnly` may be used to only remove percent-encoding.
  ///
  /// - seealso: `StringProtocol.percentDecoded(from:)`
  /// - important: Users should beware that percent-encoding has frequently been used by attackers to smuggle malicious inputs
  ///              (e.g. extra path components which lead to sensitive data when used as a relative path, ASCII NULL bytes, or SQL injection),
  ///              sometimes under multiple layers of encoding. Users to be careful not to over-decode their strings, and every time a string
  ///              is percent-decoded, the result must be considered to be **entirely unvalidated**, even if the source contents were previously validated.
  ///
  @inlinable @inline(__always)
  public func percentDecodedString<EncodeSet>(
    from decodeSet: KeyPath<PercentDecodeSet, EncodeSet.Type>
  ) -> String where EncodeSet: PercentEncodeSetProtocol {
    withContiguousStorageIfAvailable {
      String(discontiguousUTF8: $0.boundsChecked.lazy.percentDecodedUTF8(from: decodeSet))
    } ?? String(discontiguousUTF8: self.lazy.percentDecodedUTF8(from: decodeSet))
  }

  /// Interprets this collection's elements as UTF-8 code-units, and returns a string formed by decoding all percent-encoded code-unit sequences.
  ///
  /// This is equivalent to calling `percentDecodedString(from: \.percentEncodedOnly)`. If this collection's contents were encoded
  /// with substitutions (e.g. form-encoding), use `percentDecodedString(from:)` instead, providing a `PercentDecodeSet` which is able to
  /// reverse those substitutions.
  ///
  /// - seealso: `StringProtocol.percentDecoded`
  /// - important: Users should beware that percent-encoding has frequently been used by attackers to smuggle malicious inputs
  ///              (e.g. extra path components which lead to sensitive data when used as a relative path, ASCII NULL bytes, or SQL injection),
  ///              sometimes under multiple layers of encoding. Users to be careful not to over-decode their strings, and every time a string
  ///              is percent-decoded, the result must be considered to be **entirely unvalidated**, even if the source contents were previously validated.
  ///
  @inlinable
  public var percentDecodedString: String {
    percentDecodedString(from: \.percentEncodedOnly)
  }

  /// Interprets this collection's elements as UTF-8 code-units, and returns a string formed by decoding all percent-encoded code-unit sequences and
  /// reversing substitutions made by the `application/x-www-form-urlencoded` encode-set.
  ///
  /// This is equivalent to callling `percentDecodedString(from: \.form)`.
  ///
  /// - seealso: `StringProtocol.urlFormDecoded`
  /// - important: Users should beware that percent-encoding has frequently been used by attackers to smuggle malicious inputs
  ///              (e.g. extra path components which lead to sensitive data when used as a relative path, ASCII NULL bytes, or SQL injection),
  ///              sometimes under multiple layers of encoding. Users to be careful not to over-decode their strings, and every time a string
  ///              is percent-decoded, the result must be considered to be **entirely unvalidated**, even if the source contents were previously validated.
  ///
  @inlinable
  public var urlFormDecodedString: String {
    percentDecodedString(from: \.form)
  }
}

extension StringProtocol {

  /// Returns a string formed by decoding all percent-encoded code-units in this string, and using `EncodeSet` to restore substituted code-units.
  ///
  /// If no code-points were substituted when this string was encoded, `\.percentEncodingOnly` may be used to only remove percent-encoding.
  ///
  /// ```swift
  /// "hello,%20world!".percentDecoded(from: \.percentEncodingOnly) // "hello, world!"
  /// "%2Fusr%2Fbin%2Fswift".percentDecoded(\.percentEncodingOnly) // "/usr/bin/swift"
  /// "king+of+the+%F0%9F%A6%86s".percentDecoded(\.form) // "king of the 🦆s"
  /// ```
  ///
  /// - important: Users should beware that percent-encoding has frequently been used by attackers to smuggle malicious inputs
  ///              (e.g. extra path components which lead to sensitive data when used as a relative path, ASCII NULL bytes, or SQL injection),
  ///              sometimes under multiple layers of encoding. Users to be careful not to over-decode their strings, and every time a string
  ///              is percent-decoded, the result must be considered to be **entirely unvalidated**, even if the source contents were previously validated.
  ///
  @inlinable @inline(__always)
  public func percentDecoded<EncodeSet>(
    from decodeSet: KeyPath<PercentDecodeSet, EncodeSet.Type>
  ) -> String where EncodeSet: PercentEncodeSetProtocol {
    utf8.percentDecodedString(from: decodeSet)
  }

  /// Returns a string formed by decoding all percent-encoded code-units in the contents of this string.
  ///
  /// ```swift
  /// "hello%2C%20world!".percentDecoded // hello, world!
  /// "%2Fusr%2Fbin%2Fswift".percentDecoded // /usr/bin/swift
  /// "%F0%9F%98%8E".percentDecoded // 😎
  /// ```
  ///
  /// This is equivalent to calling `percentDecodedString(from: \.percentEncodedOnly)`. If this collection's contents were encoded
  /// with substitutions (e.g. form-encoding), use `percentDecoded(from:)` instead, providing a `PercentDecodeSet` which is able to
  /// reverse those substitutions.
  ///
  /// Equivalent to JavaScript's `decodeURIComponent()` function.
  ///
  /// - important: Users should beware that percent-encoding has frequently been used by attackers to smuggle malicious inputs
  ///              (e.g. extra path components which lead to sensitive data when used as a relative path, ASCII NULL bytes, or SQL injection),
  ///              sometimes under multiple layers of encoding. Users to be careful not to over-decode their strings, and every time a string
  ///              is percent-decoded, the result must be considered to be **entirely unvalidated**, even if the source contents were previously validated.
  ///
  @inlinable
  public var percentDecoded: String {
    utf8.percentDecodedString
  }

  /// Returns a string formed by decoding all percent-encoded code-units in this string and reversing substitutions made by
  /// the `application/x-www-form-urlencoded` encode-set.
  ///
  /// This is equivalent to callling `percentDecoded(from: \.form)`.
  ///
  /// The following example decodes a form-encoded URL query by splitting a string in to key-value pairs at the "&" character, splitting the key from the value
  /// at the "=" character, and decoding each key and value from its encoded representation:
  ///
  /// ```swift
  /// let form = "favourite+pet=%F0%9F%A6%86%2C+of+course&favourite+foods=%F0%9F%8D%8E+%26+%F0%9F%8D%A6"
  /// let decoded = form.split(separator: "&").map { joined_kvp in joined_kvp.split(separator: "=") }
  ///                   .map { kvp in (kvp[0].urlFormDecoded, kvp[1].urlFormDecoded) }
  /// print(decoded) // [("favourite pet", "🦆, of course"), ("favourite foods", "🍎 & 🍦")]
  /// ```
  ///
  /// - important: Users should beware that percent-encoding has frequently been used by attackers to smuggle malicious inputs
  ///              (e.g. extra path components which lead to sensitive data when used as a relative path, ASCII NULL bytes, or SQL injection),
  ///              sometimes under multiple layers of encoding. Users to be careful not to over-decode their strings, and every time a string
  ///              is percent-decoded, the result must be considered to be **entirely unvalidated**, even if the source contents were previously validated.
  ///
  @inlinable
  public var urlFormDecoded: String {
    utf8.urlFormDecodedString
  }
}


// --------------------------------------------
// MARK: - Encode Sets
// --------------------------------------------


/// A namespace for percent-decode sets.
///
/// Decoding is thankfully much simpler than encoding; in almost all cases, simply removing percent-encoding is sufficient, as regular URL encode-sets do
/// not substitute characters. Form-encoding is the only exception specified in the URL Standard.
///
/// Since percent-decode sets are not stateful, you only ever need to refer to their type, never an instance. The types are exposed as properties so you
/// can use a convenient KeyPath syntax to refer to them.
///
public enum PercentDecodeSet {

  /// A decoding set which only decodes percent-encoded characters and assumes that no substituted characters need to be restored.
  ///
  public var percentEncodedOnly: PercentEncodeSet._Passthrough.Type { PercentEncodeSet._Passthrough.self }

  /// The [application/x-www-form-urlencoded](https://url.spec.whatwg.org/#application-x-www-form-urlencoded-percent-encode-set)
  /// percent-encode set.
  ///
  public var form: PercentEncodeSet.FormEncoded.Type { PercentEncodeSet.FormEncoded.self }
}

/// A namespace for percent-encode sets.
///
/// Since percent-encode sets are not stateful, you only ever need to refer to their type, never an instance. The types are exposed as properties so you
/// can use a convenient KeyPath syntax to refer to them.
///
public enum PercentEncodeSet {

  /// The [C0 control](https://url.spec.whatwg.org/#c0-control-percent-encode-set) percent-encode set.
  ///
  public var c0Control: C0Control.Type { C0Control.self }

  /// The [fragment](https://url.spec.whatwg.org/#fragment-percent-encode-set) percent-encode set.
  ///
  public var fragment: Fragment.Type { Fragment.self }

  /// The [query](https://url.spec.whatwg.org/#query-percent-encode-set) percent-encode set.
  ///
  public var query_notSpecial: Query_NotSpecial.Type { Query_NotSpecial.self }

  /// The [special query](https://url.spec.whatwg.org/#special-query-percent-encode-set) percent-encode set.
  ///
  public var query_special: Query_Special.Type { Query_Special.self }

  /// The [path](https://url.spec.whatwg.org/#path-percent-encode-set) percent-encode set.
  ///
  public var path: Path.Type { Path.self }

  /// The [userinfo](https://url.spec.whatwg.org/#userinfo-percent-encode-set) percent-encode set.
  ///
  public var userInfo: UserInfo.Type { UserInfo.self }

  /// The [component](https://url.spec.whatwg.org/#component-percent-encode-set) percent-encode set.
  ///
  public var component: Component.Type { Component.self }

  /// The [application/x-www-form-urlencoded](https://url.spec.whatwg.org/#application-x-www-form-urlencoded-percent-encode-set)
  /// percent-encode set.
  ///
  public var form: FormEncoded.Type { FormEncoded.self }

  /// An internal percent-encode set for manipulating path components.
  ///
  @usableFromInline
  internal var pathComponent: _PathComponent.Type { _PathComponent.self }

  /// An internal percent-encode set for when content is already known to be correctly percent-encoded.
  ///
  @usableFromInline
  internal var alreadyEncoded: _Passthrough.Type { _Passthrough.self }
}

// URL encode-set implementations.

// ARM and x86 seem to have wildly different performance characteristics.
// The lookup table seems to be about 8-12% better than bitshifting on x86, but can be 90% slower on ARM.
@usableFromInline
internal protocol DualImplementedPercentEncodeSet: PercentEncodeSetProtocol {
  static func shouldEscape_binary(ascii codePoint: UInt8) -> Bool
  static func shouldEscape_table(ascii codePoint: UInt8) -> Bool
}

@inlinable @inline(__always)
internal func __shouldPercentEncode<Encoder>(
  _: Encoder.Type, ascii codePoint: UInt8
) -> Bool where Encoder: DualImplementedPercentEncodeSet {
  #if arch(x86_64)
    return Encoder.shouldEscape_table(ascii: codePoint)
  #else
    return Encoder.shouldEscape_binary(ascii: codePoint)
  #endif
}

extension PercentEncodeSet {

  public struct C0Control: PercentEncodeSetProtocol, DualImplementedPercentEncodeSet {

    @inlinable @inline(__always)
    public static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
      __shouldPercentEncode(Self.self, ascii: codePoint)
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_binary(ascii codePoint: UInt8) -> Bool {
      // TODO: [performance]: Benchmark alternative:
      // `codePoint & 0b11100000 == 0 || codePoint == 0x7F`
      // C0Control percent-encoding is used for non-hierarchical URL paths and opaque host names,
      // which currently are not benchmarked.

      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b00000000_00000000_00000000_00000000_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000
      if codePoint < 64 {
        return lo & (1 &<< codePoint) != 0
      } else {
        return hi & (1 &<< ((codePoint &- 64) & 0x7F)) != 0
      }
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_table(ascii codePoint: UInt8) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(codePoint & 0x7F)] }.contains(.c0)
    }
  }

  public struct Fragment: PercentEncodeSetProtocol, DualImplementedPercentEncodeSet {

    @inlinable @inline(__always)
    public static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
      __shouldPercentEncode(Self.self, ascii: codePoint)
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_binary(ascii codePoint: UInt8) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b01010000_00000000_00000000_00000101_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10000000_00000000_00000000_00000001_00000000_00000000_00000000_00000000
      if codePoint < 64 {
        return lo & (1 &<< codePoint) != 0
      } else {
        return hi & (1 &<< ((codePoint &- 64) & 0x7F)) != 0
      }
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_table(ascii codePoint: UInt8) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(codePoint & 0x7F)] }.contains(.fragment)
    }
  }

  public struct Query_NotSpecial: PercentEncodeSetProtocol, DualImplementedPercentEncodeSet {

    @inlinable @inline(__always)
    public static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
      __shouldPercentEncode(Self.self, ascii: codePoint)
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_binary(ascii codePoint: UInt8) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b01010000_00000000_00000000_00001101_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000
      if codePoint < 64 {
        return lo & (1 &<< codePoint) != 0
      } else {
        return hi & (1 &<< ((codePoint &- 64) & 0x7F)) != 0
      }
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_table(ascii codePoint: UInt8) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(codePoint & 0x7F)] }.contains(.query)
    }
  }

  public struct Query_Special: PercentEncodeSetProtocol, DualImplementedPercentEncodeSet {

    @inlinable @inline(__always)
    public static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
      __shouldPercentEncode(Self.self, ascii: codePoint)
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_binary(ascii codePoint: UInt8) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b01010000_00000000_00000000_10001101_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000
      if codePoint < 64 {
        return lo & (1 &<< codePoint) != 0
      } else {
        return hi & (1 &<< ((codePoint &- 64) & 0x7F)) != 0
      }
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_table(ascii codePoint: UInt8) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(codePoint & 0x7F)] }.contains(.specialQuery)
    }
  }

  public struct Path: PercentEncodeSetProtocol, DualImplementedPercentEncodeSet {

    @inlinable @inline(__always)
    public static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
      __shouldPercentEncode(Self.self, ascii: codePoint)
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_binary(ascii codePoint: UInt8) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b11010000_00000000_00000000_00001101_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10101000_00000000_00000000_00000001_00000000_00000000_00000000_00000000
      if codePoint < 64 {
        return lo & (1 &<< codePoint) != 0
      } else {
        return hi & (1 &<< ((codePoint &- 64) & 0x7F)) != 0
      }
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_table(ascii codePoint: UInt8) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(codePoint & 0x7F)] }.contains(.path)
    }
  }

  public struct UserInfo: PercentEncodeSetProtocol, DualImplementedPercentEncodeSet {

    @inlinable @inline(__always)
    public static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
      __shouldPercentEncode(Self.self, ascii: codePoint)
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_binary(ascii codePoint: UInt8) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b11111100_00000000_10000000_00001101_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10111000_00000000_00000000_00000001_01111000_00000000_00000000_00000001
      if codePoint < 64 {
        return lo & (1 &<< codePoint) != 0
      } else {
        return hi & (1 &<< ((codePoint &- 64) & 0x7F)) != 0
      }
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_table(ascii codePoint: UInt8) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(codePoint & 0x7F)] }.contains(.userInfo)
    }
  }

  /// This encode-set is not used for any particular component, but can be used to encode data which is compatible with the escaping for
  /// the path, query, and fragment. It should give the same results as Javascript's `.encodeURIComponent()` method.
  ///
  public struct Component: PercentEncodeSetProtocol, DualImplementedPercentEncodeSet {

    @inlinable @inline(__always)
    public static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
      __shouldPercentEncode(Self.self, ascii: codePoint)
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_binary(ascii codePoint: UInt8) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b11111100_00000000_10011000_01111101_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b10111000_00000000_00000000_00000001_01111000_00000000_00000000_00000001
      if codePoint < 64 {
        return lo & (1 &<< codePoint) != 0
      } else {
        return hi & (1 &<< ((codePoint &- 64) & 0x7F)) != 0
      }
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_table(ascii codePoint: UInt8) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(codePoint & 0x7F)] }.contains(.component)
    }
  }

  public struct FormEncoded: PercentEncodeSetProtocol, DualImplementedPercentEncodeSet {

    @inlinable @inline(__always)
    public static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
      __shouldPercentEncode(Self.self, ascii: codePoint)
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_binary(ascii codePoint: UInt8) -> Bool {
      //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
      let lo: UInt64 = 0b11111100_00000000_10011011_11111110_11111111_11111111_11111111_11111111
      let hi: UInt64 = 0b11111000_00000000_00000000_00000001_01111000_00000000_00000000_00000001
      if codePoint < 64 {
        return lo & (1 &<< codePoint) != 0
      } else {
        return hi & (1 &<< ((codePoint &- 64) & 0x7F)) != 0
      }
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_table(ascii codePoint: UInt8) -> Bool {
      percent_encoding_table.withUnsafeBufferPointer { $0[Int(codePoint & 0x7F)] }.contains(.form)
    }

    @inlinable @inline(__always)
    public static func substitute(ascii codePoint: UInt8) -> UInt8? {
      codePoint == ASCII.space.codePoint ? ASCII.plus.codePoint : nil
    }

    @inlinable @inline(__always)
    public static func unsubstitute(ascii codePoint: UInt8) -> UInt8? {
      codePoint == ASCII.plus.codePoint ? ASCII.space.codePoint : nil
    }
  }
}

// Non-standard encode-sets.

extension PercentEncodeSet {

  /// An encode-set which does not escape or substitute any characters.
  ///
  /// This may be used as a decoding set in order to percent-decode content which does not have substitutions.
  ///
  public struct _Passthrough: PercentEncodeSetProtocol {

    @inlinable @inline(__always)
    public static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
      false
    }
  }

  /// An encode-set used for escaping the contents path components. **Not defined by the URL standard.**
  ///
  /// The URL 'path' encode-set, as defined in the standard, does not include the forward-slash character, as the URL parser won't ever see them in a path component.
  /// This is problematic for APIs which allow the user to insert path-components, as they might insert content which would be re-parsed as multiple components,
  /// possibly including hidden "." or ".." components and leading to non-idempotent URL strings.
  ///
  /// A solution with true minimal-escaping would be split this encode-set for special/non-special URLs, with only the former including the forwardSlash character.
  /// For simplicity, we include them both, which means that we will unnecessarily escape forwardSlashes in the path components of non-special URLs.
  ///
  @usableFromInline
  internal struct _PathComponent: PercentEncodeSetProtocol {

    @inlinable @inline(__always)
    internal static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
      PercentEncodeSet.Path.shouldPercentEncode(ascii: codePoint)
        || codePoint == ASCII.forwardSlash.codePoint
        || codePoint == ASCII.backslash.codePoint
    }
  }
}

//swift-format-ignore
/// A set of `URLEncodeSet`s.
@usableFromInline
internal struct URLEncodeSetSet: OptionSet {

  @usableFromInline
  internal var rawValue: UInt8

  @inlinable
  internal init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  @inlinable internal static var none: Self         { Self(rawValue: 0) }
  @inlinable internal static var c0: Self           { Self(rawValue: 1 << 0) }
  @inlinable internal static var fragment: Self     { Self(rawValue: 1 << 1) }
  @inlinable internal static var query: Self        { Self(rawValue: 1 << 2) }
  @inlinable internal static var specialQuery: Self { Self(rawValue: 1 << 3) }
  @inlinable internal static var path: Self         { Self(rawValue: 1 << 4) }
  @inlinable internal static var userInfo: Self     { Self(rawValue: 1 << 5) }
  @inlinable internal static var form: Self         { Self(rawValue: 1 << 6) }
  @inlinable internal static var component: Self    { Self(rawValue: 1 << 7) }
}

// swift-format-ignore
@usableFromInline
internal let percent_encoding_table: [URLEncodeSetSet] = [
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

@inlinable
internal func withPercentEncodedString<T>(
  _ byte: UInt8, _ body: (UnsafeBufferPointer<UInt8>) -> T
) -> T {
  let table: StaticString = """
    %00%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F\
    %10%11%12%13%14%15%16%17%18%19%1A%1B%1C%1D%1E%1F\
    %20%21%22%23%24%25%26%27%28%29%2A%2B%2C%2D%2E%2F\
    %30%31%32%33%34%35%36%37%38%39%3A%3B%3C%3D%3E%3F\
    %40%41%42%43%44%45%46%47%48%49%4A%4B%4C%4D%4E%4F\
    %50%51%52%53%54%55%56%57%58%59%5A%5B%5C%5D%5E%5F\
    %60%61%62%63%64%65%66%67%68%69%6A%6B%6C%6D%6E%6F\
    %70%71%72%73%74%75%76%77%78%79%7A%7B%7C%7D%7E%7F\
    %80%81%82%83%84%85%86%87%88%89%8A%8B%8C%8D%8E%8F\
    %90%91%92%93%94%95%96%97%98%99%9A%9B%9C%9D%9E%9F\
    %A0%A1%A2%A3%A4%A5%A6%A7%A8%A9%AA%AB%AC%AD%AE%AF\
    %B0%B1%B2%B3%B4%B5%B6%B7%B8%B9%BA%BB%BC%BD%BE%BF\
    %C0%C1%C2%C3%C4%C5%C6%C7%C8%C9%CA%CB%CC%CD%CE%CF\
    %D0%D1%D2%D3%D4%D5%D6%D7%D8%D9%DA%DB%DC%DD%DE%DF\
    %E0%E1%E2%E3%E4%E5%E6%E7%E8%E9%EA%EB%EC%ED%EE%EF\
    %F0%F1%F2%F3%F4%F5%F6%F7%F8%F9%FA%FB%FC%FD%FE%FF-
    """
  return table.withUTF8Buffer {
    let offset = Int(byte) &* 3
    let buffer = UnsafeBufferPointer(start: $0.baseAddress.unsafelyUnwrapped + offset, count: 3)
    return body(buffer)
  }
}

@inlinable
internal func percentEncodedCharacter(_ byte: UInt8, offset: UInt8) -> UInt8 {
  // Ideally, we'd enforce safety here by using 'ptr[Int(min(offset, 2))]', and the compiler
  // would eliminate it. But it doesn't - even when it can see the entire evolution of 'offset'
  // and that it is always within (0...2). Hmph.
  //
  // So as a cheeky work-around, the percent-encoding table includes an extra byte at the end,
  // meaning that it will not over-read if you get the _4th_ offset of a percent-encoded byte.
  // Of course, semantically you'd be reading in to the next byte, or the extra byte,
  // so your code would see incorrect results, but it wouldn't be _unsafe_.
  // This means we can enforce memory safety with a simple bitmask.

  withPercentEncodedString(byte) { ptr in ptr[Int(offset & 0b0000_0011)] }
}
