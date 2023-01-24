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

#if swift(<5.7)
  #error("WebURL.KeyValuePairs requires Swift 5.7 or newer")
#endif

// TODO: Some open questions:
//
// - Should we, by default, escape non-URL code-points? And if so, how? How would one opt-out?
//   -> Is it important that we create 'valid' URLs?
//      -> To be fair, other component setters don't care about that.
//         For example, the query setter does not percent-encode square brackets.
//      -> Then again, the component setters are supposed to take already-escaped data;
//         we take unescaped data.
//

extension WebURL {

  /// A view of a URL component as a list of key-value pairs, using a given schema.
  ///
  /// Some URL components, such as the ``WebURL/WebURL/query`` and ``WebURL/WebURL/fragment``,
  /// are entirely free to use for custom data - they are simply opaque strings, without any prescribed format.
  /// A popular convention is to write a list of key-value pairs in these components,
  /// as it is a highly versatile way to encode arbitrary data.
  ///
  /// For example, a website for a search engine might support key-value pairs in its query component,
  /// containing the user's search query, a start offset, the number of results to return,
  /// and other filters or options.
  ///
  /// ```
  ///                              key   value
  ///                               │ ┌────┴────┐
  /// http://www.example.com/search?q=hello+world&start=2&num=5&safe=on&as_rights=cc_publicdomain
  ///                               └─────┬─────┘ └──┬──┘ └─┬─┘ └──┬──┘ └────────────┬──────────┘
  ///                                   pair       pair   pair   pair              pair
  /// ```
  ///
  /// The `KeyValuePairs` view provides a rich set of APIs for reading and modifying lists of key-value pairs
  /// in opaque URL components, and supports a variety of options and formats.
  ///
  /// ### Collection API
  ///
  /// At its most fundamental level, `KeyValuePairs` is a list - it conforms to `Collection`,
  /// which allows working with the list of pairs similarly to how you might work with an `Array`.
  /// You can iterate over all key-value pairs, identify a pair by its location (index),
  /// and perform modifications such as removing or editing a particular pair, or inserting pairs at a location.
  ///
  /// ```swift
  /// var url = WebURL("http://example/students?class=8&sort=age")!
  ///
  /// // Find the location of the first existing 'sort' key.
  /// let sortIdx = url.queryParams.firstIndex(where: { $0.key == "sort" }) ?? url.queryParams.endIndex
  ///
  /// // Insert an additional 'sort' key before it.
  /// url.queryParams.insert(key: "sort", value: "name", at: sortIdx)
  /// // ✅ "http://example/students?class=8&sort=name&sort=age"
  /// //                                     ^^^^^^^^^
  /// ```
  ///
  /// The concept of "a list of key-value pairs" is quite broad,
  /// and for some URLs the position of a key-value pair might be significant.
  ///
  /// ### Map/MultiMap API
  ///
  /// In addition to identifying locations within the list, it is natural to read and write values
  /// associated with a particular key.
  ///
  /// In general, `KeyValuePairs` is a kind of multi-map - multiple pairs may have the same key.
  /// To retrieve all values associated with a key, call ``WebURL/WebURL/KeyValuePairs/allValues(forKey:)``.
  ///
  /// ```swift
  /// let url = WebURL("http://example/students?class=12&sort=name&sort=age")!
  /// url.queryParams.allValues(forKey: "sort")
  /// // ✅ ["name", "age"]
  /// ```
  ///
  /// However, many keys are expected to be unique, so it is often useful to treat the list of pairs
  /// as a plain map/`Dictionary` (at least with respect to those keys).
  ///
  /// `KeyValuePairs` includes a key-based subscript, which allows getting and setting the first value
  /// associated with a key. When setting a value, other pairs with the same key will be removed.
  ///
  /// ```swift
  /// var url = WebURL("http://example/search?q=quick+recipes&start=10&limit=20")!
  ///
  /// // Use the subscript to get/set values associated with keys.
  ///
  /// url.queryParams["q"]
  /// // ✅ "quick recipes"
  ///
  /// url.queryParams["q"]    = "some query"
  /// url.queryParams["safe"] = "on"
  /// // ✅ "http://example/search?q=some%20query&start=10&limit=20&safe=on"
  /// //                           ^^^^^^^^^^^^^^                   ^^^^^^^
  ///
  /// url.queryParams["limit"] = nil
  /// // ✅ "http://example/search?q=some%20query&start=10&safe=on"
  /// //                                                 ^^^
  /// ```
  ///
  /// > Tip:
  /// >
  /// > Even though this API feels like working with a `Dictionary`, it is just a _view_ of a URL component,
  /// > so the key-value pairs are stored encoded in a URL string rather than a hash-table.
  /// > To reduce some of the costs of searching for multiple keys, `KeyValuePairs` supports batched lookups:
  /// >
  /// > ```swift
  /// > let (searchQuery, start, limit, safeSearch) = url.queryParams["q", "start", "limit", "safe"]
  /// > // ✅ ("some query", "10", nil, "on")
  /// > ```
  ///
  /// ### In-Place Mutation
  ///
  /// `KeyValuePairs` has value semantics - if you assign it to `var` variable and modify it,
  /// everything will work, but the URL it came from will be unaffected by those changes.
  /// In order to modify the URL component, use the ``WebURL/WebURL/withMutableKeyValuePairs(in:schema:_:)`` function
  /// or the ``WebURL/WebURL/queryParams`` property:
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/gallery")!
  /// url.withMutableKeyValuePairs(in: .fragment, schema: .percentEncoded) { kvps in
  ///   kvps["image"]  = "14"
  ///   kvps["origin"] = "100,100"
  ///   kvps["zoom"]   = "200"
  /// }
  /// // ✅ "http://example.com/gallery#image=14&origin=100,100&zoom=200"
  /// //                               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// ### Specifying the Format with Schemas
  ///
  /// The schema describes how key-value pairs should be read from- and written to- the URL component string.
  /// WebURL includes two built-in schemas, for the most common kind of key-value strings:
  ///
  /// - ``WebURL/KeyValueStringSchema/formEncoded``, and
  /// - ``WebURL/KeyValueStringSchema/percentEncoded``
  ///
  /// The former is for interpreting `application/x-www-form-urlencoded` content -
  /// it considers `"+"` characters in the URL component to be escaped spaces,
  /// and is more restrictive about which characters may be used unescaped in the URL string.
  /// It should be used for HTML forms, and other strings which explicitly require form-encoding.
  ///
  /// The latter is very similar to `formEncoded`, but uses conventional percent-encoding -
  /// it considers a `"+"` character to simply be a plus sign, with no special meaning,
  /// and is more lenient about which characters may be used unescaped in the URL string.
  /// This schema should be used for interpreting `mailto:` URLs, media fragments, and other strings which
  /// do not require form-encoding.
  ///
  /// It is also possible to define your own schema, which can be useful when working with key-value strings
  /// using alternative delimiters, or which need to control other aspects of how pairs are interpreted or written.
  /// See ``WebURL/KeyValueStringSchema`` for more details.
  ///
  /// > Tip:
  /// >
  /// > WebURL's ``WebURL/WebURL/queryParams`` property is equivalent to
  /// >
  /// > ```swift
  /// > url.keyValuePairs(in: .query, schema: .formEncoded)
  /// > // or
  /// > url.withMutableKeyValuePairs(in: .query, schema: .formEncoded) { ... }
  /// > ```
  ///
  /// ## Topics
  ///
  /// ### Finding Values By Key
  ///
  /// - ``WebURL/WebURL/KeyValuePairs/subscript(_:)-7blvp``
  /// - ``WebURL/WebURL/KeyValuePairs/subscript(_:_:)``
  /// - ``WebURL/WebURL/KeyValuePairs/subscript(_:_:_:)``
  /// - ``WebURL/WebURL/KeyValuePairs/subscript(_:_:_:_:)``
  /// - ``WebURL/WebURL/KeyValuePairs/allValues(forKey:)``
  ///
  /// ### Setting Values By Key
  ///
  /// - ``WebURL/WebURL/KeyValuePairs/set(key:to:)``
  ///
  /// ### Appending Pairs
  ///
  /// - ``WebURL/WebURL/KeyValuePairs/append(key:value:)``
  /// - ``WebURL/WebURL/KeyValuePairs/append(contentsOf:)-84bng``
  /// - ``WebURL/WebURL/KeyValuePairs/+=(_:_:)-4gres``
  ///
  /// ### Inserting Pairs at a Location
  ///
  /// - ``WebURL/WebURL/KeyValuePairs/insert(key:value:at:)``
  /// - ``WebURL/WebURL/KeyValuePairs/insert(contentsOf:at:)``
  ///
  /// ### Removing Pairs by Location
  ///
  /// - ``WebURL/WebURL/KeyValuePairs/removeAll(in:where:)``
  /// - ``WebURL/WebURL/KeyValuePairs/removeAll(where:)``
  /// - ``WebURL/WebURL/KeyValuePairs/remove(at:)``
  /// - ``WebURL/WebURL/KeyValuePairs/removeSubrange(_:)``
  ///
  /// ### Replacing Pairs by Location
  ///
  /// - ``WebURL/WebURL/KeyValuePairs/replaceKey(at:with:)``
  /// - ``WebURL/WebURL/KeyValuePairs/replaceValue(at:with:)``
  /// - ``WebURL/WebURL/KeyValuePairs/replaceSubrange(_:with:)``
  ///
  /// ### Appending Pairs (Overloads)
  ///
  /// Overloads of `append(contentsOf:)` allow appending dictionaries and permit variations in tuple labels.
  ///
  /// - ``WebURL/WebURL/KeyValuePairs/append(contentsOf:)-9lkdx``
  /// - ``WebURL/WebURL/KeyValuePairs/+=(_:_:)-54t4m``
  ///
  /// - ``WebURL/WebURL/KeyValuePairs/append(contentsOf:)-5nok5``
  /// - ``WebURL/WebURL/KeyValuePairs/+=(_:_:)-8zyqk``
  ///
  /// ### Schemas
  ///
  /// - ``WebURL/KeyValueStringSchema/formEncoded``
  /// - ``WebURL/KeyValueStringSchema/percentEncoded``
  /// - ``WebURL/KeyValueStringSchema``
  ///
  /// ### Supported URL Components
  ///
  /// - ``WebURL/KeyValuePairsSupportedComponent``
  ///
  /// ### View Type
  ///
  /// - ``WebURL/WebURL/KeyValuePairs``
  ///
  @inlinable
  public func keyValuePairs<Schema>(
    in component: KeyValuePairsSupportedComponent, schema: Schema
  ) -> KeyValuePairs<Schema> {
    KeyValuePairs(storage: storage, component: component, schema: schema)
  }

  /// A read-write view of a URL component as a list of key-value pairs, using a given schema.
  ///
  /// This function is a mutating version of ``WebURL/WebURL/keyValuePairs(in:schema:)``.
  /// It executes the `body` closure with a mutable `KeyValuePairs` view,
  /// which can be used to modify a URL component in-place.
  ///
  /// See the documentation for ``WebURL/WebURL/keyValuePairs(in:schema:)`` for more information about the
  /// operations exposed by the `KeyValuePairs` view.
  ///
  /// ```swift
  /// var url = WebURL("http://www.example.com/example.ogv#track=french&t=10,20")!
  /// url.withMutableKeyValuePairs(in: .fragment, schema: .percentEncoded) { kvps in
  ///   kvps["track"] = "german"
  /// }
  /// // ✅ "http://www.example.com/example.ogv#track=german&t=10,20"
  /// //                                              ^^^^^^
  /// ```
  ///
  /// Do not reassign the given `KeyValuePairs` to a value taken from another URL.
  ///
  /// > Tip:
  /// >
  /// > WebURL's ``WebURL/WebURL/queryParams`` property is equivalent to
  /// >
  /// > ```swift
  /// > url.keyValuePairs(in: .query, schema: .formEncoded)
  /// > // or
  /// > url.withMutableKeyValuePairs(in: .query, schema: .formEncoded) { ... }
  /// > ```
  ///
  @inlinable
  public mutating func withMutableKeyValuePairs<Schema, Result>(
    in component: KeyValuePairsSupportedComponent,
    schema: Schema,
    _ body: (inout KeyValuePairs<Schema>) throws -> Result
  ) rethrows -> Result {
    // TODO: How can we protect against reassignment?
    // ```
    // let kvps = urlA.keyValuePairs(...)
    // urlB.withMutableKeyValuePairs(...) { $0 = kvps }
    // print(urlB) // !!! - reassigns the entire URL.
    // ```
    // Maybe stash a unique token in the KeyValuePairs view.
    var view = KeyValuePairs(storage: storage, component: component, schema: schema)
    storage = _tempStorage
    defer { storage = view.storage }
    return try body(&view)
  }
}

extension WebURL {

