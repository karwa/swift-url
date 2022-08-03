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

import IDNA

extension WebURL {

  /// A domain is a non-empty ASCII string which identifies a realm within a network.
  ///
  /// A domain consists of one of more _labels_, delimited by periods.
  /// An example of a domain is `"www.example.com"`, which consists of the labels `["www", "example", "com"]`.
  ///
  /// Each label is a subordinate namespace (a _subdomain_) in the label which follows it -
  /// so `"news.example.com"` and `"weather.example.com"` are siblings, and are both subdomains of `"example.com"`.
  /// This syntax is used by the **Domain Name System (DNS)** for organizing internet hostnames.
  ///
  /// Internationalized Domain Names (IDNs) encode Unicode labels in an ASCII format.
  /// Such labels can be recognized by the `"xn--"` prefix. An example of an IDN is `"api.xn--igbi0gl.com"`,
  /// which is the encoded version of the Arabic domain `"api.أهلا.com"`.
  ///
  /// The `WebURL.Domain` type represents domains allowed by URLs. The way in which they are resolved to
  /// a network address is not specified, but is not limited to DNS. System resolvers may consult
  /// a variety of sources - including DNS, the system's `hosts` file, mDNS ("Bonjour"), NetBIOS, LLMNR, etc.
  /// Domains in URLs are normalized to lowercase, and do not enforce any restrictions on label or domain length.
  /// They do **not** support encoding arbitrary bytes, although they [allow][url-domaincp] most non-control
  /// ASCII characters that are not otherwise used as URL delimiters. IDNs are validated, and must decode
  /// to an allowed Unicode domain.
  ///
  /// ```swift
  /// WebURL.Domain("example.com")  // ✅ "example.com"
  /// WebURL.Domain("EXAMPLE.com")  // ✅ "example.com"
  /// WebURL.Domain("localhost")    // ✅ "localhost"
  ///
  /// WebURL.Domain("api.أهلا.com")  // ✅ "api.xn--igbi0gl.com"
  /// WebURL.Domain("xn--caf-dma")  // ✅ "xn--caf-dma" ("café")
  ///
  /// WebURL.Domain("in valid")     // ✅ nil (spaces are not allowed)
  /// WebURL.Domain("xn--cafe-yvc") // ✅ nil (invalid IDN)
  /// WebURL.Domain("192.168.0.1")  // ✅ nil (not a domain)
  /// WebURL.Domain("[::1]")        // ✅ nil (not a domain)
  /// ```
  ///
  /// > Note:
  /// > Developers are encouraged to parse hostnames using the ``WebURL/WebURL/Host-swift.enum`` API.
  /// > It returns a `Domain` value if the hostname is a domain, but it also supports other kinds of hosts as well.
  ///
  /// [url-domaincp]: https://url.spec.whatwg.org/#forbidden-domain-code-point
  ///
  /// ## Topics
  ///
  /// ### Parsing a Domain
  ///
  /// - ``WebURL/WebURL/Domain/init(_:)``
  /// - ``WebURL/WebURL/Domain/init(utf8:)``
  ///
  /// ### Properties
  ///
  /// - ``WebURL/WebURL/Domain/serialized``
  /// - ``WebURL/WebURL/Domain/isIDN``
  ///
  /// ### Rendering a Domain
  ///
  /// - ``WebURL/WebURL/Domain/render(_:)-lssu``
  /// - ``WebURL/WebURL/Domain/Renderer``
  /// - ``WebURL/DomainRenderer/uncheckedUnicodeString``
  ///
  public struct Domain {

    @usableFromInline
    internal var _serialization: String

    @usableFromInline
    internal var _hasPunycodeLabels: Bool

    @inlinable
    internal init(serialization: String, hasPunycodeLabels: Bool) {
      self._serialization = serialization
      self._hasPunycodeLabels = hasPunycodeLabels
    }
  }
}


// --------------------------------------------
// MARK: - Standard protocols
// --------------------------------------------


extension WebURL.Domain: Equatable, Hashable, LosslessStringConvertible {

  @inlinable
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.serialized == rhs.serialized
  }

  @inlinable
  public func hash(into hasher: inout Hasher) {
    hasher.combine(serialized)
  }

  @inlinable
  public var description: String {
    serialized
  }
}

extension WebURL.Domain: Codable {

  @inlinable
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(serialized)
  }

  @inlinable
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    guard let parsedValue = WebURL.Domain(string) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Domain")
    }
    self = parsedValue
  }
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension WebURL.Domain: Sendable {}
#endif


// --------------------------------------------
// MARK: - Parsing
// --------------------------------------------


extension WebURL.Domain {

