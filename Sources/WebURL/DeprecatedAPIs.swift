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

// These APIs will be removed at the next opportunity.


// --------------------------------------------
// MARK: - IP Addresses (deprecated from: 0.2.0)
// --------------------------------------------


extension IPv4Address {

  // swift-format-ignore
  /// A tri-state result which captures whether an IPv4 address failed to parse because it was invalid,
  /// or whether it failed because the given string does not look like an IP address.
  ///
  /// **This API is deprecated and will be removed in a future version.**
  ///
  @available(*, deprecated, message:
    "Changes to the way hostnames are parsed in the URL standard make it impractical for the IPv4 parser to detect when a hostname should not be parsed as an IPv4Address. A future API may address this more thoroughly; see github.com/karwa/swift-url/issues/63 for details."
  )
  public enum ParserResult {

    /// The string was successfully parsed as an IPv4 address.
    ///
    case success(IPv4Address)

    /// The string was recognized as probably being an IPv4 address, but was invalid and could not be parsed (e.g. because the value would overflow).
    ///
    case failure

    /// The string cannot be recognized as an IPv4 address. This is not the same as being an invalid IP address - for example, the string "9999999999.com" fails
    /// to parse because the non-numeric characters "com" mean it isn't even an IP address string, whereas the string "9999999999" _is_ a properly-formatted
    /// IP address string, but fails to parse because the value would overflow.
    ///
    /// When parsing "9999999999.com" as a hostname, it should be treated as a domain or opaque hostname rather than an invalid IP address.
    /// The string "9999999999" should be treated as a invalid IP address.
    ///
    case notAnIPAddress
  }

  // swift-format-ignore
  /// Parses an IPv4 address from a buffer of UTF-8 codeunits, returning a tri-state `ParserResult` which is useful for parsing content which _might_ be
  /// an IPv4 address.
  ///
  /// **This API is deprecated and will be removed in a future version.**
  ///
  /// The following formats are recognized:
  ///
  ///  - _a.b.c.d_, where each numeric part defines the value of the address' octet at that position.
  ///  - _a.b.c_, where _a_ and _b_ define the address' first 2 octets, and _c_ is interpreted as a 16-bit integer whose most and least significant bytes define
  ///    the address' 3rd and 4th octets respectively.
  ///  - _a.b_, where _a_ defines the address' first octet, and _b_ is interpreted as a 24-bit integer whose bytes define the remaining octets from most to least
  ///    significant.
  ///  - _a_, where _a_ is interpreted as a 32-bit integer whose bytes define the octets of the address in order from most to least significant.
  ///
  /// The numeric parts may be written in decimal, octal (prefixed with a `0`), or hexadecimal (prefixed with `0x`, case-insensitive).
  /// Additionally, a single trailing '.' is permitted (e.g. `a.b.c.d.`).
  ///
  /// Examples:
  /// ```
  /// IPv4Address("0x7f.0.0.1")!.octets == (0x7f, 0x00, 0x00, 0x01) == "127.0.0.1"
  /// IPv4Address("10.1.0x12.")!.octets == (0x0a, 0x01, 0x00, 0x12) == "10.1.0.18"
  /// IPv4Address("0300.0xa80032")!.octets == (0xc0, 0xa8, 0x00, 0x32) == "192.168.0.50"
  /// IPv4Address("0x8Badf00d")!.octets == (0x8b, 0xad, 0xf0, 0x0d) == "139.173.240.13"
  /// ```
  ///
  /// - parameters:
  ///     - utf8: The string to parse, as a collection of UTF-8 code-units.
  /// - returns: A tri-state result which captures whether the string should even be interpreted as an IPv4 address.
  ///            See `ParserResult` for more information.
  ///
  @available(*, deprecated, message:
    "Changes to the way hostnames are parsed in the URL standard make it impractical for the IPv4 parser to detect when a hostname should not be parsed as an IPv4Address. A future API may allow direct access to the URL host parser instead. Please leave a comment at github.com/karwa/swift-url/issues/63 so we can learn more about your use-case."
  )
  public static func parse<UTF8Bytes>(
    utf8: UTF8Bytes
  ) -> ParserResult where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    // Find the content of the last piece.
    var lastPieceStart = utf8.startIndex
    var lastPieceEnd = utf8.endIndex
    for idx in utf8.indices {
      if utf8[idx] == ASCII.period.codePoint {
        let pieceStart = utf8.index(after: idx)
        if pieceStart == utf8.endIndex {
          lastPieceEnd = idx
        } else {
          lastPieceStart = pieceStart
        }
      }
    }
    let lastPiece = utf8[lastPieceStart..<lastPieceEnd]
    // To be parsed as an IPv4 address, the last piece must:
    // - not be empty
    // - contain an number, regardless of whether that number overflows an IPv4 address.
    var isHex = ASCII.Lowercased(lastPiece).starts(with: "0x".utf8)
    isHex = isHex && lastPiece.dropFirst(2).allSatisfy({ ASCII($0)?.isHexDigit == true })
    guard !lastPiece.isEmpty, lastPiece.allSatisfy({ ASCII($0)?.isDigit == true }) || isHex else {
      return .notAnIPAddress
    }