  /// A read-write view of the URL's query as a list of key-value pairs
  /// in the `application/x-www-form-urlencoded` format.
  ///
  /// This property exposes a `KeyValuePairs` view of the URL's query,
  /// which can be used to modify the component in-place.
  ///
  /// `KeyValuePairs` conforms to `Collection`, so you can iterate over all pairs in the list,
  /// and it includes subscripts to get and set values associated with a key:
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/convert?from=EUR&to=USD")!
  ///
  /// // 🚩 Use subscripts to get/set values associated with a key.
  ///
  /// url.queryParams["from"] // ✅ "EUR"
  /// url.queryParams["to"]   // ✅ "USD"
  ///
  /// url.queryParams["from"] = "GBP"
  /// // ✅ "http://example.com/convert?from=GBP&to=USD"
  /// //                                ^^^^^^^^
  /// url.queryParams["amount"] = "20"
  /// // ✅ "http://example.com/convert?from=GBP&to=USD&amount=20"
  /// //                                                ^^^^^^^^^
  ///
  /// // 🚩 Look up multiple keys in a single operation.
  ///
  /// let (amount, from, to) = url.queryParams["amount", "from", "to"]
  /// // ✅ ("20", "GBP", "USD")
  /// ```
  ///
  /// Additionally, you can build query strings by appending pairs using the `+=` operator.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/convert")
  /// url.queryParams += [
  ///   ("amount", "200"),
  ///   ("from", "EUR"),
  ///   ("to", "GBP")
  /// ]
  /// // ✅ "http://example.com/convert?amount=200&from=EUR&to=GBP"
  /// //                                ^^^^^^^^^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// See the documentation for ``WebURL/WebURL/keyValuePairs(in:schema:)`` for more information about the
  /// operations exposed by the `KeyValuePairs` view.
  ///
  @inlinable
  public var queryParams: KeyValuePairs<FormCompatibleKeyValueString> {
    get {
      KeyValuePairs(storage: storage, component: .query, schema: .formEncoded)
    }
    _modify {
      var view = KeyValuePairs(storage: storage, component: .query, schema: .formEncoded)
      storage = _tempStorage
      defer { storage = view.storage }
      yield &view
    }
    set {
      try! storage.utf8.setQuery(newValue.storage.utf8.query)
    }
  }
}

extension WebURL.UTF8View {

  /// A pair of slices, containing the contents of the given key-value pair's key and value.
  ///
  /// ```swift
  /// let url = WebURL("http://example/convert?amount=200&from=EUR&to=USD")!
  ///
  /// if let match = url.queryParams.firstIndex(where: { $0.key == "from" }) {
  ///   let valueSlice = url.utf8.keyValuePair(match).value
  ///   assert(valueSlice.elementsEqual("EUR".utf8)) // ✅
  /// }
  /// ```
  ///
  @inlinable
  public func keyValuePair(
    _ i: WebURL.KeyValuePairs<some KeyValueStringSchema>.Index
  ) -> (key: SubSequence, value: SubSequence) {
    (self[i.rangeOfKey], self[i.rangeOfValue])
  }
}


// --------------------------------------------
// MARK: - Key-Value String Schemas
// --------------------------------------------


/// A specification for encoding and decoding a list of key-value pairs in a URL component.
///
/// Some URL components, such as the ``WebURL/WebURL/query`` and ``WebURL/WebURL/fragment``,
/// are opaque strings with no prescribed format. A popular convention is to write a list of key-value pairs
/// in these components, as it is a highly versatile way to encode arbitrary data.
///
/// The details can vary, but by convention keys and values are delimited using an equals sign (`=`),
/// and each key-value pair is delimited from the next one using an ampersand (`&`).
/// For example:
///
/// ```
/// key1=value1&key2=value2
/// └┬─┘ └─┬──┘ └┬─┘ └─┬──┘
/// key  value  key  value
/// ```
///
/// The built-in ``WebURL/KeyValueStringSchema/formEncoded`` and ``WebURL/KeyValueStringSchema/percentEncoded`` schemas
/// are appropriate for the most common key-value strings.
///
/// However, some systems require variations in the string format and may define a custom schema.
///
/// ## Topics
///
/// ### Customizing Delimiters
///
/// - ``isKeyValueDelimiter(_:)-4o6s0``
/// - ``isPairDelimiter(_:)-5cnsh``
/// - ``preferredKeyValueDelimiter``
/// - ``preferredPairDelimiter``
///
/// ### Customizing Encoding of Spaces
///
/// - ``decodePlusAsSpace``
/// - ``encodeSpaceAsPlus-4i9g2``
///
/// ### Customizing Percent-encoding
///
/// - ``shouldPercentEncode(ascii:)-3p9fx``
///
/// ### Verifying Custom Schemas
///
/// - ``verify(for:)``
///
public protocol KeyValueStringSchema {

  // - Delimiters.

  /// Whether a given ASCII code-point is a delimiter between key-value pairs.
  ///
  /// Schemas may accept more than one delimiter between key-value pairs.
  /// For instance, some systems must allow both semicolons and ampersands between pairs:
  ///
  /// ```
  /// key1=value1&key2=value2;key3=value3
  ///            ^           ^
  /// ```
  ///
  /// The default implementation returns `true` if `codePoint` is equal to ``preferredPairDelimiter``.
  ///
  func isPairDelimiter(_ codePoint: UInt8) -> Bool

  /// Whether a given ASCII code-point is a delimiter between a key and a value.
  ///
  /// Schemas may accept more than one delimiter between keys and values.
  /// For instance, a system may decide to accept both equals-signs and colons between keys and values:
  ///
  /// ```
  /// key1=value1&key2:value2
  ///     ^           ^
  /// ```
  ///
  /// The default implementation returns `true` if `codePoint` is equal to ``preferredKeyValueDelimiter``.
  ///
  func isKeyValueDelimiter(_ codePoint: UInt8) -> Bool

  /// The delimiter to write between key-value pairs when they are inserted in a string.
  ///
  /// ```
  /// // delimiter = ampersand:
  /// key1=value1&key2=value2&key3=value3
  ///            ^           ^
  ///
  /// // delimiter = comma:
  /// key1=value1,key2=value2,key3=value3
  ///            ^           ^
  /// ```
  ///
  /// The delimiter:
  ///
  /// - Must be an ASCII code-point,
  /// - Must not be the percent sign (`%`), plus sign (`+`), space, or a hex digit, and
  /// - Must not require escaping in the URL component(s) used with this schema.
  ///
  /// For the schema to be well-formed, ``WebURL/KeyValueStringSchema/isPairDelimiter(_:)-5cnsh``
  /// must recognize the code-point as a pair delimiter.
  ///
  var preferredPairDelimiter: UInt8 { get }

  /// The delimiter to write between the key and value when they are inserted in a string.
  ///
  /// ```
  /// // delimiter = equals:
  /// key1=value1&key2=value2
  ///     ^           ^
  ///
  /// // delimiter = colon:
  /// key1:value1&key2:value2
  ///     ^           ^
  /// ```
  ///
  /// The delimiter:
  ///
  /// - Must be an ASCII code-point,
  /// - Must not be the percent sign (`%`), plus sign (`+`), space, or a hex digit, and
  /// - Must not require escaping in the URL component(s) used with this schema.
  ///
  /// For the schema to be well-formed, ``WebURL/KeyValueStringSchema/isKeyValueDelimiter(_:)-4o6s0``
  /// must recognize the code-point as a key-value delimiter.
  ///
  var preferredKeyValueDelimiter: UInt8 { get }

  // - Escaping.

  /// Whether the given ASCII code-point should be percent-encoded.
  ///
  /// Some characters which occur in keys and values must be escaped
  /// because they have a reserved purpose for the key-value string or URL component:
  ///
  /// - Pair delimiters, as determined by ``WebURL/KeyValueStringSchema/isPairDelimiter(_:)-5cnsh``.
  /// - Key-value delimiters, as determined by ``WebURL/KeyValueStringSchema/isKeyValueDelimiter(_:)-4o6s0``.
  /// - The percent sign (`%`), as it is required for URL percent-encoding.
  /// - The plus sign (`+`), as it is sometimes used to encode spaces.
  /// - Any other code-points which must be escaped in the URL component.
  ///
  /// All other characters are written to the URL component without escaping.
  ///
  /// If this function returns `true` for a code-point, that code-point will _also_ be considered reserved and,
  /// if it occurs within a key or value, will be escaped when written to the key-value string.
  ///
  /// The default implementation returns `false`, so no additional code-points are escaped.
  ///
  func shouldPercentEncode(ascii codePoint: UInt8) -> Bool

  /// Whether a non-escaped plus sign (`+`) is decoded as a space.
  ///
  /// Some key-value strings support encoding spaces using the plus sign (`+`),
  /// as a shorthand alternative to percent-encoding them.
  /// This property must return `true` in order to accurately decode such strings.
  ///
  /// An example of key-value strings using this shorthand are `application/x-www-form-urlencoded`
  /// ("form encoded") strings, as used by HTML forms.
  ///
  /// ```
  /// Encoded: name=Johnny+Appleseed
  /// //                  ^
  /// Decoded: (key: "name", value: "Johnny Appleseed")
  /// //                                   ^
  /// ```
  ///
  /// Other key-value strings give no special meaning to the plus sign.
  /// This property must return `false` in order to accurately decode _those_ strings.
  ///
  /// An example of key-value strings for which plus signs are defined to simply mean literal plus signs
  /// are the query components of `mailto:` URLs.
  ///
  /// ```
  /// Encoded: cc=bob+swift@example.com
  /// //             ^
  /// Decoded: (key: "cc", value: "bob+swift@example.com")
  /// //                              ^
  /// ```
  ///
  /// Unfortunately, you need to know in advance which interpretation is appropriate
  /// for a particular key-value string.
  ///
  var decodePlusAsSpace: Bool { get }

  /// Whether spaces should be encoded as plus signs (`+`).
  ///
  /// Some key-value strings support encoding spaces using the plus sign (`+`),
  /// as a shorthand alternative to percent-encoding them.
  ///
  /// If this property returns `true`, the shorthand will be used.
  /// Otherwise, spaces will be percent-encoded, as all other disallowed characters are.
  ///
  /// ```
  /// Pair:  (key: "text", value: "hello, world")
  ///
  /// True:  text=hello,+world
  /// //                ^
  /// False: text=hello,%20world
  /// //                ^^^
  /// ```
  ///
  /// The default value is `false`. Use of the shorthand is **not recommended**,
  /// as the receiving system may not know that these encoded values require special decoding logic.
  /// The version without the shorthand can be accurately decoded by any system,
  /// even without that prior knowledge.
  ///
  /// If this property returns `true`, ``WebURL/KeyValueStringSchema/decodePlusAsSpace`` must also return `true`.
  ///
  var encodeSpaceAsPlus: Bool { get }
}

extension KeyValueStringSchema {

  @inlinable @inline(__always)
  public func isPairDelimiter(_ byte: UInt8) -> Bool {
    // Default: single delimiter.
    byte == preferredPairDelimiter
  }

  @inlinable @inline(__always)
  public func isKeyValueDelimiter(_ byte: UInt8) -> Bool {
    // Default: single delimiter.
    byte == preferredKeyValueDelimiter
  }

  @inlinable @inline(__always)
  public func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    // Default: no additional percent-encoding.
    false
  }

  @inlinable @inline(__always)
  public var encodeSpaceAsPlus: Bool {
    // Default: encode spaces as "%20", not "+".
    false
  }
}

extension KeyValueStringSchema {

  // TODO: Expose this as a customization point? e.g. for non-UTF8 encodings?
  @inlinable
  internal func unescapeAsUTF8String(_ source: some Collection<UInt8>) -> String {
    if decodePlusAsSpace {
      return source.percentDecodedString(substitutions: .formEncoding)
    } else {
      return source.percentDecodedString(substitutions: .none)
    }
  }
}

internal enum KeyValueStringSchemaVerificationFailure: Error, CustomStringConvertible {

  case preferredKeyValueDelimiterIsInvalid
  case preferredKeyValueDelimiterNotRecognized
  case preferredPairDelimiterIsInvalid
  case preferredPairDelimiterNotRecognized
  case invalidKeyValueDelimiterIsRecognized
  case invalidPairDelimiterIsRecognized
  case inconsistentSpaceEncoding

  public var description: String {
    switch self {
    case .preferredKeyValueDelimiterIsInvalid:
      return "Schema's preferred key-value delimiter is invalid"
    case .preferredKeyValueDelimiterNotRecognized:
      return "Schema does not recognize its preferred key-value delimiter as a key-value delimiter"
    case .preferredPairDelimiterIsInvalid:
      return "Schema's preferred pair delimiter is invalid"
    case .preferredPairDelimiterNotRecognized:
      return "Schema does not recognize its preferred pair delimiter as a pair delimiter"
    case .invalidKeyValueDelimiterIsRecognized:
      return "isKeyValueDelimiter recognizes an invalid delimiter"
    case .invalidPairDelimiterIsRecognized:
      return "isPairDelimiter recognizes an invalid delimiter"
    case .inconsistentSpaceEncoding:
      return "encodeSpaceAsPlus is true, so decodePlusAsSpace must also be true"
    }
  }
}

extension KeyValueStringSchema {

