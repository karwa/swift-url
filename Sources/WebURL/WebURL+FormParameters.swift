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

  /// A view of the `application/x-www-form-urlencoded` key-value pairs in a URL's `query`.
  ///
  public var formParams: FormEncodedQueryParameters {
    get {
      FormEncodedQueryParameters(storage: storage)
    }
    _modify {
      var view = FormEncodedQueryParameters(storage: storage)
      storage = _tempStorage
      defer { storage = view.storage }
      yield &view
    }
    set {
      if newValue.storage.structure.queryIsKnownFormEncoded {
        storage.withUnwrappedMutableStorage(
          { small in small.setQuery(toKnownFormEncoded: newValue.storage.utf8.query) },
          { large in large.setQuery(toKnownFormEncoded: newValue.storage.utf8.query) }
        )
      } else {
        let formEncoded = newValue.formEncodedQueryBytes
        storage.withUnwrappedMutableStorage(
          { small in small.setQuery(toKnownFormEncoded: formEncoded) },
          { large in large.setQuery(toKnownFormEncoded: formEncoded) }
        )
      }
    }
  }

  /// A view of the `application/x-www-form-urlencoded` key-value pairs in this URL's `query`.
  ///
  /// The `formParams` view allows you to conveniently get and set the values for particular keys by accessing them as members.
  /// For keys which cannot be written as members, the `get` and `set` functions provide equivalent functionality.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/shopping/deals?category=food&limit=25")!
  /// assert(url.formParams.category == "food")
  ///
  /// url.formParams.distance = "10km"
  /// assert(url.serialized == "http://example.com/shopping/deals?category=food&limit=25&distance=10km")
  ///
  /// url.formParams.limit = nil
  /// assert(url.serialized == "http://example.com/shopping/deals?category=food&distance=10km")
  ///
  /// url.formParams.set("cuisine", to: "🇮🇹")
  /// assert(url.serialized == "http://example.com/shopping/deals?category=food&distance=10km&cuisine=%F0%9F%87%AE%F0%9F%87%B9")
  /// ```
  ///
  /// Additionally, you can iterate all of the key-value pairs using the `.allKeyValuePairs` property:
  ///
  /// ```swift
  /// for (key, value) in url.formParams.allKeyValuePairs {
  ///   // ("category", "food")
  ///   // ("distance", "10km")
  ///   // ("cuisine", "🇮🇹")
  /// }
  /// ```
  ///
  @dynamicMemberLookup
  public struct FormEncodedQueryParameters {

    @usableFromInline
    internal var storage: AnyURLStorage

    internal init(storage: AnyURLStorage) {
      self.storage = storage
    }
  }
}

extension WebURL.FormEncodedQueryParameters {

  internal var formEncodedQueryBytes: ContiguousArray<UInt8>? {
    guard let queryUTF8 = storage.utf8.query else {
      return nil
    }
    var result = ContiguousArray<UInt8>()
    result.reserveCapacity(queryUTF8.count + 1)
    for kvp in RawKeyValuePairs(utf8: queryUTF8) {
      result.append(contentsOf: queryUTF8[kvp.key].lazy.percentDecodedUTF8(from: \.form).percentEncoded(as: \.form))
      result.append(ASCII.equalSign.codePoint)
      result.append(contentsOf: queryUTF8[kvp.value].lazy.percentDecodedUTF8(from: \.form).percentEncoded(as: \.form))
      result.append(ASCII.ampersand.codePoint)
    }
    _ = result.popLast()
    // Non-empty queries may become empty once form-encoded (e.g. "&&&&").
    // These should result in 'nil' queries.
    return result.isEmpty ? nil : result
  }

  @usableFromInline
  internal mutating func reencodeQueryIfNeeded() {
    guard !storage.structure.queryIsKnownFormEncoded else { return }
    let reencodedQuery = formEncodedQueryBytes
    storage.withUnwrappedMutableStorage(
      { small in small.setQuery(toKnownFormEncoded: reencodedQuery) },
      { large in large.setQuery(toKnownFormEncoded: reencodedQuery) }
    )
    assert(storage.structure.queryIsKnownFormEncoded)
  }
}


