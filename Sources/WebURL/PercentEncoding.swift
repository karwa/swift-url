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
/// Percent-encoding transforms arbitrary bytes to ASCII strings (e.g. the byte value 200, or `0xC8`, to `"%C8"`),
/// and is most commonly used to escape special characters in URLs. Data is encoded using an _encode-set_, which
/// determines whether a particular ASCII byte should be encoded. Non-ASCII bytes are always percent-encoded.
///
/// To percent-encode a string or some data, use the `.percentEncoded(using:)` or `.lazy.percentEncoded(using:)`
/// functions respectively. Similarly, the `.percentDecoded()` function can be used to decode a percent-encoded string.
///
/// The URL Standard defines many encode-sets, and you may define your own by conforming to this protocol
/// and implementing the ``shouldPercentEncode(ascii:)`` method. The following example demonstrates an encode-set
/// which encodes single and double ASCII quotation marks:
///
/// ```swift
/// struct NoQuotes: PercentEncodeSet {
///   func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
///     codePoint == Character("\"").asciiValue! ||
///     codePoint == Character("'").asciiValue!
///   }
/// }
///
/// #"Quoth the Raven "Nevermore.""#.percentEncoded(using: NoQuotes())
/// // "Quoth the Raven %22Nevermore.%22"
/// "Quoth the Raven %22Nevermore.%22".percentDecoded()
/// // "Quoth the Raven "Nevermore.""
///
/// #""He's over there", said Mary"#.percentEncoded(using: NoQuotes())
/// // "%22He%27s over there%22, said Mary"
/// "%22He%27s over there%22, said Mary".percentDecoded()
/// // ""He's over there", said Mary"
/// ```
///
/// **Form-encoding** is a legacy variant of percent-encoding, which includes a ``SubstitutionMap`` that replaces
/// spaces with the "+" character. Whilst you may define encode-sets with custom substitution maps, doing so
/// is discouraged.
///
/// ## Topics
///
/// ### Encode Sets from the URL Standard
///
/// - ``WebURL/PercentEncodeSet/urlComponentSet``
/// - ``WebURL/PercentEncodeSet/formEncoding``
/// - ``WebURL/PercentEncodeSet/c0ControlSet``
/// - ``WebURL/PercentEncodeSet/userInfoSet``
/// - ``WebURL/PercentEncodeSet/pathSet``
/// - ``WebURL/PercentEncodeSet/querySet``
/// - ``WebURL/PercentEncodeSet/specialQuerySet``
/// - ``WebURL/PercentEncodeSet/fragmentSet``
/// - ``WebURL/URLEncodeSet``
///
/// ### Requirements for Custom Encode Sets
///
/// - ``WebURL/PercentEncodeSet/shouldPercentEncode(ascii:)``
///
/// ### Substitution Maps
///
/// - ``WebURL/PercentEncodeSet/substitutions-swift.property-fk3r``
/// - ``WebURL/PercentEncodeSet/Substitutions-swift.associatedtype``
/// - ``WebURL/NoSubstitutions``
/// - ``WebURL/SubstitutionMap``
///
public protocol PercentEncodeSet {

  typealias _Member = _StaticMember<Self>

  /// Whether or not an ASCII code-point should be percent-encoded.
  ///
  /// If this function returns true, percent encoding will replace this byte with the ASCII string `"%XX"`, where
  /// `XX` is the byte's value in hexadecimal.
  ///
  /// ```swift
  /// struct NoSpaces: PercentEncodeSet {
  ///   func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
  ///     codePoint == Character(" ").asciiValue!
  ///   }
  /// }
  ///
  /// "Hello, world!".percentEncoded(using: NoSpaces())
  /// // "Hello,%20world!"
  /// ```
  ///
  /// If this function returns false and this encode-set includes a legacy substitution map,
  /// the byte may be substituted. Otherwise, it will be copied to the output.
  ///
  /// - parameters:
  ///   - codePoint: An ASCII code-point. Results for values > 127 are not specified.
  ///
  func shouldPercentEncode(ascii codePoint: UInt8) -> Bool

  /// A ``SubstitutionMap`` which may replace ASCII code-points that are not percent-encoded.
  ///
  /// This is a legacy feature to support form-encoding; modern percent-encoding does not use substitutions.
  /// Should you have reason to create a custom substitution map, please observe the following guidelines:
  ///
  /// 1. No code-point may be both percent-encoded and substituted. For any code-point `x`, only one of the following
  ///    must be true:
  ///
  ///     - `substitutions.substitute(ascii: x) != nil`, or
  ///     - `shouldPercentEncode(ascii: x)`
  ///
  /// 2. Substitute code-points _returned_ by `substitute(ascii:)` must be percent-encoded. In other words,
  ///
  ///     - If `y = substitutions.substitute(ascii: x)` and `y != nil`,
  ///     - `shouldPercentEncode(ascii: y)` must be `true`.
  ///
  /// For example, form-encoding substitutes spaces with the "+" character.
  /// It would be incorrect for that encode-set to say that the space character should be
  /// both substituted and percent-encoded (#1 above), and it must ensure that _actual_ "+" characters
  /// in the source data are percent-encoded (#2 above), so it is free to use "+" to encode spaces.
  ///
  associatedtype Substitutions: SubstitutionMap = NoSubstitutions