  /// Checks this schema for consistency.
  ///
  /// This function allows authors of custom schemas to verify their implementations
  /// for use in a particular URL component. If a schema fails verification, a fatal error will be triggered.
  ///
  /// ```swift
  /// struct HashBetweenPairsSchema: KeyValueStringSchema {
  ///   var preferredPairDelimiter: UInt8 { UInt8(ascii: "#") }
  ///   // ...
  /// }
  ///
  /// // We cannot write a key-value string like "http://ex/?key=value#key=value",
  /// // because the "#" is the sigil for the start of the fragment.
  ///
  /// HashBetweenPairsSchema().verify(for: .query)
  /// // ❗️ fatal error: "Schema's preferred pair delimiter may not be used in the query"
  ///
  /// // But we *can* use it in the fragment itself - "http://ex/#key=value#key=value"
  ///
  /// HashBetweenPairsSchema().verify(for: .fragment)
  /// // ✅ OK
  /// ```
  ///
  /// > Tip:
  /// >
  /// > Most developers will not have to define custom schemas.
  /// > For those that do, it is recommended to run this verification
  /// > as part of your regular unit tests.
  ///
  public func verify(for component: KeyValuePairsSupportedComponent) throws {

    // Preferred delimiters must not require escaping.

    let preferredDelimiters = verifyDelimitersDoNotNeedEscaping(in: component)

    if preferredDelimiters.keyValue == .max {
      throw KeyValueStringSchemaVerificationFailure.preferredKeyValueDelimiterIsInvalid
    }
    if preferredDelimiters.pair == .max {
      throw KeyValueStringSchemaVerificationFailure.preferredPairDelimiterIsInvalid
    }

    // isKeyValueDelimiter/isPairDelimiter must recognize preferred delimiters,
    // and must not recognize other reserved characters (e.g. %, ASCII hex digits, +).

    if !isKeyValueDelimiter(preferredDelimiters.keyValue) {
      throw KeyValueStringSchemaVerificationFailure.preferredKeyValueDelimiterNotRecognized
    }
    if !isPairDelimiter(preferredDelimiters.pair) {
      throw KeyValueStringSchemaVerificationFailure.preferredPairDelimiterNotRecognized
    }

    func delimiterPredicateIsInvalid(_ isDelimiter: (UInt8) -> Bool) -> Bool {
      "0123456789abcdefABCDEF%+".utf8.contains(where: isDelimiter)
    }

    if delimiterPredicateIsInvalid(isKeyValueDelimiter) {
      throw KeyValueStringSchemaVerificationFailure.invalidKeyValueDelimiterIsRecognized
    }
    if delimiterPredicateIsInvalid(isPairDelimiter) {
      throw KeyValueStringSchemaVerificationFailure.invalidPairDelimiterIsRecognized
    }

    // Space encoding must be consistent.

    if encodeSpaceAsPlus, !decodePlusAsSpace {
      throw KeyValueStringSchemaVerificationFailure.inconsistentSpaceEncoding
    }

    // All checks passed.
  }
}


// --------------------------------------------
// MARK: - Built-in Schemas
// --------------------------------------------


extension KeyValueStringSchema where Self == FormCompatibleKeyValueString {

  /// A key-value string compatible with the `application/x-www-form-urlencoded` format.
  ///
  /// **Specification:**
  ///
  /// - Pair delimiter: U+0026 AMPERSAND (&)
  /// - Key-value delimiter: U+003D EQUALS SIGN (=)
  /// - Decode `+` as space: `true`
  /// - Encode space as `+`: `false`
  /// - Escapes all characters except:
  ///   - ASCII alphanumerics
  ///   - U+002A (\*), U+002D (-), U+002E (.), and U+005F (\_)
  ///
  /// This schema is used to read `application/x-www-form-urlencoded` content,
  /// such as that produced by HTML forms or Javascript's `URLSearchParams` class.
  ///
  /// Unlike Javascript's `URLSearchParams`, spaces in inserted key-value pairs
  /// are written using regular percent-encoding, rather than using the shorthand
  /// which escapes them using plus signs.
  ///
  /// This removes a potential source of ambiguity for other systems processing the string.
  ///
  /// ## Topics
  ///
  /// ### Schema Type
  ///
  /// - ``WebURL/FormCompatibleKeyValueString``
  ///
  @inlinable
  public static var formEncoded: Self { Self() }
}

/// A key-value string compatible with the `application/x-www-form-urlencoded` format.
///
/// See ``WebURL/KeyValueStringSchema/formEncoded`` for more information.
///
public struct FormCompatibleKeyValueString: KeyValueStringSchema, Sendable {

  @inlinable
  public init() {}

  @inlinable
  public var preferredPairDelimiter: UInt8 {
    ASCII.ampersand.codePoint
  }

  @inlinable
  public var preferredKeyValueDelimiter: UInt8 {
    ASCII.equalSign.codePoint
  }

  @inlinable
  public var decodePlusAsSpace: Bool {
    true
  }

  @inlinable
  public func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    URLEncodeSet.FormEncoding().shouldPercentEncode(ascii: codePoint)
  }
}

extension KeyValueStringSchema where Self == PercentEncodedKeyValueString {

  /// A key-value string which uses conventional percent-encoding.
  ///
  /// **Specification:**
  ///
  /// - Pair delimiter: U+0026 AMPERSAND (&)
  /// - Key-value delimiter: U+003D EQUALS SIGN (=)
  /// - Decode `+` as space: `false`
  /// - Encode space as `+`: `false`
  /// - Escapes all characters except:
  ///   - Characters allowed by the URL component
  ///
  /// The differences between this schema and ``WebURL/FormCompatibleKeyValueString`` are:
  ///
  /// - Plus signs in the URL component have no special meaning,
  ///   and are interpreted as literal plus signs rather than escaped spaces.
  ///
  /// - All characters allowed in the URL component may be used without escaping.
  ///
  /// ## Topics
  ///
  /// ### Schema Type
  ///
  /// - ``WebURL/PercentEncodedKeyValueString``
  ///
  @inlinable
  public static var percentEncoded: Self { Self() }
}

/// A key-value string which uses conventional percent-encoding.
///
/// See ``WebURL/KeyValueStringSchema/percentEncoded`` for more information.
///
public struct PercentEncodedKeyValueString: KeyValueStringSchema, Sendable {

  @inlinable
  public init() {}

  @inlinable
  public var preferredPairDelimiter: UInt8 {
    ASCII.ampersand.codePoint
  }

  @inlinable
  public var preferredKeyValueDelimiter: UInt8 {
    ASCII.equalSign.codePoint
  }

  @inlinable
  public var decodePlusAsSpace: Bool {
    false
  }
}


// --------------------------------------------
// MARK: - WebURL.KeyValuePairs
// --------------------------------------------


/// A URL component which can contain a key-value string.
///
public struct KeyValuePairsSupportedComponent {

  @usableFromInline
  internal enum _Value {
    case query
    case fragment

    // TODO: We could support other opaque components.
    //
    // - 'mongodb:' URLs encode a comma-separated list in an opaque host.
    //   I can't find any that use key-value strings,
    //   but there is precendent for having some structured information in the host.
    //
    // - 'proxy:' URLs have key-value pairs in opaque paths.
    //   https://web.archive.org/web/20130620014949/http://getfoxyproxy.org/proxyprotocol.html
    //   This seems like it would be useful for many applications, and quite easy to support.
  }

  @usableFromInline
  internal var value: _Value

  @inlinable
  internal init(_ value: _Value) {
    self.value = value
  }

  /// The query component.
  ///
  /// See ``WebURL/WebURL/query`` for more information about this component.
  ///
  @inlinable
  public static var query: Self { Self(.query) }

  /// The fragment component.
  ///
  /// See ``WebURL/WebURL/fragment`` for more information about this component.
  ///
  @inlinable
  public static var fragment: Self { Self(.fragment) }
}

extension KeyValuePairsSupportedComponent: CaseIterable {

  public static var allCases: [KeyValuePairsSupportedComponent] {
    [.query, .fragment]
  }
}

extension WebURL {

  /// A view of a URL component as a list of key-value pairs, using a given schema.
  ///
  /// To access the view for a component, use the ``WebURL/WebURL/keyValuePairs(in:schema:)`` function.
  /// The ``WebURL/WebURL/queryParams`` property is a convenient shorthand for accessing pairs
  /// in a URL's query using the ``WebURL/FormCompatibleKeyValueString/formEncoded`` schema.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/convert?from=EUR&to=USD")!
  ///
  /// url.queryParams["from"] // ✅ "EUR"
  /// url.queryParams["to"]   // ✅ "USD"
  ///
  /// url.queryParams["from"] = "GBP"
  /// // ✅ "http://example.com/convert?from=GBP&to=USD"
  /// //                                ^^^^^^^^
  /// url.queryParams["amount"] = "20"
  /// // ✅ "http://example.com/convert?from=GBP&to=USD&amount=20"
  /// //                                                ^^^^^^^^^
  /// ```
  ///
  /// > Tip:
  /// >
  /// > The documentation for this type can be found at: ``WebURL/WebURL/keyValuePairs(in:schema:)``
  ///
  public struct KeyValuePairs<Schema: KeyValueStringSchema> {

    /// The URL.
    ///
    @usableFromInline
    internal var storage: URLStorage

    /// The component of `storage` containing the key-value string.
    ///
    @usableFromInline
    internal var component: KeyValuePairsSupportedComponent

    /// The specification of the key-value string.
    ///
    @usableFromInline
    internal var schema: Schema

    /// Data about the key-value string which is derived from the other properties,
    /// stored to accelerate certain operations which may access it frequently.
    ///
    /// > Important:
    /// > This value must be updated after the URL is modified.
    ///
    @usableFromInline
    internal var cache: Cache

    @inlinable
    internal init(storage: URLStorage, component: KeyValuePairsSupportedComponent, schema: Schema) {
      self.storage = storage
      self.component = component
      self.schema = schema
      self.cache = .calculate(storage: storage, component: component, schema: schema)
    }
  }
}

extension WebURL.KeyValuePairs {

  @usableFromInline
  internal struct Cache {

    /// The range of code-units containing the key-value string.
    ///
    /// This range does not include any leading or trailing URL component delimiters;
    /// for example, the leading `"?"` in the query is **NOT** included in this range.
    ///
    /// > Important:
    /// > This value must be updated after the URL is modified.
    ///
    @usableFromInline
    internal var componentContents: Range<URLStorage.SizeType>

    /// The index of the initial key-value pair.
    ///
    /// > Important:
    /// > This value must be updated after the URL is modified.
    ///
    @usableFromInline
    internal var startIndex: Index

    @inlinable
    internal init(componentContents: Range<URLStorage.SizeType>, startIndex: WebURL.KeyValuePairs<Schema>.Index) {
      self.componentContents = componentContents
      self.startIndex = startIndex
    }

    @inlinable
    internal static func _componentContents(
      startingAt contentStart: URLStorage.SizeType,
      storage: URLStorage,
      component: KeyValuePairsSupportedComponent
    ) -> Range<URLStorage.SizeType> {

      var contentLength: URLStorage.SizeType

      switch component.value {
      case .query:
        contentLength = storage.structure.queryLength
      case .fragment:
        contentLength = storage.structure.fragmentLength
      }
      if contentLength > 0 {
        contentLength &-= 1
      }

      return Range(uncheckedBounds: (contentStart, contentStart &+ contentLength))
    }

    /// Returns updated info about the key-value string.
    ///
    /// This function requires no prior knowledge of the URL component or key-value string,
    /// and calculates everything from scratch.
    ///
    /// | `startIndex` | Component content location | Component content length |
    /// | ------------ | -------------------------- | ------------------------ |
    /// |   unknown    |           unknown          |          unknown         |
    ///
    @inlinable
    internal static func calculate(
      storage: URLStorage,
      component: KeyValuePairsSupportedComponent,
      schema: Schema
    ) -> Cache {

      let component = component.urlComponent
      let contents = storage.structure.rangeForReplacingCodeUnits(of: component).dropFirst()
      let startIndex = Index.nextFrom(contents.lowerBound, in: storage.utf8[contents], schema: schema)
      return Cache(componentContents: contents, startIndex: startIndex)
    }

    /// Returns updated info about the key-value string.
    ///
    /// This function requires the caller to know the key-value string's startIndex,
    /// as well as the start location of the URL component's content.
    ///
    /// > Important:
    /// > The _content_ start location is required, not the _component_ start location.
    /// > If the component could have been set to/from nil, it can be difficult to know the content start location.
    ///
    /// | `startIndex` | Component content location | Component content length |
    /// | ------------ | -------------------------- | ------------------------ |
    /// |    known     |            known           |          unknown         |
    ///
    @inlinable
    internal static func withKnownStartIndex(
      startIndex: Index,
      contentStart: URLStorage.SizeType,
      storage: URLStorage,
      component: KeyValuePairsSupportedComponent
    ) -> Cache {

      let contents = _componentContents(startingAt: contentStart, storage: storage, component: component)
      return Cache(componentContents: contents, startIndex: startIndex)
    }

    @inlinable
    internal mutating func updateAfterAppend(
      storage: URLStorage,
      component: KeyValuePairsSupportedComponent,
      schema: Schema
    ) {

      // If the list was previously empty, we don't know startIndex,
      // and we don't know what the component's starting location is (it may have been nil before).

      if startIndex.keyValuePair.lowerBound == componentContents.upperBound {
        self = .calculate(storage: storage, component: component, schema: schema)
        return
      }

      // If the list was not empty, the URL component cannot be empty/nil.
      // startIndex and content start location are unchanged by append, but the URL component length will change.

      componentContents = Cache._componentContents(
        startingAt: componentContents.lowerBound,
        storage: storage,
        component: component
      )
    }
  }
}


// --------------------------------------------
// MARK: - Standard Protocols
// --------------------------------------------


