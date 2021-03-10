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

extension WebURL {

  @dynamicMemberLookup
  public struct QueryParameters {
    enum Backing {
      case borrowed(AnyURLStorage)
      case owned(String)
    }
    var backing: Backing
  }

  public var queryParams: QueryParameters {
    get {
      return QueryParameters(backing: .borrowed(storage))
    }
    set {
      switch newValue.backing {
      case .borrowed(_):
        var mutableNewValue = newValue
        mutableNewValue.withMutableOwnedString { self.query = $0.isEmpty ? nil : $0 }
      case .owned(let serialized):
        guard serialized.isEmpty == false else {
          self.query = nil
          return
        }
        withMutableStorage(
          { small in small.setQuery(toKnownFormEncoded: serialized.utf8) },
          { generic in generic.setQuery(toKnownFormEncoded: serialized.utf8) }
        )
      }
    }
  }
}

// backing.

extension WebURL.QueryParameters {

  private func withBackingUTF8<ResultType>(_ body: (UnsafeBufferPointer<UInt8>) -> ResultType) -> ResultType {
    switch backing {
    case .borrowed(let storage):
      return storage.withComponentBytes(.query) { maybeBytes in
        guard let bytes = maybeBytes, bytes.count > 1 else {
          return body(UnsafeBufferPointer(start: nil, count: 0))
        }
        return body(UnsafeBufferPointer(rebasing: bytes.dropFirst()))
      }
    case .owned(var ownedString):
      return ownedString.withUTF8(body)
    }
  }

  fileprivate mutating func withMutableOwnedString(_ body: (inout String) -> Void) {
    switch backing {
    case .owned(var string):
      body(&string)
      self.backing = .owned(string)
    case .borrowed:
      var string = withBackingUTF8 { WebURL.QueryParameters.reencode(rawQueryUTF8: $0) }
      body(&string)
      self.backing = .owned(string)
    }
  }
}

// Iteration and serialization.

extension WebURL.QueryParameters {

  /// A sequence which allows iterating the key-value pairs within a given UTF8 string.
  /// The sequence assumes the "&" and "=" characters have not been escaped, but otherwise
  /// does not assume the keys or values to be `application/x-www-form-urlencoded`.
  ///
  struct RawKeyValuePairs<Bytes>: Sequence where Bytes: Collection, Bytes.Element == UInt8 {

    /// - Note: `pair` includes the trailing ampersand separator, unless the key-value pair ends at the end of the query string.
    typealias Ranges = (pair: Range<Bytes.Index>, key: Range<Bytes.Index>, value: Range<Bytes.Index>)

    var string: Bytes

    func makeIterator() -> Iterator {
      return Iterator(remaining: string[...])
    }

    struct Iterator: IteratorProtocol {
      var remaining: Bytes.SubSequence

      mutating func next() -> Ranges? {
        guard remaining.isEmpty == false else {
          return nil
        }
        var thisKVP: Bytes.SubSequence
        repeat {
          thisKVP = remaining.prefix(while: { $0 != ASCII.ampersand.codePoint })
          remaining = remaining[thisKVP.endIndex...].dropFirst()
        } while thisKVP.isEmpty
        let key = thisKVP.prefix(while: { $0 != ASCII.equalSign.codePoint })
        let value = thisKVP.suffix(from: key.endIndex).dropFirst()
        return (
          pair: Range(uncheckedBounds: (thisKVP.startIndex, remaining.startIndex)),
          key: Range(uncheckedBounds: (key.startIndex, key.endIndex)),
          value: Range(uncheckedBounds: (value.startIndex, value.endIndex))
        )
      }
    }

    func filteredToKey<KeyType>(
      _ keyToFind: KeyType
    ) -> LazyFilterSequence<LazySequence<Self>.Elements> where KeyType: StringProtocol {
      self.lazy.filter { (_, key, _) in
        string[key].lazy.percentDecoded(using: URLEncodeSet.FormEncoded.self).elementsEqual(keyToFind.utf8)
      }
    }
  }