  /// The substitution map used by this encode-set.
  ///
  /// This is a legacy feature to support form-encoding; modern percent-encoding does not use substitutions.
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
/// This is a legacy feature to support form-encoding; regular percent-encode sets do not use substitutions.
/// For example, form-encoding does not percent-encode ASCII spaces (0x20) as "%20", and instead replaces them
/// with a "+" (0x2B). The following example demonstrates a potential implementation of this encoding:
///
/// ```swift
/// struct FormEncoding: PercentEncodeSet {
///
///   func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
///     // Do not percent-encode spaces, substitute instead.
///     if codePoint == 0x20 { return false }
///     // Percent-encode actual "+"s in the source.
///     if codePoint == 0x2B { return true }
///     // other codepoints...
///   }
///
///   struct Substitutions: SubstitutionMap {
///     func substitute(ascii codePoint: UInt8) -> UInt8? {
///       // Substitute spaces with "+".
///       codePoint == 0x20 ? 0x2B : nil
///     }
///     func unsubstitute(ascii codePoint: UInt8) -> UInt8? {
///       // Unsubstitute "+" to space.
///       codePoint == 0x2B ? 0x20 : nil
///     }
///   }
///
///   var substitutions: Substitutions { .init() }
/// }
/// ```
///
/// Most percent-encode sets use ``NoSubstitutions`` as their substitution map.
///
/// ## Topics
///
/// ### Substitution Maps Used By URLs
///
/// - ``WebURL/SubstitutionMap/none``
/// - ``WebURL/SubstitutionMap/formEncoding``
///
/// ### Requirements for Creating a Custom Substitution Map
///
/// - ``WebURL/SubstitutionMap/substitute(ascii:)``
/// - ``WebURL/SubstitutionMap/unsubstitute(ascii:)``
///
public protocol SubstitutionMap {

  typealias _Member = _StaticMember<Self>

  /// Returns the substitute to use for an ASCII code-point.
  ///
  /// In order to ensure accurate encoding, any code-points returned by this function must be percent-encoded by all
  /// ``PercentEncodeSet``s which use this substitution map.
  ///
  /// Some code-points must not be substituted:
  ///
  /// | Code Point(s)               | Values        |
  /// | ----------------------------| ------------- |
  /// | Percent sign, `%`           |     `0x25`    |
  /// | Digits, `0-9`               | `0x30...0x39` |
  /// | Uppercase hex alphas, `A-F` | `0x41...0x46` |
  /// | Lowercase hex alphas, `a-f` | `0x41...0x46` |
  ///
  /// - parameters:
  ///   - codePoint: An ASCII code-point. Results for values > 127 are not specified.
  ///
  /// - returns: The code-point to emit instead of `codePoint`, or `nil` if no substitution is required.
  ///            Substitute code-points must always be ASCII.
  ///
  func substitute(ascii codePoint: UInt8) -> UInt8?

  /// Restores a code-point from its substitute.
  ///
  /// This function restores all code-points substituted by ``substitute(ascii:)``.
  ///
  /// - parameters:
  ///   - codePoint: An ASCII code-point. Results for values > 127 are not specified.
  ///
  /// - returns: The code-point restored from `codePoint`, or `nil` if `codePoint` is not a substitute.
  ///            Restored code-points must always be ASCII.
  ///
  func unsubstitute(ascii codePoint: UInt8) -> UInt8?

  /// Returns `true` if it can be trivially determined that the given source bytes do not require decoding.
  ///
  /// For ``NoSubstitutions``, this means the bytes do not contain any "%" signs.
  /// For ``formEncoding``, this means the bytes do not contain any "%" signs or "+" signs.
  /// For custom substitution maps, this returns `false`.
  ///
  func _canSkipDecoding(_ source: UnsafeBufferPointer<UInt8>) -> Bool
}

extension SubstitutionMap {

  @inlinable @inline(__always)
  public func _canSkipDecoding(_ source: UnsafeBufferPointer<UInt8>) -> Bool {
    false
  }
}


// --------------------------------------------
// MARK: - Encoding
// --------------------------------------------


/// A `Collection` which percent-encodes elements from its `Source` on-demand using a given `EncodeSet`.
///
/// Percent-encoding transforms arbitrary bytes to ASCII strings (e.g. the byte value 200, or `0xC8`, to `"%C8"`),
/// and is most commonly used to escape special characters in URLs. Data is encoded using a ``PercentEncodeSet``, which
/// determines whether a particular ASCII byte should be encoded. Non-ASCII bytes are always percent-encoded.
/// The elements of this collection are guaranteed to be ASCII code-units, and hence valid UTF-8.
///
/// To encode a source collection, use the extension methods provided on `LazyCollectionProtocol`:
///
/// ```swift
/// // Lazy encoding is especially useful when writing data to a buffer,
/// // as it avoids allocating additional memory.
/// var buffer: Data = ...
/// let image:  Data = ...
/// buffer.append(contentsOf: image.lazy.percentEncoded(using: .urlComponentSet))
/// // buffer = [...] "%BAt_%E0%11%22%EB%10%2C%7F" [...]
///
/// // Encode-sets determine which characters are encoded, and some perform substitutions.
/// let bytes = "hello, world!".utf8
/// bytes.lazy.percentEncoded(using: .urlComponentSet)
///   .elementsEqual("hello%2C%20world!".utf8) // ✅
/// //                        ^^^     ^
/// bytes.lazy.percentEncoded(using: .formEncoding)
///   .elementsEqual("hello%2C+world%21".utf8) // ✅
/// //                        ^     ^^^
/// ```
///
/// Encode-sets may also include a ``SubstitutionMap``. If a code-point is not percent-encoded, the substitution map may
/// replace it with a different character. Content encoded with substitutions must be decoded using the same
/// substitution map it was created with.
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