extension KeyValuePairsSupportedComponent: Sendable {}
extension KeyValuePairsSupportedComponent._Value: Sendable {}
extension WebURL.KeyValuePairs: Sendable where Schema: Sendable {}
extension WebURL.KeyValuePairs.Index: Sendable where Schema: Sendable {}
extension WebURL.KeyValuePairs.Cache: Sendable where Schema: Sendable {}
extension WebURL.KeyValuePairs.Element: Sendable where Schema: Sendable {}

extension WebURL.KeyValuePairs: CustomStringConvertible {

  public var description: String {
    String(decoding: storage.utf8[cache.componentContents], as: UTF8.self)
  }
}


// --------------------------------------------
// MARK: - Reading: By Location.
// --------------------------------------------


extension WebURL.KeyValuePairs: Collection {

  @inlinable
  public var startIndex: Index {
    cache.startIndex
  }

  @inlinable
  public var endIndex: Index {
    .endIndex(cache.componentContents.upperBound)
  }

  @inlinable
  public func index(after i: Index) -> Index {
    assert(i < endIndex, "Attempt to advance endIndex")
    return .nextFrom(i.keyValuePair.upperBound &+ 1, in: storage.utf8[cache.componentContents], schema: schema)
  }

  public struct Index: Comparable {

    @usableFromInline
    internal typealias Source = WebURL.UTF8View.SubSequence

    /// The range of the entire key-value pair.
    ///
    /// - lowerBound = startIndex of key
    /// - upperBound = endIndex of value (either a pair delimiter or overall endIndex)
    ///
    @usableFromInline
    internal let keyValuePair: Range<URLStorage.SizeType>

    /// The position of the key-value delimiter.
    ///
    /// Either:
    /// - Index of the byte which separates the key from the value, or
    /// - keyValuePair.upperBound, if there is no delimiter in the key-value pair.
    ///
    @usableFromInline
    internal let keyValueDelimiter: URLStorage.SizeType

    @inlinable
    internal init(
      keyValuePair: Range<URLStorage.SizeType>,
      keyValueDelimiter: URLStorage.SizeType
    ) {
      self.keyValuePair = keyValuePair
      self.keyValueDelimiter = keyValueDelimiter
    }

    /// Returns an Index containing an empty key-value pair at the given source location.
    /// Intended to be used when creating an endIndex.
    ///
    @inlinable
    internal static func endIndex(_ i: URLStorage.SizeType) -> Index {
      return Index(keyValuePair: i..<i, keyValueDelimiter: i)
    }

    /// Returns the next Index from the given source location.
    ///
    /// The returned Index may not necessarily start at the given source location,
    /// as empty key-value pairs will be skipped.
    ///
    @inlinable
    internal static func nextFrom(_ i: URLStorage.SizeType, in source: Source, schema: Schema) -> Index {

      precondition(i >= source.startIndex)
      guard i < source.endIndex else {
        return .endIndex(URLStorage.SizeType(source.endIndex))
      }

      var cursor = i
      var kvpStart = i
      var keyValueDelimiter = Optional<URLStorage.SizeType>.none

      while cursor < source.endIndex {
        let byte = source.base[cursor]
        if schema.isKeyValueDelimiter(byte), keyValueDelimiter == nil {
          keyValueDelimiter = cursor
        } else if schema.isPairDelimiter(byte) {
          // If the KVP is empty, skip it.
          guard kvpStart != cursor else {
            cursor &+= 1
            kvpStart = cursor
            assert(keyValueDelimiter == nil)
            continue
          }
          break
        }
        cursor &+= 1
      }

      return Index(
        keyValuePair: Range(uncheckedBounds: (kvpStart, cursor)),
        keyValueDelimiter: keyValueDelimiter ?? cursor
      )
    }

    /// Returns an index with the same key and value lengths as this pair, but beginning at `newStartOfKey`.
    ///
    @inlinable
    internal func rebased(newStartOfKey: URLStorage.SizeType) -> Index {
      let rebasedPairEnd = newStartOfKey &+ (keyValuePair.upperBound &- keyValuePair.lowerBound)
      let rebasedDelimit = newStartOfKey &+ (keyValueDelimiter &- keyValuePair.lowerBound)
      return Index(
        keyValuePair: Range(uncheckedBounds: (newStartOfKey, rebasedPairEnd)),
        keyValueDelimiter: rebasedDelimit
      )
    }

    /// The region of the source collection containing this pair's key.
    ///
    @inlinable
    internal var rangeOfKey: Range<URLStorage.SizeType> {
      Range(uncheckedBounds: (keyValuePair.lowerBound, keyValueDelimiter))
    }

    /// Whether this pair contains a key-value delimiter.
    ///
    @inlinable
    internal var hasKeyValueDelimiter: Bool {
      keyValueDelimiter != keyValuePair.upperBound
    }

    /// The region of the source collection containing this pair's value.
    ///
    @inlinable
    internal var rangeOfValue: Range<URLStorage.SizeType> {
      let upper = keyValuePair.upperBound
      let lower = hasKeyValueDelimiter ? (keyValueDelimiter &+ 1) : upper
      return Range(uncheckedBounds: (lower, upper))
    }

    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.keyValuePair == rhs.keyValuePair && lhs.keyValueDelimiter == rhs.keyValueDelimiter
    }

    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.keyValuePair.lowerBound < rhs.keyValuePair.lowerBound
    }

    @inlinable
    public static func > (lhs: Self, rhs: Self) -> Bool {
      lhs.keyValuePair.lowerBound > rhs.keyValuePair.lowerBound
    }
  }
}


// MARK: TODO: BidirectionalCollection.


extension WebURL.KeyValuePairs {

  @inlinable
  public subscript(position: Index) -> Element {
    assert(position >= startIndex && position < endIndex, "Attempt to access an element at an invalid index")
    return Element(source: storage.codeUnits, position: position, schema: schema)
  }

  /// A slice of a URL component, containing a single key-value pair.
  ///
  /// Use the ``key`` and ``value`` properties to access the pair's decoded components.
  ///
  /// ```swift
  /// let url = WebURL("http://example/?name=Johnny+Appleseed&age=28")!
  /// //                                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  ///
  /// for kvp in url.queryParams {
  ///   print(kvp.key, "-", kvp.value)
  /// }
  ///
  /// // Prints:
  /// // "name - Johnny Appleseed"
  /// // "age - 28"
  /// ```
  ///
  /// Because these key-value pairs are slices, they share storage with the URL and decode the key/value on-demand.
  ///
  public struct Element: CustomStringConvertible {

    @usableFromInline
    internal var source: URLStorage.CodeUnits

    @usableFromInline
    internal var position: Index

    @usableFromInline
    internal let schema: Schema

    @inlinable
    internal init(source: URLStorage.CodeUnits, position: Index, schema: Schema) {
      self.source = source
      self.position = position
      self.schema = schema
    }

    /// The key component, as decoded by the schema.
    ///
    @inlinable
    public var key: String {
      schema.unescapeAsUTF8String(source[position.rangeOfKey])
    }

    /// The value component, as decoded by the schema.
    ///
    @inlinable
    public var value: String {
      schema.unescapeAsUTF8String(source[position.rangeOfValue])
    }

    /// The key component, as written in the URL (without decoding).
    ///
    @inlinable
    public var encodedKey: String {
      String(decoding: source[position.rangeOfKey], as: UTF8.self)
    }

    /// The value component, as written in the URL (without decoding).
    ///
    @inlinable
    public var encodedValue: String {
      String(decoding: source[position.rangeOfValue], as: UTF8.self)
    }

    @inlinable
    public var description: String {
      "(key: \"\(key)\", value: \"\(value)\")"
    }
  }
}


// --------------------------------------------
// MARK: - Writing: By Location.
// --------------------------------------------


extension WebURL.KeyValuePairs {

  @inlinable
  internal mutating func replaceSubrange(
    _ bounds: Range<Index>, withUTF8 newPairs: some Collection<(some Collection<UInt8>, some Collection<UInt8>)>
  ) -> Range<Index> {

    let newBounds = try! storage.replaceKeyValuePairs(
      bounds,
      in: component,
      schema: schema,
      startOfFirstPair: startIndex.keyValuePair.lowerBound,
      with: newPairs
    ).get()

    // TODO: Optimize cache update.
    cache = .calculate(storage: storage, component: component, schema: schema)

    return newBounds
  }

  /// Replaces the key-value pairs at the given locations.
  ///
  /// The number of new pairs does not need to equal the number of pairs being replaced.
  /// Keys and values will automatically be encoded to preserve their content exactly as given.
  ///
  /// The following example demonstrates replacing a range of pairs in the middle of the list.
  ///
  /// ```swift
  /// var url = WebURL("http://example/?q=test&sort=fieldA&sort=fieldB&sort=fieldC&limit=10")!
  ///
  /// // Find consecutive pairs named "sort".
  /// let sortFields = url.queryParams.drop { $0.key != "sort" }.prefix { $0.key == "sort" }
  ///
  /// // Combine their values.
  /// let combinedFields = sortFields.lazy.map { $0.value }.joined(separator: ",")
  ///
  /// // Replace the original pairs with the combined pair.
  /// url.queryParams.replaceSubrange(
  ///   sortFields.startIndex..<sortFields.endIndex,
  ///   with: [("sort", combinedFields)]
  /// )
  /// // ✅ "http://example/?q=test&sort=fieldA%2CfieldB%2CfieldC&limit=10"
  /// //                            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  ///
  /// url.queryParams["sort"]
  /// // ✅ "fieldA,fieldB,fieldC"
  /// ```
  ///
  /// If `bounds` is an empty range, this method inserts the new pairs at `bounds.lowerBound`.
  /// Calling ``insert(contentsOf:at:)`` instead is preferred.
  ///
  /// If `newPairs` is empty, this method removes the pairs in `bounds` without replacement.
  /// Calling ``removeSubrange(_:)`` instead is preferred.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - returns: The locations of the inserted pairs.
  ///            If `newPairs` is empty, the result is an empty range at the new location of `bounds.upperBound`.
  ///
  @inlinable
  @discardableResult
  public mutating func replaceSubrange(
    _ bounds: some RangeExpression<Index>, with newPairs: some Collection<(some StringProtocol, some StringProtocol)>
  ) -> Range<Index> {
    replaceSubrange(bounds.relative(to: self), withUTF8: newPairs.lazy.map { ($0.0.utf8, $0.1.utf8) })
  }

  /// Inserts a collection of key-value pairs at a given location.
  ///
  /// The new pairs are inserted before the pair currently at `location`.
  /// Keys and values will automatically be encoded to preserve their content exactly as given.
  ///
  /// Some services allow multiple pairs with the same key, and the location of those pairs can be significant.
  /// The following example demonstrates inserting a group of pairs, all with the key "sort",
  /// immediately before an existing pair with the same name.
  ///
  /// ```swift
  /// var url = WebURL("http://example/articles?q=test&sort=length&limit=10")!
  ///
  /// // Find the location of the existing 'sort' key.
  /// let sortKey = url.queryParams.firstIndex(where: { $0.key == "sort" }) ?? url.queryParams.endIndex
  ///
  /// // Insert additional 'sort' keys before it.
  /// url.queryParams.insert(
  ///   contentsOf: [("sort", "date"), ("sort", "title")],
  ///   at: sortKey
  /// )
  /// // ✅ "http://example/articles?q=test&sort=date&sort=title&sort=length&limit=10"
  /// //                                    ^^^^^^^^^^^^^^^^^^^^
  ///
  /// url.queryParams.allValues(forKey: "sort")
  /// // ✅ ["date", "title", "length"]
  /// ```
  ///
  /// If `location` is the list's `endIndex`, the new components are appended to the list.
  /// Calling ``append(contentsOf:)-84bng`` instead is preferred.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - returns: The locations of the inserted pairs.
  ///
  @inlinable
  @discardableResult
  public mutating func insert(
    contentsOf newPairs: some Collection<(some StringProtocol, some StringProtocol)>, at location: Index
  ) -> Range<Index> {
    replaceSubrange(Range(uncheckedBounds: (location, location)), with: newPairs)
  }

  /// Removes the key-value pairs at the given locations.
  ///
  /// The following example removes all pairs from a URL's query,
  /// with the exception of the first pair.
  ///
  /// ```
  /// var url = WebURL("http://example/search?q=test&sort=updated&limit=10&page=3")!
  ///
  /// // Find the location of the second pair.
  /// let secondPosition = url.queryParams.index(after: url.queryParams.startIndex)
  ///
  /// // Remove the second pair, and all subsequent pairs.
  /// url.queryParams.removeSubrange(secondPosition...)
  /// // ✅ "http://example/search?q=test"
  /// ```
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - returns: The new location of `bounds.upperBound`.
  ///
  @inlinable
  @discardableResult
  public mutating func removeSubrange(
    _ bounds: some RangeExpression<Index>
  ) -> Index {
    replaceSubrange(
      bounds.relative(to: self),
      withUTF8: EmptyCollection<(EmptyCollection, EmptyCollection)>()
    ).upperBound
  }