    guard let address = IPv4Address(utf8: utf8) else {
      return .failure
    }
    return .success(address)
  }
}


// --------------------------------------------
// MARK: - WebURL type (deprecated from: 0.2.0)
// --------------------------------------------


extension WebURL {

  /// Whether this URL has an opaque path.
  ///
  /// **This API is deprecated and will be removed in a future version; use `hasOpaquePath` instead.**
  ///
  /// URLs with opaque paths are non-hierarchical: they do not have a hostname, and their paths are opaque strings which cannot be split in to components.
  /// They can be recognized by the lack of slashes immediately following the scheme delimiter, for example:
  ///
  /// - `mailto:bob@example.com`
  /// - `javascript:alert("hello");`
  /// - `data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==`
  ///
  /// It is invalid to set any authority components, such as `username`, `password`, `hostname` or `port`, on these URLs.
  /// Modifying the `path` or accessing the URL's `pathComponents` is also invalid, and they only support limited forms of relative references.
  ///
  /// URLs with special schemes (such as http/s and file) never have opaque paths.
  ///
  @available(*, deprecated, renamed: "hasOpaquePath")
  public var cannotBeABase: Bool {
    hasOpaquePath
  }
}


// --------------------------------------------
// MARK: - Percent-encoding (deprecated from: 0.2.0)
// --------------------------------------------


/// A set of ASCII code-points which should be percent-encoded.
///
/// Percent-encoding transforms arbitrary bytes to ASCII strings (e.g. the byte value 200, or 0xC8, to the string "%C8"),
/// and is most commonly used to escape special characters in URLs. Bytes within the ASCII range are encoded according
/// to the encode-set's `shouldPercentEncode(ascii:)` method, and bytes which are not ASCII code-points are always
/// percent-encoded.
///
@available(*, deprecated, renamed: "PercentEncodeSet")
public typealias PercentEncodeSetProtocol = PercentEncodeSet

/// A `Collection` which percent-encodes elements from its `Source` on-demand using a given `EncodeSet`.
///
/// Percent-encoding transforms arbitrary bytes to ASCII strings (e.g. the byte value 200, or 0xC8, to the string "%C8"),
/// and is most commonly used to escape special characters in URLs. Bytes which are not ASCII code-points are always percent-encoded,
/// and bytes within the ASCII range are encoded according to the encode-set's `shouldPercentEncode(ascii:)` method.
///
@available(*, deprecated, renamed: "LazilyPercentEncoded")
public typealias LazilyPercentEncodedUTF8<Source, EncodeSet> = LazilyPercentEncoded<Source, EncodeSet>
where Source: Collection, Source.Element == UInt8, EncodeSet: PercentEncodeSet