  /// Parses the raw key-value pairs from the given UTF8 bytes, and returns a new query string by re-encoding them
  /// as `application/x-www-form-urlencoded`. The relative order of key-value pairs is preserved.
  ///
  static func reencode(rawQueryUTF8: UnsafeBufferPointer<UInt8>) -> String {

    // TODO: (performance): Can we be smarter about re-encoding? Since every mutation/assignment will re-encode,
    //                      subsequent ones will be doing redundant work.

    // Query strings borrowed from WebURL might not be form-encoded, so we have to recode them.
    // A query string which is owned (and thus mutable) by `QueryParameters` needs to be properly form-encoded.
    let reencodedQuery = RawKeyValuePairs(string: rawQueryUTF8)
      // Re-encode key and value separately, and join them back together.
      .lazy.map { (_, key, value) in
        [
          rawQueryUTF8[key].lazy.percentDecoded(using: URLEncodeSet.FormEncoded.self)
            .percentEncoded(using: URLEncodeSet.FormEncoded.self).joined(),
          rawQueryUTF8[value].lazy.percentDecoded(using: URLEncodeSet.FormEncoded.self)
            .percentEncoded(using: URLEncodeSet.FormEncoded.self).joined(),
        ].joined(separator: CollectionOfOne(ASCII.equalSign.codePoint))
        // Join each key-value pair.
      }.joined(separator: CollectionOfOne(ASCII.ampersand.codePoint))

    // Unlike regular encoding/decoding, re-encoding an already-encoded string is
    // rarely going to change the 'count' by a huge amount.
    // If available, reserve approximate space and write directly in to the String buffer.
    #if false
      if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
        var iter = (false) ? reencodedQuery.makeIterator() : nil
        var string = String(unsafeUninitializedCapacity: raw.count) { newStringBuffer in
          let (_iter, count) = newStringBuffer.initialize(from: lazyRecoded)
          iter = _iter
          return count
        }
        string.append(String(decoding: Array(IteratorSequence(iter!)), as: UTF8.self))
        return string
      }
    #endif
    return String(decoding: Array(reencodedQuery), as: UTF8.self)
  }
}

// 'contains', 'get', 'getAll'.

extension WebURL.QueryParameters {

  /// Whether or not these parameters contain a value for the given key.
  ///
  /// - complexity: O(_n_ + _m_), where _n_ is the length of the query string and _m_ is the length of the key.
  ///
  @_specialize(where KeyType == String)
  @_specialize(where KeyType == Substring)
  public func contains<KeyType>(_ keyToFind: KeyType) -> Bool where KeyType: StringProtocol {
    withBackingUTF8 {
      var iter = RawKeyValuePairs(string: $0).filteredToKey(keyToFind).makeIterator()
      return iter.next() != nil
    }
  }

  /// Returns the first value matching the given key, if present. The value is decoded from `application/x-www-form-urlencoded`.
  ///
  /// - complexity: O(_n_ + _m_), where _n_ is the length of the query string and _m_ is the length of the key.
  ///
  @_specialize(where KeyType == String)
  @_specialize(where KeyType == Substring)
  public func get<KeyType>(_ keyToFind: KeyType) -> String? where KeyType: StringProtocol {
    withBackingUTF8 { utf8 in
      var iter = RawKeyValuePairs(string: utf8).filteredToKey(keyToFind).makeIterator()
      return iter.next().map { utf8[$0.value].urlFormDecodedString }
    }
  }

  /// Returns all values matching the given key. The values are decoded from `application/x-www-form-urlencoded`.
  ///
  /// - complexity: O(_n_ + _m_), where _n_ is the length of the query string and _m_ is the length of the key.
  ///
  @_specialize(where KeyType == String)
  @_specialize(where KeyType == Substring)
  public func getAll<KeyType>(_ keyToFind: KeyType) -> [String] where KeyType: StringProtocol {
    withBackingUTF8 { utf8 in
      RawKeyValuePairs(string: utf8).filteredToKey(keyToFind).map { utf8[$0.value].urlFormDecodedString }
    }
  }

  public subscript(dynamicMember dynamicMember: String) -> String? {
    get { get(dynamicMember) }
    set { set(key: dynamicMember, to: newValue) }
  }
}

// append, delete, set.

extension WebURL.QueryParameters {

  private static func append(
    encodedKey: String, encodedValue: String, toFormEncodedString string: inout String
  ) {
    if string.isEmpty == false {
      string.append("&")
    }
    string.append("\(encodedKey)=\(encodedValue)")
  }

