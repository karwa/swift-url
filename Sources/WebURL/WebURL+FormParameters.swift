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

  /// A read-write view of the URL's form-encoded query parameters.
  ///
  /// This view interprets a URL's query string as an `application/x-www-form-urlencoded` list of key-value pairs.
  /// Keys and values are automatically form-decoded when they are returned and encoded when they are inserted.
  ///
  /// You can get or set the value for a key by accessing it as a property, or by using the
  /// ``FormEncodedQueryParameters/get(_:)`` or ``FormEncodedQueryParameters/set(_:to:)`` functions.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/currency/convert?from=EUR&to=USD")!
  /// url.formParams.from // ✅ "EUR"
  /// url.formParams.to   // ✅ "USD"
  ///
  /// url.formParams.from = "GBP"
  /// print(url)
  /// // ✅ "http://example.com/currency/convert?from=GBP&to=USD"
  /// //                                         ^^^^^^^^
  /// url.formParams.amount = "20"
  /// print(url)
  /// // ✅ "http://example.com/currency/convert?from=GBP&to=USD&amount=20"
  /// //                                                         ^^^^^^^^^
  /// ```
  ///
  /// Additionally, you can insert multiple key-value pairs using the
  /// ``FormEncodedQueryParameters/append(contentsOf:)-3zb6r`` function or `+=` operator, and iterate over
  /// all key-value pairs using the ``FormEncodedQueryParameters/allKeyValuePairs`` sequence.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/currency/convert")
  /// url.formParams += [
  ///   ("amount", "200"),
  ///   ("from", "EUR"),
  ///   ("to", "GBP")
  /// ]
  /// print(url)
  /// // ✅ "http://example.com/currency/convert?amount=200&from=EUR&to=GBP"
  /// //                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
  ///
  /// for (key, value) in url.formParams.allKeyValuePairs {
  ///   // ("amount", "200"), ("from", "EUR"), ("to", "GBP")
  /// }
  /// ```
  ///
  /// Be aware that modifying the query through this view will re-encode the _entire_ query using form-encoding.
  /// This matches the behavior of JavaScript's `URLSearchParams` class, defined in the WHATWG URL Standard.
  ///
  /// > Note:
  /// > Keys are found in the URL's query even if they are form-encoded,
  /// > but non-ASCII keys require an exact Unicode scalar match.
  ///
  /// ## Topics
  ///
  /// ### Getting the Value of a Key
  ///
  /// - ``WebURL/WebURL/FormEncodedQueryParameters/get(_:)``
  /// - ``WebURL/WebURL/FormEncodedQueryParameters/getAll(_:)``
  /// - ``WebURL/WebURL/FormEncodedQueryParameters/contains(_:)``
  ///
  /// ### Setting the Value of a Key
  ///
  /// - ``WebURL/WebURL/FormEncodedQueryParameters/set(_:to:)``
  /// - ``WebURL/WebURL/FormEncodedQueryParameters/remove(_:)``
  ///
  /// ### Appending Key-Value Pairs
  ///
  /// - ``WebURL/WebURL/FormEncodedQueryParameters/append(_:value:)``
  /// - ``WebURL/WebURL/FormEncodedQueryParameters/append(contentsOf:)-3zb6r``
  /// - ``WebURL/WebURL/FormEncodedQueryParameters/append(contentsOf:)-3vyt6``
  /// - ``WebURL/WebURL/FormEncodedQueryParameters/append(contentsOf:)-194p2``
  ///
  /// ### All Key-Value Pairs
  ///
  /// - ``WebURL/WebURL/FormEncodedQueryParameters/allKeyValuePairs``
  /// - ``WebURL/WebURL/FormEncodedQueryParameters/removeAll()``
  ///
  /// ### View Type
  ///
  /// - ``WebURL/WebURL/FormEncodedQueryParameters``
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
        try! storage.utf8.setQuery(toKnownFormEncoded: newValue.storage.utf8.query)
      } else {
        try! storage.utf8.setQuery(toKnownFormEncoded: newValue.formEncodedQueryBytes)
      }
    }
  }

  /// A read-write view of a URL's form-encoded query parameters.
  ///
  /// This view interprets a URL's query string as an `application/x-www-form-urlencoded` list of key-value pairs.
  /// Keys and values are automatically form-decoded when they are returned and encoded when they are inserted.
  ///
  /// Access a URL's form-encoded query parameters through its ``WebURL/formParams`` property.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/currency/convert?from=EUR&to=USD")!
  /// url.formParams.from // ✅ "EUR"
  /// url.formParams.to   // ✅ "USD"
  ///
  /// url.formParams.from = "GBP"
  /// print(url)
  /// // ✅ "http://example.com/currency/convert?from=GBP&to=USD"
  /// //                                         ^^^^^^^^
  /// url.formParams.amount = "20"
  /// print(url)
  /// // ✅ "http://example.com/currency/convert?from=GBP&to=USD&amount=20"
  /// //                                                         ^^^^^^^^^
  /// ```
  ///
  /// > Tip:
  /// > The documentation for this type can be found at: ``WebURL/formParams``.
  ///
  @dynamicMemberLookup
  public struct FormEncodedQueryParameters {

    @usableFromInline
    internal var storage: URLStorage

    internal init(storage: URLStorage) {
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
      result += queryUTF8[kvp.key].percentDecodedAndReencoded(using: .formEncoding)
      result.append(ASCII.equalSign.codePoint)
      result += queryUTF8[kvp.value].percentDecodedAndReencoded(using: .formEncoding)
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
    try! storage.utf8.setQuery(toKnownFormEncoded: formEncodedQueryBytes)
    assert(storage.structure.queryIsKnownFormEncoded)
  }
}