  /// Inserts a collection of key-value pairs at the end of this list.
  ///
  /// This function is equivalent to the `+=` operator.
  /// Keys and values will automatically be encoded to preserve their content exactly as given.
  ///
  /// The following example demonstrates building a URL's query by appending collections of key-value pairs.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/convert")!
  ///
  /// url.queryParams += [
  ///  ("amount", "200"),
  ///  ("from",   "USD"),
  ///  ("to",     "EUR"),
  /// ]
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR"
  /// //                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^
  ///
  /// url.queryParams.append(contentsOf: [
  ///  ("lang",   "en"),
  ///  ("client", "app"),
  /// ])
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR&lang=en&client=app"
  /// //                                                            ^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - returns: The locations of the inserted pairs.
  ///
  @inlinable
  @discardableResult
  public mutating func append(
    contentsOf newPairs: some Collection<(some StringProtocol, some StringProtocol)>
  ) -> Range<Index> {

    let inserted = try! storage.replaceKeyValuePairs(
      Range(uncheckedBounds: (endIndex, endIndex)),
      in: component,
      schema: schema,
      startOfFirstPair: startIndex.keyValuePair.lowerBound,
      with: newPairs.lazy.map { ($0.0.utf8, $0.1.utf8) }
    ).get()

    cache.updateAfterAppend(storage: storage, component: component, schema: schema)

    return inserted
  }

  /// Inserts a collection of key-value pairs at the end of this list.
  ///
  /// This operator is equivalent to the ``append(contentsOf:)-84bng`` function.
  ///
  @inlinable
  public static func += (
    lhs: inout WebURL.KeyValuePairs<Schema>,
    rhs: some Collection<(some StringProtocol, some StringProtocol)>
  ) {
    lhs.append(contentsOf: rhs)
  }

  // Append Overload: Tuple labels
  // -----------------------------
  // Unfortunately, `(String, String)` and `(key: String, value: String)` are treated as different types.
  // This can be inconvenient, so we add overloads which include the tuple labels "key" and "value" -
  // but only for `append(contentsOf:)` and the `+=` operator.

  /// Inserts a collection of key-value pairs at the end of this list.
  ///
  /// This function is equivalent to the `+=` operator.
  /// Keys and values will automatically be encoded to preserve their content exactly as given.
  ///
  /// The following example demonstrates building a URL's query by appending collections of key-value pairs.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/convert")!
  ///
  /// url.queryParams += [
  ///  (key: "amount", value: "200"),
  ///  (key: "from",   value: "USD"),
  ///  (key: "to",     value: "EUR"),
  /// ]
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR"
  /// //                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^
  ///
  /// url.queryParams.append(contentsOf: [
  ///  (key: "lang",   value: "en"),
  ///  (key: "client", value: "app"),
  /// ])
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR&lang=en&client=app"
  /// //                                                            ^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - returns: The locations of the inserted pairs.
  ///
  @inlinable
  @discardableResult
  public mutating func append(
    contentsOf newPairs: some Collection<(key: some StringProtocol, value: some StringProtocol)>
  ) -> Range<Index> {

    let inserted = try! storage.replaceKeyValuePairs(
      Range(uncheckedBounds: (endIndex, endIndex)),
      in: component,
      schema: schema,
      startOfFirstPair: startIndex.keyValuePair.lowerBound,
      with: newPairs.lazy.map { ($0.key.utf8, $0.value.utf8) }
    ).get()

    cache.updateAfterAppend(storage: storage, component: component, schema: schema)

    return inserted
  }

  /// Inserts a collection of key-value pairs at the end of this list.
  ///
  /// This operator is equivalent to the ``append(contentsOf:)-9lkdx`` function.
  ///
  @inlinable
  public static func += (
    lhs: inout WebURL.KeyValuePairs<Schema>,
    rhs: some Collection<(key: some StringProtocol, value: some StringProtocol)>
  ) {
    lhs.append(contentsOf: rhs)
  }

  // Append Overload: Dictionary
  // ---------------------------
  // Dictionary is interesting because it is an unordered collection, but users will want to append
  // dictionaries using, say, the `+=` operator, and be displeased when it results in a different order each time.
  // To make the experience less unpleasant, add an overload which sorts the keys.

  /// Inserts the key-value pairs from a `Dictionary` at the end of this list.
  ///
  /// This function is equivalent to the `+=` operator.
  /// Keys and values will automatically be encoded to preserve their content exactly as given.
  ///
  /// The following example demonstrates building a URL's query by appending dictionaries.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/convert")!
  ///
  /// url.queryParams.append += [
  ///  "amount" : "200",
  ///  "from"   : "USD",
  ///  "to"     : "EUR"
  /// ]
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR"
  /// //                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^
  ///
  /// url.queryParams.append(contentsOf: [
  ///  "lang"   : "en",
  ///  "client" : "app"
  /// ])
  /// // ✅ "https://example.com/convert?amount=200&from=USD&to=EUR&client=app&lang=en"
  /// //                                                            ^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// Since a `Dictionary`'s contents are unordered, this method will sort the new pairs
  /// by key before appending, in order to produce a predictable result.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - returns: The locations of the inserted pairs.
  ///
  @inlinable
  @discardableResult
  public mutating func append(contentsOf newPairs: [some StringProtocol: some StringProtocol]) -> Range<Index> {
    append(contentsOf: newPairs.sorted(by: { lhs, rhs in lhs.key < rhs.key }))
  }

  /// Inserts the key-value pairs from a `Dictionary` at the end of this list.
  ///
  /// This operator is equivalent to the ``append(contentsOf:)-5nok5`` function.
  ///
  @inlinable
  public static func += (lhs: inout WebURL.KeyValuePairs<Schema>, rhs: [some StringProtocol: some StringProtocol]) {
    lhs.append(contentsOf: rhs)
  }
}

extension WebURL.KeyValuePairs {

  /// Inserts a key-value pair at the end of this list.
  ///
  /// The key and value will automatically be encoded to preserve their content exactly as given.
  ///
  /// The following example demonstrates adding a single pair to a URL's query.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/articles?q=football")!
  ///
  /// url.queryParams.append(key: "limit", value: "10")
  /// // ✅ "https://example.com/articles?q=football&limit=10"
  /// //                                             ^^^^^^^^
  /// ```
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - returns: The location of the inserted pair.
  ///
  @inlinable
  @discardableResult
  public mutating func append(key: some StringProtocol, value: some StringProtocol) -> Index {

    let inserted = key._withContiguousUTF8 { unsafeKey in
      value._withContiguousUTF8 { unsafeValue in
        try! storage.replaceKeyValuePairs(
          Range(uncheckedBounds: (endIndex, endIndex)),
          in: component,
          schema: schema,
          startOfFirstPair: startIndex.keyValuePair.lowerBound,
          with: CollectionOfOne((unsafeKey.boundsChecked, unsafeValue.boundsChecked))
        ).get()
      }
    }

    cache.updateAfterAppend(storage: storage, component: component, schema: schema)

    return inserted.lowerBound
  }

  /// Inserts a key-value pair at a given location.
  ///
  /// The pair is inserted before the pair currently at `location`.
  /// The key and value will automatically be encoded to preserve their content exactly as given.
  ///
  /// Some services support multiple pairs with the same key, and the order of those pairs can be important.
  /// The following example demonstrates inserting a pair with the key "sort",
  /// immediately before an existing pair with the same name.
  ///
  /// ```swift
  /// var url = WebURL("http://example/students?class=12&sort=name")!
  ///
  /// // Find the location of the existing 'sort' key.
  /// let sortIdx = url.queryParams.firstIndex(where: { $0.key == "sort" }) ?? url.queryParams.endIndex
  ///
  /// // Insert an additional 'sort' key before it.
  /// url.queryParams.insert(key: "sort", value: "age", at: sortIdx)
  /// // ✅ "http://example/students?class=12&sort=age&sort=name"
  /// //                                      ^^^^^^^^
  ///
  /// url.queryParams.allValues(forKey: "sort")
  /// // ✅ ["age", "name"]
  /// ```
  ///
  /// If `location` is the list's `endIndex`, the new component is appended to the list.
  /// Calling ``append(key:value:)`` instead is preferred.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - returns: A `Range` containing a single index.
  ///            The range's `lowerBound` is the location of the inserted pair,
  ///            and its `upperBound` points to the pair previously at `location`.
  ///
  @inlinable
  @discardableResult
  public mutating func insert(
    key: some StringProtocol, value: some StringProtocol, at location: Index
  ) -> Range<Index> {

    let inserted = key._withContiguousUTF8 { unsafeKey in
      value._withContiguousUTF8 { unsafeValue in
        try! storage.replaceKeyValuePairs(
          Range(uncheckedBounds: (location, location)),
          in: component,
          schema: schema,
          startOfFirstPair: startIndex.keyValuePair.lowerBound,
          with: CollectionOfOne((unsafeKey.boundsChecked, unsafeValue.boundsChecked))
        ).get()
      }
    }

    // TODO: Optimize cache update.
    cache = .calculate(storage: storage, component: component, schema: schema)

    return inserted
  }

  /// Removes the key-value pair at a given location.
  ///
  /// The following example demonstrates a simple toggle for faceted search -
  /// when a user deselects brand "B", we identify the specific key-value pair for that brand and remove it.
  /// Other pairs remain intact, even though they share the key "brand".
  ///
  /// ```swift
  /// extension WebURL.KeyValuePairs {
  ///   mutating func toggleFacet(name: String, value: String) {
  ///     if let i = firstIndex(where: { $0.key == name && $0.value == value }) {
  ///       remove(at: i)
  ///     } else {
  ///       append(key: name, value: value)
  ///     }
  ///   }
  /// }
  ///
  /// var url = WebURL("http://example.com/products?brand=A&brand=B")!
  ///
  /// url.queryParams.toggleFacet(name: "brand", value: "C")
  /// // ✅ "http://example.com/products?brand=A&brand=B&brand=C"
  /// //                                                 ^^^^^^^
  ///
  /// url.queryParams.toggleFacet(name: "brand", value: "B")
  /// // ✅ "http://example.com/products?brand=A&brand=C"
  /// //                                       ^^^
  /// ```
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - returns: The new location of the pair which followed the given `location`.
  ///
  @inlinable
  @discardableResult
  public mutating func remove(at location: Index) -> Index {
    removeSubrange(Range(uncheckedBounds: (location, index(after: location))))
  }
}

extension WebURL.KeyValuePairs {

  /// Replaces the 'key' portion of the pair at a given location.
  ///
  /// The new key will automatically be encoded to preserve its content exactly as given.
  ///
  /// The following example finds the first pair with key "flag", and replaces its key with "other\_flag".
  ///
  /// ```swift
  /// var url = WebURL("http://example/?q=test&flag=1&limit=10")!
  ///
  /// if let flagIdx = url.queryParams.firstIndex(where: { $0.key == "flag" }) {
  ///   url.queryParams.replaceKey(at: flagIdx, with: "other_flag")
  /// }
  /// // ✅ "http://example/?q=test&other_flag=1&limit=10"
  /// //                            ^^^^^^^^^^^^
  /// ```
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - returns: The new index for the modified pair.
  ///
  @inlinable
  @discardableResult
  public mutating func replaceKey(at location: Index, with newKey: some StringProtocol) -> Index {

    // If there is no key-value delimiter, and we are setting this pair to the empty key,
    // we will have to insert a key-value delimiter.

    let insertDelimiter = !location.hasKeyValueDelimiter && newKey.isEmpty

    let newKeyLength = newKey._withContiguousUTF8 { unsafeNewKey in
      try! storage.replaceKeyValuePairComponent(
        location.rangeOfKey,
        in: component,
        bounds: cache.componentContents,
        schema: schema,
        insertDelimiter: insertDelimiter,
        newContent: unsafeNewKey.boundsChecked
      ).get()
    }

    let didModifyStartIndex = (location == startIndex)
    let newKeyEnd = location.keyValuePair.lowerBound &+ newKeyLength
    let valueLength = location.rangeOfValue.upperBound &- location.rangeOfValue.lowerBound
    let delimiterLength: URLStorage.SizeType = (location.hasKeyValueDelimiter || insertDelimiter) ? 1 : 0

    let adjustedIndex = Index(
      keyValuePair: location.keyValuePair.lowerBound..<(newKeyEnd &+ delimiterLength &+ valueLength),
      keyValueDelimiter: newKeyEnd
    )

    cache = .withKnownStartIndex(
      startIndex: didModifyStartIndex ? adjustedIndex : startIndex,
      contentStart: cache.componentContents.lowerBound,
      storage: storage,
      component: component
    )

    return adjustedIndex
  }

