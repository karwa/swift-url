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

// These APIs will be deprecated at the next opportunity.

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
