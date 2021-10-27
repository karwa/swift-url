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

/// A set of ASCII code-points which should be percent-encoded.
///
/// Percent-encoding transforms arbitrary bytes to ASCII strings (e.g. the byte value 200, or 0xC8, to the string "%C8"),
/// and is most commonly used to escape special characters in URLs. Bytes within the ASCII range are encoded according
/// to the encode-set's ``shouldPercentEncode(ascii:)`` method, and bytes which are not ASCII code-points are always
/// percent-encoded.
///
/// The following example demonstrates an encode-set which encodes ASCII single and double quotation marks:
///
/// ```swift
/// struct NoQuotes: PercentEncodeSet {
///   func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
///     codePoint == Character("\"").asciiValue! ||
///     codePoint == Character("'").asciiValue!
///   }
/// }
///
/// #"Quoth the Raven "Nevermore.""#.percentEncoded(using: NoQuotes()) // "Quoth the Raven %22Nevermore.%22"
/// ```
///
/// Encode-sets may also include a ``SubstitutionMap``. If an ASCII code-point is not percent-encoded, the substitution map may
/// replace it with a different character. Content encoded with substitutions must be decoded using the same substitution map it was created with.
///
public protocol PercentEncodeSet {

  typealias _Member = _StaticMember<Self>

  /// A ``SubstitutionMap`` which may replace ASCII code-points that are not percent-encoded.
  ///
  /// The set of code-points to percent-encode and substitute must not overlap. This means there must be no code-point `x`
  /// for which `substitutions.substitute(ascii: x) != nil` and `shouldPercentEncode(ascii: x) == true`.
  ///
  /// In order to ensure that data with substitutions can be accurately decoded, substitute code-points _returned_ by `substitute(ascii:)`
  /// should be percent-encoded. In other words, if `y = substitutions.substitute(ascii: x)`, `shouldPercentEncode(ascii: y)` should
  /// be `true`.
  ///
  /// For example, the `application/x-www-form-urlencoded` encode-set substitutes spaces with the "+" character.
  /// It would be incorrect for that encode-set to also say that the space character should be percent-encoded.
  /// However, to ensure that _actual_ "+" characters in the source data are not later decoded as spaces, the "+" character is part of the percent-encode set.
  ///
  associatedtype Substitutions: SubstitutionMap = NoSubstitutions

  /// Whether or not the given ASCII `codePoint` should be percent-encoded.
  ///
  /// - parameters:
  ///   - codePoint: An ASCII code-point. Always in the range `0...127`.
  ///
  /// - returns: Whether or not `codePoint` should be percent-encoded.
  ///
  func shouldPercentEncode(ascii codePoint: UInt8) -> Bool

  /// The substitution map which applies to ASCII code-points that are not percent-encoded.
  ///
  var substitutions: Substitutions { get }
}

extension PercentEncodeSet where Substitutions == NoSubstitutions {

  @inlinable @inline(__always)
  public var substitutions: NoSubstitutions {
    NoSubstitutions()
  }
}

/// A bidirectional map of ASCII code-points.
///
/// Some encodings require certain ASCII code-points to be replaced.
/// For example, the `application/x-www-form-urlencoded` encoding does not percent-encode ASCII spaces (0x20) as "%20",
/// and instead replaces them with a "+" (0x2B). The following example shows a potential implementation of this encoding:
///
/// ```swift
/// struct FormEncoding: PercentEncodeSet {
///
///   func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
///     if codePoint == 0x20 { return false } // do not percent-encode spaces, substitute instead.
///     if codePoint == 0x2B { return true } // percent-encode actual "+"s in the source.
///     // other codepoints...
///   }
///
///   struct Substitutions: SubstitutionMap {
///     func substitute(ascii codePoint: UInt8) -> UInt8? {
///       codePoint == 0x20 ? 0x2B : nil // Substitute spaces with "+".
///     }
///     func unsubstitute(ascii codePoint: UInt8) -> UInt8? {
///       codePoint == 0x2B ? 0x20 : nil // Unsubstitute "+" to space.
///     }
///   }
///
///   var substitutions: Substitutions { .init() }
/// }
/// ```
///
public protocol SubstitutionMap {

  typealias _Member = _StaticMember<Self>

  /// Returns the substitute to use for the given code-point, or `nil` if the code-point does not require substitution.
  ///
  /// The ASCII percent sign (`0x25`) and alpha characters (`0x41...0x5A` and `0x61...0x7A`) must not be substituted.
  ///
  /// In order to ensure lossless encoding, any code-points returned as substitutes should be percent-encoded by the
  /// substitution map's parent encoder and restored by the inverse function, ``unsubstitute(ascii:)``.
  ///
  /// - parameters:
  ///   - codePoint: An ASCII code-point from unencoded data. Always in the range `0...127`.
  ///
  /// - returns: The code-point to emit instead of `codePoint`, or `nil` if `codePoint` should not be substituted.
  ///            Substitute code-points must always be in the range `0...127`.
  ///
  func substitute(ascii codePoint: UInt8) -> UInt8?

  /// Returns the code-point restored from the given substitute code-point, or `nil` if the given code-point is not a substitute.
  ///
  /// In order to ensure lossless encoding, this function should restore all code-points substituted by ``substitute(ascii:)``.
  ///
  /// - parameters:
  ///   - codePoint: An ASCII codepoint from encoded data. Always in the range `0...127`.
  ///
  /// - returns: The code-point to emit instead of `codePoint`, or `nil` if `codePoint` is not a substitute recognized by this substitution map.
  ///            Restored code-points must always be in the range `0...127`.
  ///
  func unsubstitute(ascii codePoint: UInt8) -> UInt8?
}


// --------------------------------------------
// MARK: - Encoding
// --------------------------------------------