  /// Parses a domain from a String.
  ///
  /// This initializer invokes the general ``WebURL/WebURL/Host-swift.enum`` parser in the context of an HTTP URL,
  /// and succeeds only if the parser considers the string to represent an allowed domain.
  ///
  /// ```swift
  /// WebURL.Domain("example.com")  // ✅ "example.com"
  /// WebURL.Domain("EXAMPLE.com")  // ✅ "example.com"
  /// WebURL.Domain("localhost")    // ✅ "localhost"
  ///
  /// WebURL.Domain("api.أهلا.com")  // ✅ "api.xn--igbi0gl.com"
  /// WebURL.Domain("xn--caf-dma")  // ✅ "xn--caf-dma" ("café")
  ///
  /// WebURL.Domain("in valid")     // ✅ nil (spaces are not allowed)
  /// WebURL.Domain("xn--cafe-yvc") // ✅ nil (invalid IDN)
  /// WebURL.Domain("192.168.0.1")  // ✅ nil (not a domain)
  /// WebURL.Domain("[::1]")        // ✅ nil (not a domain)
  /// ```
  ///
  /// This API is a useful shorthand when parsing hostnames which **must** be a domain, and no other kind of host.
  /// For parsing general hostname strings, developers are encouraged to invoke the full URL host parser via
  /// ``WebURL/WebURL/Host-swift.enum/init(_:scheme:)`` instead. It returns a `Domain` value
  /// if the hostname is a domain, but it also supports other kinds of hosts as well.
  ///
  /// - parameters:
  ///   - string: The string to parse.
  ///
  @inlinable
  public init?<StringType>(_ string: StringType) where StringType: StringProtocol {
    guard let value = string._withContiguousUTF8({ WebURL.Domain(utf8: $0) }) else {
      return nil
    }
    self = value
  }

  /// Parses a domain from a collection of UTF-8 code-units.
  ///
  /// This initializer constructs a `Domain` from raw UTF-8 bytes rather than requiring
  /// they be stored as a `String`. It uses precisely the same parsing algorithm as ``init(_:)``.
  ///
  /// The following example demonstrates loading a file as a Foundation `Data` object, and parsing each line
  /// as a domain directly from the binary text. Doing this saves allocating a String and UTF-8 validation.
  /// Domains containing non-ASCII bytes are subject to IDNA compatibility processing, which also
  /// ensures that the contents are valid UTF-8.
  ///
  /// ```swift
  /// let fileContents: Data = getFileContents()
  ///
  /// for lineBytes = fileContents.lazy.split(0x0A /* ASCII line feed */) {
  ///   // ℹ️ Initialize from binary text.
  ///   let domain = WebURL.Domain(utf8: lineBytes)
  ///   ...
  /// }
  /// ```
  ///
  /// This API is a useful shorthand when parsing hostnames which **must** be a domain, and no other kind of host.
  /// For parsing general hostname strings, developers are encouraged to invoke the full URL host parser via
  /// ``WebURL/WebURL/Host-swift.enum/init(utf8:scheme:)`` instead. It returns a `Domain` value
  /// if the hostname is a domain, but it also supports other kinds of hosts as well.
  ///
  /// - parameters:
  ///   - utf8: The string to parse, as a collection of UTF-8 code-units.
  ///
  @inlinable
  public init?<UTF8Bytes>(utf8: UTF8Bytes) where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {
    let parsed =
      utf8.withContiguousStorageIfAvailable {
        WebURL.Host.parse(utf8: $0.boundsChecked, schemeKind: .http)
      } ?? WebURL.Host.parse(utf8: utf8, schemeKind: .http)
    guard case .domain(let domain) = parsed else {
      return nil
    }
    self = domain
  }
}


// --------------------------------------------
// MARK: - Serialization
// --------------------------------------------


extension WebURL.Domain {

  /// The ASCII serialization of this domain.
  ///
  /// This value is guaranteed to be a non-empty ASCII string.
  /// Parsing this serialization with ``init(_:)`` will succeed,
  /// and construct a value which is identical to this domain.
  ///
  /// ```swift
  /// WebURL.Domain("example.com")?.serialized  // ✅ "example.com"
  /// WebURL.Domain("EXAMPLE.com")?.serialized  // ✅ "example.com"
  /// WebURL.Domain("api.أهلا.com")?.serialized  // ✅ "api.xn--igbi0gl.com"
  ///
  /// WebURL.Domain("api.أهلا.com")?.description        // ✅ "api.xn--igbi0gl.com" -- same as above
  /// WebURL.Domain("api.أهلا.com").map { String($0) }  // ✅ "api.xn--igbi0gl.com" -- same as above
  /// ```
  ///
  @inlinable
  public var serialized: String {
    _serialization
  }
}


// --------------------------------------------
// MARK: - Properties
// --------------------------------------------


extension WebURL.Domain {

  /// Whether this is an Internationalized Domain Name (IDN).
  ///
  /// Internationalized Domain Names have at least one label which can be decoded to Unicode.
  /// In other words, one or more labels have the `"xn--"` prefix.
  ///
  /// ```swift
  /// WebURL.Domain("example.com")?.isIDN  // ✅ false -- "example.com"
  /// WebURL.Domain("api.أهلا.com")?.isIDN  // ✅ true -- "api.xn--igbi0gl.com"
  ///                                      //                 ^^^^^^^^^^^
  /// ```
  ///
  @inlinable
  public var isIDN: Bool {
    _hasPunycodeLabels
  }
}