// --------------------------------------------
// MARK: - Standard Protocols
// --------------------------------------------


#if swift(>=5.5) && canImport(_Concurrency)
  extension WebURL.FormEncodedQueryParameters: Sendable {}
#endif


// --------------------------------------------
// MARK: - Reading
// --------------------------------------------


extension WebURL.FormEncodedQueryParameters {

  /// A `Sequence` of all key-value pairs in this URL's query.
  ///
  /// The keys and values returned by this sequence are form-decoded.
  ///
  /// ```swift
  /// let url = WebURL("https://example.com/convert?amount=200&from=EUR&to=GBP")!
  /// for (key, value) in url.formParams.allKeyValuePairs {
  ///   // ("amount", "200"), ("from", "EUR"), ("to", "GBP")
  /// }
  /// ```
  ///
  public var allKeyValuePairs: KeyValuePairs {
    KeyValuePairs(params: self)
  }

  /// A `Sequence` allowing iteration over all form-encoded key-value pairs contained in a URL's query.
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
        return (
          queryUTF8[nextKVP.key].percentDecodedString(substitutions: .formEncoding),
          queryUTF8[nextKVP.value].percentDecodedString(substitutions: .formEncoding)
        )
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

    /// - Note: `pair` includes the trailing ampersand delimiter, unless the key-value pair ends at the end of the query string.
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
          if let nextKVPEnd = remaining.fastFirstIndex(of: ASCII.ampersand.codePoint) {
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
        if let keyValueSeparator = nextKVP.fastFirstIndex(of: ASCII.equalSign.codePoint) {
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
        utf8[key].lazy.percentDecoded(substitutions: .formEncoding).elementsEqual(keyToFind.utf8)
      }
    }
  }
}

extension WebURL.FormEncodedQueryParameters {

  /// Whether there are any values associated with a given key.
  ///
  /// ```swift
  /// let url = WebURL("https://example.com/convert?amount=200&from=USD&to=EUR")!
  /// //                                            ^^^^^^^^^^
  ///
  /// url.formParams.contains("amount") // ✅ true
  /// url.formParams.contains("format") // ✅ false
  /// ```
  ///
  /// > Note:
  /// > Keys are found in the URL's query even if they are form-encoded,
  /// > but non-ASCII keys require an exact Unicode scalar match.
  ///
  @inlinable
  public func contains<StringType>(_ key: StringType) -> Bool where StringType: StringProtocol {
    guard let queryUTF8 = storage.utf8.query else { return false }
    var iter = RawKeyValuePairs(utf8: queryUTF8).filteredToUnencodedKey(key).makeIterator()
    return iter.next() != nil
  }