  /// Returns the total length of the encoded UTF-8 bytes, and whether or not any code-units were altered
  /// by the `EncodeSet`. The length is calculated using arithmetic which wraps on overflow.
  ///
  /// This is useful for estimating an allocation size required to hold the contents, but **does not** eliminate
  /// the need to bounds-check when writing to that allocation.
  ///
  /// Ultimately, any user-supplied generic collection must be treated as potentially buggy,
  /// including returning a different number of elements each time it is iterated.
  /// It is unacceptable even for bugs like that to lead to memory-safety errors,
  /// therefore this value must **only** be interpreted as an estimated/expected size,
  /// and not relied upon for safety (although it is acceptable to `fatalError` if the actual size differs
  /// from this expected size).
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
  /// with bytes within the ASCII range being restricted by `encodeSet`.
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions;
  /// provide the appropriate ``SubstitutionMap`` when decoding form-encoded data to accurately recover the source contents.
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
  /// with bytes within the ASCII range being restricted by `encodeSet`.
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions;
  /// provide the appropriate ``SubstitutionMap`` when decoding form-encoded data to accurately recover the source contents.
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
  /// with bytes within the ASCII range being restricted by `encodeSet`.
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions;
  /// provide the appropriate ``SubstitutionMap`` when decoding form-encoded data to accurately recover the source contents.
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
  /// with bytes within the ASCII range being restricted by `encodeSet`.
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions;
  /// provide the appropriate ``SubstitutionMap`` when decoding form-encoded data to accurately recover the source contents.
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
  /// with bytes within the ASCII range being restricted by `encodeSet`.
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions;
  /// provide the appropriate ``SubstitutionMap`` when decoding form-encoded data to accurately recover the source contents.
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
    _withContiguousUTF8 { $0.percentEncodedString(using: encodeSet) }
  }

  // _StaticMember variant for pre-5.5 toolchains.

  /// Returns an ASCII string formed by percent-encoding this string's UTF-8 representation.
  ///
  /// Percent-encoding transforms arbitrary bytes to ASCII strings (e.g. the byte value 200, or 0xC8, to the string "%C8"),
  /// with bytes within the ASCII range being restricted by `encodeSet`.
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions;
  /// provide the appropriate ``SubstitutionMap`` when decoding form-encoded data to accurately recover the source contents.
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
/// Percent-decoding transforms certain ASCII sequences to bytes (`"%AB"` to the byte value `0xAB`, or 171),
/// and is most commonly used to decode content from URLs. The elements of this collection are raw bytes,
/// potentially including NULL bytes or invalid UTF-8.
///
/// To decode a source collection containing a percent-encoded string,
/// use the extension methods provided on `LazyCollectionProtocol`:
///
/// ```swift
/// // Lazy decoding is especially useful for looking through decoded content.
/// // When used with WebURL's UTF8View, you can process encoded URL components
/// // without allocating additional memory.
/// let someURLs: [WebURL] = [
///   WebURL("https://root@example.com/")!,
///   WebURL("https://%72oot@example.com/")!,
///   WebURL("https://r%6F%6Ft@example.com/")!
/// ]
/// for url in someURLs {
///   guard let usernameUTF8 = url.utf8.username else {
///     continue // No username.
///   }
///   if usernameUTF8.lazy.percentDecoded().elementsEqual("root".utf8) {
///     throw InvalidUsernameError()
///   }
/// }
///
/// // Any Collection of bytes can be lazily decoded, including
/// // String's UTF8View, Foundation's Data, NIO's ByteBuffer, etc.
/// "%61%62%63".utf8
///   .lazy.percentDecoded()
///   .elementsEqual("abc".utf8) // ✅
/// ```
///
/// > Note: This type does not reverse substitutions made by form-encoding.
/// > Use ``LazilyPercentDecodedWithSubstitutions`` providing the ``SubstitutionMap/formEncoding``
/// > substitution map, to lazily decode form-encoded content.
///
public typealias LazilyPercentDecoded<Source> = LazilyPercentDecodedWithSubstitutions<Source, NoSubstitutions>
where Source: Collection, Source.Element == UInt8

/// A `Collection` which percent-decodes elements from its `Source` on-demand,
/// and reverses substitutions made by a ``SubstitutionMap``.
///
/// Percent-decoding transforms certain ASCII sequences to bytes (`"%AB"` to the byte value `0xAB`, or 171),
/// and is most commonly used to decode content from URLs. The elements of this collection are raw bytes,
/// potentially including NULL bytes or invalid UTF-8.
///
/// This type supports decoding content containing legacy substitutions (such as form-encoding).
/// To decode a source collection, use the extension methods provided on `LazyCollectionProtocol`:
///
/// ```swift
/// // Lazy decoding is especially useful for looking through decoded content.
/// // When used with WebURL's UTF8View, you can process encoded URL components
/// // without allocating additional memory.
/// let url = WebURL("https://example.com/?user=karl&the+m%65ssage=h%C2%A3llo+world")!
///
/// var buffer: [UInt8] = []
/// guard let queryUTF8 = url.utf8.query else {
///   return
/// }
/// // Splits the query in to key-value pairs, and lazily form-decodes the
/// // key and value without allocating.
/// for keyValuePairUTF8 in query.lazy.split("&") {
///   let (key, value) = keyValuePairUTF8.splitOnce(at: "=")
///   if key.lazy.percentDecoded(substitutions: .formEncoding).elementsEqual("the message") {
///     buffer.append(contentsOf: value.lazy.percentDecoded(substitutions: .formEncoding))
///   }
/// }
/// // buffer = "h£llo world"
/// ```
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
  /// The index's predecessor may be obtained by creating another index ending at the index's `range.lowerBound`.
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