// --------------------------------------------
// MARK: - Rendering
// --------------------------------------------


extension WebURL.Domain {

  /// An encapsulated algorithm which operates on a domain.
  ///
  /// Renderers are encapsulated algorithms which operate on a domain. They might help protect users
  /// against confusable text using spoof-checking algorithms, smartly abbreviate domains
  /// using an ownership database (as many browsers do by default in their address bars),
  /// or they might have custom formatting for particular domains.
  ///
  /// The ``WebURL/WebURL/Domain/render(_:)-lssu`` function visits a domain's labels,
  /// invoking callbacks on a "renderer" object which builds up some kind of result.
  /// Since processing Unicode text can be expensive, the callbacks are structured to enable fast-paths,
  /// lazy computation, and buffer reuse.
  ///
  /// ### Conforming to `WebURL.Domain.Renderer`
  ///
  /// A renderer only needs 2 things: a ``WebURL/DomainRenderer/result`` property (which can be a computed property),
  /// and a ``WebURL/DomainRenderer/processLabel(_:isEnd:)`` function. `processLabel` visits labels
  /// from right to left, and once all labels have been processed, the render function will access
  /// and return the value of the `result` property.
  ///
  /// The following example shows a simple renderer which forces labels with mathematical characters
  /// to be displayed as Punycode. More sophisticated renderers are possible.
  ///
  /// ```swift
  /// struct NoMath: WebURL.Domain.Renderer {
  ///   var result = ""
  ///   mutating func processLabel(_ label: inout Label, isEnd: Bool) {
  ///     if label.isIDN == false || label.unicodeScalars.contains(where: \.properties.isMath) {
  ///       result.insert(contentsOf: label.ascii, at: result.startIndex)
  ///     } else {
  ///       result.insert(contentsOf: label.unicode, at: result.startIndex)
  ///     }
  ///     if !isEnd { result.insert(".", at: result.startIndex) }
  ///   }
  /// }
  ///
  /// let domain = WebURL.Domain("hello.xn--e28h.xn--6dh.com")!
  /// domain.render(.uncheckedUnicodeString)
  /// // "hello.😀.⊈.com"
  /// //           ^ OH NO - A MATH SYMBOL!
  ///
  /// domain.render(NoMath())
  /// // "hello.😀.xn--6dh.com"
  /// //           ^^^^^^^
  /// ```
  ///
  /// ### The `render` function
  ///
  /// The ``WebURL/WebURL/Domain/render(_:)-lssu`` function processes domains in 2 stages:
  ///
  /// 1. Full-domain processing.
  ///
  ///    The optional ``WebURL/DomainRenderer/processDomain(_:)-6b0yy`` callback visits the domain.
  ///    Since the entire serialization is available, it can be used to integrate arbitrary processing
  ///    and fast-paths that consider the domain as a whole rather than as individual labels.
  ///
  /// 2. Per-label processing.
  ///
  ///    The renderer's ``WebURL/DomainRenderer/processLabel(_:isEnd:)`` callback visits the domain's labels
  ///    from right to left. The ``WebURL/DomainRenderer/Label`` type provides both the label's ASCII and Unicode
  ///    representations, and integrates efficiently with the render function.
  ///
  /// Between these stages, and before processing each label, the render function checks the value of
  /// ``WebURL/DomainRenderer/readyToReturn-xve4``. If `true`, the function stops processing labels
  /// and returns ``WebURL/DomainRenderer/result``. Otherwise, `result` is returned after all labels
  /// have been processed.
  ///
  /// [icu]: https://unicode-org.github.io/icu-docs/apidoc/dev/icu4c/uspoof_8h.html
  ///
  /// ## Topics
  ///
  /// ### Full-Domain Processing (Optional)
  ///
  /// - ``WebURL/DomainRenderer/processDomain(_:)-6b0yy``
  ///
  /// ### Per-Label Processing
  ///
  /// - ``WebURL/DomainRenderer/processLabel(_:isEnd:)``
  /// - ``WebURL/DomainRenderer/Label``
  /// - ``WebURL/DomainRenderer/readyToReturn-xve4``
  ///
  /// ### The Result
  ///
  /// - ``WebURL/DomainRenderer/Output``
  /// - ``WebURL/DomainRenderer/result``
  ///
  /// ### Aliases
  ///
  /// - ``WebURL/DomainRenderer``
  /// - ``WebURL/DomainRendererLabel``
  ///
  public typealias Renderer = DomainRenderer
}

/// See ``WebURL/WebURL/Domain/Renderer``.
///
/// The preferred name of this protocol is `WebURL.Domain.Renderer`.
/// This protocol exists because Swift does not allow protocols to be nested in types.
///
public protocol DomainRenderer {