// --------------------------------------------
// MARK: - Reading
// --------------------------------------------


extension WebURL.FormEncodedQueryParameters {

  /// A `Sequence` allowing iteration over all form-encoded key-value pairs contained by the query parameters.
  ///
  public var allKeyValuePairs: KeyValuePairs {
    KeyValuePairs(params: self)
  }

  /// A `Sequence` allowing iteration over all form-encoded key-value pairs contained by a set of query parameters.
  ///
  public struct KeyValuePairs: Sequence {

    internal var rawKVPs: RawKeyValuePairs<WebURL.UTF8View.SubSequence>?

    internal init(params: WebURL.FormEncodedQueryParameters) {
      self.rawKVPs = params.storage.utf8.query.map { RawKeyValuePairs(utf8: $0) }
    }

    public func makeIterator() -> Iterator {
      Iterator(rawIter: rawKVPs?.makeIterator())
    }

    public struct Iterator: IteratorProtocol {

      internal var rawIter: RawKeyValuePairs<WebURL.UTF8View.SubSequence>.Iterator?

      internal init(rawIter: RawKeyValuePairs<WebURL.UTF8View.SubSequence>.Iterator?) {
        self.rawIter = rawIter
      }

      public mutating func next() -> (String, String)? {
        guard let nextKVP = rawIter?.next() else {
          return nil
        }
        let queryUTF8 = rawIter!.remaining.base
        return (queryUTF8[nextKVP.key].urlFormDecodedString, queryUTF8[nextKVP.value].urlFormDecodedString)
      }
    }

    /// Whether or not this sequence contains any key-value pairs.
    ///
    public var isEmpty: Bool {
      var iter = makeIterator()
      return iter.next() == nil
    }
  }

  /// A sequence which allows iterating the key-value pairs within a collection of UTF8 bytes.
  ///
  /// The sequence assumes the "&" and "=" delimiters have _not_ been encoded, but otherwise does not assume the contents of the keys or values
  /// to be encoded in any particular way.
  ///
  @usableFromInline
  internal struct RawKeyValuePairs<UTF8Bytes>: Sequence where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    /// - Note: `pair` includes the trailing ampersand separator, unless the key-value pair ends at the end of the query string.
    @usableFromInline
    internal typealias Ranges = (
      pair: Range<UTF8Bytes.Index>, key: Range<UTF8Bytes.Index>, value: Range<UTF8Bytes.Index>
    )

    @usableFromInline
    internal var utf8: UTF8Bytes

    @inlinable
    internal init(utf8: UTF8Bytes) {
      self.utf8 = utf8
    }

    @inlinable
    internal func makeIterator() -> Iterator {
      return Iterator(remaining: utf8[...])
    }

    @usableFromInline
    internal struct Iterator: IteratorProtocol {

      @usableFromInline
      internal var remaining: UTF8Bytes.SubSequence

      @inlinable
      internal init(remaining: UTF8Bytes.SubSequence) {
        self.remaining = remaining
      }

      @inlinable
      internal mutating func next() -> Ranges? {

        guard remaining.isEmpty == false else {
          return nil
        }
        var nextKVP: UTF8Bytes.SubSequence
        repeat {
          if let nextKVPEnd = remaining.firstIndex(of: ASCII.ampersand.codePoint) {
            nextKVP = remaining[..<nextKVPEnd]
            remaining = remaining[remaining.index(after: nextKVPEnd)...]
          } else if remaining.isEmpty == false {
            nextKVP = remaining
            remaining = remaining[remaining.endIndex...]
          } else {
            return nil
          }
        } while nextKVP.isEmpty
        // If there is no "=" sign, the standard requires that 'value' be the empty string.
        let key: Range<UTF8Bytes.Index>
        let value: Range<UTF8Bytes.Index>
        if let keyValueSeparator = nextKVP.firstIndex(of: ASCII.equalSign.codePoint) {
          key = nextKVP.startIndex..<keyValueSeparator
          value = nextKVP.index(after: keyValueSeparator)..<nextKVP.endIndex
        } else {
          key = nextKVP.startIndex..<nextKVP.endIndex
          value = nextKVP.endIndex..<nextKVP.endIndex
        }
        return (pair: nextKVP.startIndex..<remaining.startIndex, key: key, value: value)
      }
    }