extension LazilyPercentDecodedWithSubstitutions {

  /// Whether the byte at the given index has been percent-decoded or unsubstituted from the source contents.
  ///
  /// The given index must be valid for this collection.
  /// If `false`, the byte at this index is returned verbatim from the source collection.
  /// If the index is ``endIndex``, this function returns `false`.
  ///
  /// ```swift
  /// let decoded = "h%65llo".utf8.lazy.percentDecoded()
  ///
  /// var idx = decoded.startIndex
  /// UnicodeScalar(decoded[idx]) // "h"
  /// decoded.isByteDecodedOrUnsubstituted(at: idx) // false
  ///
  /// decoded.formIndex(after: &idx)
  /// UnicodeScalar(decoded[idx]) // "e"
  /// decoded.isByteDecodedOrUnsubstituted(at: idx) // true
  /// ```
  ///
  @inlinable
  public func isByteDecodedOrUnsubstituted(at i: Index) -> Bool {
    i.isDecodedOrUnsubstituted
  }

  /// The range of elements from the source collection contributing to the value at the given index.
  ///
  /// The given index must be valid for this collection.
  /// If the index is ``endIndex``, the result is an empty range whose bounds are equal to the source's `endIndex`.
  /// Otherwise, the result covers either one or three bytes from the source.
  ///
  /// ```swift
  /// let source = "h%65llo".utf8
  /// let decoded = source.lazy.percentDecoded()
  ///
  /// var idx = decoded.startIndex
  /// UnicodeScalar(decoded[idx]) // "h"
  /// String(source[decoded.sourceIndices(at: idx)]) // "h"
  ///
  /// decoded.formIndex(after: &idx)
  /// UnicodeScalar(decoded[idx]) // "e"
  /// String(source[decoded.sourceIndices(at: idx)]) // "%65"
  /// ```
  ///
  @inlinable
  public func sourceIndices(at i: Index) -> Range<Source.Index> {
    i.sourceRange
  }
}

// Internal utilities.

extension Collection where Element == UInt8 {