  private static func remove<KeyType>(
    encodedKey: KeyType, fromFormEncodedString string: inout String, utf8Offset: Int = 0
  ) where KeyType: StringProtocol {

    // Find the UTF8 offsets of all KVPs with the given key.
    // Note that the string and key are already enoded, so we can do a literal search.
    let utf8OffsetRanges = string.withUTF8 { stringBuffer in
      RawKeyValuePairs(string: stringBuffer.suffix(from: utf8Offset)).compactMap {
        (pair, key, _) in stringBuffer[key].elementsEqual(encodedKey.utf8) ? pair : nil
      }
    }
    // Remove KVPs in reverse order to avoid clobbering.
    // It's okay to force-unwrap the String.Index creation, because the string is form-encoded and therefore ASCII.
    for range in utf8OffsetRanges.reversed() {
      let start = string.utf8.index(string.utf8.startIndex, offsetBy: range.lowerBound).samePosition(in: string)!
      let end = string.utf8.index(string.utf8.startIndex, offsetBy: range.upperBound).samePosition(in: string)!
      string.removeSubrange(start..<end)
    }
    // The range for the last key-value pair doesn't include a trailing ampersand (since it doesn't have one),
    // but if we remove it, we would leave a trailing ampersand from the _new_ last key-value pair.
    if string.utf8.last == ASCII.ampersand.codePoint {
      string.removeLast()
    }
  }

  /// Appends the given key-value pair to the query parameters. No existing key-value pairs are removed.
  ///
  @_specialize(where KeyValueType == String)
  @_specialize(where KeyValueType == Substring)
  public mutating func append<KeyValueType>(key: KeyValueType, value: KeyValueType) where KeyValueType: StringProtocol {
    withMutableOwnedString {
      WebURL.QueryParameters.append(
        encodedKey: key.urlFormEncoded,
        encodedValue: value.urlFormEncoded,
        toFormEncodedString: &$0
      )
    }
  }

  /// Removes all instances of the given key from the query parameters.
  ///
  @_specialize(where KeyType == String)
  @_specialize(where KeyType == Substring)
  public mutating func remove<KeyType>(key keyToDelete: KeyType) where KeyType: StringProtocol {
    withMutableOwnedString {
      WebURL.QueryParameters.remove(encodedKey: keyToDelete.urlFormEncoded, fromFormEncodedString: &$0)
    }
  }

  /// Sets the given key to the given value, if present, and appends if otherwise. If `newValue` is `nil`, the key is removed if present.
  ///
  /// If a key is present multiple times, all but the first instance will be removed. It is this first instance which is paired with the new value.
  ///
  @_specialize(where KeyValueType == String)
  @_specialize(where KeyValueType == Substring)
  public mutating func set<KeyValueType>(
    key keyToSet: KeyValueType, to newValue: KeyValueType?
  ) where KeyValueType: StringProtocol {

    guard let newValue = newValue else {
      remove(key: keyToSet)
      return
    }

    let encodedKeyToSet = keyToSet.urlFormEncoded
    let encodedNewValue = newValue.urlFormEncoded
    withMutableOwnedString { str in

      let firstMatch = str.withUTF8 { stringBuffer in
        RawKeyValuePairs(string: stringBuffer).first {
          (_, key, value) in stringBuffer[key].elementsEqual(encodedKeyToSet.utf8)
        }
      }
      if let match = firstMatch {
        WebURL.QueryParameters.remove(
          encodedKey: encodedKeyToSet, fromFormEncodedString: &str, utf8Offset: match.pair.upperBound
        )
        let start = str.utf8.index(str.utf8.startIndex, offsetBy: match.value.lowerBound).samePosition(in: str)!
        let end = str.utf8.index(str.utf8.startIndex, offsetBy: match.value.upperBound).samePosition(in: str)!
        str.replaceSubrange(start..<end, with: encodedNewValue)
      } else {
        WebURL.QueryParameters.append(
          encodedKey: encodedKeyToSet, encodedValue: encodedNewValue, toFormEncodedString: &str
        )
      }
    }
  }
}

// TODO:
// append(contentsOf:), removeAll
// Sequence view.
// sort.
