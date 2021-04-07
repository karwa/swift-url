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


// MARK: - Percent Decoding


extension Collection where Element == UInt8 {

  /// Interpets this collection's elements as a UTF-8 string, and returns its `urlDecoded` representation.
  ///
  public var urlDecodedString: String {
    withContiguousStorageIfAvailable {
      String(decoding: $0.lazy.percentDecoded, as: UTF8.self)
    } ?? String(decoding: self.lazy.percentDecoded, as: UTF8.self)
  }

  /// Interpets this collection's elements as a UTF-8 string, and returns its `urlFormDecoded` representation.
  ///
  public var urlFormDecodedString: String {
    withContiguousStorageIfAvailable {
      String(decoding: $0.lazy.percentDecoded(using: URLEncodeSet.FormEncoded.self), as: UTF8.self)
    } ?? String(decoding: self.lazy.percentDecoded(using: URLEncodeSet.FormEncoded.self), as: UTF8.self)
  }
}

extension StringProtocol {

  /// Returns a copy of this string with url-encoded sequences decoded as UTF-8.
  /// Equivalent to JavaScript's `decodeURIComponent()` function.
  ///
  /// ```swift
  /// "hello%2C%20world!".urlDecoded // hello, world!
  /// "%2Fusr%2Fbin%2Fswift".urlDecoded // /usr/bin/swift
  /// "%F0%9F%98%8E".urlDecoded // 😎
  /// ```
  ///
  public var urlDecoded: String {
    @_specialize(where Self == String)
    @_specialize(where Self == Substring)
    get {
      utf8.urlDecodedString
    }
  }

  /// Returns a copy of this string that has been decoded from `application/x-www-form-urlencoded` format.
  ///
  /// For example, to decode a form-encoded string in to an array of key-value pairs, split the string at the "&" character, and then further
  /// split each piece in to its key and value, which can be decoded separately.
  /// ```
  /// let form = "favourite+pet=%F0%9F%A6%86%2C+of+course&favourite+foods=%F0%9F%8D%8E+%26+%F0%9F%8D%A6"
  /// let decoded = form.split(separator: "&").map { joined_kvp in joined_kvp.split(separator: "=") }
  ///                   .map { kvp in (kvp[0].urlFormDecoded, kvp[1].urlFormDecoded) }
  /// print(decoded) // [("favourite pet", "🦆, of course"), ("favourite foods", "🍎 & 🍦")]
  /// ```
  ///
  public var urlFormDecoded: String {
    @_specialize(where Self == String)
    @_specialize(where Self == Substring)
    get {
      utf8.urlFormDecodedString
    }
  }
}

// Note: This is sloooooow, because it doesn't get specialized.

extension LazyCollectionProtocol where Elements: StringProtocol {

  /// Returns a view of this string which lazily decodes url-encoded sequences as UTF-8, and presents the result as a sequence of `UnicodeScalar`s.
  ///
  /// Note that some characters may require more than a single unicode scalar to represent, and that comparing strings based on scalars is sensitive
  /// to unicode normalization forms.
  /// ```swift
  /// Array("hello%2C%20world! 😎✈️".lazy.urlDecodedScalars)
  /// // ["h", "e", "l", "l", "o", ",", " ", "w", "o", "r", "l", "d", "!", " ", "\u{0001F60E}", "\u{2708}", "\u{FE0F}"]
  /// ```
  public var urlDecodedScalars: PercentDecodedUnicodeScalars<Elements.UTF8View> {
    return PercentDecodedUnicodeScalars(codeUnits: elements.utf8.lazy.percentDecoded)
  }
}

public struct PercentDecodedUnicodeScalars<Source>: Sequence where Source: Collection, Source.Element == UInt8 {
  fileprivate var codeUnits: LazilyPercentDecoded<Source, PassthroughEncodeSet>

  public func makeIterator() -> Iterator {
    return Iterator(codeUnitIterator: codeUnits.makeIterator())
  }

  public struct Iterator: IteratorProtocol {
    var codeUnitIterator: LazilyPercentDecoded<Source, PassthroughEncodeSet>.Iterator
    var decoder = UTF8()

    public mutating func next() -> UnicodeScalar? {
      switch decoder.decode(&codeUnitIterator) {
      case .scalarValue(let scalar):
        return scalar
      case .emptyInput, .error:
        return nil
      }
    }
  }
}