/// A namespace for percent-encode sets defined by the URL Standard.
///
@available(*, deprecated)
public struct PercentEncodeSet_Namespace {
  internal init() {}

  /// The [C0 control](https://url.spec.whatwg.org/#c0-control-percent-encode-set) percent-encode set.
  ///
  @available(*, deprecated, renamed: "PercentEncodeSet.c0ControlSet")
  public var c0Control: URLEncodeSet.C0Control { .init() }

  /// The [fragment](https://url.spec.whatwg.org/#fragment-percent-encode-set) percent-encode set.
  ///
  @available(*, deprecated, renamed: "PercentEncodeSet.fragmentSet")
  public var fragment: URLEncodeSet.Fragment { .init() }

  /// The [query](https://url.spec.whatwg.org/#query-percent-encode-set) percent-encode set.
  ///
  @available(*, deprecated, renamed: "PercentEncodeSet.querySet")
  public var query_notSpecial: URLEncodeSet.Query { .init() }

  /// The [special query](https://url.spec.whatwg.org/#special-query-percent-encode-set) percent-encode set.
  ///
  @available(*, deprecated, renamed: "PercentEncodeSet.specialQuerySet")
  public var query_special: URLEncodeSet.SpecialQuery { .init() }

  /// The [path](https://url.spec.whatwg.org/#path-percent-encode-set) percent-encode set.
  ///
  @available(*, deprecated, renamed: "PercentEncodeSet.pathSet")
  public var path: URLEncodeSet.Path { .init() }

  /// The [userinfo](https://url.spec.whatwg.org/#userinfo-percent-encode-set) percent-encode set.
  ///
  @available(*, deprecated, renamed: "PercentEncodeSet.userInfoSet")
  public var userInfo: URLEncodeSet.UserInfo { .init() }

  /// The [component](https://url.spec.whatwg.org/#component-percent-encode-set) percent-encode set.
  ///
  @available(*, deprecated, renamed: "PercentEncodeSet.urlComponentSet")
  public var component: URLEncodeSet.Component { .init() }

  /// The [application/x-www-form-urlencoded](https://url.spec.whatwg.org/#application-x-www-form-urlencoded-percent-encode-set)
  /// percent-encode set.
  ///
  @available(*, deprecated, renamed: "PercentEncodeSet.formEncoding")
  public var form: URLEncodeSet.FormEncoding { .init() }
}

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
  @available(*, deprecated, message: "Use percentEncoded(using:) and static-member syntax rather than a KeyPath")
  public func percentEncoded<EncodeSet: PercentEncodeSet>(
    as encodeSetKP: KeyPath<PercentEncodeSet_Namespace, EncodeSet>
  ) -> LazilyPercentEncoded<Elements, EncodeSet> {
    self.percentEncoded(using: PercentEncodeSet_Namespace()[keyPath: encodeSetKP])
  }
}

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
  @available(*, deprecated, message: "Use percentEncodedString(using:) and static-member syntax rather than a KeyPath")
  public func percentEncodedString<EncodeSet: PercentEncodeSet>(
    as encodeSetKP: KeyPath<PercentEncodeSet_Namespace, EncodeSet>
  ) -> String {
    self.percentEncodedString(using: PercentEncodeSet_Namespace()[keyPath: encodeSetKP])
  }

  /// Returns an ASCII string formed by percent-encoding this collection's elements with `.urlComponentSet`.
  ///
  @available(*, deprecated, message: "Use percentEncodedString(using: .urlComponentSet)")
  public var urlComponentEncodedString: String {
    percentEncodedString(using: .urlComponentSet)
  }

  /// Returns an ASCII string formed by percent-encoding this collection's elements with `.formEncoding`.
  ///
  @available(*, deprecated, message: "Use percentEncodedString(using: .formEncoding)")
  public var urlFormEncodedString: String {
    percentEncodedString(using: .formEncoding)
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
  @available(*, deprecated, message: "Use percentEncoded(using:) and static-member syntax rather than a KeyPath")
  public func percentEncoded<EncodeSet: PercentEncodeSet>(
    as encodeSetKP: KeyPath<PercentEncodeSet_Namespace, EncodeSet>
  ) -> String {
    self.percentEncoded(using: PercentEncodeSet_Namespace()[keyPath: encodeSetKP])
  }

  /// Returns an ASCII string formed by percent-encoding this string's UTF-8 representation with `.urlComponentSet`.
  ///
  @available(*, deprecated, message: "Use percentEncoded(using: .urlComponentSet)")
  public var urlComponentEncoded: String {
    percentEncoded(using: .urlComponentSet)
  }

  /// Returns an ASCII string formed by percent-encoding this string's UTF-8 representation with `.formEncoding`.
  ///
  @available(*, deprecated, message: "Use percentEncoded(using: .formEncoding)")
  public var urlFormEncoded: String {
    percentEncoded(using: .formEncoding)
  }
}