    /// Returns a `Sequence` of key-value pairs whose keys, when form-decoded, contain the same UTF-8 code-units as the given key.
    ///
    /// This is useful in situations where the query string is not known to be precisely form-encoded (e.g. contains spaces, or extra percent-encoding).
    ///
    @inlinable
    internal func filteredToUnencodedKey<StringType>(
      _ keyToFind: StringType
    ) -> LazyFilterSequence<Self> where StringType: StringProtocol {
      self.lazy.filter { (_, key, _) in
        utf8[key].lazy.percentDecodedUTF8(from: \.form).elementsEqual(keyToFind.utf8)
      }
    }
  }
}

extension WebURL.FormEncodedQueryParameters {

  /// Whether or not the query parameters contain a value for the given key.
  ///
  @inlinable
  public func contains<StringType>(_ keyToFind: StringType) -> Bool where StringType: StringProtocol {
    guard let queryUTF8 = storage.utf8.query else { return false }
    var iter = RawKeyValuePairs(utf8: queryUTF8).filteredToUnencodedKey(keyToFind).makeIterator()
    return iter.next() != nil
  }

  /// Returns the first value matching the given key. The value is decoded from `application/x-www-form-urlencoded`.
  ///
  @inlinable
  public func get<StringType>(_ keyToFind: StringType) -> String? where StringType: StringProtocol {
    guard let queryUTF8 = storage.utf8.query else { return nil }
    var iter = RawKeyValuePairs(utf8: queryUTF8).filteredToUnencodedKey(keyToFind).makeIterator()
    return iter.next().map { queryUTF8[$0.value].urlFormDecodedString }
  }

  /// Returns all values matching the given key. The values are decoded from `application/x-www-form-urlencoded`.
  ///
  @inlinable
  public func getAll<StringType>(_ keyToFind: StringType) -> [String] where StringType: StringProtocol {
    guard let queryUTF8 = storage.utf8.query else { return [] }
    return RawKeyValuePairs(utf8: queryUTF8).filteredToUnencodedKey(keyToFind).map {
      queryUTF8[$0.value].urlFormDecodedString
    }
  }

  @inlinable
  public subscript(dynamicMember dynamicMember: String) -> String? {
    get { get(dynamicMember) }
    set { set(dynamicMember, to: newValue) }
  }
}


// --------------------------------------------
// MARK: - Writing
// --------------------------------------------


extension WebURL.FormEncodedQueryParameters {

  /// Appends the given key-value pair to the query parameters.
  ///
  /// The key and value will be form-encoded in the query.
  /// Even if the key is already present in the query, no existing key-value pairs will be removed.
  ///
  @inlinable
  public mutating func append<StringType>(_ key: StringType, value: StringType) where StringType: StringProtocol {
    append(contentsOf: CollectionOfOne((key, value)))
  }

  /// Removes all instances of the given key from the query parameters.
  ///
  @inlinable
  public mutating func remove<StringType>(_ keyToDelete: StringType) where StringType: StringProtocol {
    set(keyToDelete, to: nil)
  }

  /// Removes all key-value pairs from the query parameters.
  ///
  @inlinable
  public mutating func removeAll() {
    storage.utf8.setQuery(UnsafeBufferPointer?.none)
  }

  /// Sets `key` to the given value, if already present in the query, and appends if otherwise.
  /// If `newValue` is `nil`, all pairs with the given key are removed.
  ///
  /// The new value will be form-encoded in the query.
  /// If a key is present multiple times in the query, the first occurence will be modified and all other occurences removed.
  ///
  @inlinable
  public mutating func set<StringType>(
    _ key: StringType, to newValue: StringType?
  ) where StringType: StringProtocol {
    reencodeQueryIfNeeded()
    let encodedKeyToSet = key.urlFormEncoded
    let encodedNewValue = newValue?.urlFormEncoded
    storage.withUnwrappedMutableStorage(
      { small in small.setFormParamPair(encodedKey: encodedKeyToSet.utf8, encodedValue: encodedNewValue?.utf8) },
      { large in large.setFormParamPair(encodedKey: encodedKeyToSet.utf8, encodedValue: encodedNewValue?.utf8) }
    )
  }
}