  /// Returns the first value associated with a given key.
  ///
  /// If there are multiple values associated with the key, the first one is returned.
  /// To obtain all values associated with a key, use ``getAll(_:)``.
  /// The returned value is form-decoded.
  ///
  /// This function is equivalent to accessing the key using property syntax.
  ///
  /// ```swift
  /// let url = WebURL("https://example.com/convert?amount=200&from=USD&to=EUR")!
  /// //                                                       ^^^^^^^^
  ///
  /// url.formParams.get("from")
  /// // ✅ "USD"
  /// url.formParams.from
  /// // ✅ "USD"
  /// ```
  ///
  /// > Note:
  /// > Keys are found in the URL's query even if they are form-encoded,
  /// > but non-ASCII keys require an exact Unicode scalar match.
  ///
  @inlinable
  public func get<StringType>(_ key: StringType) -> String? where StringType: StringProtocol {
    guard let queryUTF8 = storage.utf8.query else { return nil }
    var iter = RawKeyValuePairs(utf8: queryUTF8).filteredToUnencodedKey(key).makeIterator()
    return iter.next().map { queryUTF8[$0.value].percentDecodedString(substitutions: .formEncoding) }
  }

  /// Returns all values associated with a given key.
  ///
  /// The returned values are form-decoded, and their relative order is preserved.
  ///
  /// ```swift
  /// let url = WebURL("https://example.com/books?cat=123&cat=456&format=json")!
  /// //                                          ^^^^^^^ ^^^^^^^
  ///
  /// url.formParams.get("cat")
  /// // "123"
  /// url.formParams.getAll("cat")
  /// // ✅ ["123", "456"]
  /// ```
  ///
  /// > Note:
  /// > Keys are found in the URL's query even if they are form-encoded,
  /// > but non-ASCII keys require an exact Unicode scalar match.
  ///
  @inlinable
  public func getAll<StringType>(_ key: StringType) -> [String] where StringType: StringProtocol {
    guard let queryUTF8 = storage.utf8.query else { return [] }
    return RawKeyValuePairs(utf8: queryUTF8).filteredToUnencodedKey(key).map {
      queryUTF8[$0.value].percentDecodedString(substitutions: .formEncoding)
    }
  }

  public subscript(dynamicMember dynamicMember: String) -> String? {
    get { get(dynamicMember) }
    set { set(dynamicMember, to: newValue) }
  }
}


// --------------------------------------------
// MARK: - Writing
// --------------------------------------------


extension WebURL.FormEncodedQueryParameters {

  /// Appends a key-value pair.
  ///
  /// The key-value pair is added to the end of the URL's query; any values already
  /// associated with the key will not be removed.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/books")!
  ///
  /// url.formParams.append("cat", value: "123")
  /// print(url)
  /// // ✅ "https://example.com/books?cat=123"
  /// //                               ^^^^^^^
  /// url.formParams.append("cat", value: "456")
  /// print(url)
  /// // ✅ "https://example.com/books?cat=123&cat=456"
  /// //                                       ^^^^^^^
  /// ```
  ///
  /// The key and value must **not** be form-encoded, as this view will apply its own form-encoding.
  ///
  @inlinable
  public mutating func append<StringType>(_ key: StringType, value: StringType) where StringType: StringProtocol {
    append(contentsOf: CollectionOfOne((key, value)))
  }