  typealias _Member = _StaticMember<Self>

  /// The contents of a domain label.
  ///
  /// This type provides information about a label in a domain, such as its ASCII and Unicode textual representations.
  /// It serves as the interface between the ``WebURL/WebURL/Domain/render(_:)-lssu`` function and renderer objects,
  /// which receive `inout` values of this type in the ``WebURL/DomainRenderer/processLabel(_:isEnd:)`` callback.
  ///
  /// The following example shows a renderer which inspects the core properties of a label:
  ///
  /// ```swift
  /// struct LabelInfo: WebURL.Domain.Renderer {
  ///   var result: Void { () }
  ///
  ///   func processLabel(_ label: inout Label, isEnd: Bool) {
  ///     print("ASCII:", label.ascii)
  ///     print("isIDN:", label.isIDN)
  ///     print("Unicode:", label.unicode)
  ///     print("")
  ///   }
  /// }
  ///
  /// WebURL.Domain("api.xn--e28h.com")!.render(LabelInfo())
  /// ```
  ///
  /// It produces the following output. Note that labels are visited from right to left:
  ///
  /// ```
  /// ASCII:  com
  /// isIDN:  false
  /// Unicode:  com
  ///
  /// ASCII:  xn--e28h
  /// isIDN:  true
  /// Unicode: 😀
  ///
  /// ASCII:  api
  /// isIDN:  false
  /// Unicode:  api
  /// ```
  ///
  /// ## Topics
  ///
  /// ### Essential Properties
  ///
  /// - ``WebURL/DomainRendererLabel/ascii``
  /// - ``WebURL/DomainRendererLabel/unicode``
  /// - ``WebURL/DomainRendererLabel/unicodeScalars``
  /// - ``WebURL/DomainRendererLabel/isIDN``
  ///
  /// ### Other Properties
  ///
  /// - ``WebURL/DomainRendererLabel/asciiWithLeadingDelimiter``
  ///
  typealias Label = DomainRendererLabel

  // The Result.

  /// The type of this renderer's ``result``.
  ///
  associatedtype Output

  /// The renderer's final result.
  ///
  /// This property is accessed by the render function after processing all of the domain's labels
  /// (after the ``WebURL/DomainRenderer/processLabel(_:isEnd:)`` callback where `isEnd = true`).
  ///
  /// If a renderer can early-exit, its ``WebURL/DomainRenderer/readyToReturn-xve4`` property should return `true`,
  /// in which case the render function will stop processing labels and immediately return this value.
  ///
  var result: Output { get }

  // Full-domain processing.

  /// An optional callback which processes an entire domain.
  ///
  /// This callback is invoked before processing the domain's labels, allowing the renderer
  /// to implement fast-paths or other kinds of processing on the entire domain value.
  ///
  /// The default implementation does nothing.
  ///
  mutating func processDomain(_ domain: WebURL.Domain)

  // Per-label processing.

  /// A callback which processes the next label in the domain. Labels are visited from right to left.
  ///
  /// The provided ``WebURL/DomainRenderer/Label`` value serves as an interface between the render function
  /// and the renderer. It provides various kinds of information about the label, such as its ASCII and Unicode
  /// serializations, some of which is calculated on-demand in buffers which the render function can reuse.
  ///
  /// The following example shows a simple renderer which forces labels with mathematical characters
  /// to be displayed as Punycode. More sophisticated renderers are possible.
  ///
  /// ```swift
  /// struct NoMath: WebURL.Domain.Renderer {
  ///   var result = ""
  ///   mutating func processLabel(_ label: inout Label, isEnd: Bool) {
  ///     if label.isIDN == false || label.unicodeScalars.contains(where: \.properties.isMath) {
  ///       result.insert(contentsOf: label.ascii, at: result.startIndex)
  ///     } else {
  ///       result.insert(contentsOf: label.unicode, at: result.startIndex)
  ///     }
  ///     if !isEnd { result.insert(".", at: result.startIndex) }
  ///   }
  /// }
  ///
  /// let domain = WebURL.Domain("hello.xn--e28h.xn--6dh.com")!
  /// domain.render(.uncheckedUnicodeString)
  /// // "hello.😀.⊈.com"
  /// //           ^ OH NO - A MATH SYMBOL!
  ///
  /// domain.render(NoMath())
  /// // "hello.😀.xn--6dh.com"
  /// //           ^^^^^^^
  /// ```
  ///
  /// - parameters:
  ///   - label: The contents of the label.
  ///   - isEnd: Whether this is the leftmost label in the domain.
  ///            If `true`, there will be no labels processed after this one.
  ///
  mutating func processLabel(_ label: inout Label, isEnd: Bool)

  // Early Completion.