  /// Replaces the 'value' portion of the pair at a given location.
  ///
  /// The new value will automatically be encoded to preserve its content exactly as given.
  ///
  /// The following example finds the first pair with key "offset", and increments its value.
  ///
  /// ```swift
  /// extension WebURL.KeyValuePairs {
  ///   mutating func incrementOffset(by amount: Int = 10) {
  ///     if let i = firstIndex(where: { $0.key == "offset" }) {
  ///       let newValue = Int(self[i].value).map { $0 + amount } ?? 0
  ///       replaceValue(at: i, with: String(newValue))
  ///     } else {
  ///       append(key: "offset", value: "0")
  ///     }
  ///   }
  /// }
  ///
  /// var url = WebURL("http://example/?q=test&offset=0")!
  ///
  /// url.queryParams.incrementOffset()
  /// // ✅ "http://example/?q=test&offset=10"
  /// //                            ^^^^^^^^^
  ///
  /// url.queryParams.append(key: "limit", value: "20")
  /// // ✅ "http://example/?q=test&offset=10&limit=20"
  /// //                            ^^^^^^^^^
  ///
  /// url.queryParams.incrementOffset(by: 7)
  /// // ✅ "http://example/?q=test&offset=17&limit=20"
  /// //                            ^^^^^^^^^
  ///
  /// url.queryParams.incrementOffset()
  /// // ✅ "http://example/?q=test&offset=27&limit=20"
  /// //                            ^^^^^^^^^
  /// ```
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - returns: The new index for the modified pair.
  ///
  @inlinable
  @discardableResult
  public mutating func replaceValue(at location: Index, with newValue: some StringProtocol) -> Index {

    // If there is no key-value delimiter, and we are inserting a non-empty value,
    // we will have to add a delimiter.

    let insertDelimiter = !location.hasKeyValueDelimiter && !newValue.isEmpty

    let newValueLength = newValue._withContiguousUTF8 { unsafeNewValue in
      try! storage.replaceKeyValuePairComponent(
        location.rangeOfValue,
        in: component,
        bounds: cache.componentContents,
        schema: schema,
        insertDelimiter: insertDelimiter,
        newContent: unsafeNewValue.boundsChecked
      ).get()
    }

    let didModifyStartIndex = (location == startIndex)
    let delimiterLen: URLStorage.SizeType = (location.hasKeyValueDelimiter || insertDelimiter) ? 1 : 0
    let adjustedIndex = Index(
      keyValuePair: location.keyValuePair.lowerBound..<(location.keyValueDelimiter &+ delimiterLen &+ newValueLength),
      keyValueDelimiter: location.keyValueDelimiter
    )

    cache = .withKnownStartIndex(
      startIndex: didModifyStartIndex ? adjustedIndex : startIndex,
      contentStart: cache.componentContents.lowerBound,
      storage: storage,
      component: component
    )

    return adjustedIndex
  }
}

extension WebURL.KeyValuePairs {

  /// Removes all key-value pairs in the given range which match a predicate.
  ///
  /// The following example removes some key-value pairs commonly used to track marketing campaigns.
  ///
  /// ```swift
  /// let trackingKeys: Set<String> = [
  ///   "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", /* ... */
  /// ]
  ///
  /// var url = WebURL("http://example/p?sort=new&utm_source=swift.org&utm_campaign=example&version=2")!
  ///
  /// url.queryParams.removeAll { trackingKeys.contains($0.key) }
  /// // ✅ "http://example/p?sort=new&version=2"
  /// ```
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - parameters:
  ///   - bounds:    The locations of the key-value pairs to be checked.
  ///                Pairs outside of this range will not be passed to `predicate` and will not be removed.
  ///
  ///   - predicate: A closure which decides whether the key-value pair should be removed.
  ///
  @inlinable
  public mutating func removeAll(in bounds: some RangeExpression<Index>, where predicate: (Element) -> Bool) {
    _removeAll(in: bounds.relative(to: self), where: predicate)
  }

  /// Removes all key-value pairs which match a predicate.
  ///
  /// The following example removes some key-value pairs commonly used to track marketing campaigns.
  ///
  /// ```swift
  /// let trackingKeys: Set<String> = [
  ///   "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", /* ... */
  /// ]
  ///
  /// var url = WebURL("http://example/p?sort=new&utm_source=swift.org&utm_campaign=example&version=2")!
  ///
  /// url.queryParams.removeAll { trackingKeys.contains($0.key) }
  /// // ✅ "http://example/p?sort=new&version=2"
  /// ```
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - parameters:
  ///   - predicate: A closure which decides whether the key-value pair should be removed.
  ///
  @inlinable
  public mutating func removeAll(where predicate: (Element) -> Bool) {
    _removeAll(in: Range(uncheckedBounds: (startIndex, endIndex)), where: predicate)
  }

  @inlinable
  internal mutating func _removeAll(in bounds: Range<Index>, where predicate: (Element) -> Bool) {

    let lowerBound =
      (bounds.lowerBound == startIndex) ? cache.componentContents.lowerBound : bounds.lowerBound.keyValuePair.lowerBound
    let upperBound = bounds.upperBound.keyValuePair.lowerBound
    URLStorage.verifyRange(from: lowerBound, to: upperBound, inBounds: cache.componentContents)

    let bounds = (lowerBound..<upperBound).toCodeUnitsIndices()
    guard !bounds.isEmpty else { return }

    var newUpperBound = storage.codeUnits.trimSegments(
      from: bounds.lowerBound,
      to: bounds.upperBound,
      skipInitialSeparator: false,
      separatedBy: schema.isPairDelimiter
    ) { codeUnits, range, _ in

      // Always remove empty key-value pairs.
      guard range.lowerBound < range.upperBound else { return nil }

      let keyValueDelimiter =
        codeUnits.fastFirstIndex(
          from: range.lowerBound, to: range.upperBound, where: schema.isKeyValueDelimiter
        ) ?? range.upperBound

      let index = Index(
        keyValuePair: range.toURLStorageIndices(),
        keyValueDelimiter: URLStorage.SizeType(bitPattern: .init(truncatingIfNeeded: keyValueDelimiter))
      )
      return predicate(Element(source: codeUnits, position: index, schema: schema)) ? nil : range
    }

    assert(newUpperBound <= bounds.upperBound)
    guard newUpperBound < bounds.upperBound else { return }

    if bounds.upperBound == Int(cache.componentContents.upperBound) {
      if newUpperBound == Int(cache.componentContents.lowerBound) {
        // Removing the entire component content. Set to nil rather than empty.
        assert(storage.codeUnits[newUpperBound &- 1] == component.leadingDelimiter.codePoint)
        newUpperBound &-= 1
      } else if schema.isPairDelimiter(storage.codeUnits[newUpperBound &- 1]) {
        // Otherwise (truncating component), trim a trailing pair delimiter.
        newUpperBound &-= 1
      }
    }

    let rangeToRemove = newUpperBound..<bounds.upperBound
    let amountToRemove = URLStorage.SizeType(truncatingBitPatternIfNeeded: rangeToRemove.count)
    storage.codeUnits.removeSubrange(rangeToRemove)

    switch component.value {
    case .query:
      storage.structure.queryLength &-= amountToRemove
      if storage.structure.queryLength <= 1 {
        storage.structure.queryIsKnownFormEncoded = true
      }
    case .fragment:
      storage.structure.fragmentLength &-= amountToRemove
    }

    if bounds.lowerBound == Int(cache.componentContents.lowerBound) {
      // TODO: Optimize cache update.
      cache = .calculate(
        storage: storage,
        component: component,
        schema: schema
      )
    } else {
      cache = .withKnownStartIndex(
        startIndex: startIndex,
        contentStart: cache.componentContents.lowerBound,
        storage: storage,
        component: component
      )
    }
  }
}


// --------------------------------------------
// MARK: - Reading: By Key
// --------------------------------------------


extension WebURL.KeyValuePairs {

  /// The first value associated with a key.
  ///
  /// ```swift
  /// let url = WebURL("http://example.com/?foo=bar&client=mobile&format=json")!
  /// url.queryParams["client"]  // ✅ "mobile"
  /// ```
  ///
  /// In general, `KeyValuePairs` are multi-maps, so multiple pairs may have the same key.
  /// This subscript returns the value component of the first pair to match a key,
  /// but the ``allValues(forKey:)`` function can be used to retrieve the values from all matching pairs.
  ///
  /// When setting a value using this subscript, it finds the first pair which matches the given key,
  /// and replaces its value component with the given value. If there is no existing match,
  /// the key and value are appended to the list. **All other matching pairs are removed.**
  ///
  /// Inserted keys and values will automatically be encoded to preserve their content exactly as given.
  /// Setting a key to `nil` removes all matching pairs.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/?category=shoes&page=4&num=20")!
  ///
  /// url.queryParams["page"] = "5"
  /// // ✅ "http://example.com/?category=shoes&page=5&num=20"
  /// //                                        ^^^^^^
  ///
  /// url.queryParams["sort"] = "price-asc"
  /// // ✅ "http://example.com/?category=shoes&page=5&num=20&sort=price-asc"
  /// //                                                      ^^^^^^^^^^^^^^
  ///
  /// url.queryParams["num"] = nil
  /// // ✅ "http://example.com/?category=shoes&page=5&sort=price-asc"
  /// //                                             ^^^
  /// ```
  ///
  /// Unlike key lookups in a `Dictionary` (which are performed in constant time),
  /// the cost of looking up a value by key scales _linearly_ with the number of pairs in the list.
  /// In order to reduce the number of lookup operations which need to be performed,
  /// this subscript comes with overloads which allow looking up multiple keys in a single pass:
  ///
  /// ```swift
  /// let (category, page, numResults) = url.queryParams["category", "page", "num"]
  /// // ✅ ("shoes", "4", "20")
  /// ```
  ///
  /// > Note:
  /// > Keys are matched using Unicode canonical equivalence, as is standard for Strings in Swift.
  ///
  /// - complexity: O(*n*)
  ///
  /// - parameters:
  ///   - key: The key to search for.
  ///
  @inlinable
  public subscript(
    _ key: some StringProtocol
  ) -> String? {
    get {
      var i = startIndex
      while i < endIndex {
        let pair = self[i]
        if pair.key == key { return pair.value }
        formIndex(after: &i)
      }
      return nil
    }
    set {
      guard let newValue = newValue else { return _remove(key: key) }
      set(key: key, to: newValue)
    }
  }

  /// Returns the first value associated with each of the given keys.
  ///
  /// ```swift
  /// let url = WebURL("http://example.com/?category=shoes&page=4&num=20")!
  ///
  /// let (category, page, numResults) = url.queryParams["category", "page", "num"]
  /// // ✅ ("shoes", "4", "20")
  /// ```
  ///
  /// In general, `KeyValuePairs` are multi-maps, so multiple pairs may have the same key.
  /// This subscript returns the value component of the first pair to match each key,
  /// but the ``allValues(forKey:)`` function can be used to retrieve the values from all matching pairs.
  ///
  /// Unlike key lookups in a `Dictionary` (which are performed in constant time),
  /// the cost of looking up a value by key scales _linearly_ with the number of pairs in the list.
  /// In order to reduce the number of lookup operations which need to be performed,
  /// this subscript looks up multiple keys in a single pass.
  ///
  /// > Note:
  /// > Keys are matched using Unicode canonical equivalence, as is standard for Strings in Swift.
  ///
  /// - complexity: O(*n*)
  ///
  /// - parameters:
  ///   - key: The key to search for.
  ///
  @inlinable
  public subscript(
    _ key0: some StringProtocol, _ key1: some StringProtocol
  ) -> (String?, String?) {

    var result: (Index?, Index?) = (nil, nil)
    var i = startIndex
    while i < endIndex {
      let key = self[i].key
      if result.0 == nil, key == key0 { result.0 = i }
      if result.1 == nil, key == key1 { result.1 = i }

      if result.0 != nil, result.1 != nil { break }
      formIndex(after: &i)
    }
    return (
      result.0.map { self[$0].value },
      result.1.map { self[$0].value }
    )
  }

  /// Returns the values associated with each of the given keys.
  ///
  /// ```swift
  /// let url = WebURL("http://example.com/?category=shoes&page=4&num=20")!
  ///
  /// let (category, page, numResults) = url.queryParams["category", "page", "num"]
  /// // ✅ ("shoes", "4", "20")
  /// ```
  ///
  /// In general, `KeyValuePairs` are multi-maps, so multiple pairs may have the same key.
  /// This subscript returns the value component of the first pair to match each key,
  /// but the ``allValues(forKey:)`` function can be used to retrieve the values from all matching pairs.
  ///
  /// Unlike key lookups in a `Dictionary` (which are performed in constant time),
  /// the cost of looking up a value by key scales _linearly_ with the number of pairs in the list.
  /// In order to reduce the number of lookup operations which need to be performed,
  /// this subscript looks up multiple keys in a single pass.
  ///
  /// > Note:
  /// > Keys are matched using Unicode canonical equivalence, as is standard for Strings in Swift.
  ///
  /// - complexity: O(*n*)
  ///
  /// - parameters:
  ///   - key: The key to search for.
  ///
  @inlinable
  public subscript(
    _ key0: some StringProtocol, _ key1: some StringProtocol, _ key2: some StringProtocol
  ) -> (String?, String?, String?) {

    var result: (Index?, Index?, Index?) = (nil, nil, nil)
    var i = startIndex
    while i < endIndex {
      let key = self[i].key
      if result.0 == nil, key == key0 { result.0 = i }
      if result.1 == nil, key == key1 { result.1 = i }
      if result.2 == nil, key == key2 { result.2 = i }

      if result.0 != nil, result.1 != nil, result.2 != nil { break }
      formIndex(after: &i)
    }
    return (
      result.0.map { self[$0].value },
      result.1.map { self[$0].value },
      result.2.map { self[$0].value }
    )
  }

