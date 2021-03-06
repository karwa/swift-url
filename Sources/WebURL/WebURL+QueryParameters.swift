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
      // A borrowed backing gives read-only access to a URL's buffer.
      // However, we need to assume it is percent-encoded rather than form-encoded.
      case borrowed(AnyURLStorage)
      // An owned backing is our own String which we can write to.
      // Upon transitioning from borrowed -> owned, the contents of the URL's buffer are re-encoded with form-encoding.
      case owned(String)
    }
    var backing: Backing
  }

  /// A view of the `application/x-www-form-urlencoded` key-value pairs in this URL's `query`, if present.
  ///
  /// The `queryParams` view allows you to conveniently get and set the values for particular keys by accessing them as members.
  /// For keys which are not valid Swift identifiers, the `get` and `set` functions provide equivalent functionality.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/?keyOne=valueOne&keyTwo=valueTwo")!
  /// assert(url.queryParams.keyOne == "valueOne")
  ///
  /// url.queryParams.keyThree = "valueThree"
  /// assert(url.serialized == "http://example.com/?keyOne=valueOne&keyTwo=valueTwo&keyThree=valueThree")
  ///
  /// url.queryParams.keyTwo = nil
  /// assert(url.serialized == "http://example.com/?keyOne=valueOne&keyThree=valueThree")
  ///
  /// url.queryParams.set(key: "my key", to: "🦆")
  /// assert(url.serialized == "http://example.com/?keyOne=valueOne&keyThree=valueThree&my+key=%F0%9F%A6%86")
  /// ```
  ///
  /// Additionally, you can iterate all of the key-value pairs using the `.allKeyValuePairs` property:
  ///
  /// ```swift
  /// for (key, value) in url.queryParams.allKeyValuePairs {
  ///   // ("keyOne", "valueOne")
  ///   // ("keyThree", "valueThree")
  ///   // ("my key", "🦆")
  /// }
  /// ```
  ///
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

  fileprivate func withBackingUTF8<ResultType>(_ body: (UnsafeBufferPointer<UInt8>) -> ResultType) -> ResultType {
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

  @usableFromInline
  internal mutating func withMutableOwnedString(_ body: (inout String) -> Void) {
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
        // Find the next non-empty KVP.
        var thisKVP: Bytes.SubSequence
        repeat {
          if let thisKVPEnd = remaining.firstIndex(of: ASCII.ampersand.codePoint) {
            thisKVP = remaining[Range(uncheckedBounds: (remaining.startIndex, thisKVPEnd))]
            remaining = remaining[Range(uncheckedBounds: (remaining.index(after: thisKVPEnd), remaining.endIndex))]
          } else if remaining.isEmpty == false {
            thisKVP = remaining
            remaining = remaining[Range(uncheckedBounds: (remaining.endIndex, remaining.endIndex))]
          } else {
            return nil
          }
        } while thisKVP.isEmpty
        // Split on the "=" sign if there is one.
        let key: Range<Bytes.Index>
        let value: Range<Bytes.Index>
        if let keyValueSeparator = thisKVP.firstIndex(of: ASCII.equalSign.codePoint) {
          key = Range(uncheckedBounds: (thisKVP.startIndex, keyValueSeparator))
          value = Range(uncheckedBounds: (thisKVP.index(after: keyValueSeparator), thisKVP.endIndex))
        } else {
          key = Range(uncheckedBounds: (thisKVP.startIndex, thisKVP.endIndex))
          value = Range(uncheckedBounds: (thisKVP.endIndex, thisKVP.endIndex))
        }
        return (pair: Range(uncheckedBounds: (thisKVP.startIndex, remaining.startIndex)), key: key, value: value)
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

  @usableFromInline
  internal static func append(
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

// removeAll, append(contentsOf:).

extension WebURL.QueryParameters {

  /// Removes all key-value pairs in these query parameters.
  ///
  public mutating func removeAll() {
    self.backing = .owned("")
  }

  /// Appends the given sequence of key-value pairs to these query parameters. Existing values will not be removed.
  ///
  @inlinable
  public mutating func append<SequenceType, KeyValueType>(
    contentsOf keyValuePairs: SequenceType
  ) where SequenceType: Sequence, SequenceType.Element == (KeyValueType, KeyValueType), KeyValueType: StringProtocol {

    withMutableOwnedString { str in
      for (key, value) in keyValuePairs {
        WebURL.QueryParameters.append(
          encodedKey: key.urlFormEncoded,
          encodedValue: value.urlFormEncoded,
          toFormEncodedString: &str
        )
      }
    }
  }

  @inlinable
  public static func += <SequenceType, KeyValueType>(
    lhs: inout WebURL.QueryParameters, rhs: SequenceType
  ) where SequenceType: Sequence, SequenceType.Element == (KeyValueType, KeyValueType), KeyValueType: StringProtocol {
    lhs.append(contentsOf: rhs)
  }

  // Unfortunately, (String, String) and (key: String, value: String) appear to be treated as different types.
  // Removing this overload gives an error, recommending we add conformance to RangeReplaceableCollection (?!).

  /// Appends the given sequence of key-value pairs to these query parameters. Existing values will not be removed.
  ///
  @inlinable
  public mutating func append<SequenceType, KeyValueType>(
    contentsOf keyValuePairs: SequenceType
  )
  where
    SequenceType: Sequence, SequenceType.Element == (key: KeyValueType, value: KeyValueType),
    KeyValueType: StringProtocol
  {
    append(
      contentsOf: keyValuePairs.lazy.map { ($0, $1) } as LazyMapSequence<SequenceType, (KeyValueType, KeyValueType)>
    )
  }

  @inlinable
  public static func += <SequenceType, KeyValueType>(
    lhs: inout WebURL.QueryParameters, rhs: SequenceType
  )
  where
    SequenceType: Sequence, SequenceType.Element == (key: KeyValueType, value: KeyValueType),
    KeyValueType: StringProtocol
  {
    lhs.append(contentsOf: rhs)
  }

  // Add an overload for Dictionary, so that its key-value pairs at least get a predictable order.
  // There is no way to enforce an order for Dictionary, so this isn't breaking anybody's expectations.

  /// Appends the given sequence of key-value pairs to these query parameters. Existing values will not be removed.
  ///
  /// - Note: Since `Dictionary`'s contents are not ordered, this method will sort the key-value pairs by name before they are form-encoded
  ///         (using the standard library's Unicode comparison), so that the results are at least predictable. If this order is not desirable, sort the key-value
  ///         pairs before appending them.
  ///
  @inlinable
  public mutating func append<KeyValueType>(
    contentsOf keyValuePairs: [KeyValueType: KeyValueType]
  ) where KeyValueType: StringProtocol {
    append(
      contentsOf: keyValuePairs.sorted(by: { lhs, rhs in
        assert(lhs.key != rhs.key, "Dictionary with non-unique keys?")
        return lhs.key < rhs.key
      })
    )
  }

  @inlinable
  public static func += <KeyValueType>(
    lhs: inout WebURL.QueryParameters, rhs: [KeyValueType: KeyValueType]
  ) where KeyValueType: StringProtocol {
    lhs.append(contentsOf: rhs)
  }
}

// allKeyValuePairs (Sequence view).

extension WebURL.QueryParameters {

  /// A `Sequence` allowing the key-value pairs of these query parameters to be iterated over.
  ///
  public var allKeyValuePairs: KeyValuePairs {
    KeyValuePairs(params: self)
  }

  /// A `Sequence` allowing the key-value pairs of these query parameters to be iterated over.
  ///
  public struct KeyValuePairs: Sequence {
    var params: WebURL.QueryParameters

    public func makeIterator() -> Iterator {
      Iterator(params: params)
    }

    /// Whether or not these query parameters have any key-value pairs.
    ///
    public var isEmpty: Bool {
      var iterator = makeIterator()
      return iterator.next() == nil
    }

    public struct Iterator: IteratorProtocol {
      var params: WebURL.QueryParameters
      var utf8Offset: Int = 0

      public mutating func next() -> (String, String)? {
        return params.withBackingUTF8 { utf8Bytes in
          guard utf8Offset != utf8Bytes.count else { return nil }
          var resumedIter = RawKeyValuePairs(string: utf8Bytes.suffix(from: utf8Offset)).makeIterator()
          guard let nextKVP = resumedIter.next() else {
            utf8Offset = utf8Bytes.count
            return nil
          }
          utf8Offset = nextKVP.pair.upperBound
          return (utf8Bytes[nextKVP.key].urlFormDecodedString, utf8Bytes[nextKVP.value].urlFormDecodedString)
        }
      }
    }
  }
}