// --------------------------------------------
// MARK: - Percent-decoding (deprecated from: 0.2.0)
// --------------------------------------------


/// A `Collection` which percent-decodes elements from its `Source` on-demand.
///
/// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB),
/// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding;
/// use ``LazilyPercentDecodedWithSubstitutions``, providing the correct ``SubstitutionMap``,
/// to accurately decode content encoded with substitutions.
///
@available(*, deprecated, renamed: "LazilyPercentDecoded")
public typealias LazilyPercentDecodedUTF8WithoutSubstitutions<Source> = LazilyPercentDecoded<Source>
where Source: Collection, Source.Element == UInt8

/// A `Collection` which percent-decodes elements from its `Source` on-demand, and reverses substitutions made by a ``SubstitutionMap``.
///
/// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB),
/// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
/// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
///
@available(*, deprecated, renamed: "LazilyPercentDecodedWithSubstitutions")
public typealias LazilyPercentDecodedUTF8<Source, Subs> = LazilyPercentDecodedWithSubstitutions<Source, Subs>
where Source: Collection, Source.Element == UInt8, Subs: SubstitutionMap

/// A namespace for substitution maps used by percent-encode sets defined by the URL Standard.
///
@available(*, deprecated)
public struct PercentDecodeSet_Namespace {
  internal init() {}

  /// No substitutions. This is the substitution map used by all encode-sets specified in the URL standard, except form-encoding.
  ///
  @available(*, deprecated, renamed: "SubstitutionMap.none")
  public var percentEncodedOnly: NoSubstitutions { .init() }

  /// Substitutions applicable to the [application/x-www-form-urlencoded][form-encoded] percent-encode set.
  ///
  /// [form-encoded]: https://url.spec.whatwg.org/#application-x-www-form-urlencoded-percent-encode-set
  ///
  @available(*, deprecated, renamed: "SubstitutionMap.formEncoding")
  public var form: URLEncodeSet.FormEncoding.Substitutions { .init() }
}

extension LazyCollectionProtocol where Element == UInt8 {

  // swift-format-ignore
  /// Returns a `Collection` whose elements are computed lazily by percent-decoding the elements of this collection.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  @available(*, deprecated, message: "Use percentDecoded(substitutions:) and static-member syntax rather than a KeyPath")
  public func percentDecodedUTF8<Substitutions>(
    from subsKP: KeyPath<PercentDecodeSet_Namespace, Substitutions>
  ) -> LazilyPercentDecodedWithSubstitutions<Elements, Substitutions> {
    self.percentDecoded(substitutions: PercentDecodeSet_Namespace()[keyPath: subsKP])
  }