  /// An optional property which signals whether the result is ready to be returned early.
  ///
  /// The render function inspects this value before starting processing individual labels, and between processing
  /// each label. If it returns `true`, no more labels will be processed and the renderer's ``WebURL/DomainRenderer/result``
  /// will be returned.
  ///
  /// This allows renderers to exit early, but **not** prevent exit; once all labels have been processed,
  /// the renderer's ``WebURL/DomainRenderer/result`` will be called even if this value returns `false`.
  ///
  /// The default implementation always returns `false`, so all labels are processed.
  ///
  var readyToReturn: Bool { get }
}

extension DomainRenderer {

  @inlinable
  public func processDomain(_ domain: WebURL.Domain) {
    // No-op.
  }

  @inlinable
  public var readyToReturn: Bool {
    false  // Process all labels; do not exit early.
  }
}

extension WebURL.Domain {

  /// Processes this domain with the given renderer.
  ///
  /// Renderers are encapsulated algorithms which operate on a domain. They might help protect users
  /// against confusable text using spoof-checking algorithms, smartly abbreviate domains
  /// using an ownership database (as many browsers do by default in their address bars),
  /// or they might have custom formatting for particular domains.
  /// You can write your own renderers by conforming to the ``WebURL/WebURL/Domain/Renderer`` protocol.
  ///
  /// This library includes an ``WebURL/DomainRenderer/uncheckedUnicodeString`` renderer which
  /// returns a domain's Unicode representation without performing confusable/spoof detection.
  /// For display to humans, you should consider using a renderer with spoof detection and mitigation instead.
  ///
  /// ```swift
  /// WebURL.Domain("example.com")!
  ///   .render(.uncheckedUnicodeString)  // ✅ "example.com"
  /// WebURL.Domain("api.xn--igbi0gl.com")!
  ///   .render(.uncheckedUnicodeString)  // ✅ "api.أهلا.com"
  /// WebURL.Domain("xn--6qqa088eba.com")!
  ///   .render(.uncheckedUnicodeString)  // ✅ "你好你好.com"
  ///
  /// // Consider whether spoof-checking is required
  /// // for your context.
  ///
  /// WebURL.Domain("xn--pal-vxc83d5c.com")!
  ///   .render(.uncheckedUnicodeString)  // ❗️  "раγpal.com" - possible spoof!
  ///                                     // NOT "paypal.com"
  /// ```
  ///
  /// - parameters:
  ///   - renderer: The renderer to process this domain with
  ///
  /// - returns: The result of the given renderer.
  ///
  /// ## Topics
  ///
  /// ### Compatibility with older versions of Swift
  ///
  /// - ``WebURL/WebURL/Domain/render(_:)-6xt1s``
  ///
  @inlinable
  public func render<Renderer: WebURL.Domain.Renderer>(_ renderer: Renderer) -> Renderer.Output {

    var renderer = renderer

    // 1. Full-domain.

    renderer.processDomain(self)

    if renderer.readyToReturn {
      return renderer.result
    }

    // 2. Per-label.

    let serialization = self.serialized

    var scalarBuffer: [Unicode.Scalar] = []
    var scalarBufferIsReserved = false
    var utf8Buffer = ""
    var utf8BufferIsReserved = false

    var delimiter = serialization.utf8.endIndex
    precondition(delimiter > serialization.utf8.startIndex, "Domains may not be empty")
    processLabels: while delimiter > serialization.utf8.startIndex {

      if renderer.readyToReturn {
        break processLabels
      }

      // Find the next label (right to left).
      let nameStart: String.Index
      let nameEnd: String.Index
      let isEnd: Bool
      if let nextLeadingDelimiter = serialization[..<delimiter].utf8.fastLastIndex(of: ASCII.period.codePoint) {
        nameStart = serialization.utf8.index(after: nextLeadingDelimiter)
        nameEnd = delimiter
        delimiter = nextLeadingDelimiter
        isEnd = false
      } else {
        nameStart = serialization.utf8.startIndex
        nameEnd = delimiter
        delimiter = nameStart
        isEnd = true
      }

      var renderLabel = DomainRendererLabel(
        _domain: serialization,
        isIDNLabel: self.isIDN && hasIDNAPrefix(utf8: serialization[nameStart...].utf8),
        leadingDelimiterIndex: delimiter,
        nameStartIndex: nameStart,
        nameEndIndex: nameEnd,
        scalarBuffer: scalarBuffer,
        scalarBufferIsReserved: scalarBufferIsReserved,
        utf8Buffer: utf8Buffer,
        utf8BufferIsReserved: utf8BufferIsReserved
      )

      // Set scalarBuffer to [] and utf8Buffer to "", so DomainRendererLabel has unique ownership of the buffers,
      // and can use them for decoding Punycoded labels. We take ownership back after 'processLabel',
      // so later iterations of the loop can reuse the allocation. This is like a poor man's "move".
      scalarBuffer = []
      utf8Buffer = ""

      renderer.processLabel(&renderLabel, isEnd: isEnd)

      swap(&renderLabel._scalarBuffer, &scalarBuffer)
      swap(&renderLabel._utf8Buffer, &utf8Buffer)
      if renderLabel._scalarBufferState != .unreserved { scalarBufferIsReserved = true }
      if renderLabel._utf8BufferState != .unreserved { utf8BufferIsReserved = true }
    }

    return renderer.result
  }