/// A `Collection` which percent-encodes elements from its `Source` on-demand using a given `EncodeSet`.
///
/// Percent-encoding transforms arbitrary bytes to ASCII strings (e.g. the byte value 200, or 0xC8, to the string "%C8"),
/// and is most commonly used to escape special characters in URLs. Bytes which are not ASCII code-points are always percent-encoded,
/// and bytes within the ASCII range are encoded according to the encode-set's `shouldPercentEncode(ascii:)` method.
///
/// Encode-sets may also include a ``SubstitutionMap``. If a code-point is not percent-encoded, the substitution map may
/// replace it with a different character. Content encoded with substitutions must be decoded using the same substitution map it was created with.
///
/// To encode a source collection, use the extension methods provided on `LazyCollectionProtocol`:
///
/// ```swift
/// // Encode arbitrary data as an ASCII string.
/// let image: Data = ...
/// image.lazy.percentEncoded(using: .urlComponentSet) // ASCII bytes, decoding to "%BAt_%E0%11%22%EB%10%2C%7F..."
///
/// // Encode-sets determine which characters are encoded, and some perform substitutions.
/// let bytes = "hello, world!".utf8
/// bytes.lazy.percentEncoded(using: .urlComponentSet)
///   .elementsEqual("hello%2C%20world!".utf8) // ✅
/// bytes.lazy.percentEncoded(using: .formEncoding)
///   .elementsEqual("hello%2C+world%21".utf8) // ✅
/// ```
///
/// The elements of this collection are guaranteed to be ASCII code-units, and hence valid UTF-8.
///
public struct LazilyPercentEncoded<Source, EncodeSet>: Collection, LazyCollectionProtocol
where Source: Collection, Source.Element == UInt8, EncodeSet: PercentEncodeSet {

  @usableFromInline
  internal let source: Source

  @usableFromInline
  internal let encodeSet: EncodeSet

  public let startIndex: Index

  @inlinable
  internal init(source: Source, encodeSet: EncodeSet) {
    self.source = source
    self.encodeSet = encodeSet
    let sourceStartIndex = source.startIndex
    if sourceStartIndex < source.endIndex {
      self.startIndex = Index(sourceIndex: sourceStartIndex, sourceByte: source[sourceStartIndex], encodeSet: encodeSet)
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
    internal init(sourceIndex: Source.Index, sourceByte: UInt8, encodeSet: EncodeSet) {
      self.sourceIndex = sourceIndex
      self.encodedByteOffset = 0
      self.encodedByte = _EncodedByte(byte: sourceByte, encodeSet: encodeSet)
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
    i.encodedByte = _EncodedByte(byte: source[i.sourceIndex], encodeSet: encodeSet)
  }
}

extension LazilyPercentEncoded: BidirectionalCollection where Source: BidirectionalCollection {

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
    i.encodedByte = _EncodedByte(byte: source[i.sourceIndex], encodeSet: encodeSet)
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
  internal init<EncodeSet>(byte: UInt8, encodeSet: EncodeSet) where EncodeSet: PercentEncodeSet {
    if let asciiChar = ASCII(byte), encodeSet.shouldPercentEncode(ascii: asciiChar.codePoint) == false {
      self.count = 1
      if let substitute = encodeSet.substitutions.substitute(ascii: asciiChar.codePoint) {
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

extension LazilyPercentEncoded {

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
      i.encodedByte = _EncodedByte(byte: source[i.sourceIndex], encodeSet: encodeSet)
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

// Percent-encoding API.
//
// - The source data is raw bytes.
//   It may be UTF-8 bytes stored in a String, or binary data in any storage type.
//
// - The result of encoding is an ASCII string.
//   It is guaranteed to be ASCII, so there is little downside to having String be our eager storage type.
//
// Hence we need 2 APIs:
//
// 1. Lazy encoding (bytes -> bytes)
//    Covers expert use-cases where result should not be a String.
//    Useful for avoiding allocations, and chaining with lazy decoding.
//
// 2. Eager encoding to string (bytes -> string, string -> string)
//
// Naming:
//
// - When the source/result types are similar (bytes -> bytes, string -> string),
//   use the base name "percentEncoded".
// - When the source/result types are different (bytes -> string),
//   use "percentEncodedString".

// Lazy encoding to (ASCII) bytes.

extension LazyCollectionProtocol where Element == UInt8 {

  /// Returns a `Collection` whose elements are computed lazily by percent-encoding this collection's elements.
  ///
  /// Percent-encoding transforms arbitrary bytes to ASCII strings (e.g. the byte value 200, or 0xC8, to the string "%C8"),
  /// with bytes within the ASCII range being restricted by `encodeSet`. Some encodings (e.g. form encoding) apply substitutions
  /// in addition to percent-encoding; provide the appropriate ``SubstitutionMap`` when decoding to accurately recover the source contents.
  ///
  /// ```swift
  /// // Encode arbitrary data as an ASCII string.
  /// let image: Data = ...
  /// image.lazy.percentEncoded(using: .urlComponentSet) // ASCII bytes, decoding to "%BAt_%E0%11%22%EB%10%2C%7F..."
  ///
  /// // Encode-sets determine which characters are encoded, and some perform substitutions.
  /// let bytes = "hello, world!".utf8
  /// bytes.lazy.percentEncoded(using: .urlComponentSet)
  ///   .elementsEqual("hello%2C%20world!".utf8) // ✅
  /// bytes.lazy.percentEncoded(using: .formEncoding)
  ///   .elementsEqual("hello%2C+world%21".utf8) // ✅
  /// ```
  ///
  @inlinable @inline(__always)
  public func percentEncoded<EncodeSet>(using encodeSet: EncodeSet) -> LazilyPercentEncoded<Elements, EncodeSet> {
    LazilyPercentEncoded(source: elements, encodeSet: encodeSet)
  }

  // _StaticMember variant for pre-5.5 toolchains.

  /// Returns a `Collection` whose elements are computed lazily by percent-encoding this collection's elements.
  ///
  /// Percent-encoding transforms arbitrary bytes to ASCII strings (e.g. the byte value 200, or 0xC8, to the string "%C8"),
  /// with bytes within the ASCII range being restricted by `encodeSet`. Some encodings (e.g. form encoding) apply substitutions
  /// in addition to percent-encoding; provide the appropriate ``SubstitutionMap`` when decoding to accurately recover the source contents.
  ///
  /// ```swift
  /// // Encode arbitrary data as an ASCII string.
  /// let image: Data = ...
  /// image.lazy.percentEncoded(using: .urlComponentSet) // ASCII bytes, decoding to "%BAt_%E0%11%22%EB%10%2C%7F..."
  ///
  /// // Encode-sets determine which characters are encoded, and some perform substitutions.
  /// let bytes = "hello, world!".utf8
  /// bytes.lazy.percentEncoded(using: .urlComponentSet)
  ///   .elementsEqual("hello%2C%20world!".utf8) // ✅
  /// bytes.lazy.percentEncoded(using: .formEncoding)
  ///   .elementsEqual("hello%2C+world%21".utf8) // ✅
  /// ```
  ///
  @inlinable @inline(__always) @_disfavoredOverload
  public func percentEncoded<EncodeSet>(
    using encodeSet: EncodeSet._Member
  ) -> LazilyPercentEncoded<Elements, EncodeSet> {
    percentEncoded(using: encodeSet.base)
  }
}

// Eager encoding to String.

extension Collection where Element == UInt8 {

  /// Returns an ASCII string formed by percent-encoding this collection's elements.
  ///
  /// Percent-encoding transforms arbitrary bytes to ASCII strings (e.g. the byte value 200, or 0xC8, to the string "%C8"),
  /// with bytes within the ASCII range being restricted by `encodeSet`. Some encodings (e.g. form encoding) apply substitutions
  /// in addition to percent-encoding; provide the appropriate ``SubstitutionMap`` when decoding to accurately recover the source contents.
  ///
  /// ```swift
  /// // Encode arbitrary data as an ASCII string.
  /// let image: Data = ...
  /// image.percentEncodedString(using: .urlComponentSet) // "%BAt_%E0%11%22%EB%10%2C%7F..."
  ///
  /// // Encode-sets determine which characters are encoded, and some perform substitutions.
  /// let bytes = "hello, world!".utf8
  /// bytes.percentEncodedString(using: .urlComponentSet) == "hello%2C%20world!" // ✅
  /// bytes.percentEncodedString(using: .formEncoding) == "hello%2C+world%21" // ✅
  /// ```
  ///
  @inlinable
  public func percentEncodedString<EncodeSet: PercentEncodeSet>(using encodeSet: EncodeSet) -> String {
    withContiguousStorageIfAvailable {
      String(discontiguousUTF8: $0.boundsChecked.lazy.percentEncoded(using: encodeSet))
    } ?? String(discontiguousUTF8: self.lazy.percentEncoded(using: encodeSet))
  }

  // _StaticMember variant for pre-5.5 toolchains.

  /// Returns an ASCII string formed by percent-encoding this collection's elements.
  ///
  /// Percent-encoding transforms arbitrary bytes to ASCII strings (e.g. the byte value 200, or 0xC8, to the string "%C8"),
  /// with bytes within the ASCII range being restricted by `encodeSet`. Some encodings (e.g. form encoding) apply substitutions
  /// in addition to percent-encoding; provide the appropriate ``SubstitutionMap`` when decoding to accurately recover the source contents.
  ///
  /// ```swift
  /// // Encode arbitrary data as an ASCII string.
  /// let image: Data = ...
  /// image.percentEncodedString(using: .urlComponentSet) // "%BAt_%E0%11%22%EB%10%2C%7F..."
  ///
  /// // Encode-sets determine which characters are encoded, and some perform substitutions.
  /// let bytes = "hello, world!".utf8
  /// bytes.percentEncodedString(using: .urlComponentSet) == "hello%2C%20world!" // ✅
  /// bytes.percentEncodedString(using: .formEncoding) == "hello%2C+world%21" // ✅
  /// ```
  ///
  @inlinable @_disfavoredOverload
  public func percentEncodedString<EncodeSet: PercentEncodeSet>(using encodeSet: EncodeSet._Member) -> String {
    percentEncodedString(using: encodeSet.base)
  }
}

extension StringProtocol {

  /// Returns an ASCII string formed by percent-encoding this string's UTF-8 representation.
  ///
  /// Percent-encoding transforms arbitrary bytes to ASCII strings (e.g. the byte value 200, or 0xC8, to the string "%C8"),
  /// with bytes within the ASCII range being restricted by `encodeSet`. Some encodings (e.g. form encoding) apply substitutions
  /// in addition to percent-encoding; provide the appropriate ``SubstitutionMap`` when decoding to accurately recover the source contents.
  ///
  /// ```swift
  /// // Percent-encoding can be used to escapes special characters, e.g. spaces.
  /// "hello, world!".percentEncoded(using: .userInfoSet) // "hello,%20world!"
  ///
  /// // Encode-sets determine which characters are encoded, and some perform substitutions.
  /// "/usr/bin/swift".percentEncoded(using: .urlComponentSet) // "%2Fusr%2Fbin%2Fswift"
  /// "king of the 🦆s".percentEncoded(using: .formEncoding) // "king+of+the+%F0%9F%A6%86s"
  /// ```
  ///
  @inlinable
  public func percentEncoded<EncodeSet: PercentEncodeSet>(using encodeSet: EncodeSet) -> String {
    utf8.percentEncodedString(using: encodeSet)
  }

  // _StaticMember variant for pre-5.5 toolchains.

  /// Returns an ASCII string formed by percent-encoding this string's UTF-8 representation.
  ///
  /// Percent-encoding transforms arbitrary bytes to ASCII strings (e.g. the byte value 200, or 0xC8, to the string "%C8"),
  /// with bytes within the ASCII range being restricted by `encodeSet`. Some encodings (e.g. form encoding) apply substitutions
  /// in addition to percent-encoding; provide the appropriate ``SubstitutionMap`` when decoding to accurately recover the source contents.
  ///
  /// ```swift
  /// // Percent-encoding can be used to escapes special characters, e.g. spaces.
  /// "hello, world!".percentEncoded(using: .userInfoSet) // "hello,%20world!"
  ///
  /// // Encode-sets determine which characters are encoded, and some perform substitutions.
  /// "/usr/bin/swift".percentEncoded(using: .urlComponentSet) // "%2Fusr%2Fbin%2Fswift"
  /// "king of the 🦆s".percentEncoded(using: .formEncoding) // "king+of+the+%F0%9F%A6%86s"
  /// ```
  ///
  @inlinable @_disfavoredOverload
  public func percentEncoded<EncodeSet: PercentEncodeSet>(using encodeSet: EncodeSet._Member) -> String {
    percentEncoded(using: encodeSet.base)
  }
}


// --------------------------------------------
// MARK: - Decoding
// --------------------------------------------


/// A `Collection` which percent-decodes elements from its `Source` on-demand.
///
/// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB),
/// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding;
/// use ``LazilyPercentDecodedWithSubstitutions``, providing the correct ``SubstitutionMap``,
/// to accurately decode content encoded with substitutions.
///
/// To decode a source collection containing a percent-encoded string, use the extension methods provided on `LazyCollectionProtocol`:
///
/// ```swift
/// // The bytes, containing a string with percent-encoding.
/// let source: [UInt8] = [0x25, 0x36, 0x31, 0x25, 0x36, 0x32, 0x25, 0x36, 0x33]
/// String(decoding: source, as: UTF8.self) // "%61%62%63"
///
/// // In this case, the decoded bytes contain the ASCII string "abc".
/// source.lazy.percentDecoded().elementsEqual("abc".utf8) // ✅
/// ```
///
/// The elements of this collection are raw bytes, potenially including NULL bytes or invalid UTF-8.
///
public typealias LazilyPercentDecoded<Source> = LazilyPercentDecodedWithSubstitutions<Source, NoSubstitutions>
where Source: Collection, Source.Element == UInt8

/// A `Collection` which percent-decodes elements from its `Source` on-demand, and reverses substitutions made by a ``SubstitutionMap``.
///
/// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB),
/// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
/// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
///
/// To decode a source collection containing a percent-encoded string, use the extension methods provided on `LazyCollectionProtocol`:
///
/// ```swift
/// // The bytes, containing a string with UTF-8 form-encoding.
/// let source: [UInt8] = [
///   0x68, 0x25, 0x43, 0x32, 0x25, 0x41, 0x33, 0x6C, 0x6C, 0x6F, 0x2B, 0x77, 0x6F, 0x72, 0x6C, 0x64
/// ]
/// String(decoding: source, as: UTF8.self) // "h%C2%A3llo+world"
///
/// // Specify the `.formEncoding` substitution map to decode the contents.
/// source.lazy.percentDecoded(substitutions: .formEncoding)
///   .elementsEqual("h£llo world".utf8) // ✅
/// ```
///
/// The elements of this collection are raw bytes, potenially including NULL bytes or invalid UTF-8.
///
public struct LazilyPercentDecodedWithSubstitutions<Source, Substitutions>: Collection, LazyCollectionProtocol
where Source: Collection, Source.Element == UInt8, Substitutions: SubstitutionMap {

  @usableFromInline
  internal let source: Source

  @usableFromInline
  internal let substitutions: Substitutions

  public let startIndex: Index

  @inlinable
  internal init(source: Source, substitutions: Substitutions) {
    self.source = source
    self.substitutions = substitutions
    self.startIndex = Index(at: source.startIndex, in: source, subsMap: substitutions)
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
    return position.byte
  }

  @inlinable
  public func index(after i: Index) -> Index {
    assert(i != endIndex, "Attempt to advance endIndex")
    // Does not trap in release mode - just keeps returning 'endIndex'.
    return Index(at: i.sourceRange.upperBound, in: source, subsMap: substitutions)
  }

  @inlinable
  public func formIndex(after i: inout Index) {
    assert(i != endIndex, "Attempt to advance endIndex")
    // Does not trap in release mode - just keeps returning 'endIndex'.
    i = Index(at: i.sourceRange.upperBound, in: source, subsMap: substitutions)
  }

  public struct Index: Comparable {

    /// Always either 0, 1, or 3 bytes from the source:
    /// - 0 bytes: `endIndex` only.
    /// - 1 byte: non-encoded or substituted byte.
    /// - 3 bytes: percent-encoded byte.
    ///
    @usableFromInline
    internal let sourceRange: Range<Source.Index>

    @usableFromInline
    internal let byte: UInt8

    @usableFromInline
    internal let isDecodedOrUnsubstituted: Bool

    /// Creates an index referencing the given source collection's `endIndex`.
    /// This index's `decodedValue` is always 0. It is meaningless and should not be read.
    ///
    @inlinable
    internal init(_endIndex i: Source.Index) {
      self.sourceRange = Range(uncheckedBounds: (i, i))
      self.byte = 0
      self.isDecodedOrUnsubstituted = false
    }

    @inlinable @inline(__always)
    internal init(_unsubstituting value: UInt8, range: Range<Source.Index>, subsMap: Substitutions) {
      self.sourceRange = range
      if let unsub = ASCII(value).flatMap({ subsMap.unsubstitute(ascii: $0.codePoint) }) {
        self.byte = unsub
        self.isDecodedOrUnsubstituted = true
      } else {
        self.byte = value
        self.isDecodedOrUnsubstituted = false
      }
    }

    /// Decodes the octet starting at the given index in the given `source` collection.
    /// The index's successor may be obtained by creating another index starting at the index's `range.upperBound`.
    ///
    /// The index which starts at `source.endIndex` is also given by `Index(endIndexOf:)`.
    ///
    @inlinable
    internal init(at i: Source.Index, in source: Source, subsMap: Substitutions) {
      // The successor of endIndex is endIndex.
      guard i < source.endIndex else {
        self = .init(_endIndex: i)
        return
      }

      let byte0 = source[i]
      let byte1Index = source.index(after: i)
      guard byte0 == ASCII.percentSign.codePoint else {
        self = Index(_unsubstituting: byte0, range: Range(uncheckedBounds: (i, byte1Index)), subsMap: subsMap)
        return
      }
      var cursor = byte1Index
      guard cursor < source.endIndex, let decodedByte1 = ASCII(source[cursor])?.hexNumberValue else {
        self.sourceRange = Range(uncheckedBounds: (i, byte1Index))
        self.byte = byte0  // Percent-sign, should never be substituted.
        self.isDecodedOrUnsubstituted = false
        return
      }
      source.formIndex(after: &cursor)
      guard cursor < source.endIndex, let decodedByte2 = ASCII(source[cursor])?.hexNumberValue else {
        self.sourceRange = Range(uncheckedBounds: (i, byte1Index))
        self.byte = byte0  // Percent-sign, should never be substituted.
        self.isDecodedOrUnsubstituted = false
        return
      }
      source.formIndex(after: &cursor)

      self.sourceRange = Range(uncheckedBounds: (i, cursor))
      self.byte = (decodedByte1 &* 16) &+ (decodedByte2)
      self.isDecodedOrUnsubstituted = true
    }

    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.sourceRange.lowerBound == rhs.sourceRange.lowerBound
    }

    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.sourceRange.lowerBound < rhs.sourceRange.lowerBound
    }

    @inlinable
    public static func > (lhs: Self, rhs: Self) -> Bool {
      lhs.sourceRange.lowerBound > rhs.sourceRange.lowerBound
    }
  }
}

extension LazilyPercentDecodedWithSubstitutions.Index where Source: BidirectionalCollection {

  /// Decodes the octet whose final code-unit precedes the given index in the given `source` collection.
  /// The index's predeccessor may be obtained by creating another index ending at the index's `range.lowerBound`.
  ///
  @inlinable
  internal init(endingAt i: Source.Index, in source: Source, startIndex: Self, subsMap: Substitutions) {
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
      self = Self(_unsubstituting: byte2, range: Range(uncheckedBounds: (byte2Index, i)), subsMap: subsMap)
      return
    }
    guard
      let decodedByte1 = ASCII(source[source.index(before: byte2Index)])?.hexNumberValue,
      let decodedByte2 = ASCII(byte2)?.hexNumberValue
    else {
      self = Self(_unsubstituting: byte2, range: Range(uncheckedBounds: (byte2Index, i)), subsMap: subsMap)
      return
    }
    self.sourceRange = Range(uncheckedBounds: (byte0Index, i))
    self.byte = (decodedByte1 &* 16) &+ (decodedByte2)
    self.isDecodedOrUnsubstituted = true
  }
}

extension LazilyPercentDecodedWithSubstitutions: BidirectionalCollection where Source: BidirectionalCollection {

  @inlinable
  public func index(before i: Index) -> Index {
    assert(i != startIndex, "Cannot decrement startIndex")
    // Does not trap in release mode - just keeps returning 'startIndex'.
    return Index(endingAt: i.sourceRange.lowerBound, in: source, startIndex: startIndex, subsMap: substitutions)
  }

  @inlinable
  public func formIndex(before i: inout Index) {
    assert(i != startIndex, "Cannot decrement startIndex")
    // Does not trap in release mode - just keeps returning 'startIndex'.
    i = Index(endingAt: i.sourceRange.lowerBound, in: source, startIndex: startIndex, subsMap: substitutions)
  }
}

// Internal utilities.

extension Collection where Element == UInt8 {

  /// Returns the percent-decoding of this collection's elements, interpreted as UTF-8 code-units.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  /// If the bytes obtained by percent-decoding this collection's elements represent anything other than UTF-8 text,
  /// use the `percentDecoded(substitutions:)` lazy wrapper to decode the collection as binary data.
  ///
  /// ```swift
  /// // The bytes, containing a string with UTF-8 form-encoding.
  /// let source: [UInt8] = [
  ///   0x68, 0x25, 0x43, 0x32, 0x25, 0x41, 0x33, 0x6C, 0x6C, 0x6F, 0x2B, 0x77, 0x6F, 0x72, 0x6C, 0x64
  /// ]
  /// String(decoding: source, as: UTF8.self) // "h%C2%A3llo+world"
  ///
  /// // Specify the `.formEncoding` substitution map to decode the contents.
  /// source.percentDecodedString(substitutions: .formEncoding) == "h£llo world" // ✅
  /// ```
  ///
  /// - important: The returned string may include NULL bytes or other values which your program might not expect.
  ///   Percent-encoding has frequently been used to perform path traversal attacks, SQL injection, and exploit similar vulnerabilities
  ///   stemming from unvalidated input (somtimes under multiple levels of encoding). Ensure you do not over-decode your data,
  ///   and every time you _do_ decode some data, you must consider the result to be **entirely unvalidated**,
  ///   even if the source contents were previously validated.
  ///
  @inlinable
  internal func percentDecodedString<Substitutions: SubstitutionMap>(substitutions: Substitutions) -> String {
    withContiguousStorageIfAvailable {
      String(discontiguousUTF8: $0.boundsChecked.lazy.percentDecoded(substitutions: substitutions))
    } ?? String(discontiguousUTF8: self.lazy.percentDecoded(substitutions: substitutions))
  }

  // _StaticMember variant for pre-5.5 toolchains.

  @inlinable @inline(__always) @_disfavoredOverload
  internal func percentDecodedString<Substitutions: SubstitutionMap>(substitutions: Substitutions._Member) -> String {
    percentDecodedString(substitutions: substitutions.base)
  }
}

extension Collection where Element == UInt8 {

  /// Returns the percent-decoding of this collection with the given encode-set, re-encoded with the same encode-set.
  ///
  /// This is useful to minimize data which should already be using the given percent-encode set, as it removes encoding which is not strictly necessary.
  ///
  internal func percentDecodedAndReencoded<EncodeSet: PercentEncodeSet>(
    using encodeSet: EncodeSet
  ) -> LazilyPercentEncoded<LazilyPercentDecodedWithSubstitutions<Self, EncodeSet.Substitutions>, EncodeSet> {
    self.lazy.percentDecoded(substitutions: encodeSet.substitutions).percentEncoded(using: encodeSet)
  }

  // _StaticMember variant for pre-5.5 toolchains.

  internal func percentDecodedAndReencoded<EncodeSet: PercentEncodeSet>(
    using encodeSet: EncodeSet._Member
  ) -> LazilyPercentEncoded<LazilyPercentDecodedWithSubstitutions<Self, EncodeSet.Substitutions>, EncodeSet> {
    percentDecodedAndReencoded(using: encodeSet.base)
  }
}

// Percent-decoding API.
//
// - The source data is some kind of ASCII-compatible text.
//   It is most often going to be stored as a String, but in rare/expert cases may be another data type.
//
// - The result of decoding is raw bytes.
//   It is most often going to contain UTF-8 code-units, but may also be binary data or text in a legacy encoding.
//
// Hence we need 3 APIs:
//
// 1. Lazy decoding (bytes -> bytes)
//    Covers expert use-cases where source is not a String.
//    Useful for avoiding allocations, and chaining with lazy encoding.
//
// 2. Eager decoding to bytes (string -> bytes)
//    Covers decoding binary data or non-UTF-8 text, which is less common but not quite an "expert" use-case.
//
// 3. Eager decoding to string (string -> string)
//    Covers decoding UTF-8 text, which is by far the most common use of percent-encoding.
//
// Naming:
//
// - When the source/result types are similar (bytes -> bytes, string -> string),
//   use the base name "percentDecoded".
// - When the source/result types are different (string -> bytes),
//   use "percentDecodedBytes".
//   => _EXCEPT_ that the standard library doesn't have a safe "bytes" type.
//      There is reason to think it may add one soon, so for now decode to Array<UInt8>
//      and call it "percentDecodedBytesArray".

// Lazy decoding to bytes.

extension LazyCollectionProtocol where Element == UInt8 {

  /// Returns a `Collection` whose elements are computed lazily by percent-decoding the elements of this collection.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  /// ```swift
  /// // The bytes, containing a string with UTF-8 form-encoding.
  /// let source: [UInt8] = [
  ///   0x68, 0x25, 0x43, 0x32, 0x25, 0x41, 0x33, 0x6C, 0x6C, 0x6F, 0x2B, 0x77, 0x6F, 0x72, 0x6C, 0x64
  /// ]
  /// String(decoding: source, as: UTF8.self) // "h%C2%A3llo+world"
  ///
  /// // Specify the `.formEncoding` substitution map to decode the contents.
  /// source.lazy.percentDecoded(substitutions: .formEncoding)
  ///   .elementsEqual("h£llo world".utf8) // ✅
  /// ```
  ///
  /// The elements of this collection are raw bytes, potenially including NULL bytes or invalid UTF-8.
  ///
  @inlinable @inline(__always)
  public func percentDecoded<Substitutions>(
    substitutions: Substitutions
  ) -> LazilyPercentDecodedWithSubstitutions<Elements, Substitutions> {
    LazilyPercentDecodedWithSubstitutions(source: elements, substitutions: substitutions)
  }

  // _StaticMember variant for pre-5.5 toolchains.

  /// Returns a `Collection` whose elements are computed lazily by percent-decoding the elements of this collection.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  /// ```swift
  /// // The bytes, containing a string with UTF-8 form-encoding.
  /// let source: [UInt8] = [
  ///   0x68, 0x25, 0x43, 0x32, 0x25, 0x41, 0x33, 0x6C, 0x6C, 0x6F, 0x2B, 0x77, 0x6F, 0x72, 0x6C, 0x64
  /// ]
  /// String(decoding: source, as: UTF8.self) // "h%C2%A3llo+world"
  ///
  /// // Specify the `.formEncoding` substitution map to decode the contents.
  /// source.lazy.percentDecoded(substitutions: .formEncoding)
  ///   .elementsEqual("h£llo world".utf8) // ✅
  /// ```
  ///
  /// The elements of this collection are raw bytes, potenially including NULL bytes or invalid UTF-8.
  ///
  @inlinable @inline(__always) @_disfavoredOverload
  public func percentDecoded<Substitutions>(
    substitutions: Substitutions._Member
  ) -> LazilyPercentDecodedWithSubstitutions<Elements, Substitutions> {
    percentDecoded(substitutions: substitutions.base)
  }

  // Default parameter: Substitutions == NoSubstitutions.

  /// Returns a `Collection` whose elements are computed lazily by percent-decoding the elements of this collection.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  /// This function is equivalent to calling `percentDecoded(substitutions: .none)`.
  ///
  /// ```swift
  /// // The bytes, containing a string with percent-encoding.
  /// let source: [UInt8] = [0x25, 0x36, 0x31, 0x25, 0x36, 0x32, 0x25, 0x36, 0x33]
  /// String(decoding: source, as: UTF8.self) // "%61%62%63"
  ///
  /// // In this case, the decoded bytes contain the ASCII string "abc".
  /// source.lazy.percentDecoded().elementsEqual("abc".utf8) // ✅
  /// ```
  ///
  /// The elements of this collection are raw bytes, potenially including NULL bytes or invalid UTF-8.
  ///
  @inlinable @inline(__always)
  public func percentDecoded() -> LazilyPercentDecoded<Elements> {
    percentDecoded(substitutions: .none)
  }
}

// Eager decoding to bytes.

extension StringProtocol {

  /// Returns the percent-decoding of this string as binary data.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  /// ```swift
  /// let originalImage: Data = ...
  ///
  /// // Encode the data, e.g. using form-encoding.
  /// let encodedImage = originalImage.percentEncodedString(using: .formEncoding) // "%BAt_%E0%11%22%EB%10%2C%7F..."
  ///
  /// // Decode the data, giving the same substitution map.
  /// let decodedImage = encodedImage.percentDecodedBytesArray(substitutions: .formEncoding)
  /// assert(decodedImage.elementsEqual(originalImage)) // ✅
  /// ```
  ///
  /// The returned data contains raw bytes, potenially including NULL bytes or invalid UTF-8.
  ///
  @inlinable
  public func percentDecodedBytesArray<Substitutions: SubstitutionMap>(substitutions: Substitutions) -> [UInt8] {
    Array(utf8.lazy.percentDecoded(substitutions: substitutions))
  }

  // _StaticMember variant for pre-5.5 toolchains.

  /// Returns the percent-decoding of this string as binary data.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  /// ```swift
  /// let originalImage: Data = ...
  ///
  /// // Encode the data, e.g. using form-encoding.
  /// let encodedImage = originalImage.percentEncodedString(using: .formEncoding) // "%BAt_%E0%11%22%EB%10%2C%7F..."
  ///
  /// // Decode the data, giving the same substitution map.
  /// let decodedImage = encodedImage.percentDecodedBytesArray(substitutions: .formEncoding)
  /// assert(decodedImage.elementsEqual(originalImage)) // ✅
  /// ```
  ///
  /// The returned data contains raw bytes, potenially including NULL bytes or invalid UTF-8.
  ///
  @inlinable @inline(__always)
  public func percentDecodedBytesArray<Substitutions: SubstitutionMap>(
    substitutions: Substitutions._Member
  ) -> [UInt8] {
    percentDecodedBytesArray(substitutions: substitutions.base)
  }

  // Default parameter: Substitutions == NoSubstitutions.

  /// Returns the percent-decoding of this string as binary data.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  /// This function is equivalent to calling `percentDecodedBytesArray(substitutions: .none)`.
  ///
  /// ```swift
  /// let url = WebURL("data:application/octet-stream,%BC%A8%CD")!
  ///
  /// // Check the data URL's payload.
  /// let payloadOptions = url.path.prefix(while: { $0 != "," })
  /// if payloadOptions.hasSuffix(";base64") {
  ///   // ... decode as base-64
  /// } else {
  ///   let encodedPayload = url.path[payloadOptions.endIndex...].dropFirst()
  ///   let decodedPayload = encodedPayload.percentDecodedBytesArray()
  ///   assert(decodedPayload == [0xBC, 0xA8, 0xCD]) // ✅
  /// }
  /// ```
  ///
  /// The returned data contains raw bytes, potenially including NULL bytes or invalid UTF-8.
  ///
  @inlinable @inline(__always)
  public func percentDecodedBytesArray() -> [UInt8] {
    percentDecodedBytesArray(substitutions: .none)
  }
}

// Eager decoding to String.

extension StringProtocol {

  /// Returns the percent-decoding of this string, interpreted as UTF-8 code-units.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  /// If the bytes obtained by percent-decoding this string represent anything other than UTF-8 text,
  /// use the `percentDecodedByteArray` function to decode the string as binary data.
  ///
  /// ```swift
  /// // Decode percent-encoded UTF-8 as a string.
  /// "hello,%20world!".percentDecoded(substitutions: .none) // "hello, world!"
  /// "%2Fusr%2Fbin%2Fswift".percentDecoded(substitutions: .none) // "/usr/bin/swift"
  ///
  /// // Some encodings require a substitution map to accurately decode.
  /// "king+of+the+%F0%9F%A6%86s".percentDecoded(substitutions: .formEncoding) // "king of the 🦆s"
  /// ```
  ///
  /// - important: The returned string may include NULL bytes or other values which your program might not expect.
  ///   Percent-encoding has frequently been used to perform path traversal attacks, SQL injection, and exploit similar vulnerabilities
  ///   stemming from unvalidated input (somtimes under multiple levels of encoding). Ensure you do not over-decode your data,
  ///   and every time you _do_ decode some data, you must consider the result to be **entirely unvalidated**,
  ///   even if the source contents were previously validated.
  ///
  @inlinable
  public func percentDecoded<Substitutions: SubstitutionMap>(substitutions: Substitutions) -> String {
    utf8.percentDecodedString(substitutions: substitutions)
  }

  // _StaticMember variant for pre-5.5 toolchains.

  /// Returns the percent-decoding of this string, interpreted as UTF-8 code-units.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  /// If the bytes obtained by percent-decoding this string represent anything other than UTF-8 text,
  /// use the `percentDecodedByteArray` function to decode the string as binary data.
  ///
  /// ```swift
  /// // Decode percent-encoded UTF-8 as a string.
  /// "hello,%20world!".percentDecoded(substitutions: .none) // "hello, world!"
  /// "%2Fusr%2Fbin%2Fswift".percentDecoded(substitutions: .none) // "/usr/bin/swift"
  ///
  /// // Some encodings require a substitution map to accurately decode.
  /// "king+of+the+%F0%9F%A6%86s".percentDecoded(substitutions: .formEncoding) // "king of the 🦆s"
  /// ```
  ///
  /// - important: The returned string may include NULL bytes or other values which your program might not expect.
  ///   Percent-encoding has frequently been used to perform path traversal attacks, SQL injection, and exploit similar vulnerabilities
  ///   stemming from unvalidated input (somtimes under multiple levels of encoding). Ensure you do not over-decode your data,
  ///   and every time you _do_ decode some data, you must consider the result to be **entirely unvalidated**,
  ///   even if the source contents were previously validated.
  ///
  @inlinable @inline(__always) @_disfavoredOverload
  public func percentDecoded<Substitutions: SubstitutionMap>(substitutions: Substitutions._Member) -> String {
    percentDecoded(substitutions: substitutions.base)
  }

  // Default parameter: Substitutions == NoSubstitutions.

  /// Returns the percent-decoding of this string, interpreted as UTF-8 code-units.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  /// If the bytes obtained by percent-decoding this string represent anything other than UTF-8 text,
  /// use the `percentDecodedByteArray` function to decode the string as binary data.
  ///
  /// This function is equivalent to calling `percentDecoded(substitutions: .none)`.
  ///
  /// ```swift
  /// // Decode percent-encoded UTF-8 as a string.
  /// "hello%2C%20world!".percentDecoded() // "hello, world!"
  /// "%2Fusr%2Fbin%2Fswift".percentDecoded() // "/usr/bin/swift"
  /// "%F0%9F%98%8E".percentDecoded() // "😎"
  /// ```
  ///
  /// - important: The returned string may include NULL bytes or other values which your program might not expect.
  ///   Percent-encoding has frequently been used to perform path traversal attacks, SQL injection, and exploit similar vulnerabilities
  ///   stemming from unvalidated input (somtimes under multiple levels of encoding). Ensure you do not over-decode your data,
  ///   and every time you _do_ decode some data, you must consider the result to be **entirely unvalidated**,
  ///   even if the source contents were previously validated.
  ///
  @inlinable @inline(__always)
  public func percentDecoded() -> String {
    percentDecoded(substitutions: .none)
  }
}


// --------------------------------------------
// MARK: - Substitution Maps
// --------------------------------------------


#if swift(>=5.5)

  // For Swift 5.5+, provide static members on the PercentEncodeSet protocol. Requires SE-0299.
  // This is the preferred approach, as it does not require additional '_Member' overloads.

  extension SubstitutionMap where Self == NoSubstitutions {

    /// No substitutions. This is the substitution map used by all encode-sets specified in the URL standard, except form-encoding.
    ///
    @inlinable
    public static var none: NoSubstitutions { .init() }
  }

  extension SubstitutionMap where Self == URLEncodeSet.FormEncoding.Substitutions {

    /// Substitutions applicable to the [application/x-www-form-urlencoded][form-encoded] percent-encode set.
    ///
    /// [form-encoded]: https://url.spec.whatwg.org/#application-x-www-form-urlencoded-percent-encode-set
    ///
    @inlinable
    public static var formEncoding: URLEncodeSet.FormEncoding.Substitutions { .init() }
  }

#endif

// For older versions of Swift, use _StaticMember to provide a source-compatible interface.
// Unfortunately, we don't know whether our clients need compatibility with pre-5.5 toolchains,
// so these can't be only conditionally included.

extension _StaticMember where Base: SubstitutionMap {

  /// No substitutions. This applies to all encode-sets specified in the URL standard, except form-encoding.
  ///
  @inlinable
  public static var none: _StaticMember<NoSubstitutions> { .init(.init()) }

  /// Substitutions applicable to the [application/x-www-form-urlencoded][form-encoded] percent-encode set.
  ///
  /// [form-encoded]: https://url.spec.whatwg.org/#application-x-www-form-urlencoded-percent-encode-set
  ///
  @inlinable
  public static var formEncoding: _StaticMember<URLEncodeSet.FormEncoding.Substitutions> { .init(.init()) }
}

/// A substitution map which does not substitute/unsubstitute any code-points.
///
public struct NoSubstitutions: SubstitutionMap {

  @inlinable @inline(__always)
  public init() {}

  @inlinable @inline(__always)
  public func substitute(ascii codePoint: UInt8) -> UInt8? { nil }

  @inlinable @inline(__always)
  public func unsubstitute(ascii codePoint: UInt8) -> UInt8? { nil }
}


// --------------------------------------------
// MARK: - Encode Sets
// --------------------------------------------


#if swift(>=5.5)

  // For Swift 5.5+, provide static members on the PercentEncodeSet protocol. Requires SE-0299.
  // This is the preferred approach, as it does not require additional '_Member' overloads.

  extension PercentEncodeSet where Self == URLEncodeSet.C0Control {

    /// The [C0 control](https://url.spec.whatwg.org/#c0-control-percent-encode-set) percent-encode set.
    ///
    @inlinable
    public static var c0ControlSet: URLEncodeSet.C0Control { .init() }
  }

  extension PercentEncodeSet where Self == URLEncodeSet.Fragment {

    /// The [fragment](https://url.spec.whatwg.org/#fragment-percent-encode-set) percent-encode set.
    ///
    @inlinable
    public static var fragmentSet: URLEncodeSet.Fragment { .init() }
  }

  extension PercentEncodeSet where Self == URLEncodeSet.Query {

    /// The [query](https://url.spec.whatwg.org/#query-percent-encode-set) percent-encode set.
    ///
    @inlinable
    public static var querySet: URLEncodeSet.Query { .init() }
  }

  extension PercentEncodeSet where Self == URLEncodeSet.SpecialQuery {

    /// The [special query](https://url.spec.whatwg.org/#special-query-percent-encode-set) percent-encode set.
    ///
    @inlinable
    public static var specialQuerySet: URLEncodeSet.SpecialQuery { .init() }
  }

  extension PercentEncodeSet where Self == URLEncodeSet.Path {

    /// The [path](https://url.spec.whatwg.org/#path-percent-encode-set) percent-encode set.
    ///
    @inlinable
    public static var pathSet: URLEncodeSet.Path { .init() }
  }

  extension PercentEncodeSet where Self == URLEncodeSet.UserInfo {

    /// The [userinfo](https://url.spec.whatwg.org/#userinfo-percent-encode-set) percent-encode set.
    ///
    @inlinable
    public static var userInfoSet: URLEncodeSet.UserInfo { .init() }
  }

  extension PercentEncodeSet where Self == URLEncodeSet.Component {

    /// The [component](https://url.spec.whatwg.org/#component-percent-encode-set) percent-encode set.
    ///
    @inlinable
    public static var urlComponentSet: URLEncodeSet.Component { .init() }
  }

  extension PercentEncodeSet where Self == URLEncodeSet.FormEncoding {

    /// The [application/x-www-form-urlencoded](https://url.spec.whatwg.org/#application-x-www-form-urlencoded-percent-encode-set)
    /// percent-encode set.
    ///
    @inlinable
    public static var formEncoding: URLEncodeSet.FormEncoding { .init() }
  }

#endif

// For older versions of Swift, use _StaticMember to provide a source-compatible interface.
// Unfortunately, we don't know whether our clients need compatibility with pre-5.5 toolchains,
// so these can't be only conditionally included.

extension _StaticMember where Base: PercentEncodeSet {

  /// The [C0 control](https://url.spec.whatwg.org/#c0-control-percent-encode-set) percent-encode set.
  ///
  @inlinable
  public static var c0ControlSet: _StaticMember<URLEncodeSet.C0Control> { .init(.init()) }

  /// The [fragment](https://url.spec.whatwg.org/#fragment-percent-encode-set) percent-encode set.
  ///
  @inlinable
  public static var fragmentSet: _StaticMember<URLEncodeSet.Fragment> { .init(.init()) }

  /// The [query](https://url.spec.whatwg.org/#query-percent-encode-set) percent-encode set.
  ///
  @inlinable
  public static var querySet: _StaticMember<URLEncodeSet.Query> { .init(.init()) }

  /// The [special query](https://url.spec.whatwg.org/#special-query-percent-encode-set) percent-encode set.
  ///
  @inlinable
  public static var specialQuerySet: _StaticMember<URLEncodeSet.SpecialQuery> { .init(.init()) }

  /// The [path](https://url.spec.whatwg.org/#path-percent-encode-set) percent-encode set.
  ///
  @inlinable
  public static var pathSet: _StaticMember<URLEncodeSet.Path> { .init(.init()) }

  /// The [userinfo](https://url.spec.whatwg.org/#userinfo-percent-encode-set) percent-encode set.
  ///
  @inlinable
  public static var userInfoSet: _StaticMember<URLEncodeSet.UserInfo> { .init(.init()) }

  /// The [component](https://url.spec.whatwg.org/#component-percent-encode-set) percent-encode set.
  ///
  @inlinable
  public static var urlComponentSet: _StaticMember<URLEncodeSet.Component> { .init(.init()) }

  /// The [application/x-www-form-urlencoded](https://url.spec.whatwg.org/#application-x-www-form-urlencoded-percent-encode-set)
  /// percent-encode set.
  ///
  @inlinable
  public static var formEncoding: _StaticMember<URLEncodeSet.FormEncoding> { .init(.init()) }

  /// An internal percent-encode set for manipulating path components.
  ///
  @inlinable
  internal static var pathComponentSet: _StaticMember<URLEncodeSet._PathComponent> { .init(.init()) }
}

// URL encode-set implementations.

// ARM and x86 seem to have wildly different performance characteristics.
// The lookup table seems to be about 8-12% better than bitshifting on x86, but can be 90% slower on ARM.
@usableFromInline
internal protocol DualImplementedPercentEncodeSet: PercentEncodeSet {
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

/// A namespace for percent-encode sets defined by the URL Standard.
///
public enum URLEncodeSet {}

extension URLEncodeSet {

  public struct C0Control: PercentEncodeSet, DualImplementedPercentEncodeSet {

    @inlinable
    internal init() {}

    @inlinable @inline(__always)
    public func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
      __shouldPercentEncode(Self.self, ascii: codePoint)
    }

    @inlinable @inline(__always)
    internal static func shouldEscape_binary(ascii codePoint: UInt8) -> Bool {
      // TODO: [performance]: Benchmark alternative:
      // `codePoint & 0b11100000 == 0 || codePoint == 0x7F`
      // C0Control percent-encoding is used for opaque paths and opaque host names,
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

  public struct Fragment: PercentEncodeSet, DualImplementedPercentEncodeSet {

    @inlinable
    internal init() {}

    @inlinable @inline(__always)
    public func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
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

  public struct Query: PercentEncodeSet, DualImplementedPercentEncodeSet {

    @inlinable
    internal init() {}

    @inlinable @inline(__always)
    public func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
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

  public struct SpecialQuery: PercentEncodeSet, DualImplementedPercentEncodeSet {

    @inlinable
    internal init() {}

    @inlinable @inline(__always)
    public func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
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

  public struct Path: PercentEncodeSet, DualImplementedPercentEncodeSet {

    @inlinable
    internal init() {}

    @inlinable @inline(__always)
    public func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
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

  public struct UserInfo: PercentEncodeSet, DualImplementedPercentEncodeSet {

    @inlinable
    internal init() {}

    @inlinable @inline(__always)
    public func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
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
  public struct Component: PercentEncodeSet, DualImplementedPercentEncodeSet {

    @inlinable
    internal init() {}

    @inlinable @inline(__always)
    public func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
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

  public struct FormEncoding: PercentEncodeSet, DualImplementedPercentEncodeSet {

    @inlinable
    internal init() {}

    @inlinable @inline(__always)
    public func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
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

    public struct Substitutions: SubstitutionMap {

      @inlinable @inline(__always)
      public init() {}

      @inlinable @inline(__always)
      public func substitute(ascii codePoint: UInt8) -> UInt8? {
        codePoint == ASCII.space.codePoint ? ASCII.plus.codePoint : nil
      }

      @inlinable @inline(__always)
      public func unsubstitute(ascii codePoint: UInt8) -> UInt8? {
        codePoint == ASCII.plus.codePoint ? ASCII.space.codePoint : nil
      }
    }

    @inlinable @inline(__always)
    public var substitutions: Substitutions { .init() }
  }
}

// Non-standard encode-sets.

extension URLEncodeSet {

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
  internal struct _PathComponent: PercentEncodeSet {

    @inlinable
    internal init() {}

    @inlinable @inline(__always)
    internal func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
      __shouldPercentEncode(URLEncodeSet.Path.self, ascii: codePoint)
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