  /// Removes all values associated with a given key.
  ///
  /// This is equivalent to setting the value associated with the key to `nil`.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/books?cat=123&cat=456&format=json")!
  /// //                                          ^^^^^^^ ^^^^^^^
  /// url.formParams.removeAll("cat")
  /// print(url)
  /// // ✅ "https://example.com/books?format=json"
  /// //                               ^
  /// ```
  ///
  /// > Note:
  /// > Keys are found in the URL's query even if they are form-encoded,
  /// > but non-ASCII keys require an exact Unicode scalar match.
  ///
  @inlinable
  public mutating func remove<StringType>(_ key: StringType) where StringType: StringProtocol {
    set(key, to: nil)
  }

  /// Removes all key-value pairs.
  ///
  /// This is equivalent to setting the URL's ``WebURL/query`` to `nil`.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/convert?amount=200&from=EUR&to=GBP")!
  /// url.formParams.removeAll()
  /// print(url)
  /// // ✅ "https://example.com/convert"
  /// ```
  ///
  public mutating func removeAll() {
    try! storage.utf8.setQuery(toKnownFormEncoded: UnsafeBoundsCheckedBufferPointer?.none)
  }

  /// Associates a value with a given key.
  ///
  /// This function has the effect of removing all existing values associated with the key,
  /// and, if `newValue` is not nil, inserting a new key-value pair where the first match used to be.
  /// If the key was not previously associated with any value, the new key-value pair is inserted at the end
  /// of the query.
  ///
  /// This function is equivalent to assigning a value using property syntax.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/books?cat=123&cat=456&format=json")!
  /// //                                          ^^^^^^^ ^^^^^^^
  ///
  /// url.formParams.set("cat", to: "789")
  /// print(url)
  /// // ✅ "https://example.com/books?cat=789&format=json"
  /// //                               ^^^^^^^
  /// url.formParams.sort = "published-desc"
  /// print(url)
  /// // ✅ "https://example.com/books?cat=789&format=json&sort=published-desc"
  /// //                                                   ^^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// The assigned value must **not** be form-encoded, as this view will apply its own form-encoding.
  ///
  /// > Note:
  /// > Keys are found in the URL's query even if they are form-encoded,
  /// > but non-ASCII keys require an exact Unicode scalar match.
  ///
  @inlinable
  public mutating func set<StringType>(
    _ key: StringType, to newValue: StringType?
  ) where StringType: StringProtocol {
    reencodeQueryIfNeeded()
    let encodedKeyToSet = key.percentEncoded(using: .formEncoding)
    let encodedNewValue = newValue?.percentEncoded(using: .formEncoding)
    storage.setFormParamPair(encodedKey: encodedKeyToSet.utf8, encodedValue: encodedNewValue?.utf8)
  }
}

// The many faces of append(contentsOf:).

extension WebURL.FormEncodedQueryParameters {

  /// Appends a collection of key-value pairs.
  ///
  /// The key-value pairs are added to the end of the URL's query; if the given keys already have values
  /// associated with them, those associations will not be removed.
  ///
  /// This function is equivalent to the `+=` operator.
  /// The following example demonstrates building a URL query by appending key-value pairs.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/convert")!
  /// url.formParams.append(contentsOf: [
  ///  ("amount", "200"),
  ///  ("from", "USD"),
  ///  ("to", "EUR")
  /// ])
  /// print(url)
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR"
  /// //                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^
  ///
  /// url.formParams += [
  ///  ("lang", "en"),
  ///  ("client", "app")
  /// ]
  /// print(url)
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR&lang=en&client=app"
  /// //                                                            ^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// The keys and values must **not** be form-encoded, as this view will apply its own form-encoding.
  ///
  @inlinable
  public mutating func append<CollectionType, StringType>(
    contentsOf keyValuePairs: CollectionType
  ) where CollectionType: Collection, CollectionType.Element == (StringType, StringType), StringType: StringProtocol {
    reencodeQueryIfNeeded()
    storage.appendFormParamPairs(fromUnencoded: keyValuePairs.lazy.map { ($0.0.utf8, $0.1.utf8) })
  }