  /// Returns the percent-decoding of this collection's elements, interpreted as UTF-8 code-units.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode form-encoded content.
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
  ///   stemming from unvalidated input (sometimes under multiple levels of encoding). Ensure you do not over-decode your data,
  ///   and every time you _do_ decode some data, you must consider the result to be **entirely unvalidated**,
  ///   even if the source contents were previously validated.
  ///
  @inlinable
  internal func percentDecodedString<Substitutions: SubstitutionMap>(substitutions: Substitutions) -> String {
    withContiguousStorageIfAvailable { sourceBytes in
      if substitutions._canSkipDecoding(sourceBytes) {
        return String(decoding: sourceBytes, as: UTF8.self)
      } else {
        return String(discontiguousUTF8: sourceBytes.boundsChecked.lazy.percentDecoded(substitutions: substitutions))
      }
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
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode form-encoded content, or `.none` for modern percent-encoded content.
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
  /// The elements of this collection are raw bytes, potentially including NULL bytes or invalid UTF-8.
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
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode form-encoded content, or `.none` for modern percent-encoded content.
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
  /// The elements of this collection are raw bytes, potentially including NULL bytes or invalid UTF-8.
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
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode form-encoded content, or `.none` for modern percent-encoded content.
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
  /// The elements of this collection are raw bytes, potentially including NULL bytes or invalid UTF-8.
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
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode form-encoded content, or `.none` for modern percent-encoded content.
  ///
  /// ```swift
  /// let originalImage: Data = ...
  ///
  /// // Encode the data, e.g. using form-encoding.
  /// let encodedImage = originalImage.percentEncodedString(using: .formEncoding) // "%BAt_%E0%11%22%EB%10%2C%7F..."
  ///
  /// // Decode the data, giving the appropriate substitution map.
  /// let decodedImage = encodedImage.percentDecodedBytesArray(substitutions: .formEncoding)
  /// assert(decodedImage.elementsEqual(originalImage)) // ✅
  /// ```
  ///
  /// The returned data contains raw bytes, potentially including NULL bytes or invalid UTF-8.
  ///
  @inlinable
  public func percentDecodedBytesArray<Substitutions: SubstitutionMap>(substitutions: Substitutions) -> [UInt8] {
    _withContiguousUTF8 { utf8 in
      if substitutions._canSkipDecoding(utf8) {
        return Array(utf8)
      }
      return Array(utf8.lazy.percentDecoded(substitutions: substitutions))
    }
  }

  // _StaticMember variant for pre-5.5 toolchains.

  /// Returns the percent-decoding of this string as binary data.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode form-encoded content, or `.none` for modern percent-encoded content.
  ///
  /// ```swift
  /// let originalImage: Data = ...
  ///
  /// // Encode the data, e.g. using form-encoding.
  /// let encodedImage = originalImage.percentEncodedString(using: .formEncoding) // "%BAt_%E0%11%22%EB%10%2C%7F..."
  ///
  /// // Decode the data, giving the appropriate substitution map.
  /// let decodedImage = encodedImage.percentDecodedBytesArray(substitutions: .formEncoding)
  /// assert(decodedImage.elementsEqual(originalImage)) // ✅
  /// ```
  ///
  /// The returned data contains raw bytes, potentially including NULL bytes or invalid UTF-8.
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
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode form-encoded content, or `.none` for modern percent-encoded content.
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
  /// The returned data contains raw bytes, potentially including NULL bytes or invalid UTF-8.
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
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode form-encoded content, or `.none` for modern percent-encoded content.
  ///
  /// If the bytes obtained by percent-decoding this string represent anything other than UTF-8 text,
  /// use the `percentDecodedByteArray` function to decode the string as binary data.
  ///
  /// ```swift
  /// // Decode percent-encoded UTF-8 as a string.
  /// "hello,%20world!".percentDecoded(substitutions: .none) // "hello, world!"
  /// "%2Fusr%2Fbin%2Fswift".percentDecoded(substitutions: .none) // "/usr/bin/swift"
  ///
  /// // Form-encoded content requires a substitution map to accurately decode.
  /// "king+of+the+%F0%9F%A6%86s".percentDecoded(substitutions: .formEncoding) // "king of the 🦆s"
  /// ```
  ///
  /// - important: The returned string may include NULL bytes or other values which your program might not expect.
  ///   Percent-encoding has frequently been used to perform path traversal attacks, SQL injection, and exploit similar vulnerabilities
  ///   stemming from unvalidated input (sometimes under multiple levels of encoding). Ensure you do not over-decode your data,
  ///   and every time you _do_ decode some data, you must consider the result to be **entirely unvalidated**,
  ///   even if the source contents were previously validated.
  ///
  @inlinable
  public func percentDecoded<Substitutions: SubstitutionMap>(substitutions: Substitutions) -> String {
    _withContiguousUTF8 { utf8 in
      if substitutions._canSkipDecoding(utf8) {
        return String(self)
      }
      return utf8.percentDecodedString(substitutions: substitutions)
    }
  }

  // _StaticMember variant for pre-5.5 toolchains.

  /// Returns the percent-decoding of this string, interpreted as UTF-8 code-units.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode form-encoded content, or `.none` for modern percent-encoded content.
  ///
  /// If the bytes obtained by percent-decoding this string represent anything other than UTF-8 text,
  /// use the `percentDecodedByteArray` function to decode the string as binary data.
  ///
  /// ```swift
  /// // Decode percent-encoded UTF-8 as a string.
  /// "hello,%20world!".percentDecoded(substitutions: .none) // "hello, world!"
  /// "%2Fusr%2Fbin%2Fswift".percentDecoded(substitutions: .none) // "/usr/bin/swift"
  ///
  /// // Form-encoded content requires a substitution map to accurately decode.
  /// "king+of+the+%F0%9F%A6%86s".percentDecoded(substitutions: .formEncoding) // "king of the 🦆s"
  /// ```
  ///
  /// - important: The returned string may include NULL bytes or other values which your program might not expect.
  ///   Percent-encoding has frequently been used to perform path traversal attacks, SQL injection, and exploit similar vulnerabilities
  ///   stemming from unvalidated input (sometimes under multiple levels of encoding). Ensure you do not over-decode your data,
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
  ///
  /// Form-encoding (as used by HTML forms) is a legacy variant of percent-encoding which includes substitutions; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode form-encoded content, or `.none` for modern percent-encoded content.
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
  ///   stemming from unvalidated input (sometimes under multiple levels of encoding). Ensure you do not over-decode your data,
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


/// Threshold for percent-decoding fast-path.
/// If the source contains more bytes than this, it should be assumed to contain percent-decoding.
/// If it contains fewer bytes, it's likely profitable to check whether decoding is really required or not.
@usableFromInline let _percentDecodingFastPathThreshold = 200

#if swift(>=5.5)

  // For Swift 5.5+, provide static members on the PercentEncodeSet protocol. Requires SE-0299.
  // This is the preferred approach, as it does not require additional '_Member' overloads.

  extension SubstitutionMap where Self == NoSubstitutions {

    /// No substitutions. This is the default for all regular percent-encode sets; substitutions are a legacy
    /// feature used only by form-encoding.
    ///
    @inlinable
    public static var none: NoSubstitutions { .init() }
  }

  extension SubstitutionMap where Self == URLEncodeSet.FormEncoding.Substitutions {

    /// Form-encoding. This substitution map is used to encode or decode
    /// [application/x-www-form-urlencoded][form-encoded] content.
    ///
    /// [form-encoded]: https://url.spec.whatwg.org/#application/x-www-form-urlencoded
    ///
    /// ## See Also
    ///
    /// - ``WebURL/PercentEncodeSet/formEncoding``
    ///
    @inlinable
    public static var formEncoding: URLEncodeSet.FormEncoding.Substitutions { .init() }
  }

#endif

// For older versions of Swift, use _StaticMember to provide a source-compatible interface.
// Unfortunately, we don't know whether our clients need compatibility with pre-5.5 toolchains,
// so these can't be only conditionally included.

extension _StaticMember where Base: SubstitutionMap {

  /// No substitutions. This is the default for all regular percent-encode sets; substitutions are a legacy
  /// feature used only by form-encoding.
  ///
  /// > Note:
  /// > This is a fallback API for pre-5.5 Swift compilers. Please refer to ``SubstitutionMap/none``.
  ///
  @inlinable
  public static var none: _StaticMember<NoSubstitutions> { .init(.init()) }

  /// Form-encoding. This substitution map is used to encode or decode
  /// [application/x-www-form-urlencoded][form-encoded] content.
  ///
  /// [form-encoded]: https://url.spec.whatwg.org/#application/x-www-form-urlencoded
  ///
  /// > Note:
  /// > This is a fallback API for pre-5.5 Swift compilers. Please refer to ``SubstitutionMap/formEncoding``.
  ///
  @inlinable
  public static var formEncoding: _StaticMember<URLEncodeSet.FormEncoding.Substitutions> { .init(.init()) }
}

/// A substitution map which does not substitute any code-points.
///
/// This is the default substitution map for all regular percent-encode sets;
/// substitutions are a legacy feature used only by form-encoding.
///
public struct NoSubstitutions: SubstitutionMap {

  @inlinable @inline(__always)
  public init() {}

  @inlinable @inline(__always)
  public func substitute(ascii codePoint: UInt8) -> UInt8? { nil }

  @inlinable @inline(__always)
  public func unsubstitute(ascii codePoint: UInt8) -> UInt8? { nil }

  @inlinable @inline(__always)
  public func _canSkipDecoding(_ source: UnsafeBufferPointer<UInt8>) -> Bool {
    source.count <= _percentDecodingFastPathThreshold
      && !source.boundsChecked.uncheckedFastContains(ASCII.percentSign.codePoint)
  }
}


// --------------------------------------------
// MARK: - Encode Sets
// --------------------------------------------


#if swift(>=5.5)

  // For Swift 5.5+, provide static members on the PercentEncodeSet protocol. Requires SE-0299.
  // This is the preferred approach, as it does not require additional '_Member' overloads.

  extension PercentEncodeSet where Self == URLEncodeSet.C0Control {

    /// The ASCII C0 Controls and U+007F DELETE.
    ///
    /// This encode-set is [defined][definition] by the URL Standard.
    ///
    /// [definition]: https://url.spec.whatwg.org/#c0-control-percent-encode-set
    ///
    @inlinable
    public static var c0ControlSet: URLEncodeSet.C0Control { .init() }
  }

  extension PercentEncodeSet where Self == URLEncodeSet.Fragment {

    /// The fragment percent-encode set.
    ///
    /// This encode-set is [defined][definition] by the URL Standard, and is used to encode
    /// content for the URL's ``WebURL/fragment`` component.
    ///
    /// [definition]: https://url.spec.whatwg.org/#fragment-percent-encode-set
    ///
    @inlinable
    public static var fragmentSet: URLEncodeSet.Fragment { .init() }
  }

  extension PercentEncodeSet where Self == URLEncodeSet.Query {

    /// The query percent-encode set used for non-special schemes.
    ///
    /// This encode-set is [defined][definition] by the URL Standard, and is used to encode
    /// content for the URL's ``WebURL/query`` component for non-special schemes.
    ///
    /// [definition]: https://url.spec.whatwg.org/#query-percent-encode-set
    ///
    @inlinable
    public static var querySet: URLEncodeSet.Query { .init() }
  }

  extension PercentEncodeSet where Self == URLEncodeSet.SpecialQuery {

    /// The query percent-encode set used for special schemes.
    ///
    /// This encode-set is [defined][definition] by the URL Standard, and is used to encode
    /// content for the URL's ``WebURL/query`` component for special schemes.
    ///
    /// [definition]: https://url.spec.whatwg.org/#special-query-percent-encode-set
    ///
    @inlinable
    public static var specialQuerySet: URLEncodeSet.SpecialQuery { .init() }
  }

  extension PercentEncodeSet where Self == URLEncodeSet.Path {

    /// The path percent-encode set used for special schemes.
    ///
    /// This encode-set is [defined][definition] by the URL Standard, and is used to encode
    /// content for the URL's ``WebURL/path`` component for special schemes.
    ///
    /// > Note:
    /// > This encode-set is used to percent-encode an individual parsed path component,
    /// > and does not include the path delimiter characters themselves. This makes it, counter-intuitively,
    /// > **unsuitable for encoding strings you wish to include in a URL's path**.
    /// > Instead, use the ``WebURL/PercentEncodeSet/urlComponentSet``.
    /// >
    /// > ```swift
    /// > func getURL_bad(_ username: String) -> String {
    /// >   var url  = WebURL("https://example.com")!
    /// >   url.path = "/users/" + username.percentEncoded(using: .pathSet) + "/profile"
    /// >   return url
    /// > }
    /// > getURL_bad("AC/DC")
    /// > // ❌ "https://example.com/users/AC/DC/profile"
    /// > //                               ^^^^^
    /// > getURL_bad("../about")
    /// > // ❌ "https://example.com/about/profile"
    /// > //                        ^^^^^^^^^^^^^^
    /// >
    /// > func getURL_good(_ username: String) -> String {
    /// >   var url  = WebURL("https://example.com")!
    /// >   url.path = "/users/" + username.percentEncoded(using: .urlComponentSet) + "/profile"
    /// >   return url
    /// > }
    /// > getURL_good("AC/DC")
    /// > // ✅ "https://example.com/users/AC%2FDC/profile"
    /// > //                               ^^^^^^^
    /// > getURL_good("../about")
    /// > // ✅ "https://example.com/users/..%2Fabout/profile"
    /// > //                               ^^^^^^^^^^
    /// > ```
    ///
    /// [definition]: https://url.spec.whatwg.org/#path-percent-encode-set
    ///
    @inlinable
    public static var pathSet: URLEncodeSet.Path { .init() }
  }

  extension PercentEncodeSet where Self == URLEncodeSet.UserInfo {

    /// The userinfo percent-encode set.
    ///
    /// This encode-set is [defined][definition] by the URL Standard, and is used to encode
    /// content for the URL's ``WebURL/username`` and ``WebURL/password`` components.
    ///
    /// [definition]: https://url.spec.whatwg.org/#userinfo-percent-encode-set
    ///
    @inlinable
    public static var userInfoSet: URLEncodeSet.UserInfo { .init() }
  }

  extension PercentEncodeSet where Self == URLEncodeSet.Component {

    /// The component percent-encode set. This set includes almost all special characters, making
    /// it suitable for encoding arbitrary strings at runtime for use in any URL component.
    ///
    /// This encode-set is [defined][definition] by the URL Standard, and is used for the JavaScript API
    /// `encodeURIComponent`.
    ///
    /// Since this encode-set includes almost all special characters, it is simpler to list the characters
    /// it **does not** encode. The allowed characters are:
    ///
    /// | Description             | Characters |
    /// | ----------------------- | ---------- |
    /// | Exclamation Mark        |     `!`    |
    /// | Apostrophe/Single-quote |     `'`    |
    /// | Parentheses             |    `()`    |
    /// | Asterisk                |     `*`    |
    /// | Minus                   |     `-`    |
    /// | Period                  |     `.`    |
    /// | Digits                  |    `0-9`   |
    /// | Uppercase alphas        |    `A-Z`   |
    /// | Underscore              |     `_`    |
    /// | Lowercase alphas        |    `a-z`   |
    /// | Tilde                   |     `~`    |
    ///
    /// The component encode-set is a good default to use when you need to exactly preserve a string containing
    /// arbitrary user input and include it in a URL component.
    ///
    /// Note however that even this small number of allowed characters is sometimes still too many when URLs are
    /// included in documents. Unescaped single quotes in URLs can be used to perform truncation attacks,
    /// for example in JavaScript strings, and unescaped asterisks and underscores might be parsed as Markdown styling
    /// annotations (for example, Xcode considers "`scheme://x/abc**cd`" as starting bold text).
    ///
    /// [definition]: https://url.spec.whatwg.org/#component-percent-encode-set
    ///
    @inlinable
    public static var urlComponentSet: URLEncodeSet.Component { .init() }
  }

  extension PercentEncodeSet where Self == URLEncodeSet.FormEncoding {

    /// Form-encoding. This encode-set is used to encode [application/x-www-form-urlencoded][form-encoded]
    /// content. It is unique in that it performs substitutions as well as percent-encoding.
    ///
    /// When creating form-encoded content, ensure that the receiver is also expecting form-encoded content.
    /// Form-encoding uses a legacy variant of percent-encoding that is not compatible with regular decoding
    /// due to its use of substitutions.
    ///
    /// When decoding form-encoded content, specify the ``SubstitutionMap/formEncoding`` substitution map.
    ///
    /// ```swift
    /// "hello world!".percentEncoded(using: .formEncoding)
    /// // ✅ "hello+world%21"
    ///
    /// // ℹ️ Make sure to decode with `.formEncoding` substitutions!
    /// "hello+world%21".percentDecoded()
    /// // ❌ "hello+world!"
    /// //          ^
    /// "hello+world%21".percentDecoded(substitutions: .formEncoding)
    /// // ✅ "hello world!"
    /// //          ^
    /// ```
    ///
    /// [form-encoded]: https://url.spec.whatwg.org/#application/x-www-form-urlencoded
    ///
    /// ## See Also
    ///
    /// - ``WebURL/SubstitutionMap/formEncoding``
    ///
    @inlinable
    public static var formEncoding: URLEncodeSet.FormEncoding { .init() }
  }

#endif

// For older versions of Swift, use _StaticMember to provide a source-compatible interface.
// Unfortunately, we don't know whether our clients need compatibility with pre-5.5 toolchains,
// so these can't be only conditionally included.

extension _StaticMember where Base: PercentEncodeSet {

  /// The ASCII C0 Controls and U+007F DELETE.
  ///
  /// This encode-set is [defined][definition] by the URL Standard.
  ///
  /// [definition]: https://url.spec.whatwg.org/#c0-control-percent-encode-set
  ///
  /// > Note:
  /// > This is a fallback API for pre-5.5 Swift compilers. Please refer to ``PercentEncodeSet/c0ControlSet``.
  ///
  @inlinable
  public static var c0ControlSet: _StaticMember<URLEncodeSet.C0Control> { .init(.init()) }

  /// The fragment percent-encode set.
  ///
  /// This encode-set is [defined][definition] by the URL Standard, and is used to encode
  /// content for the URL's ``WebURL/fragment`` component.
  ///
  /// [definition]: https://url.spec.whatwg.org/#fragment-percent-encode-set
  ///
  /// > Note:
  /// > This is a fallback API for pre-5.5 Swift compilers. Please refer to ``PercentEncodeSet/fragmentSet``.
  ///
  @inlinable
  public static var fragmentSet: _StaticMember<URLEncodeSet.Fragment> { .init(.init()) }

  /// The query percent-encode set used for non-special schemes.
  ///
  /// This encode-set is [defined][definition] by the URL Standard, and is used to encode
  /// content for the URL's ``WebURL/query`` component for non-special schemes.
  ///
  /// [definition]: https://url.spec.whatwg.org/#query-percent-encode-set
  ///
  /// > Note:
  /// > This is a fallback API for pre-5.5 Swift compilers. Please refer to ``PercentEncodeSet/querySet``.
  ///
  @inlinable
  public static var querySet: _StaticMember<URLEncodeSet.Query> { .init(.init()) }

  /// The query percent-encode set used for special schemes.
  ///
  /// This encode-set is [defined][definition] by the URL Standard, and is used to encode
  /// content for the URL's ``WebURL/query`` component for special schemes.
  ///
  /// [definition]: https://url.spec.whatwg.org/#special-query-percent-encode-set
  ///
  /// > Note:
  /// > This is a fallback API for pre-5.5 Swift compilers. Please refer to ``PercentEncodeSet/specialQuerySet``.
  ///
  @inlinable
  public static var specialQuerySet: _StaticMember<URLEncodeSet.SpecialQuery> { .init(.init()) }

  /// The path percent-encode set used for special schemes.
  ///
  /// This encode-set is [defined][definition] by the URL Standard, and is used to encode
  /// content for the URL's ``WebURL/path`` component for special schemes.
  ///
  /// > Note:
  /// > This encode-set is used to percent-encode an individual parsed path component,
  /// > and does not include the path delimiter characters themselves. This makes it, counter-intuitively,
  /// > **unsuitable for encoding strings you wish to include in a URL's path**.
  /// > Instead, use the ``WebURL/PercentEncodeSet/urlComponentSet``.
  ///
  /// [definition]: https://url.spec.whatwg.org/#path-percent-encode-set
  ///
  /// > Note:
  /// > This is a fallback API for pre-5.5 Swift compilers. Please refer to ``PercentEncodeSet/pathSet``.
  ///
  @inlinable
  public static var pathSet: _StaticMember<URLEncodeSet.Path> { .init(.init()) }

  /// The userinfo percent-encode set.
  ///
  /// This encode-set is [defined][definition] by the URL Standard, and is used to encode
  /// content for the URL's ``WebURL/username`` and ``WebURL/password`` components.
  ///
  /// [definition]: https://url.spec.whatwg.org/#userinfo-percent-encode-set
  ///
  /// > Note:
  /// > This is a fallback API for pre-5.5 Swift compilers. Please refer to ``PercentEncodeSet/userInfoSet``.
  ///
  @inlinable
  public static var userInfoSet: _StaticMember<URLEncodeSet.UserInfo> { .init(.init()) }

  /// The component percent-encode set. This set includes almost all special characters, making
  /// it suitable for encoding arbitrary strings at runtime for use in any URL component.
  ///
  /// This encode-set is [defined][definition] by the URL Standard, and is used for the JavaScript API
  /// `encodeURIComponent`.
  ///
  /// > Note:
  /// > This is a fallback API for pre-5.5 Swift compilers. Please refer to ``PercentEncodeSet/urlComponentSet``.
  ///
  @inlinable
  public static var urlComponentSet: _StaticMember<URLEncodeSet.Component> { .init(.init()) }

  /// Form-encoding. This encode-set is used to encode [application/x-www-form-urlencoded][form-encoded]
  /// content. It is unique in that it performs substitutions as well as percent-encoding.
  ///
  /// When creating form-encoded content, ensure that the receiver is also expecting form-encoded content.
  /// Form-encoding uses a legacy variant of percent-encoding that is not compatible with regular decoding
  /// due to its use of substitutions.
  ///
  /// When decoding form-encoded content, specify the ``SubstitutionMap/formEncoding`` substitution map.
  ///
  /// ```swift
  /// "hello world!".percentEncoded(using: .formEncoding)
  /// // ✅ "hello+world%21"
  ///
  /// // ℹ️ Make sure to decode with `.formEncoding` substitutions!
  /// "hello+world%21".percentDecoded()
  /// // ❌ "hello+world!"
  /// //          ^
  /// "hello+world%21".percentDecoded(substitutions: .formEncoding)
  /// // ✅ "hello world!"
  /// //          ^
  /// ```
  ///
  /// [form-encoded]: https://url.spec.whatwg.org/#application/x-www-form-urlencoded
  ///
  /// > Note:
  /// > This is a fallback API for pre-5.5 Swift compilers. Please refer to ``PercentEncodeSet/formEncoding``.
  ///
  @inlinable
  public static var formEncoding: _StaticMember<URLEncodeSet.FormEncoding> { .init(.init()) }
}

// URL encode-set implementations.

// ARM and x86 seem to have wildly different performance characteristics.
// The lookup table seems to be about 8-12% better than bit-shifting on x86, but can be 90% slower on ARM.
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
/// These types are generally not referred to directly; instead, use the static members available
/// on ``PercentEncodeSet``.
///
public enum URLEncodeSet {}

extension URLEncodeSet {

  /// The C0 Control percent-encode set. See the static member ``WebURL/PercentEncodeSet/c0ControlSet`` for details.
  ///
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

  /// The fragment percent-encode set. See the static member ``WebURL/PercentEncodeSet/fragmentSet`` for details.
  ///
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

  /// The query percent-encode set. See the static member ``WebURL/PercentEncodeSet/querySet`` for details.
  ///
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

  /// The special-query percent-encode set. See the static member ``WebURL/PercentEncodeSet/specialQuerySet``
  /// for details.
  ///
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

  /// The path percent-encode set. See the static member ``WebURL/PercentEncodeSet/pathSet`` for details.
  ///
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

  /// The userinfo percent-encode set. See the static member ``WebURL/PercentEncodeSet/userInfoSet`` for details.
  ///
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

  /// The component percent-encode set. See the static member ``WebURL/PercentEncodeSet/urlComponentSet`` for details.
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

  /// Form-encoding. See the static member ``WebURL/PercentEncodeSet/formEncoding`` for details.
  ///
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

      @inlinable @inline(__always)
      public func _canSkipDecoding(_ source: UnsafeBufferPointer<UInt8>) -> Bool {
        source.count <= _percentDecodingFastPathThreshold
          && !(source.boundsChecked.uncheckedFastContains(ASCII.percentSign.codePoint)
            || source.boundsChecked.uncheckedFastContains(ASCII.plus.codePoint))
      }
    }

    @inlinable @inline(__always)
    public var substitutions: Substitutions { .init() }
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