  /// Processes this domain with the given renderer.
  ///
  /// > Note:
  /// > This is a fallback API for pre-5.5 Swift compilers.
  /// > Please refer to ``WebURL/WebURL/Domain/render(_:)-lssu``.
  ///
  @inlinable @inline(__always) @_disfavoredOverload
  public func render<Renderer: WebURL.Domain.Renderer>(_ renderer: Renderer._Member) -> Renderer.Output {
    render(renderer.base)
  }
}

/// See ``WebURL/DomainRenderer/Label``.
///
/// The preferred name of this type is `WebURL.Domain.Renderer.Label`.
/// This struct exists because Swift does not allow types to be nested in protocols.
///
public struct DomainRendererLabel {

  // The serialization of the entire domain.
  //
  @usableFromInline
  internal var _domain: String

  // Leading '.' which delimited this label, if it has one
  // (if not, this is the first label, and this value will equal '_nameStart')
  //
  @usableFromInline
  internal var _leadingDelimiter: String.Index

  @usableFromInline
  internal var _nameStart: String.Index

  @usableFromInline
  internal var _nameEnd: String.Index

  // A buffer used for the label's `unicodeScalars` property.
  //
  // This starts as the empty Array singleton; storage is reserved lazily so ASCII domains can avoid allocating.
  // The render function takes ownership of this buffer, so later labels can reuse its capacity.
  //
  @usableFromInline
  internal var _scalarBuffer: [Unicode.Scalar]

  @usableFromInline
  internal var _scalarBufferState: _BufferState

  // A buffer used for the label's `unicode` property.
  //
  // This starts as the singleton empty String; storage is reserved lazily so it does not allocate unless accessed.
  // The render function takes ownership of this buffer, so later labels can reuse its capacity.
  //
  @usableFromInline
  internal var _utf8Buffer: String

  @usableFromInline
  internal var _utf8BufferState: _BufferState

  @usableFromInline
  internal enum _BufferState {
    // The empty singleton.
    case unreserved
    // There is allocated capacity, but the contents are from some previous label.
    case reserved
    // The buffer contains the correct content for this label.
    case decodedContents
  }

  /// Whether this is an IDN label - i.e. whether its ASCII and Unicode representations are different.
  ///
  /// If `true`, this label's ASCII serialization starts with `"xn--"`.
  ///
  public var isIDN: Bool

  @inlinable
  internal init(
    _domain: String,
    isIDNLabel: Bool,
    leadingDelimiterIndex: String.Index,
    nameStartIndex: String.Index,
    nameEndIndex: String.Index,
    scalarBuffer: [Unicode.Scalar],
    scalarBufferIsReserved: Bool,
    utf8Buffer: String,
    utf8BufferIsReserved: Bool
  ) {
    self._domain = _domain
    self.isIDN = isIDNLabel
    self._leadingDelimiter = leadingDelimiterIndex
    self._nameStart = nameStartIndex
    self._nameEnd = nameEndIndex
    self._scalarBuffer = scalarBuffer
    self._scalarBufferState = scalarBufferIsReserved ? .reserved : .unreserved
    self._utf8Buffer = utf8Buffer
    self._utf8BufferState = utf8BufferIsReserved ? .reserved : .unreserved
  }

  /// The label's ASCII representation.
  ///
  /// This is the label as it appears in the domain's ``WebURL/WebURL/Domain/serialized`` string.
  /// It has the same properties as the domain's serialization, such as being normalized to lowercase.
  ///
  /// If this is an IDN label (``isIDN`` is `true`), the label starts with `"xn--"` and contains Unicode text
  /// encoded as ASCII. The Unicode representation may be accessed using the ``unicode`` or ``unicodeScalars``
  /// properties.
  ///
  /// > Tip:
  /// >
  /// > This substring is a slice of an internal buffer used by the render function.
  /// > For best performance, avoid storing this value beyond the `processLabel` callback,
  /// > and make a copy if you will need it later.
  ///
  @inlinable
  public var ascii: Substring {
    _domain[_nameStart..<_nameEnd]
  }

  /// The label's ASCII representation, including its leading delimiter.
  ///
  /// This returns the same value as ``ascii``, but includes the label's leading `"."` delimiter if it has one,
  /// which all but the leftmost label do. By including the delimiter, this substring allows ASCII labels
  /// to be accumulated in a single insertion operation.
  ///
  /// ```swift
  /// // Before:
  /// result.insert(label.ascii, at: result.startIndex)
  /// if !isEnd { result.insert(".", at: result.startIndex)
  ///
  /// // After:
  /// result.insert(label.asciiWithLeadingDelimiter, at: result.startIndex)
  /// ```
  ///
  /// > Tip:
  /// >
  /// > This substring is a slice of an internal buffer used by the render function.
  /// > For best performance, avoid storing this value beyond the `processLabel` callback,
  /// > and make a copy if you will need it later.
  ///
  @inlinable
  public var asciiWithLeadingDelimiter: Substring {
    _domain[_leadingDelimiter..<_nameEnd]
  }