  /// Returns the values associated with each of the given keys.
  ///
  /// ```swift
  /// let url = WebURL("http://example.com/?category=shoes&page=4&num=20")!
  ///
  /// let (category, page, numResults) = url.queryParams["category", "page", "num"]
  /// // ✅ ("shoes", "4", "20")
  /// ```
  ///
  /// In general, `KeyValuePairs` are multi-maps, so multiple pairs may have the same key.
  /// This subscript returns the value component of the first pair to match each key,
  /// but the ``allValues(forKey:)`` function can be used to retrieve the values from all matching pairs.
  ///
  /// Unlike key lookups in a `Dictionary` (which are performed in constant time),
  /// the cost of looking up a value by key scales _linearly_ with the number of pairs in the list.
  /// In order to reduce the number of lookup operations which need to be performed,
  /// this subscript looks up multiple keys in a single pass.
  ///
  /// > Note:
  /// > Keys are matched using Unicode canonical equivalence, as is standard for Strings in Swift.
  ///
  /// - complexity: O(*n*)
  ///
  /// - parameters:
  ///   - key: The key to search for.
  ///
  @inlinable
  public subscript(
    _ key0: some StringProtocol, _ key1: some StringProtocol, _ key2: some StringProtocol, _ key3: some StringProtocol
  ) -> (String?, String?, String?, String?) {

    var result: (Index?, Index?, Index?, Index?) = (nil, nil, nil, nil)
    var i = startIndex
    while i < endIndex {
      let key = self[i].key
      if result.0 == nil, key == key0 { result.0 = i }
      if result.1 == nil, key == key1 { result.1 = i }
      if result.2 == nil, key == key2 { result.2 = i }
      if result.3 == nil, key == key3 { result.3 = i }

      if result.0 != nil, result.1 != nil, result.2 != nil, result.3 != nil { break }
      formIndex(after: &i)
    }
    return (
      result.0.map { self[$0].value },
      result.1.map { self[$0].value },
      result.2.map { self[$0].value },
      result.3.map { self[$0].value }
    )
  }
}

extension WebURL.KeyValuePairs {

  /// Returns all values associated with the given key.
  ///
  /// The returned values have the same order as they do in the key-value string.
  ///
  /// ```swift
  /// let url = WebURL("http://example.com/articles?sort=date&sort=length")!
  ///
  /// url.queryParams.allValues(forKey: "sort")
  /// // ✅ ["date", "length"]
  /// ```
  ///
  /// > Note:
  /// > Keys are matched using Unicode canonical equivalence, as is standard for Strings in Swift.
  ///
  /// - parameters:
  ///   - key: The key to search for.
  ///
  @inlinable
  public func allValues(forKey key: some StringProtocol) -> [String] {
    compactMap { $0.key == key ? $0.value : nil }
  }
}


// --------------------------------------------
// MARK: - Writing: By Key.
// --------------------------------------------


extension WebURL.KeyValuePairs {

  /// Associates a value with a given key.
  ///
  /// This function finds the first pair which matches the given key,
  /// and replaces its value component with the given value. If there is no existing match,
  /// the key and value are appended to the list. **All other matching pairs are removed.**
  ///
  /// Inserted keys and values will automatically be encoded to preserve their content exactly as given.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/shop?category=shoes&page=1&num=20")!
  /// //                                                        ^^^^^^
  ///
  /// url.queryParams.set(key: "page", to: "3")
  /// // ✅ "https://example.com/shop?category=shoes&page=3&num=20"
  /// //                                             ^^^^^^
  ///
  /// url.queryParams["page"] = "14"
  /// // ✅ "https://example.com/shop?category=shoes&page=14&num=20"
  /// //                                             ^^^^^^^
  ///
  /// url.queryParams["sort"] = "price-asc"
  /// // ✅ "https://example.com/shop?category=shoes&page=14&num=20&sort=price-asc"
  /// //                                                            ^^^^^^^^^^^^^^
  /// ```
  ///
  /// > Note:
  /// > Keys are matched using Unicode canonical equivalence, as is standard for Strings in Swift.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - parameters:
  ///   - key:      The key to search for.
  ///   - newValue: The value to associate with `key`.
  ///
  /// - returns: The index of the modified or inserted pair.
  ///
  @inlinable
  @discardableResult
  public mutating func set(key: some StringProtocol, to newValue: some StringProtocol) -> Index {

    guard var firstMatch = fastFirstIndex(where: { $0.key == key }) else {
      return append(key: key, value: newValue)
    }
    firstMatch = replaceValue(at: firstMatch, with: newValue)

    if let secondMatch = fastFirstIndex(from: index(after: firstMatch), to: endIndex, where: { $0.key == key }) {
      removeAll(in: Range(uncheckedBounds: (secondMatch, endIndex)), where: { $0.key == key })
    }
    return firstMatch
  }

  @inlinable
  internal mutating func _remove(key: some StringProtocol) {

    guard var firstMatch = fastFirstIndex(where: { $0.key == key }) else { return }
    firstMatch = remove(at: firstMatch)

    if let secondMatch = fastFirstIndex(from: firstMatch, to: endIndex, where: { $0.key == key }) {
      removeAll(in: Range(uncheckedBounds: (secondMatch, endIndex)), where: { $0.key == key })
    }
  }
}


// --------------------------------------------
// MARK: - URLStorage + KeyValuePairs
// --------------------------------------------


@usableFromInline
internal enum KeyValuePairsSetterError: Error, CustomStringConvertible {
  case exceedsMaximumSize