  /// Appends a collection of key-value pairs.
  ///
  /// The key-value pairs are added to the end of the URL's query; if the given keys already have values
  /// associated with them, those associations will not be removed.
  ///
  /// This operator is equivalent to the ``append(contentsOf:)-3zb6r`` function.
  /// The following example demonstrates building a URL query by appending key-value pairs.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/convert")!
  /// url.formParams.append(contentsOf: [
  ///  ("amount", "200"),
  ///  ("from", "USD"),
  ///  ("to", "EUR")
  /// ])
  /// print(url)
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR"
  /// //                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^
  ///
  /// url.formParams += [
  ///  ("lang", "en"),
  ///  ("client", "app")
  /// ]
  /// print(url)
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR&lang=en&client=app"
  /// //                                                            ^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// The keys and values must **not** be form-encoded, as this view will apply its own form-encoding.
  ///
  @inlinable
  public static func += <CollectionType, StringType>(
    lhs: inout WebURL.FormEncodedQueryParameters, rhs: CollectionType
  ) where CollectionType: Collection, CollectionType.Element == (StringType, StringType), StringType: StringProtocol {
    lhs.append(contentsOf: rhs)
  }

  // Unfortunately, (String, String) and (key: String, value: String) appear to be treated as different types.

  /// Appends a collection of key-value pairs.
  ///
  /// The key-value pairs are added to the end of the URL's query; if the given keys already have values
  /// associated with them, those associations will not be removed.
  ///
  /// This function is equivalent to the `+=` operator.
  /// The following example demonstrates building a URL query by appending key-value pairs.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/convert")!
  /// url.formParams.append(contentsOf: [
  ///  (key: "amount", value: "200"),
  ///  (key: "from", value: "USD"),
  ///  (key: "to", value: "EUR")
  /// ])
  /// print(url)
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR"
  /// //                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^
  ///
  /// url.formParams += [
  ///  (key: "lang", value: "en"),
  ///  (key: "client", value: "app")
  /// ]
  /// print(url)
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR&lang=en&client=app"
  /// //                                                            ^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// The keys and values must **not** be form-encoded, as this view will apply its own form-encoding.
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

  /// Appends a collection of key-value pairs.
  ///
  /// The key-value pairs are added to the end of the URL's query; if the given keys already have values
  /// associated with them, those associations will not be removed.
  ///
  /// This operator is equivalent to the ``append(contentsOf:)-3vyt6`` function.
  /// The following example demonstrates building a URL query by appending key-value pairs.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/convert")!
  /// url.formParams.append(contentsOf: [
  ///  (key: "amount", value: "200"),
  ///  (key: "from", value: "USD"),
  ///  (key: "to", value: "EUR")
  /// ])
  /// print(url)
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR"
  /// //                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^
  ///
  /// url.formParams += [
  ///  (key: "lang", value: "en"),
  ///  (key: "client", value: "app")
  /// ]
  /// print(url)
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR&lang=en&client=app"
  /// //                                                            ^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// The keys and values must **not** be form-encoded, as this view will apply its own form-encoding.
  ///
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

  /// Appends a `Dictionary` of key-value pairs.
  ///
  /// The key-value pairs are added to the end of the URL's query; if the given keys already have values
  /// associated with them, those associations will not be removed.
  ///
  /// This function is equivalent to the `+=` operator.
  /// The following example demonstrates building a URL query by appending key-value pairs.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/convert")!
  /// url.formParams.append(contentsOf: [
  ///  "amount" : "200",
  ///  "from"   : "USD",
  ///  "to"     : "EUR"
  /// ])
  /// print(url)
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR"
  /// //                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^
  ///
  /// url.formParams += [
  ///  "lang"   : "en",
  ///  "client" : "app"
  /// ]
  /// print(url)
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR&client=app&lang=en"
  /// //                                                            ^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// The keys and values must **not** be form-encoded, as this view will apply its own form-encoding.
  ///
  /// > Note:
  /// > Since `Dictionary`'s contents are not ordered, this method will sort the key-value pairs by key name
  /// > before appending (using the standard library's Unicode-aware comparison), in order to produce a repeatable
  /// > result.
  ///
  @inlinable
  public mutating func append<StringType>(
    contentsOf keyValuePairs: [StringType: StringType]
  ) where StringType: StringProtocol {
    append(contentsOf: keyValuePairs.sorted(by: { lhs, rhs in lhs.key < rhs.key }))
  }

