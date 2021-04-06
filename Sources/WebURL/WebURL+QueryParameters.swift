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

  /// A view of the `application/x-www-form-urlencoded` key-value pairs in this URL's `query`.
  ///
  /// The `queryParams` view allows you to conveniently get and set the values for particular keys by accessing them as members.
  /// For keys which cannot be written as members, the `get` and `set` functions provide equivalent functionality.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/shopping/deals?category=food&limit=25")!
  /// assert(url.queryParams.category == "food")
  ///
  /// url.queryParams.distance = "10km"
  /// assert(url.serialized == "http://example.com/shopping/deals?category=food&limit=25&distance=10km")
  ///
  /// url.queryParams.limit = nil
  /// assert(url.serialized == "http://example.com/shopping/deals?category=food&distance=10km")
  ///
  /// url.queryParams.set("cuisine", to: "🇮🇹")
  /// assert(url.serialized == "http://example.com/shopping/deals?category=food&distance=10km&cuisine=%F0%9F%87%AE%F0%9F%87%B9")
  /// ```
  ///
  /// Additionally, you can iterate all of the key-value pairs using the `.allKeyValuePairs` property:
  ///
  /// ```swift
  /// for (key, value) in url.queryParams.allKeyValuePairs {
  ///   // ("category", "food")
  ///   // ("distance", "10km")
  ///   // ("cuisine", "🇮🇹")
  /// }
  /// ```
  ///
  public var queryParams: QueryParameters {
    get {
      return QueryParameters(url: self)
    }
    _modify {
      var params = QueryParameters(url: self)
      self.storage = _tempStorage
      defer { self.storage = params.url.storage }
      yield &params
    }
    set {
      if newValue.url.storage.structure.queryIsKnownFormEncoded {
        newValue.withQueryUTF8 { src in
          let src = src.isEmpty ? nil : src
          withMutableStorage(
            { small in small.setQuery(toKnownFormEncoded: src) },
            { large in large.setQuery(toKnownFormEncoded: src) }
          )
        }
        return
      }
      let formEncoded = newValue.formEncodedQueryBytes
      withMutableStorage(
        { small in small.setQuery(toKnownFormEncoded: formEncoded) },
        { large in large.setQuery(toKnownFormEncoded: formEncoded) }
      )
    }
  }

  /// A view of the `application/x-www-form-urlencoded` key-value pairs in a URL's `query`.
  ///
  @dynamicMemberLookup
  public struct QueryParameters {

    @usableFromInline
    internal var url: WebURL

    internal init(url: WebURL) {
      self.url = url
    }
  }
}

// backing.

extension WebURL.QueryParameters {

  internal func withQueryUTF8<ResultType>(_ body: (UnsafeBufferPointer<UInt8>) -> ResultType) -> ResultType {
    return url.storage.withUTF8(of: .query) { maybeBytes in
      guard let bytes = maybeBytes, bytes.count > 1 else {
        return body(UnsafeBufferPointer(start: nil, count: 0))
      }
      return body(UnsafeBufferPointer(rebasing: bytes.dropFirst()))
    }
  }

  internal var formEncodedQueryBytes: [UInt8]? {
    withQueryUTF8 { queryBytes in
      var result = [UInt8]()
      result.reserveCapacity(queryBytes.count + 1)
      for kvp in RawKeyValuePairs(utf8: queryBytes) {
        result.append(
          contentsOf: queryBytes[kvp.key].lazy.percentDecoded(using: URLEncodeSet.FormEncoded.self)
            .percentEncoded(using: URLEncodeSet.FormEncoded.self).joined())
        result.append(ASCII.equalSign.codePoint)
        result.append(
          contentsOf: queryBytes[kvp.value].lazy.percentDecoded(using: URLEncodeSet.FormEncoded.self)
            .percentEncoded(using: URLEncodeSet.FormEncoded.self).joined())
        result.append(ASCII.ampersand.codePoint)
      }
      _ = result.popLast()
      // Non-empty queries may become empty once form-encoded (e.g. "&&&&").
      // These should result in 'nil' queries.
      return result.isEmpty ? nil : result
    }
  }

  internal mutating func reencodeQueryIfNeeded() {
    guard url.storage.structure.queryIsKnownFormEncoded == false else { return }
    let reencodedQuery = formEncodedQueryBytes
    url.withMutableStorage(
      { small in small.setQuery(toKnownFormEncoded: reencodedQuery) },
      { large in large.setQuery(toKnownFormEncoded: reencodedQuery) }
    )
    assert(url.storage.structure.queryIsKnownFormEncoded)
  }
}