  /// The label's Unicode representation, as a buffer of scalars.
  ///
  /// If this is an IDN label (``isIDN`` is `true`), the buffer contains the result of decoding
  /// the label's ASCII serialization from Punycode. If it is not an IDN label, the buffer
  /// contains the same scalars as the ASCII representation.
  ///
  /// Since ``WebURL/WebURL/Domain`` values are validated and normalized by the URL host parser,
  /// the array is guaranteed to contain a string in Unicode Normalization Form C (NFC),
  /// and has passed certain checks required by the URL Standard, such as not containing forbidden scalars,
  /// or making invalid use of joiners or bidirectional text. Despite this, you are **encouraged** to employ
  /// additional spoof-checking if presenting this text to a human.
  ///
  /// ```swift
  /// "раγpal.com"  // <- This is NOT "paypal.com"
  /// ```
  ///
  /// > Tip:
  /// >
  /// > This value is created on-demand and cached in the `Label` value.
  /// > That is why it has a `mutating get`, and why the `processLabel` function provides an `inout Label`.
  /// >
  /// > For IDN labels, it is cheaper to access the label's scalars than its ``unicode`` string.
  /// > Some kinds of processing can also be more efficient when operating on a buffer of scalars.
  /// >
  /// > This substring is a slice of an internal buffer used by the render function.
  /// > For best performance, avoid storing this value beyond the `processLabel` callback,
  /// > and make a copy if you will need it later.
  ///
  @inlinable
  public var unicodeScalars: [Unicode.Scalar] {
    mutating get {
      switch _scalarBufferState {
      case .decodedContents:
        return _scalarBuffer
      case .unreserved:
        _scalarBuffer.reserveCapacity(64)
        break
      case .reserved:
        break
      }

      _scalarBuffer.replaceSubrange(
        Range(uncheckedBounds: (0, _scalarBuffer.count)),
        with: ascii.utf8.lazy.map { Unicode.Scalar($0) }
      )
      switch Punycode.decodeInPlace(&_scalarBuffer) {
      case .success(count: let newCount):
        assert(isIDN)
        _scalarBuffer.removeLast(_scalarBuffer.count &- newCount)
      case .notPunycode:
        assert(!isIDN)
        break
      case .failed:
        fatalError("WebURL.Domain should be validated; shouldn't contain invalid Punycode")
      }
      _scalarBufferState = .decodedContents
      return _scalarBuffer
    }
  }

  /// The label's Unicode representation.
  ///
  /// If this is an IDN label (``isIDN`` is `true`), the string contains the result of decoding
  /// the label's ASCII serialization from Punycode. If it is not an IDN label, the string
  /// contains the same contents as the ASCII representation.
  ///
  /// Since ``WebURL/WebURL/Domain`` values are validated and normalized by the URL host parser,
  /// the string is guaranteed to be in Unicode Normalization Form C (NFC),
  /// and has passed certain checks required by the URL Standard, such as not containing forbidden scalars,
  /// or making invalid use of joiners or bidirectional text. Despite this, you are **encouraged** to employ
  /// additional spoof-checking if presenting this text to a human.
  ///
  /// ```swift
  /// "раγpal.com"  // <- This is NOT "paypal.com"
  /// ```
  ///
  /// > Tip:
  /// >
  /// > This value is created on-demand, and cached in the `Label` value.
  /// > That is why it has a `mutating get`, and why the `processLabel` function provides an `inout Label`.
  /// >
  /// > This substring is a slice of an internal buffer used by the render function.
  /// > For best performance, avoid storing this value beyond the `processLabel` callback,
  /// > and make a copy if you will need it later.
  ///
  @inlinable
  public var unicode: Substring {
    mutating get {
      guard isIDN else {
        return ascii
      }
      switch _utf8BufferState {
      case .decodedContents:
        return _utf8Buffer[...]
      case .unreserved:
        _utf8Buffer.reserveCapacity(64)
        break
      case .reserved:
        break
      }

      _utf8Buffer.unicodeScalars.replaceSubrange(
        Range(uncheckedBounds: (_utf8Buffer.startIndex, _utf8Buffer.endIndex)), with: unicodeScalars
      )
      _utf8BufferState = .decodedContents
      return _utf8Buffer[...]
    }
  }

}

