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
    return PercentDecodedUnicodeScalars(codeUnits: elements.utf8.lazy.percentDecodedUTF8)
  }
}

public struct PercentDecodedUnicodeScalars<Source>: Sequence where Source: Collection, Source.Element == UInt8 {
  fileprivate var codeUnits: LazilyPercentDecodedUTF8<Source, PassthroughEncodeSet>

  public func makeIterator() -> Iterator {
    return Iterator(codeUnitIterator: codeUnits.makeIterator())
  }

  public struct Iterator: IteratorProtocol {
    var codeUnitIterator: LazilyPercentDecodedUTF8<Source, PassthroughEncodeSet>.Iterator
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