// --------------------------------------------
// MARK: - Reading
// --------------------------------------------


extension WebURL.QueryParameters {

  /// A `Sequence` allowing iteration over all key-value pairs contained by the query parameters.
  ///
  public var allKeyValuePairs: KeyValuePairs {
    KeyValuePairs(params: self)
  }

  /// A `Sequence` allowing iteration over all key-value pairs contained by a set of query parameters.
  ///
  public struct KeyValuePairs: Sequence {

    internal var params: WebURL.QueryParameters

    internal init(params: WebURL.QueryParameters) {
      self.params = params
    }

    /// Whether or not these query parameters contain any key-value pairs.
    ///
    public var isEmpty: Bool {
      var iterator = makeIterator()
      return iterator.next() == nil
    }

    public func makeIterator() -> Iterator {
      Iterator(params: params)
    }

    public struct Iterator: IteratorProtocol {

      internal var params: WebURL.QueryParameters
      internal var utf8Offset: Int

      internal init(params: WebURL.QueryParameters) {
        self.params = params
        self.utf8Offset = 0
      }

      public mutating func next() -> (String, String)? {
        return params.withQueryUTF8 { utf8Bytes in
          guard utf8Offset != utf8Bytes.count else { return nil }
          var resumedIter = RawKeyValuePairs(utf8: utf8Bytes.suffix(from: utf8Offset)).makeIterator()
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

  /// A sequence which allows iterating the key-value pairs within a collection of UTF8 bytes.
  /// The sequence assumes the "&" and "=" separator characters have _not_ been escaped, but otherwise
  /// does not assume the content of the keys or values to be escaped in any particular way.
  ///
  internal struct RawKeyValuePairs<UTF8Bytes>: Sequence where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    /// - Note: `pair` includes the trailing ampersand separator, unless the key-value pair ends at the end of the query string.
    internal typealias Ranges = (
      pair: Range<UTF8Bytes.Index>, key: Range<UTF8Bytes.Index>, value: Range<UTF8Bytes.Index>
    )

    internal var utf8: UTF8Bytes

    internal init(utf8: UTF8Bytes) {
      self.utf8 = utf8
    }

    internal func makeIterator() -> Iterator {
      return Iterator(remaining: utf8[...])
    }

    internal struct Iterator: IteratorProtocol {

      internal var remaining: UTF8Bytes.SubSequence

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

    internal func filteredToUnencodedKey<StringType>(
      _ keyToFind: StringType
    ) -> LazyFilterSequence<Self> where StringType: StringProtocol {
      self.lazy.filter { (_, key, _) in
        utf8[key].lazy.percentDecoded(using: URLEncodeSet.FormEncoded.self).elementsEqual(keyToFind.utf8)
      }
    }
  }
}

extension WebURL.QueryParameters {

  /// Whether or not these query parameters contain a value for the given key.
  ///
  @_specialize(where StringType == String)
  @_specialize(where StringType == Substring)
  public func contains<StringType>(_ keyToFind: StringType) -> Bool where StringType: StringProtocol {
    withQueryUTF8 {
      var iter = RawKeyValuePairs(utf8: $0).filteredToUnencodedKey(keyToFind).makeIterator()
      return iter.next() != nil
    }
  }

  /// Returns the first value matching the given key, if present. The value is decoded from `application/x-www-form-urlencoded`.
  ///
  @_specialize(where StringType == String)
  @_specialize(where StringType == Substring)
  public func get<StringType>(_ keyToFind: StringType) -> String? where StringType: StringProtocol {
    withQueryUTF8 { utf8 in
      var iter = RawKeyValuePairs(utf8: utf8).filteredToUnencodedKey(keyToFind).makeIterator()
      return iter.next().map { utf8[$0.value].urlFormDecodedString }
    }
  }

  /// Returns all values matching the given key. The values are decoded from `application/x-www-form-urlencoded`.
  ///
  @_specialize(where StringType == String)
  @_specialize(where StringType == Substring)
  public func getAll<StringType>(_ keyToFind: StringType) -> [String] where StringType: StringProtocol {
    withQueryUTF8 { utf8 in
      RawKeyValuePairs(utf8: utf8).filteredToUnencodedKey(keyToFind).map { utf8[$0.value].urlFormDecodedString }
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


extension WebURL.QueryParameters {

  /// Appends the given key-value pair to the query parameters. No existing key-value pairs are removed.
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

  /// Removes all key-value pairs in these query parameters.
  ///
  @inlinable
  public mutating func removeAll() {
    url.query = nil
  }

  /// Sets the given key to the given value, if present, or appends if otherwise. If `newValue` is `nil`, all pairs with the given key are removed.
  ///
  /// If a key is present multiple times, all but the first instance will be removed. It is this first instance which is set to the new value, so the relative order
  /// of key-value pairs in the overall string is maintained.
  ///
  @_specialize(where StringType == String)
  @_specialize(where StringType == Substring)
  public mutating func set<StringType>(
    _ keyToSet: StringType, to newValue: StringType?
  ) where StringType: StringProtocol {
    reencodeQueryIfNeeded()
    let encodedKeyToSet = keyToSet.urlFormEncoded
    let encodedNewValue = newValue?.urlFormEncoded
    url.withMutableStorage(
      { small in small.setQueryPair(encodedKey: encodedKeyToSet.utf8, encodedValue: encodedNewValue?.utf8) },
      { large in large.setQueryPair(encodedKey: encodedKeyToSet.utf8, encodedValue: encodedNewValue?.utf8) }
    )
  }
}

// The many faces of append(contentsOf:).

extension WebURL.QueryParameters {

  /// Appends the given sequence of key-value pairs to these query parameters. Existing values will not be removed.
  ///
  //  @_specialize(where CollectionType == CollectionOfOne<String>, StringType == String)
  //  @_specialize(where CollectionType == CollectionOfOne<Substring>, StringType == Substring)
  //  @_specialize(where CollectionType == [String], StringType == String)
  //  @_specialize(where CollectionType == [Substring], StringType == Substring)
  public mutating func append<CollectionType, StringType>(
    contentsOf keyValuePairs: CollectionType
  ) where CollectionType: Collection, CollectionType.Element == (StringType, StringType), StringType: StringProtocol {
    reencodeQueryIfNeeded()
    url.withMutableStorage(
      { small in small.appendPairsToQuery(fromUnencoded: keyValuePairs.lazy.map { ($0.0.utf8, $0.1.utf8) }) },
      { large in large.appendPairsToQuery(fromUnencoded: keyValuePairs.lazy.map { ($0.0.utf8, $0.1.utf8) }) }
    )
  }

  @inlinable
  public static func += <CollectionType, StringType>(
    lhs: inout WebURL.QueryParameters, rhs: CollectionType
  ) where CollectionType: Collection, CollectionType.Element == (StringType, StringType), StringType: StringProtocol {
    lhs.append(contentsOf: rhs)
  }

  // Unfortunately, (String, String) and (key: String, value: String) appear to be treated as different types.

  /// Appends the given sequence of key-value pairs to these query parameters. Existing values will not be removed.
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
    lhs: inout WebURL.QueryParameters, rhs: CollectionType
  )
  where
    CollectionType: Collection, CollectionType.Element == (key: StringType, value: StringType),
    StringType: StringProtocol
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
  public mutating func append<StringType>(
    contentsOf keyValuePairs: [StringType: StringType]
  ) where StringType: StringProtocol {
    append(
      contentsOf: keyValuePairs.sorted(by: { lhs, rhs in
        assert(lhs.key != rhs.key, "Dictionary with non-unique keys?")
        return lhs.key < rhs.key
      }))
  }

  @inlinable
  public static func += <StringType>(
    lhs: inout WebURL.QueryParameters, rhs: [StringType: StringType]
  ) where StringType: StringProtocol {
    lhs.append(contentsOf: rhs)
  }
}


// --------------------------------------------
// MARK: - URLStorage + QueryParameters
// --------------------------------------------


extension URLStorage {

  /// Appends the given key-value pairs to this URL's query, form-encoding them as it does so.
  ///
  internal mutating func appendPairsToQuery<CollectionType, UTF8Bytes>(
    fromUnencoded keyValuePairs: CollectionType
  ) -> AnyURLStorage
  where
    CollectionType: Collection, CollectionType.Element == (UTF8Bytes, UTF8Bytes),
    UTF8Bytes: Collection, UTF8Bytes.Element == UInt8
  {

    let combinedLength: Int
    let needsEscaping: Bool
    (combinedLength, needsEscaping) = keyValuePairs.reduce(into: (0, false)) { info, kvp in
      let encodeKey = kvp.0.lazy.percentEncoded(using: URLEncodeSet.FormEncoded.self).write { info.0 += $0.count }
      let encodeVal = kvp.1.lazy.percentEncoded(using: URLEncodeSet.FormEncoded.self).write { info.0 += $0.count }
      info.1 = info.1 || encodeKey || encodeVal
    }
    if needsEscaping {
      return appendPairsToQuery(
        fromEncoded: keyValuePairs.lazy.map {
          (
            $0.0.lazy.percentEncoded(using: URLEncodeSet.FormEncoded.self).joined(),
            $0.1.lazy.percentEncoded(using: URLEncodeSet.FormEncoded.self).joined()
          )
        },
        knownLength: combinedLength
      )
    } else {
      return appendPairsToQuery(fromEncoded: keyValuePairs, knownLength: combinedLength)
    }
  }

  /// Appends the given key-value pairs to this URL's query, assuming that they are already form-encoded.
  ///
  /// - parameters:
  ///   - keyValuePairs: The key-value pairs to be appended to the query. Must be form-encoded.
  ///   - knownLength:   The combined length of all keys and values, if known. Must not include `=` or `&` separator characters.
  ///
  internal mutating func appendPairsToQuery<CollectionType, UTF8Bytes>(
    fromEncoded keyValuePairs: CollectionType, knownLength: Int? = nil
  ) -> AnyURLStorage
  where
    CollectionType: Collection, CollectionType.Element == (UTF8Bytes, UTF8Bytes),
    UTF8Bytes: Collection, UTF8Bytes.Element == UInt8
  {

    let oldStructure = header.structure

    let appendedStringLength: Int
    if let knownLength = knownLength {
      appendedStringLength = knownLength + (keyValuePairs.count * 2 /* '=' and '&' */) - 1 /* one too many '&'s */
    } else {
      appendedStringLength =
        keyValuePairs.reduce(into: 0) { info, kvp in
          info += kvp.0.count + 1 /* '=' */ + kvp.1.count + 1 /* '&' */
        } - 1 /* one too many '&'s */
    }

    let separatorLength: Int
    if oldStructure.queryLength == 0 {
      separatorLength = 1  // "?"
    } else if oldStructure.queryLength == 1 {
      separatorLength = 0  // queryLength == 1 means there is already a "?" and we are appending immediately after it.
    } else {
      separatorLength = 1  // "&"
    }

    var newStructure = oldStructure
    newStructure.queryLength += separatorLength + appendedStringLength
    return replaceSubrange(
      oldStructure.fragmentStart..<oldStructure.fragmentStart,
      withUninitializedSpace: separatorLength + appendedStringLength,
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
        bytesWritten += UnsafeMutableBufferPointer(rebasing: buffer[bytesWritten...]).initialize(from: key).1
        buffer[bytesWritten] = ASCII.equalSign.codePoint
        bytesWritten += 1
        bytesWritten += UnsafeMutableBufferPointer(rebasing: buffer[bytesWritten...]).initialize(from: value).1
        if bytesWritten < buffer.count {
          buffer[bytesWritten] = ASCII.ampersand.codePoint
          bytesWritten += 1
        }
      }
      return bytesWritten
    }.newStorage
  }

  /// Sets the first key-value pair whose key matches `encodedKey` to `encodedValue`, and removes all other pairs with a matching key.
  /// If `encodedValue` is `nil`, removes all matching pairs.
  ///
  /// - important: This method assumes that the query string is already minimally `application/x-www-form-urlencoded`; i.e. that
  ///              pairs which match the given key encode it using exactly the same code-units.
  ///
  internal mutating func setQueryPair<UTF8Bytes>(
    encodedKey: UTF8Bytes, encodedValue: UTF8Bytes?
  ) -> AnyURLStorage where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    let oldQueryRange = header.structure.rangeForReplacingCodeUnits(of: .query).dropFirst()

    // If we have a new value to set, find the first matching KVP.
    // The standard requires us to alter this pair's value in-place, and remove any other pairs with the same key.
    // - Important: These offsets are relative to the start of the query.
    let firstOccurence: (pairEnd: Int, value: Range<Int>)
    if let encodedValue = encodedValue {
      let _firstMatch = codeUnits.withUnsafeBufferPointer(range: oldQueryRange) { queryBytes in
        WebURL.QueryParameters.RawKeyValuePairs(utf8: queryBytes)
          .first(where: { queryBytes[$0.key].elementsEqual(encodedKey) })
      }
      guard let firstMatch = _firstMatch else {
        return appendPairsToQuery(fromEncoded: CollectionOfOne((encodedKey, encodedValue)))
      }
      firstOccurence = (firstMatch.pair.upperBound, firstMatch.value)
    } else {
      firstOccurence = (0, 0..<0)
    }

    // Remove key-value pairs from the code-units directly.
    // We don't need to worry about swapping header types, since all headers support *fewer* code-units,
    // even if they are not the optimal headers for the shrunk-down URL string.
    // This is fixed-up later by copying to the optimal header representation if required.
    var totalRemovedBytes = 0
    codeUnits.unsafeTruncate(oldQueryRange.lowerBound + firstOccurence.pairEnd..<oldQueryRange.upperBound) { query in
      var remaining = query
      while let nextMatch = WebURL.QueryParameters.RawKeyValuePairs(utf8: remaining)
        .first(where: { remaining[$0.key].elementsEqual(encodedKey) })
      {
        (remaining.baseAddress! + nextMatch.pair.lowerBound).assign(
          from: remaining.baseAddress! + nextMatch.pair.upperBound, count: remaining.count - nextMatch.pair.upperBound
        )
        remaining = UnsafeMutableBufferPointer(
          rebasing: remaining[nextMatch.pair.lowerBound..<remaining.endIndex - nextMatch.pair.count]
        )
        totalRemovedBytes += nextMatch.pair.count
      }
      // The 'pair' range for the last key-value pair in the query doesn't include a trailing ampersand
      // (since it doesn't have one), but if we remove it, we leave a _new_ key-value pair at the end,
      // which needs its trailing ampersand removed.
      if totalRemovedBytes != query.count, query[query.count - totalRemovedBytes - 1] == ASCII.ampersand.codePoint {
        totalRemovedBytes += 1
      }
      (query.baseAddress! + query.count - totalRemovedBytes).deinitialize(count: totalRemovedBytes)

      return query.count - totalRemovedBytes
    }

    var newStructure = header.structure
    newStructure.queryLength -= totalRemovedBytes

    guard let encodedValue = encodedValue else {
      if newStructure.queryLength == 1 {
        // If the query is just a lone "?", set it to nil instead.
        assert(codeUnits[newStructure.queryStart] == ASCII.questionMark.codePoint)
        codeUnits.replaceSubrange(newStructure.queryStart..<newStructure.queryStart + 1, with: EmptyCollection())
        newStructure.queryLength = 0
      }
      // Since we are only removing, the header will definitely support its new, smaller count.
      header.copyStructure(from: newStructure)
      if !AnyURLStorage.isOptimalStorageType(Self.self, requiredCapacity: codeUnits.count, structure: newStructure) {
        return AnyURLStorage(optimalStorageForCapacity: codeUnits.count, structure: newStructure) { buffer in
          buffer.initialize(from: codeUnits).1
        }
      }
      return AnyURLStorage(self)
    }

    let firstValueCodeUnitOffset = oldQueryRange.lowerBound + firstOccurence.value.lowerBound
    newStructure.queryLength += (encodedValue.count - firstOccurence.value.count)
    return replaceSubrange(
      firstValueCodeUnitOffset..<firstValueCodeUnitOffset + firstOccurence.value.count,
      withUninitializedSpace: encodedValue.count,
      newStructure: newStructure,
      initializer: { buffer in buffer.initialize(from: encodedValue).1 }
    ).newStorage
  }
}

extension ManagedArrayBuffer {

  /// Calls `body`, allowing it to alter or truncate the elements in the given range. `body` must return the new number of elements within the range, `n`.
  /// The `n` elements at the start of the buffer must be initialized, and elements from `n` until the end of the buffer must be deinitialized.
  ///
  internal mutating func unsafeTruncate(
    _ range: Range<Index>, _ body: (inout UnsafeMutableBufferPointer<Element>) -> Int
  ) {
    var removedElements = 0
    withUnsafeMutableBufferPointer { buffer in
      var slice = UnsafeMutableBufferPointer(rebasing: buffer[range])
      let newSliceCount = body(&slice)
      precondition(newSliceCount <= slice.count, "unsafeTruncate cannot initialize more content than it had space for")
      // Space in the range newSliceCount..<range.upperBound is now uninitialized. Move elements to fill the gap.
      (buffer.baseAddress! + range.lowerBound + newSliceCount).moveInitialize(
        from: (buffer.baseAddress! + range.upperBound), count: buffer.count - range.upperBound
      )
      removedElements = range.count - newSliceCount
    }
    self.header.count -= removedElements
  }
}