#if swift(>=5.5)

  extension WebURL.Domain.Renderer where Self == UncheckedUnicodeDomainRenderer {

    /// A renderer which produces a domain's full Unicode form, without any confusable/spoof detection.
    ///
    /// When presenting a domain to a human, it is advised to make use of spoof detection algorithms,
    /// and to display confusable labels in Punycode or otherwise highlight that they may be an attempt to deceive.
    /// See [UTR36][utr36] and [UTS39][uts39] for more information about the dangers of confusable text.
    /// ICU's [`USpoofChecker`][icu] is an implementation of UTS39 which may be available on some platforms.
    ///
    /// This renderer should only be used in situations where spoof detection is not necessary.
    ///
    /// ```swift
    /// WebURL.Domain("example.com")!
    ///   .render(.uncheckedUnicodeString)  // ✅ "example.com"
    /// WebURL.Domain("api.xn--igbi0gl.com")!
    ///   .render(.uncheckedUnicodeString)  // ✅ "api.أهلا.com"
    /// WebURL.Domain("xn--6qqa088eba.com")!
    ///   .render(.uncheckedUnicodeString)  // ✅ "你好你好.com"
    ///
    /// // Consider whether spoof-checking is required
    /// // for your context.
    ///
    /// WebURL.Domain("xn--pal-vxc83d5c.com")!
    ///   .render(.uncheckedUnicodeString)  // ❗️  "раγpal.com" - possible spoof!
    ///                                     // NOT "paypal.com"
    /// ```
    ///
    /// [utr36]: https://unicode.org/reports/tr36/#international_domain_names
    /// [uts39]: http://unicode.org/reports/tr39/
    /// [icu]: https://unicode-org.github.io/icu-docs/apidoc/dev/icu4c/uspoof_8h.html
    ///
    /// ## Topics
    ///
    /// ### Type Definition
    ///
    /// - ``WebURL/UncheckedUnicodeDomainRenderer``
    ///
    @inlinable
    public static var uncheckedUnicodeString: Self { .init() }
  }

#endif

// For older versions of Swift, use _StaticMember to provide a source-compatible interface.
// Unfortunately, we don't know whether our clients need compatibility with pre-5.5 toolchains,
// so these can't be only conditionally included.

extension _StaticMember where Base: WebURL.Domain.Renderer {

  /// A renderer which produces a domain's full Unicode form, without any confusable/spoof detection.
  ///
  /// > Note:
  /// > This is a fallback API for pre-5.5 Swift compilers.
  /// > Please refer to ``WebURL/DomainRenderer/uncheckedUnicodeString``.
  ///
  @inlinable
  public static var uncheckedUnicodeString: _StaticMember<UncheckedUnicodeDomainRenderer> { .init(.init()) }
}

/// A renderer which produces a domain's full Unicode form, without any confusable/spoof detection.
///
/// When presenting a domain to a human, it is advised to make use of spoof detection algorithms,
/// and to display confusable labels in Punycode or otherwise highlight that they may be an attempt to deceive.
/// See [UTR36][utr36] and [UTS39][uts39] for more information about the dangers of confusable text.
/// ICU's [`USpoofChecker`][icu] is an implementation of UTS39 which may be available on some platforms.
///
/// This renderer should only be used in situations where spoof detection is not necessary.
///
/// ```swift
/// WebURL.Domain("example.com")!
///   .render(.uncheckedUnicodeString)  // ✅ "example.com"
/// WebURL.Domain("api.xn--igbi0gl.com")!
///   .render(.uncheckedUnicodeString)  // ✅ "api.أهلا.com"
/// WebURL.Domain("xn--6qqa088eba.com")!
///   .render(.uncheckedUnicodeString)  // ✅ "你好你好.com"
///
/// // Consider whether spoof-checking is required
/// // for your context.
///
/// WebURL.Domain("xn--pal-vxc83d5c.com")!
///   .render(.uncheckedUnicodeString)  // ❗️  "раγpal.com" - possible spoof!
///                                     // NOT "paypal.com"
/// ```
///
/// [utr36]: https://unicode.org/reports/tr36/#international_domain_names
/// [uts39]: http://unicode.org/reports/tr39/
/// [icu]: https://unicode-org.github.io/icu-docs/apidoc/dev/icu4c/uspoof_8h.html
///
public struct UncheckedUnicodeDomainRenderer: WebURL.Domain.Renderer {

  @usableFromInline
  internal var _result: String
  @usableFromInline
  internal var _readyToReturn: Bool

  @usableFromInline
  internal init() {
    _result = ""
    _readyToReturn = false
  }

  public typealias Output = String

  @inlinable
  public var result: String { _result }

  @inlinable
  public var readyToReturn: Bool { _readyToReturn }

  @inlinable
  public mutating func processDomain(_ domain: WebURL.Domain) {
    if !domain.isIDN {
      _result = domain.serialized
      _readyToReturn = true
    }
  }

  @inlinable
  public mutating func processLabel(_ label: inout Label, isEnd: Bool) {
    if !label.isIDN {
      _result.insert(contentsOf: label.asciiWithLeadingDelimiter, at: _result.startIndex)
    } else {
      _result.insert(contentsOf: label.unicode, at: _result.startIndex)
      if !isEnd { _result.insert(".", at: _result.startIndex) }
    }
  }
}