  /// Appends a `Dictionary` of key-value pairs.
  ///
  /// The key-value pairs are added to the end of the URL's query; if the given keys already have values
  /// associated with them, those associations will not be removed.
  ///
  /// This operator is equivalent to the ``append(contentsOf:)-194p2`` function.
  /// The following example demonstrates building a URL query by appending key-value pairs.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/convert")!
  /// url.formParams.append(contentsOf: [
  ///  "amount" : "200",
  ///  "from"   : "USD",
  ///  "to"     : "EUR"
  /// ])
  /// print(url)
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR"
  /// //                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^
  ///
  /// url.formParams += [
  ///  "lang"   : "en",
  ///  "client" : "app"
  /// ]
  /// print(url)
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR&client=app&lang=en"
  /// //                                                            ^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// The keys and values must **not** be form-encoded, as this view will apply its own form-encoding.
  ///
  /// > Note:
  /// > Since `Dictionary`'s contents are not ordered, this method will sort the key-value pairs by key name
  /// > before appending (using the standard library's Unicode-aware comparison), in order to produce a repeatable
  /// > result.
  ///
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
  ) where C: Collection, C.Element == (UTF8Bytes, UTF8Bytes), UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    let combinedLength: UInt
    let needsEscaping: Bool
    (combinedLength, needsEscaping) = keyValuePairs.reduce(into: (0, false)) { metrics, kvp in
      let (keyLength, encodeKey) = kvp.0.lazy.percentEncoded(using: .formEncoding).unsafeEncodedLength
      let (valLength, encodeVal) = kvp.1.lazy.percentEncoded(using: .formEncoding).unsafeEncodedLength
      metrics.0 += keyLength + valLength
      metrics.1 = metrics.1 || encodeKey || encodeVal
    }
    if needsEscaping {
      appendFormParamPairs(
        fromEncoded: keyValuePairs.lazy.map {
          ($0.0.lazy.percentEncoded(using: .formEncoding), $0.1.lazy.percentEncoded(using: .formEncoding))
        },
        lengthIfKnown: Int(combinedLength)
      )
    } else {
      appendFormParamPairs(fromEncoded: keyValuePairs, lengthIfKnown: Int(combinedLength))
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
  ) where C: Collection, C.Element == (UTF8Bytes, UTF8Bytes), UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    var appendedKVPStringLength: Int
    if let knownLength = lengthIfKnown {
      appendedKVPStringLength = knownLength + (keyValuePairs.count * 2) /* '=' and '&' */ - 1
    } else {
      appendedKVPStringLength = keyValuePairs.reduce(into: 0) { length, kvp in
        length += kvp.0.count + 1 /* '=' */ + kvp.1.count + 1 /* '&' */
      }
      appendedKVPStringLength -= 1
    }

    guard appendedKVPStringLength > 0 else {
      return
    }

    // Calculate the new structure and replace the code-units.
    var newStructure = structure

    let bytesToWrite = URLStorage.SizeType(appendedKVPStringLength) + 1
    let insertPosition: URLStorage.SizeType
    let delimiter: ASCII

    if structure.queryLength <= 1 {
      // Replace the entire query.
      (insertPosition, delimiter) = (structure.queryStart, .questionMark)
      newStructure.queryLength = bytesToWrite
    } else {
      // Append the KVP string to an existing query.
      (insertPosition, delimiter) = (structure.fragmentStart, .ampersand)
      newStructure.queryLength += bytesToWrite
    }

    try! replaceSubrange(
      insertPosition..<structure.fragmentStart,
      withUninitializedSpace: bytesToWrite,
      newStructure: newStructure
    ) { buffer in

      buffer[0] = delimiter.codePoint
      var bytesWritten = 1

      for (key, value) in keyValuePairs {
        bytesWritten += UnsafeMutableBufferPointer(rebasing: buffer[bytesWritten...]).fastInitialize(from: key)
        precondition(bytesWritten < buffer.count, "Invalid collection: contents have changed between iterations")
        buffer[bytesWritten] = ASCII.equalSign.codePoint
        bytesWritten += 1
        precondition(bytesWritten <= buffer.count, "Invalid collection: contents have changed between iterations")
        bytesWritten += UnsafeMutableBufferPointer(rebasing: buffer[bytesWritten...]).fastInitialize(from: value)
        if bytesWritten < buffer.count {
          buffer[bytesWritten] = ASCII.ampersand.codePoint
          bytesWritten += 1
        }
      }
      return bytesWritten
    }.get()
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
  ) where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    assert(structure.queryIsKnownFormEncoded)
    let oldQueryRange = structure.rangeForReplacingCodeUnits(of: .query).dropFirst().toCodeUnitsIndices()

    // Find the first KVP to match the key. If no keys match, and we have a value to set, append the new value.
    let formParams = WebURL.FormEncodedQueryParameters.RawKeyValuePairs(utf8: codeUnits[oldQueryRange])
    guard let firstMatch = formParams.first(where: { codeUnits[$0.key].elementsEqual(encodedKey) }) else {
      if let encodedValue = encodedValue {
        appendFormParamPairs(fromEncoded: CollectionOfOne((encodedKey, encodedValue)))
      } else {
        // No matching keys, and no value to set. We're done.
      }
      return
    }

    // We have a match. If we have a new value to set, remove all subsequent KVPs with the same key.
    var rangeToInsertNewValue: Range<Int>?
    let rangeToRemoveMatchesFrom: Range<Int>

    if encodedValue != nil {
      rangeToInsertNewValue = firstMatch.value
      rangeToRemoveMatchesFrom = firstMatch.pair.upperBound..<oldQueryRange.upperBound
    } else {
      rangeToInsertNewValue = nil
      rangeToRemoveMatchesFrom = oldQueryRange  // TODO: Start removals from firstMatch
    }

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
      // If we removed the last KVP, we may have a trailing ampersand that needs dropping.
      if totalRemovedBytes < query.count, query[query.count - totalRemovedBytes - 1] == ASCII.ampersand.codePoint {
        totalRemovedBytes += 1
      }
      (query.baseAddress! + query.count - totalRemovedBytes).deinitialize(count: totalRemovedBytes)

      return query.count - totalRemovedBytes
    }

    // Now that all subsequent KVPs have been removed, replace the value in the first match.
    // Since it already exists as part of a KVP, it already has the required separators around it.
    var newStructure = structure
    newStructure.queryLength -= URLStorage.SizeType(totalRemovedBytes)

    if let encodedValue = encodedValue, let rangeOfFirstValue = rangeToInsertNewValue {
      guard let encodedValueLength = URLStorage.SizeType(exactly: encodedValue.count) else {
        fatalError(URLSetterError.exceedsMaximumSize.description)
      }
      let rangeOfFirstValue = rangeOfFirstValue.toURLStorageIndices()
      newStructure.queryLength -= URLStorage.SizeType(rangeOfFirstValue.count)
      newStructure.queryLength += encodedValueLength
      try! replaceSubrange(
        rangeOfFirstValue,
        withUninitializedSpace: encodedValueLength,
        newStructure: newStructure,
        initializer: { buffer in buffer.fastInitialize(from: encodedValue) }
      ).get()

    } else {
      // TODO: Move this up in to the 'unsafeTruncate' operation to avoid the 'removeSubrange'.
      // If the query is just a lone "?", set it to nil instead.
      if newStructure.queryLength == 1 {
        assert(codeUnits[newStructure.queryStart] == ASCII.questionMark.codePoint)
        newStructure.queryLength = 0
        removeSubrange(newStructure.queryStart..<newStructure.queryStart + 1, newStructure: newStructure)
      } else {
        structure = newStructure
      }
    }
  }
}