  /// Returns a `Collection` whose elements are computed lazily by percent-decoding the elements of this collection.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  @available(*, deprecated, renamed: "percentDecoded()")
  public var percentDecodedUTF8: LazilyPercentDecoded<Elements> {
    self.percentDecoded()
  }
}

extension Collection where Element == UInt8 {

  // swift-format-ignore
  /// Returns the percent-decoding of this collection's elements, interpreted as UTF-8 code-units.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  @available(*, deprecated, message: """
    Use .lazy.percentDecoded(substitutions:) with static-member syntax rather than a KeyPath \
    to decode the bytes, and String(decoding: _, as: UTF8.self) to construct a String from it.
    """
  )
  public func percentDecodedString<Substitutions: SubstitutionMap>(
    from subsKP: KeyPath<PercentDecodeSet_Namespace, Substitutions>
  ) -> String {
    self.percentDecodedString(substitutions: PercentDecodeSet_Namespace()[keyPath: subsKP])
  }

  // swift-format-ignore
  /// Returns the percent-decoding of this collection's elements, interpreted as UTF-8 code-units.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  @available(*, deprecated, message: """
    Use .lazy.percentDecoded(substitutions: .none) to decode the bytes, \
    and String(decoding: _, as: UTF8.self) to construct a String from it.
    """
  )
  public var percentDecodedString: String {
    self.percentDecodedString(substitutions: .none)
  }

  // swift-format-ignore
  /// Returns the form-decoding of this collection's elements, interpreted as UTF-8 code-units.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  @available(*, deprecated, message: """
    Use .lazy.percentDecoded(substitutions: .formEncoding) to decode the bytes, \
    and String(decoding: _, as: UTF8.self) to construct a String from it.
    """
  )
  public var urlFormDecodedString: String {
    self.percentDecodedString(substitutions: .formEncoding)
  }
}

extension StringProtocol {

  // swift-format-ignore
  /// Returns the percent-decoding of this string, interpreted as UTF-8 code-units.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  @available(*, deprecated, message: "Use percentDecoded(substitutions:) with static-member syntax rather than a KeyPath")
  public func percentDecoded<Substitutions: SubstitutionMap>(
    from subsKP: KeyPath<PercentDecodeSet_Namespace, Substitutions>
  ) -> String {
    self.percentDecoded(substitutions: PercentDecodeSet_Namespace()[keyPath: subsKP])
  }

  // Cannot be back-ported; changed from a computed property to a function.
  // public var percentDecoded: String {
  //   self.percentDecoded()
  // }

  /// Returns the form-decoding of this string, interpreted as UTF-8 code-units.
  ///
  /// Percent-decoding transforms certain ASCII sequences to bytes ("%AB" to the byte value 171, or 0xAB).
  /// Some encodings (e.g. form encoding) apply substitutions in addition to percent-encoding; provide the appropriate
  /// ``SubstitutionMap`` to accurately decode content encoded with substitutions.
  ///
  @available(*, deprecated, message: "Use percentDecoded(substitutions: .formEncoding)")
  public var urlFormDecoded: String {
    self.percentDecoded(substitutions: .formEncoding)
  }
}


// ------------------------------------------------
// MARK: - Binary File Paths (renamed from: 0.2.1)
// ------------------------------------------------


extension WebURL {

  @available(*, deprecated, renamed: "fromBinaryFilePath")
  public static func fromFilePathBytes<Bytes>(
    _ path: Bytes, format: FilePathFormat = .native
  ) throws -> WebURL where Bytes: BidirectionalCollection, Bytes.Element == UInt8 {
    try fromBinaryFilePath(path, format: format)
  }

  @available(*, deprecated, renamed: "binaryFilePath")
  public static func filePathBytes(
    from url: WebURL, format: FilePathFormat = .native, nullTerminated: Bool
  ) throws -> ContiguousArray<UInt8> {
    ContiguousArray(try binaryFilePath(from: url, format: format, nullTerminated: nullTerminated))
  }
}