// The many faces of append(contentsOf:).

extension WebURL.FormEncodedQueryParameters {

  /// Appends the given collection of key-value pairs to the query parameters.
  ///
  /// The keys and values will be form-encoded in the query.
  /// Even if keys are already present in the query, no existing key-value pairs will be removed.
  ///
  @inlinable
  public mutating func append<CollectionType, StringType>(
    contentsOf keyValuePairs: CollectionType
  ) where CollectionType: Collection, CollectionType.Element == (StringType, StringType), StringType: StringProtocol {
    reencodeQueryIfNeeded()
    storage.withUnwrappedMutableStorage(
      { small in small.appendFormParamPairs(fromUnencoded: keyValuePairs.lazy.map { ($0.0.utf8, $0.1.utf8) }) },
      { large in large.appendFormParamPairs(fromUnencoded: keyValuePairs.lazy.map { ($0.0.utf8, $0.1.utf8) }) }
    )
  }

  @inlinable
  public static func += <CollectionType, StringType>(
    lhs: inout WebURL.FormEncodedQueryParameters, rhs: CollectionType
  ) where CollectionType: Collection, CollectionType.Element == (StringType, StringType), StringType: StringProtocol {
    lhs.append(contentsOf: rhs)
  }

  // Unfortunately, (String, String) and (key: String, value: String) appear to be treated as different types.

  /// Appends the given collection of key-value pairs to the query parameters.
  ///
  /// The keys and values will be form-encoded in the query.
  /// Even if keys are already present in the query, no existing key-value pairs will be removed.
  ///
  @inlinable
  public mutating func append<CollectionType, StringType>(
    contentsOf keyValuePairs: CollectionType
  )
  where
    CollectionType: Collection, CollectionType.Element == (key: StringType, value: StringType),
    StringType: StringProtocol
  {
    append(contentsOf: keyValuePairs.lazy.map { ($0, $1) } as LazyMapCollection)
  }

  @inlinable
  public static func += <CollectionType, StringType>(
    lhs: inout WebURL.FormEncodedQueryParameters, rhs: CollectionType
  )
  where
    CollectionType: Collection, CollectionType.Element == (key: StringType, value: StringType),
    StringType: StringProtocol
  {
    lhs.append(contentsOf: rhs)
  }

  // Add an overload for Dictionary, so that its key-value pairs at least get a predictable order.
  // There is no way to enforce an order for Dictionary, so this isn't breaking anybody's expectations.

  /// Appends the given sequence of key-value pairs to these query parameters.
  ///
  /// The keys and values will be form-encoded in the query.
  /// Even if keys are already present in the query, no existing key-value pairs will be removed.
  ///
  /// - Note: Since `Dictionary`'s contents are not ordered, this method will sort the key-value pairs by name before they are form-encoded
  ///         (using the standard library's Unicode comparison), so that the results are at least predictable. If this order is not desirable, sort the key-value
  ///         pairs before appending them.
  ///
  @inlinable
  public mutating func append<StringType>(
    contentsOf keyValuePairs: [StringType: StringType]
  ) where StringType: StringProtocol {
    append(contentsOf: keyValuePairs.sorted(by: { lhs, rhs in lhs.key < rhs.key }))
  }

  @inlinable
  public static func += <StringType>(
    lhs: inout WebURL.FormEncodedQueryParameters, rhs: [StringType: StringType]
  ) where StringType: StringProtocol {
    lhs.append(contentsOf: rhs)
  }
}


// --------------------------------------------
// MARK: - URLStorage + FormEncodedQueryParameters
// --------------------------------------------


extension URLStorage {