  @usableFromInline
  internal var description: String {
    switch self {
    case .exceedsMaximumSize:
      return #"""
        The operation would exceed the maximum supported size of a URL string (\#(URLStorage.SizeType.self).max).
        """#
    }
  }
}

/// A `PercentEncodeSet` for escaping a subcomponent (key or value) of a key-value pair.
///
/// The escaped contents are valid for writing directly to the URL component `component`,
/// without additional escaping.
///
@usableFromInline
internal struct KeyValuePairComponentEncodeSet<Schema>: PercentEncodeSet where Schema: KeyValueStringSchema {

  @usableFromInline
  internal var schema: Schema

  @usableFromInline
  internal var component: KeyValuePairsSupportedComponent

  @inlinable
  public init(schema: Schema, component: KeyValuePairsSupportedComponent) {
    self.schema = schema
    self.component = component
  }

  @inlinable
  internal func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {

    // Non-ASCII must always be escaped.
    guard let ascii = ASCII(codePoint) else {
      return true
    }

    // The percent sign must always be escaped. It is reserved for percent-encoding.
    if ascii == .percentSign {
      return true
    }

    // We choose to always escape the plus sign. It can be ambiguous.
    if ascii == .plus {
      return true
    }

    // Characters which the schema reserves as delimiters must be escaped.
    if schema.isPairDelimiter(ascii.codePoint) || schema.isKeyValueDelimiter(ascii.codePoint) {
      return true
    }

    // The schema can opt to substitute spaces rather than percent-encoding them.
    if ascii == .space {
      return !schema.encodeSpaceAsPlus
    }

    // The schema can opt in to additional escaping.
    if schema.shouldPercentEncode(ascii: ascii.codePoint) {
      return true
    }

    // Finally, escape anything else required by the URL component.
    switch component.value {
    case .query:
      return URLEncodeSet.SpecialQuery().shouldPercentEncode(ascii: ascii.codePoint)
    case .fragment:
      return URLEncodeSet.Fragment().shouldPercentEncode(ascii: ascii.codePoint)
    }
  }

  @usableFromInline
  internal struct Substitutions: SubstitutionMap {

    @usableFromInline
    internal var schema: Schema

    @inlinable
    internal init(schema: Schema) {
      self.schema = schema
    }

    @inlinable
    internal func substitute(ascii codePoint: UInt8) -> UInt8? {
      if schema.encodeSpaceAsPlus, codePoint == ASCII.space.codePoint {
        return ASCII.plus.codePoint
      }
      return nil
    }

    @inlinable
    internal func unsubstitute(ascii codePoint: UInt8) -> UInt8? {
      // See: `KeyValueStringSchema.unescapeAsUTF8String`
      fatalError("This encode set is not used for unescaping")
    }
  }

  @inlinable
  internal var substitutions: Substitutions {
    Substitutions(schema: schema)
  }
}

extension KeyValueStringSchema {

  @inlinable @inline(__always)
  internal func escape<Source>(
    _ source: Source, for component: KeyValuePairsSupportedComponent
  ) -> LazilyPercentEncoded<Source, KeyValuePairComponentEncodeSet<Self>> {
    source.lazy.percentEncoded(using: KeyValuePairComponentEncodeSet(schema: self, component: component))
  }

  /// Returns this schema's preferred delimiters.
  ///
  /// This function checks that the preferred delimiters are valid and may be written unescaped
  /// in the given URL component. If the delimiters are not valid, a runtime error is triggered.
  ///
  @inlinable
  internal func verifyDelimitersDoNotNeedEscaping(
    in component: KeyValuePairsSupportedComponent
  ) -> (keyValue: UInt8, pair: UInt8) {

    let (keyValueDelimiter, pairDelimiter) = (preferredKeyValueDelimiter, preferredPairDelimiter)

    // The delimiter:
    //
    // - Must be an ASCII code-point,
    // - Must not be the percent sign (`%`), plus sign (`+`), space, or a hex digit, and
    // - Must not require escaping in the URL component(s) used with this schema.

    guard
      ASCII(keyValueDelimiter)?.isHexDigit == false,
      keyValueDelimiter != ASCII.percentSign.codePoint,
      keyValueDelimiter != ASCII.plus.codePoint
    else {
      return (.max, 0)
    }
    guard
      ASCII(pairDelimiter)?.isHexDigit == false,
      pairDelimiter != ASCII.percentSign.codePoint,
      pairDelimiter != ASCII.plus.codePoint
    else {
      return (0, .max)
    }

    switch component.value {
    case .query:
      let encodeSet = URLEncodeSet.SpecialQuery()
      guard !encodeSet.shouldPercentEncode(ascii: keyValueDelimiter) else {
        return (.max, 0)
      }
      guard !encodeSet.shouldPercentEncode(ascii: pairDelimiter) else {
        return (0, .max)
      }
    case .fragment:
      let encodeSet = URLEncodeSet.Fragment()
      guard !encodeSet.shouldPercentEncode(ascii: keyValueDelimiter) else {
        return (.max, 0)
      }
      guard !encodeSet.shouldPercentEncode(ascii: pairDelimiter) else {
        return (0, .max)
      }
    }

    return (keyValueDelimiter, pairDelimiter)
  }

  @inlinable
  internal func isPairBoundary(_ first: UInt8, _ second: UInt8) -> Bool {
    isPairDelimiter(first) && !isPairDelimiter(second)
  }
}

extension KeyValuePairsSupportedComponent {

  @inlinable
  internal var urlComponent: WebURL.Component {
    switch value {
    case .query: return .query
    case .fragment: return .fragment
    }
  }

  @inlinable
  internal var leadingDelimiter: ASCII {
    switch value {
    case .query:
      return .questionMark
    case .fragment:
      return .numberSign
    }
  }
}

@inlinable
internal func _trapOnInvalidDelimiters(
  _ delimiters: (keyValue: UInt8, pair: UInt8)
) -> (keyValue: UInt8, pair: UInt8) {
  precondition(
    delimiters.keyValue != .max && delimiters.pair != .max,
    "Schema has invalid delimiters"
  )
  return delimiters
}

extension URLStorage {

  /// Replaces the given range of key-value pairs with a new collection of key-value pairs.
  /// Inserted content will be escaped as required by both the schema and URL component.
  ///
  /// - parameters:
  ///   - oldPairs:         The range of key-value pairs to replace.
  ///   - component:        The URL component containing `oldPairs`.
  ///   - schema:           The ``KeyValueStringSchema`` specifying the format of the key-value string.
  ///   - startOfFirstPair: The location of the first code-unit of the first non-empty key in `component`.
  ///                       In other words, `startIndex.keyValuePair.lowerBound`.
  ///   - newPairs:         The pairs to insert in the space that `oldPairs` currently occupies.
  ///
  /// - returns: The locations of the inserted pairs.
  ///            If the pairs in `oldPairs` are removed without replacement,
  ///            this function returns an empty range at the new location of `oldPairs.upperBound`.
  ///
  @inlinable
  internal mutating func replaceKeyValuePairs<Schema>(
    _ oldPairs: Range<WebURL.KeyValuePairs<Schema>.Index>,
    in component: KeyValuePairsSupportedComponent,
    schema: Schema,
    startOfFirstPair: URLStorage.SizeType,
    with newPairs: some Collection<(some Collection<UInt8>, some Collection<UInt8>)>
  ) -> Result<Range<WebURL.KeyValuePairs<Schema>.Index>, KeyValuePairsSetterError> {

    let componentAndDelimiter = structure.rangeForReplacingCodeUnits(of: component.urlComponent)
    let componentContent = componentAndDelimiter.dropFirst()

    let rangeToReplace: Range<URLStorage.SizeType>
    do {
      // Replacements from startIndex snap to the start of the URL component.
      // This ensures any content preceding the first non-empty pair also gets replaced.
      let lowerBound =
        (oldPairs.lowerBound.keyValuePair.lowerBound == startOfFirstPair)
        ? componentContent.lowerBound
        : oldPairs.lowerBound.keyValuePair.lowerBound
      let upperBound = oldPairs.upperBound.keyValuePair.lowerBound
      URLStorage.verifyRange(from: lowerBound, to: upperBound, inBounds: componentContent)
      // TODO: Validate age. The URL must not have been mutated after the indexes were created.

      rangeToReplace = lowerBound..<upperBound
    }

    guard !newPairs.isEmpty else {
      let bytesRemoved = _replaceKeyValuePairs_withEmptyCollection(
        rangeToReplace,
        in: component,
        bounds: componentAndDelimiter,
        isPairBoundary: { schema.isPairBoundary($0, $1) }
      )
      let newUpper = oldPairs.upperBound.rebased(newStartOfKey: rangeToReplace.upperBound &- bytesRemoved)
      return .success(newUpper..<newUpper)
    }

    let (keyValueDelimiter, pairDelimiter) = _trapOnInvalidDelimiters(
      schema.verifyDelimitersDoNotNeedEscaping(in: component)
    )

    // Measure the replacement string.

    let bytesToReplace = rangeToReplace.upperBound - rangeToReplace.lowerBound

    let (expectedLength, encodeKeys, encodeVals) = newPairs.reduce(into: (0 as UInt, false, false)) { stats, kvp in
      let (keyLength, encodeKey) = schema.escape(kvp.0, for: component).unsafeEncodedLength
      let (valLength, encodeVal) = schema.escape(kvp.1, for: component).unsafeEncodedLength
      stats.0 &+= keyLength &+ valLength &+ 2  // 1 pair delimiter byte + 1 key-value delimiter byte
      stats.1 = stats.1 || encodeKey
      stats.2 = stats.2 || encodeVal
    }

    guard var bytesToWrite = URLStorage.SizeType(exactly: expectedLength) else {
      return .failure(.exceedsMaximumSize)
    }
    bytesToWrite -= 1

    // Consider how to integrate the start of the replacement string.

    var leadingDelimiter = UInt8?.none
    if componentAndDelimiter.isEmpty {

      // - The URL component is currently nil.
      //   Write the component's leading delimiter (e.g. "?" for query) before the key-value string.
      assert(rangeToReplace == componentAndDelimiter)
      leadingDelimiter = component.leadingDelimiter.codePoint
      bytesToWrite &+= 1

    } else if rangeToReplace.lowerBound == componentContent.upperBound {

      // - Appending to a non-nil component.
      //   Write a delimiter after existing pairs, unless they already end with a trailing delimiter.
      assert(rangeToReplace.upperBound == componentContent.upperBound)
      if !componentContent.isEmpty, !schema.isPairDelimiter(codeUnits[componentContent.upperBound &- 1]) {
        leadingDelimiter = pairDelimiter
        bytesToWrite &+= 1
      }

    } else if rangeToReplace.lowerBound != componentContent.lowerBound {

      // - Inserting in the middle of a non-nil, non-empty component.
      //   Index is expected to be aligned to a pair boundary.
      // TODO: Lower to an assertion once we validate Index age.
      precondition(
        schema.isPairBoundary(codeUnits[rangeToReplace.lowerBound &- 1], codeUnits[rangeToReplace.lowerBound]),
        "Invalid index or schema - lowerBound is not aligned to the start of a key-value pair"
      )
    }

    // Consider how to integrate the end of the replacement string.

    if rangeToReplace.upperBound != componentContent.upperBound {

      // - There is content after the replacement string.
      //   Insert a delimiter after the inserted pairs.
      //   Will automatically be filled with a pair delimiter.
      bytesToWrite &+= 1

      // TODO: Lower to an assertion once we validate Index age.
      precondition(
        rangeToReplace.upperBound == componentContent.lowerBound
          || schema.isPairBoundary(codeUnits[rangeToReplace.upperBound &- 1], codeUnits[rangeToReplace.upperBound]),
        "Invalid index or schema - upperBound is not aligned to the start of a key-value pair"
      )
    }

    // Calculate the new structure.

    var newStructure = structure

    switch component.value {
    case .query:
      guard let newLength = newStructure.queryLength.subtracting(bytesToReplace, adding: bytesToWrite) else {
        return .failure(.exceedsMaximumSize)
      }
      newStructure.queryLength = newLength

    case .fragment:
      guard let newLength = newStructure.fragmentLength.subtracting(bytesToReplace, adding: bytesToWrite) else {
        return .failure(.exceedsMaximumSize)
      }
      newStructure.fragmentLength = newLength
    }

    // Replace the code-units.

    var firstKeyLength = -1
    var firstValLength = -1

    let result = replaceSubrange(
      rangeToReplace,
      withUninitializedSpace: bytesToWrite,
      newStructure: newStructure
    ) { buffer in

      let baseAddress = buffer.baseAddress!
      var buffer = buffer

      if let leading = leadingDelimiter {
        precondition(!buffer.isEmpty)
        buffer[0] = leading
        buffer = UnsafeMutableBufferPointer(
          start: buffer.baseAddress! + 1,
          count: buffer.count &- 1
        )
      }

      for (key, value) in newPairs {

        let keyLength =
          encodeKeys
          ? buffer.fastInitialize(from: schema.escape(key, for: component))
          : buffer.fastInitialize(from: key)
        buffer = UnsafeMutableBufferPointer(
          start: buffer.baseAddress! + keyLength,
          count: buffer.count &- keyLength
        )
        if firstKeyLength < 0 {
          firstKeyLength = keyLength
        }

        precondition(!buffer.isEmpty)
        buffer[0] = keyValueDelimiter
        buffer = UnsafeMutableBufferPointer(
          start: buffer.baseAddress! + 1,
          count: buffer.count &- 1
        )

        let valLength =
          encodeVals
          ? buffer.fastInitialize(from: schema.escape(value, for: component))
          : buffer.fastInitialize(from: value)
        buffer = UnsafeMutableBufferPointer(
          start: buffer.baseAddress! + valLength,
          count: buffer.count &- valLength
        )
        if firstValLength < 0 {
          firstValLength = valLength
        }

        if !buffer.isEmpty {
          buffer[0] = pairDelimiter
          buffer = UnsafeMutableBufferPointer(
            start: buffer.baseAddress! + 1,
            count: buffer.count &- 1
          )
        }
      }

      return baseAddress.distance(to: buffer.baseAddress!)
    }

    switch result {
    case .success:
      assert(firstKeyLength >= 0 && firstValLength >= 0)
      let newLowerPairStart = rangeToReplace.lowerBound &+ (leadingDelimiter != nil ? 1 : 0)
      let newLowerKeyLength = SizeType(firstKeyLength)
      let newLowerEndOfPair = newLowerPairStart &+ newLowerKeyLength &+ 1 &+ SizeType(firstValLength)
      let newLower = WebURL.KeyValuePairs<Schema>.Index(
        keyValuePair: Range(uncheckedBounds: (newLowerPairStart, newLowerEndOfPair)),
        keyValueDelimiter: newLowerPairStart &+ newLowerKeyLength
      )
      let newUpper = oldPairs.upperBound.rebased(newStartOfKey: rangeToReplace.lowerBound + bytesToWrite)
      return .success(newLower..<newUpper)

    case .failure(let error):
      assert(error == .exceedsMaximumSize)
      return .failure(.exceedsMaximumSize)
    }
  }

  /// Replaces the given range of code-units with an empty collection of key-value pairs.
  ///
  /// > Important:
  /// > This function should only be called by `replaceKeyValuePairs`.
  ///
  @usableFromInline
  internal mutating func _replaceKeyValuePairs_withEmptyCollection(
    _ rangeToReplace: Range<URLStorage.SizeType>,
    in component: KeyValuePairsSupportedComponent,
    bounds componentAndDelimiter: Range<URLStorage.SizeType>,
    isPairBoundary: (UInt8, UInt8) -> Bool
  ) -> URLStorage.SizeType {

    guard !componentAndDelimiter.isEmpty else {
      assert(rangeToReplace == componentAndDelimiter)
      return 0
    }

    var rangeToReplace = rangeToReplace
    let componentContent = componentAndDelimiter.dropFirst()

    if rangeToReplace.upperBound == componentContent.upperBound {

      if rangeToReplace.lowerBound == componentContent.lowerBound {

        // Removing entire component, so also remove its leading delimiter.
        assert(rangeToReplace.lowerBound - 1 == componentAndDelimiter.lowerBound)
        rangeToReplace = componentAndDelimiter

      } else if rangeToReplace.lowerBound != componentContent.upperBound {

        // Removing some (not all) pairs from the end of the component.
        // Widen the bounds so we don't leave a trailing delimiter behind.

        // TODO: Lower to an assertion once we validate Index age.
        precondition(
          isPairBoundary(codeUnits[rangeToReplace.lowerBound &- 1], codeUnits[rangeToReplace.lowerBound]),
          "Invalid index or schema - lowerBound is not aligned to the start of a key-value pair"
        )
        rangeToReplace = (rangeToReplace.lowerBound &- 1)..<rangeToReplace.upperBound
      }

    } else {

      // Removing some (not all) pairs at the start/middle.
      // Check that we are cleaning up our trailing delimiter.
      // TODO: Lower to an assertion once we validate Index age.
      precondition(
        rangeToReplace.upperBound == componentContent.lowerBound
          || isPairBoundary(codeUnits[rangeToReplace.upperBound &- 1], codeUnits[rangeToReplace.upperBound]),
        "Invalid index or schema - upperBound is not aligned to the start of a key-value pair"
      )
    }

    // Calculate the new structure and remove the code-units.

    let bytesToReplace = rangeToReplace.upperBound - rangeToReplace.lowerBound

    guard bytesToReplace > 0 else {
      return 0
    }

    var newStructure = structure

    switch component.value {
    case .query:
      newStructure.queryLength &-= bytesToReplace
      assert(newStructure.queryLength != 1, "Component should never be left non-nil but empty")
      if newStructure.queryLength <= 1 {
        assert(rangeToReplace == componentAndDelimiter)
        newStructure.queryIsKnownFormEncoded = true
      }

    case .fragment:
      newStructure.fragmentLength &-= bytesToReplace
      assert(newStructure.fragmentLength != 1, "Component should never be left non-nil but empty")
    }

    removeSubrange(rangeToReplace, newStructure: newStructure)

    return bytesToReplace
  }
}

extension URLStorage {

  /// Replaces a key or value within a key-value pair.
  ///
  /// - parameters:
  ///   - oldContent:      The range of code-units to replace. Must not include any key-value or pair delimiters.
  ///   - component:       The URL component containing `oldContent`.
  ///   - bounds:          The bounds of `component`.
  ///   - schema:          The ``KeyValueStringSchema`` specifying the format of the key-value string.
  ///   - insertDelimiter: Whether a key-value delimiter should be inserted before the new contents.
  ///   - newContent:      The bytes of the new key or value.
  ///
  /// - returns: The length of `newContent`, as it was written to the URL (including percent-encoding).
  ///            Note that in order to calculate an adjusted `KeyValuePairs.Index`,
  ///            you will also need to consider whether a delimiter was inserted.
  ///
  @inlinable
  internal mutating func replaceKeyValuePairComponent(
    _ oldContent: Range<URLStorage.SizeType>,
    in component: KeyValuePairsSupportedComponent,
    bounds componentContent: Range<URLStorage.SizeType>,
    schema: some KeyValueStringSchema,
    insertDelimiter: Bool,
    newContent: some Collection<UInt8>
  ) -> Result<URLStorage.SizeType, KeyValuePairsSetterError> {

    // Diagnose invalid indexes.
    // - They must point to a range within this URL component.
    // - TODO: Validate age. The URL must not have been mutated after the indexes were created.

    URLStorage.verifyRange(oldContent, inBounds: componentContent)

    // Calculate the new structure.

    let bytesToReplace = oldContent.upperBound - oldContent.lowerBound
    let newContentInfo = schema.escape(newContent, for: component).unsafeEncodedLength

    guard let bytesToWrite = URLStorage.SizeType(exactly: newContentInfo.count + (insertDelimiter ? 1 : 0)) else {
      return .failure(.exceedsMaximumSize)
    }

    var newStructure = structure

    switch component.value {
    case .query:
      guard let newLength = newStructure.queryLength.subtracting(bytesToReplace, adding: bytesToWrite) else {
        return .failure(.exceedsMaximumSize)
      }
      assert(newLength > 0, "replaceKeyValuePairComponent should never set the URL component to nil")
      newStructure.queryLength = newLength

    case .fragment:
      guard let newLength = newStructure.fragmentLength.subtracting(bytesToReplace, adding: bytesToWrite) else {
        return .failure(.exceedsMaximumSize)
      }
      assert(newLength > 0, "replaceKeyValuePairComponent should never set the URL component to nil")
      newStructure.fragmentLength = newLength
    }

    // Replace the code-units.

    let result = replaceSubrange(
      oldContent,
      withUninitializedSpace: bytesToWrite,
      newStructure: newStructure
    ) { buffer in

      let baseAddress = buffer.baseAddress!
      var buffer = buffer

      if insertDelimiter {
        precondition(!buffer.isEmpty)
        buffer[0] = _trapOnInvalidDelimiters(schema.verifyDelimitersDoNotNeedEscaping(in: component)).keyValue
        buffer = UnsafeMutableBufferPointer(
          start: buffer.baseAddress! + 1,
          count: buffer.count &- 1
        )
      }

      let bytesWritten =
        newContentInfo.needsEncoding
        ? buffer.fastInitialize(from: schema.escape(newContent, for: component))
        : buffer.fastInitialize(from: newContent)
      buffer = UnsafeMutableBufferPointer(
        start: buffer.baseAddress! + bytesWritten,
        count: buffer.count &- bytesWritten
      )

      return baseAddress.distance(to: buffer.baseAddress!)
    }

    switch result {
    case .success:
      return .success(bytesToWrite &- (insertDelimiter ? 1 : 0))

    case .failure(let error):
      assert(error == .exceedsMaximumSize)
      return .failure(.exceedsMaximumSize)
    }
  }
}