  /// Appends the given key-value pairs to this URL's query, form-encoding them as it does so.
  ///
  @inlinable
  internal mutating func appendFormParamPairs<C, UTF8Bytes>(
    fromUnencoded keyValuePairs: C
  ) -> AnyURLStorage
  where C: Collection, C.Element == (UTF8Bytes, UTF8Bytes), UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    let combinedLength: Int
    let needsEscaping: Bool
    (combinedLength, needsEscaping) = keyValuePairs.reduce(into: (0, false)) { metrics, kvp in
      let (keyLength, encodeKey) = kvp.0.lazy.percentEncodedGroups(as: \.form).encodedLength
      let (valLength, encodeVal) = kvp.1.lazy.percentEncodedGroups(as: \.form).encodedLength
      metrics.0 += keyLength + valLength
      metrics.1 = metrics.1 || encodeKey || encodeVal
    }
    if needsEscaping {
      return appendFormParamPairs(
        fromEncoded: keyValuePairs.lazy.map {
          ($0.0.lazy.percentEncoded(as: \.form), $0.1.lazy.percentEncoded(as: \.form))
        },
        lengthIfKnown: combinedLength
      )
    } else {
      return appendFormParamPairs(fromEncoded: keyValuePairs, lengthIfKnown: combinedLength)
    }
  }

  /// Appends the given key-value pairs to this URL's query, assuming that they are already form-encoded.
  ///
  /// - parameters:
  ///   - keyValuePairs: The key-value pairs to be appended to the query. Must be form-encoded.
  ///   - lengthIfKnown: The combined length of all keys and values, if known. Must not include `=` or `&` separator characters.
  ///
  @inlinable
  internal mutating func appendFormParamPairs<C, UTF8Bytes>(
    fromEncoded keyValuePairs: C, lengthIfKnown: Int? = nil
  ) -> AnyURLStorage
  where C: Collection, C.Element == (UTF8Bytes, UTF8Bytes), UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    let oldStructure = header.structure

    let encodedKVPsLength: Int
    if let knownLength = lengthIfKnown {
      encodedKVPsLength = knownLength + (keyValuePairs.count * 2) - 1 /* '=' and '&' */
    } else {
      encodedKVPsLength =
        keyValuePairs.reduce(into: 0) { length, kvp in
          length += kvp.0.count + 1 /* '=' */ + kvp.1.count + 1 /* '&' */
        } - 1
    }

    let separatorLength: Int
    if oldStructure.queryLength == 0 {
      // No query. We need to add a "?" delimiter.
      separatorLength = 1
    } else if oldStructure.queryLength == 1 {
      // There is a query, but it's a lone "?" with no string after it.
      separatorLength = 0
    } else {
      // There is a query, and we need to add a "&" between the existing contents and appended KVPs.
      separatorLength = 1
    }

    var newStructure = oldStructure
    newStructure.queryLength += separatorLength + encodedKVPsLength

    return replaceSubrange(
      oldStructure.fragmentStart..<oldStructure.fragmentStart,
      withUninitializedSpace: separatorLength + encodedKVPsLength,
      newStructure: newStructure
    ) { buffer in
      var bytesWritten = 0
      if oldStructure.queryLength == 0 {
        buffer[0] = ASCII.questionMark.codePoint
        bytesWritten += 1
      } else if oldStructure.queryLength != 1 {
        buffer[0] = ASCII.ampersand.codePoint
        bytesWritten += 1
      }
      for (key, value) in keyValuePairs {
        bytesWritten += UnsafeMutableBufferPointer(rebasing: buffer[bytesWritten...]).fastInitialize(from: key)
        buffer[bytesWritten] = ASCII.equalSign.codePoint
        bytesWritten += 1
        bytesWritten += UnsafeMutableBufferPointer(rebasing: buffer[bytesWritten...]).fastInitialize(from: value)
        if bytesWritten < buffer.count {
          buffer[bytesWritten] = ASCII.ampersand.codePoint
          bytesWritten += 1
        }
      }
      return bytesWritten
    }.newStorage
  }

  /// Sets the value of the first key-value pair whose key matches `encodedKey` to `encodedValue`.
  ///
  /// If no key-value pair's key matches `encodedKey`, the key-value pair will be appended.
  /// All other key-value pairs whose key matches `encodedKey` will be removed. If `encodedValue` is `nil`, all matching pairs will be removed.
  ///
  /// - important: This method assumes that the query string is already minimally `application/x-www-form-urlencoded`; i.e. that
  ///              pairs which match the given key encode it using exactly the same code-units.
  ///
  @inlinable
  internal mutating func setFormParamPair<UTF8Bytes>(
    encodedKey: UTF8Bytes, encodedValue: UTF8Bytes?
  ) -> AnyURLStorage where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    let oldQueryRange = header.structure.rangeForReplacingCodeUnits(of: .query).dropFirst()

    // If we have a new value to set, find the first KVP which matches the key.
    let rangeToRemoveMatchesFrom: Range<Int>
    var _rangeOfFirstValue: Range<Int>?
    if let encodedValue = encodedValue {
      guard
        let firstMatch = WebURL.FormEncodedQueryParameters.RawKeyValuePairs(
          utf8: codeUnits[oldQueryRange]
        ).first(where: { codeUnits[$0.key].elementsEqual(encodedKey) })
      else {
        return appendFormParamPairs(fromEncoded: CollectionOfOne((encodedKey, encodedValue)))
      }
      _rangeOfFirstValue = firstMatch.value
      rangeToRemoveMatchesFrom = firstMatch.pair.upperBound..<oldQueryRange.upperBound
    } else {
      _rangeOfFirstValue = nil
      rangeToRemoveMatchesFrom = oldQueryRange
    }

    // Remove key-value pairs in the range after the first match.
    // Since all `URLHeader`s support *fewer* code-units (even if not the optimal header type for the smaller string),
    // we'll just remove the KVPs from the query's code-units and copy to the optimal the header type later (if needed).
    // This will potentially cause an extra copy due to COW.
    var totalRemovedBytes = 0
    codeUnits.unsafeTruncate(rangeToRemoveMatchesFrom) { query in
      var remaining = query
      while let match = WebURL.FormEncodedQueryParameters.RawKeyValuePairs(
        utf8: remaining
      ).first(where: { remaining[$0.key].elementsEqual(encodedKey) }) {
        let baseAddress = remaining.baseAddress!
        (baseAddress + match.pair.lowerBound).assign(
          from: baseAddress + match.pair.upperBound, count: remaining.count - match.pair.upperBound
        )
        remaining = UnsafeMutableBufferPointer(
          start: baseAddress + match.pair.lowerBound,
          count: remaining.count - match.pair.upperBound
        )
        totalRemovedBytes += match.pair.count
      }
      // If we removed the last KVP in the query, we may have a trailing ampersand that needs dropping.
      if totalRemovedBytes != query.count, query[query.count - totalRemovedBytes - 1] == ASCII.ampersand.codePoint {
        totalRemovedBytes += 1
      }
      (query.baseAddress! + query.count - totalRemovedBytes).deinitialize(count: totalRemovedBytes)

      return query.count - totalRemovedBytes
    }

    var newStructure = header.structure
    newStructure.queryLength -= totalRemovedBytes

    if let encodedValue = encodedValue, let rangeOfFirstValue = _rangeOfFirstValue {
      newStructure.queryLength += (encodedValue.count - rangeOfFirstValue.count)
      return replaceSubrange(
        rangeOfFirstValue,
        withUninitializedSpace: encodedValue.count,
        newStructure: newStructure,
        initializer: { buffer in buffer.fastInitialize(from: encodedValue) }
      ).newStorage

    } else {
      // If the query is just a lone "?", set it to nil instead.
      if newStructure.queryLength == 1 {
        assert(codeUnits[newStructure.queryStart] == ASCII.questionMark.codePoint)
        codeUnits.removeSubrange(newStructure.queryStart..<newStructure.queryStart + 1)
        newStructure.queryLength = 0
      }
      header.copyStructure(from: newStructure)
      if !AnyURLStorage.isOptimalStorageType(Self.self, requiredCapacity: codeUnits.count, structure: newStructure) {
        return AnyURLStorage(optimalStorageForCapacity: codeUnits.count, structure: newStructure) { buffer in
          buffer.fastInitialize(from: codeUnits)
        }
      }
      return AnyURLStorage(self)
    }
  }
}
