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

import UnicodeDataStructures

/// Functions relating to Internationalizing Domain Names for Applications (IDNA) compatibility processing.
///
/// IDNA is a way of encoding Unicode domain names as ASCII strings in a way that works essentially identically
/// to plain ASCII domain names. It is compatible with existing DNS infrastructure, and with existing security-related
/// decisions applications make by inspecting domains (for example, evaluating whether two domains are equal or
/// have a common root).
///
/// The readability of the ASCII form depends on the properties of the input string. The format is primarily
/// optimized for compactness, as DNS has strict length limitations (63 bytes per label goes far with ASCII, but much
/// less far with Unicode; in UTF-8 some scalars can take 4 bytes). For example, the string `你好你好`
/// becomes `xn--6qqa088eba` in ASCII form.
///
/// Instead, IDNs in ASCII form may be restored to Unicode form for display.
///
/// > Important:
/// >
/// > Domains are often displayed in a context which establishes authority. For example, a person
/// > viewing an email from `"support@apple.com"` expects the sender to represent Apple Inc.
/// >
/// > Displaying Unicode text in such contexts should be considered carefully. It is possible for certain
/// > characters to appear visually similar, or even identically, to other characters - to the extent that
/// > readers may be mislead about the authority being established.
/// >
/// > This does not only apply to domains. For instance, consider an App on a digital storefront,
/// > claiming to be developed by "Google". It would likely be wise for the storefront to forbid characters
/// > such as zero-width non-joiners from developer names, otherwise somebody else could register "Go\{200C}ogle"
/// > which appears as visually indistinguishable from the original. Additionally, some emoji can be ambiguous,
/// > especially at smaller font sizes.
/// >
/// > The IDNA specification has some basic protection against normalization differences, joiners (as described above),
/// > and bidirectional text built-in. Nonetheless, it is wise to employ a display strategy to make its
/// > own determination for a given context.
///
/// ## Compatibility Processing
///
/// This type exposes two static functions, for converting domains to their canonical Unicode or ASCII forms.
///
/// Both functions are idempotent, so applying them to an already-canonicalized input does not change the value.
/// This makes it convenient to pass a domain through `toUnicode` or `toASCII` as part of an existing workflow,
/// **without** having to worry about which form its already in and whether you'd be double-encoding, etc.
///
/// ### Converting a domain to Unicode form
///
/// - ``toUnicode(utf8:writer:)``
///
///    Takes a domain, in ASCII or Unicode form, and converts it to its canonical Unicode form.
///    It performs all necessary compatibility processing, normalization, validation, etc.
///
///    This is how you would turn `www.xn--6qqa088eba.com` in to `www.你好你好.com`.
///
///    This function visits each label of the domain as a buffer of Unicode scalars, which is where you can apply
///    your own logic to detect confusable domains, and decide how you want to present them.
///    For example, if the label contains scripts the user is not known to be familiar with, or mixes scripts,
///    it may be wise to display it as Punycode or show some other warning in the UI.
///
/// ### Converting a domain to ASCII form
///
/// - ``toASCII(utf8:beStrict:writer:)``
///
///    Takes a domain, in ASCII or Unicode form, and converts it to its canonical ASCII form.
///    It performs the same IDNA compatibility processing as ``toUnicode(utf8:writer:)``, with an additional
///    `beStrict` parameter to enforce STD3 ASCII rules, and encodes all canonicalized domains as Punycode.
///
///    This is how you would turn `www.你好你好.com` in to `www.xn--6qqa088eba.com`.
///
/// These APIs follow definitions in the WHATWG URL Standard, which implements IDNA-2008
/// according to the compatibility guidelines in [Unicode Technical Standard #46](https://www.unicode.org/reports/tr46/).
///
/// ## Topics
///
/// ### IDNA Compatibility Processing
///
/// - ``IDNA/toUnicode(utf8:writer:)``
/// - ``IDNA/toASCII(utf8:beStrict:writer:)``
///
public enum IDNA {}


// --------------------------------------------
// MARK: - ToUnicode/ToASCII
// --------------------------------------------


extension IDNA {

  /// Converts a domain to its canonical Unicode form.
  ///
  /// The domain may be given in ASCII or Unicode form. This function will perform all required
  /// compatibility processing, including mapping and case-folding, normalization, Punycode decoding, etc.
  /// Finally, each label and the entire domain are validated, producing a nice, canonicalized, Unicode-form domain.
  ///
  /// This function is idempotent, so if it is applied to a domain that is already in canonical Unicode form,
  /// it just produces the same value, unchanged.
  ///
  /// ```swift
  /// // ASCII domains.
  /// toUnicode("example.com")  // ✅ "example.com"
  ///
  /// // Punycode.
  /// toUnicode("xn--weswift-z98d")        // ✅ "we❤️swift"
  /// toUnicode("api.xn--6qqa088eba.com")  // ✅ "api.你好你好.com"
  ///
  /// // Idempotent.
  /// toUnicode("api.你好你好.com")  // ✅ "api.你好你好.com"
  ///
  /// // Normalizes Unicode domains.
  /// toUnicode("www.caf\u{00E9}.fr")   // ✅ "www.café.fr" ("caf\u{00E9}")
  /// toUnicode("www.cafe\u{0301}.fr")  // ✅ "www.café.fr" ("caf\u{00E9}")
  /// toUnicode("www.xn--caf-dma.fr")   // ✅ "www.café.fr" ("caf\u{00E9}")
  /// ```
  ///
  /// Validation ensures that domains are NFC normalized and case-folded, and enforces some rules
  /// with regards to use of joiners and bidirectional text.
  ///
  /// ```swift
  /// // Zero-width joiners and non-joiners are only allowed in certain contexts.
  /// let notApple = "a\u{200C}pple.com"     // 🥸 Hey! There's a zero-width non-joiner hiding there!
  /// print(notApple)           "a‌pple.com"  // To a human, it looks like "apple.com"
  /// print(notApple == "apple.com")  false  // A computer knows it ISN'T "apple.com"
  /// toUnicode("a\u{200C}pple.com")  <nil>  // ❎ Not a valid IDN!
  ///
  /// // "xn--cafe-yvc" is how you would Punycode "cafe\u{0301}" (the non-NFC "café").
  /// // This ensures there is only one "café.fr".
  /// toUnicode("xn--caf-dma.fr")   // ✅ "café.fr" ("caf\u{00E9}")
  /// toUnicode("xn--cafe-yvc.fr")  // ❎ <nil> - Not a valid IDN!
  /// ```
  ///
  /// ## Rendering Domains
  ///
  /// Domains are often displayed in a context which establishes authority. For example, a person
  /// viewing an email from `"support@apple.com"` expects the sender to represent Apple Inc.
  ///
  /// Displaying Unicode text in such contexts should be considered carefully. It is possible for certain
  /// characters to appear visually similar, or even identically, to other characters - to the extent that
  /// readers may be mislead about the authority being established. [Unicode Technical Report #36][UTR36]
  /// and [Unicode Technical Standard #39][UTS39] explain these issues in more detail, with examples.
  ///
  /// Applications can decide how this applies to them; perhaps they can consider which scripts the user is familiar
  /// with, or perhaps they will render potentially-confusable labels with a different font or other UI marker.
  /// Alternatively, they might render confusable labels as Punycode, although note that this can be counter-productive
  /// (see UTR36). It's a bit of an open question: how can we present text that is truly unambiguous, such that you
  /// can trust its authority? The best answer we have so far is: do what makes sense in your context 🤷‍♂️.
  ///
  /// To facilitate high-level Unicode processing, this function takes a callback closure which visits each label
  /// of the domain. Labels are provided to the closure as a buffer of canonicalized Unicode scalars
  /// (i.e. NFC normalized, case-folded, and validated). The closure can then decide how it wishes to present
  /// the Unicode label for display, or which flags it wishes to remember about this domain.
  ///
  /// Here's how we might implement that. Let's say we have a function, `DecidePresentationStrategyForLabel`,
  /// which decides the best way to render a domain label in our UI, given our user's locale preferences
  /// and other heuristics:
  ///
  /// ```swift
  /// func DecidePresentationStrategyForLabel(
  ///   _ label: some RandomAccessCollection<Unicode.Scalar>
  /// ) -> PresentationStrategy {
  ///   // Your logic here...
  /// }
  ///
  /// func RenderDomain(_ input: String) -> String? {
  ///   var result = ""
  ///   let success = IDNA.toUnicode(utf8: input.utf8) { label, needsTrailingDot in
  ///     switch DecidePresentationStrategyForLabel(label) {
  ///     // Unicode presentation.
  ///     case .unicode:
  ///       result.unicodeScalars += label
  ///
  ///     // Punycode can also be a valid way to write this label.
  ///     // Note that it can _also_ be ambiguous, so use with caution!
  ///     case .punycode:
  ///       Punycode.encode(label) { ascii in
  ///         result.unicodeScalars.append(Unicode.Scalar(ascii))
  ///       }
  ///
  ///     // Other context-appropriate responses, beyond Punycode...
  ///     case .confusableWithKnownBrand:
  ///       /* Use AttributedString to force a certain font/spacing/color? */
  ///       /* Add an extra warning for certain actions, like making a purchase/entering a password? */
  ///     }
  ///
  ///     if needsTrailingDot { result += "." }
  ///     return true
  ///   }
  ///   return success ? result : nil
  /// }
  /// ```
  ///
  /// And then we would use that function to decide how to display the domain:
  ///
  /// ```swift
  /// RenderDomain("x.example.com")
  /// // ✅ "x.example.com" (ASCII)
  ///
  /// RenderDomain("shop.xn--igbi0gl.com")
  /// // ✅ "shop.أهلا.com"
  ///
  /// RenderDomain("åpple.com")
  /// // ✅ "xn--pple-poa.com", NOT "åpple.com"
  ///
  /// RenderDomain("xn--citibank.com")
  /// // ✅ "岍岊岊岅岉岎.com" NOT "xn--citibank.com"
  /// ```
  ///
  /// If an error occurs, the function will stop processing the domain and return `false`,
  /// and any previously-written data should be discarded. The callback closure can also
  /// signal a validation error and halt further processing by returning `false`.
  ///
  /// ### UTS46 Parameters
  ///
  /// This function implements `"domain to Unicode"` as defined by the [WHATWG URL Standard][WHATWG-ToUnicode].
  /// It is the same as the `ToUnicode` function defined by [Unicode Technical Standard #46][UTS46-ToUnicode],
  /// with parameters bound as follows:
  ///
  /// - `CheckHyphens` is `false`
  /// - `CheckBidi` is `true`
  /// - `CheckJoiners` is `true`
  /// - `UseSTD3ASCIIRules` is `false`
  /// - `Transitional_Processing` is `false`
  ///
  /// [WHATWG-ToUnicode]: https://url.spec.whatwg.org/#concept-domain-to-unicode
  /// [UTS46-ToUnicode]: https://www.unicode.org/reports/tr46/#ToUnicode
  /// [UTR36]: https://www.unicode.org/reports/tr36/
  /// [UTS39]: https://www.unicode.org/reports/tr39/
  ///
  /// - parameters:
  ///   - utf8:   A domain in either Unicode or ASCII form, expressed as a Collection of UTF-8 code-units.
  ///   - writer: A closure which receives the domain labels emitted by this function.
  ///             The labels should be written in the order they are received, and if `needsTrailingDot` is true,
  ///             the label should be followed by U+002E FULL STOP ("."). Processing continues for as long as
  ///             the closure returns `true`; meaning that it may perform validation, and may signal that processing
  ///             should stop by returning `false`.
  ///
  /// - returns: Whether or not the operation was successful.
  ///            If `false`, the given domain is not valid, and any data previously yielded to `writer`
  ///            should be discarded.
  ///
  @inlinable
  public static func toUnicode<Source>(
    utf8 source: Source, writer: (_ label: AnyRandomAccessCollection<Unicode.Scalar>, _ needsTrailingDot: Bool) -> Bool
  ) -> Bool where Source: Collection, Source.Element == UInt8 {
    return process(utf8: source, useSTD3ASCIIRules: false) { label, needsTrailingDot in
      writer(AnyRandomAccessCollection(label), needsTrailingDot)
    }
  }

  /// Converts a domain to its canonical ASCII form.
  ///
  /// The domain may be given in ASCII or Unicode form. This function will perform all required
  /// compatibility processing, including mapping and case-folding, normalization, Punycode decoding, etc.
  /// Finally, each label and the entire domain are validated, and the result is encoded as ASCII using
  /// the Punycode encoding.
  ///
  /// This function is idempotent, so if it is applied to a domain that is already in canonical ASCII form,
  /// it just produces the same value, unchanged.
  ///
  /// ```swift
  /// // ASCII domains.
  /// toASCII("example.com")  // ✅ "example.com"
  ///
  /// // Unicode.
  /// toASCII("we❤️swift")        // ✅ "xn--weswift-z98d"
  /// toASCII("api.你好你好.com")  // ✅ "api.xn--6qqa088eba.com"
  ///
  /// // Idempotent.
  /// toASCII("api.xn--6qqa088eba.com") // ✅ "api.xn--6qqa088eba.com"
  ///
  /// // Normalizes Unicode domains.
  /// toASCII("caf\u{00E9}.fr")   // ✅ "xn--caf-dma.fr"
  /// toASCII("cafe\u{0301}.fr")  // ✅ "xn--caf-dma.fr"
  /// ```
  ///
  /// Validation ensures that domains are NFC normalized and case-folded, and enforces some rules
  /// with regards to use of joiners and bidirectional text.
  ///
  /// ```swift
  /// // Zero-width joiners and non-joiners are only allowed in certain contexts.
  /// let notApple = "a\u{200C}pple.com"     // 🥸 Hey! There's a zero-width non-joiner hiding there!
  /// print(notApple)           "a‌pple.com"  // To a human, it looks like "apple.com"
  /// print(notApple == "apple.com")  false  // A computer knows it ISN'T "apple.com"
  /// toASCII("a\u{200C}pple.com")    <nil>  // ❎ Not a valid IDN!
  ///
  /// // "xn--cafe-yvc" is how you would Punycode "cafe\u{0301}" (the non-NFC "café").
  /// // This ensures there is only one "café.fr".
  /// toASCII("xn--caf-dma.fr")   // ✅ "xn--caf-dma.fr" - valid IDN
  /// toASCII("xn--cafe-yvc.fr")  // ❎ <nil> - Not a valid IDN!
  /// ```
  ///
  /// ## Rendering Domains
  ///
  /// Although the ASCII representation is less commonly used to render a domain,
  /// it is still worth considering carefully whether it is an appropriate presentation for the context:
  ///
  /// In particular, note that in situations such as `"岍岊岊岅岉岎.com"` (or `"xn--citibank.com"`),
  /// the ASCII representation may do more to mislead than the Unicode representation. For more information
  /// about rendering domains for display, see ``toUnicode(utf8:writer:)``.
  ///
  /// This function emits the ASCII bytes of the result using a callback closure. To construct the full domain,
  /// the bytes can be written to a buffer or appended to a string as individual scalars.
  ///
  /// ```swift
  /// func idna_encode(_ input: String) -> String? {
  ///   var buffer = [UInt8]()
  ///   let success = IDNA.toASCII(utf8: input.utf8) { ascii in
  ///     buffer.append(ascii)
  ///   }
  ///   return success ? String(decoding: buffer, as: UTF8.self) : nil
  /// }
  ///
  /// idna_encode("x.example.com")
  /// // ✅ "x.example.com" (ASCII)
  ///
  /// idna_encode("shop.أهلا.com")
  /// // ✅ "shop.xn--igbi0gl.com"
  /// ```
  ///
  /// If an error occurs, the function will stop processing the domain and return `false`,
  /// and any previously-written data should be discarded.
  ///
  /// ### UTS46 Parameters
  ///
  /// This function implements `"domain to ASCII"` as defined by the [WHATWG URL Standard][WHATWG-ToASCII].
  /// It is the same as the `ToASCII` function defined by [Unicode Technical Standard #46][UTS46-ToASCII],
  /// with parameters bound as follows:
  ///
  /// - `CheckHyphens` is `false`
  /// - `CheckBidi` is `true`
  /// - `CheckJoiners` is `true`
  /// - `UseSTD3ASCIIRules` is given by the parameter `beStrict`
  /// - `Transitional_Processing` is `false`
  ///
  /// Additionally, for this implementation, `VerifyDnsLength` is `false`.
  /// URLs do not enforce DNS length limits, so it is not necessary for users of this API who wish to process
  /// domains as URLs do.
  ///
  /// [WHATWG-ToASCII]: https://url.spec.whatwg.org/#concept-domain-to-ascii
  /// [UTS46-ToASCII]: https://www.unicode.org/reports/tr46/#ToASCII
  ///
  /// - parameters:
  ///   - utf8:      A domain in either Unicode or ASCII form, expressed as a Collection of UTF-8 code-units.
  ///   - beStrict:  If `true`, limits allowed domain names as described by STD3/RFC-1122 - i.e. ASCII letters, digits,
  ///                and hyphens only (LHD). URLs do not assume STD3 name restrictions apply, and have a
  ///                less restrictive set of disallowed characters based on URL syntax requirements
  ///                (for example, they allow underscores, such as in `"http://some_hostname/"`, whereas STD3 does not).
  ///                The default is `false`.
  ///   - writer:    A closure which receives the ASCII bytes emitted by this function.
  ///
  /// - returns: Whether or not the operation was successful.
  ///            If `false`, the given domain is not valid, and any data previously yielded to `writer`
  ///            should be discarded.
  ///
  @inlinable
  public static func toASCII<Source>(
    utf8 source: Source, beStrict: Bool = false, writer: (UInt8) -> Void
  ) -> Bool where Source: Collection, Source.Element == UInt8 {

    return process(utf8: source, useSTD3ASCIIRules: beStrict) { label, needsTrailingDot in
      // Encode each validated label to ASCII using Punycode.
      guard Punycode.encode(label, into: writer) else { return false }
      // Join labels with U+002E.
      if needsTrailingDot { writer(UInt8(ascii: ".")) }
      return true
    }
  }
}


// --------------------------------------------
// MARK: - Compatibility Processing
// --------------------------------------------


/// A parameter defined by the UTS46 Specification, which for this implementation is a constant value.
/// For example, `Transitional_Processing` is always `false`.
///
@inlinable @inline(__always)
internal func FixedParameter(_ value: Bool) -> Bool { value }

extension IDNA {

  /// Performs IDNA compatibility processing, as defined by https://www.unicode.org/reports/tr46/#Processing
  ///
  @usableFromInline
  internal static func process<Source>(
    utf8 source: Source, useSTD3ASCIIRules: Bool,
    writer: (_ buffer: ArraySlice<Unicode.Scalar>, _ needsTrailingDot: Bool) -> Bool
  ) -> Bool where Source: Collection, Source.Element == UInt8 {

    // 1 & 2. Map & Normalize.
    var preppedScalars = _MappedAndNormalized(source: source.makeIterator())
    var validationState = DomainValidationState()

    // 3. Break.
    return _breakLabels(consuming: &preppedScalars, checkSourceError: { $0.hasError }) {
      encodedLabel, needsTrailingDot in

      // 4(a). Convert.
      guard let (count, wasDecoded) = _decodePunycodeIfNeeded(&encodedLabel) else { return false }
      let decodedLabel = encodedLabel.prefix(count)

      // 4(b). Validate.
      guard
        _validate(
          label: decodedLabel,
          isKnownMappedAndNormalized: !wasDecoded,
          useSTD3ASCIIRules: useSTD3ASCIIRules,
          state: &validationState)
      else { return false }

      guard !validationState.hasFailure() else { return false }

      // Yield the label.
      return writer(decodedLabel, needsTrailingDot)
    }
  }
}


// --------------------------------------------
// MARK: - 1 & 2 - Map & Normalize
// --------------------------------------------


extension IDNA {

  /// Transforms a stream of UTF-8 bytes to a stream of case-folded, compatibility-mapped, NFC normalized
  /// Unicode scalars.
  ///
  /// This iterator performs the first 2 steps of IDNA Compatibility Processing, as defined by UTS#46 section 4
  /// <https://www.unicode.org/reports/tr46/#Processing>. Similar processing is sometimes referred to as "nameprep".
  /// The mapping is applied with parameters `Transitional_Processing=false`and `UseSTD3ASCIIRules=false`.
  ///
  /// Should any stage of processing encounter an error (for example, if the source contains invalid UTF-8,
  /// or disallowed codepoints), the iterator will terminate and its `hasError` flag will be set.
  ///
  @usableFromInline
  internal struct _MappedAndNormalized<UTF8Bytes>: IteratorProtocol
  where UTF8Bytes: IteratorProtocol, UTF8Bytes.Element == UInt8 {

    @usableFromInline
    internal private(set) var hasError = false

    // Private state.

    @usableFromInline
    internal private(set) var _state = _State.decodeFromSource

    @usableFromInline
    internal private(set) var _source: UTF8Bytes

    @usableFromInline
    internal private(set) var _decoder = UTF8()

    @usableFromInline
    internal private(set) var _normalizationBuffer = ""

    @usableFromInline
    internal private(set) var _nfcIterator: Optional<NFCIterator> = .none

    @inlinable
    internal init(source: UTF8Bytes) {
      self._source = source
    }

    @usableFromInline
    internal enum _State {
      case decodeFromSource
      case map(Unicode.Scalar)
      case feedNormalizer(MappedScalar)
      case sourceConsumed
      case emitNormalized
    }

    @inlinable
    internal mutating func next() -> Unicode.Scalar? {
      while true {
        switch _state {

        // 0. Decode a scalar from the source bytes.
        //
        case .decodeFromSource:
          switch _decoder.decode(&_source) {
          case .scalarValue(let scalar):
            self._state = .map(scalar)
          case .error:
            self.hasError = true
            fallthrough
          case .emptyInput:
            self._state = .sourceConsumed
          }

        // 1. Map the scalar using the UTS46 mapping table.
        //
        case .map(let decodedScalar):
          let mappedScalar = IDNA.mapScalar(decodedScalar)
          switch mappedScalar {
          case .single, .multiple:
            self._state = .feedNormalizer(mappedScalar)
          case .ignored:
            self._state = .decodeFromSource
          case .disallowed:
            self.hasError = true
            self._state = .sourceConsumed
          }

        // 2. Normalize the scalars to NFC.
        //
        // === HACK HACK HACK ===
        //
        // There are 2 ways to do this: using an unstable standard library SPI, or using Foundation.
        // In both cases, the functions accept a String, not an iterator of Unicode scalars - so, we need to
        // consume the entire input source in to a string, mapping everything, normalize that string, then serialize
        // the result as a stream of scalars. It's pretty ugly, ngl.
        //
        // The standard library's implementation is generic and could work directly with a stream of scalars.
        // That's what this design is intended to work with. We would just feed the stream of mapped scalars
        // and it would emit them as a stream of NFC scalars. But we're not there yet.
        //
        // === HACK HACK HACK ===
        //
        // i. Gather the mapped scalar in to a String... then return to '.decodeFromSource' to decode the next scalar.
        //    This will consume the entire input, eventually landing at '.sourceConsumed'.
        //
        case .feedNormalizer(let mappedScalar):
          switch mappedScalar {
          case .single(let scalar):
            _normalizationBuffer.unicodeScalars.append(scalar)
          case .multiple(let idx):
            // String.unicodeScalars.replaceSubrange is faster than append(contentsOf:)
            _normalizationBuffer.unicodeScalars.replaceSubrange(
              Range(uncheckedBounds: (_normalizationBuffer.endIndex, _normalizationBuffer.endIndex)),
              with: idx.get(table: _idna_map_replacements_table)
            )
          default:
            fatalError()
          }
          self._state = .decodeFromSource

        // ii. In an ideal world, this would be a terminal state and always just return `nil`.
        //     As things are, we may have an unprocessed "normalization buffer" (String from [i]).
        //     Now that the input is all consumed, we can do the NFC normalization and forward those scalars.
        //
        case .sourceConsumed:
          if self.hasError {
            return nil
          }
          if !_normalizationBuffer.isEmpty {
            self._nfcIterator = toNFC(_normalizationBuffer)
            self._normalizationBuffer = ""
            self._state = .emitNormalized
            continue
          }
          return nil

        // iii. Yield the NFC scalars, then return to '.sourceConsumed'.
        //
        case .emitNormalized:
          if let next = self._nfcIterator?.next() {
            return next
          }
          self._state = .sourceConsumed
          assert(_normalizationBuffer.isEmpty)
        }
      }
    }
  }
}

@usableFromInline
internal let _idna_db = CodePointDatabase<IDNAMappingData>(
  asciiData: _idna_map_ascii,
  bmpIndex: _idna_map_bmp_index,
  bmpData: (_idna_map_bmp_codepoint, _idna_map_bmp_data),
  nonbmpData: _idna_map_nonbmp
)

extension IDNA {

  /// The result of mapping a scalar from the source contents.
  ///
  @usableFromInline
  internal enum MappedScalar {
    case single(Unicode.Scalar)
    case multiple(ReplacementsTable.Index)
    case ignored
    case disallowed

    @inlinable
    internal static func resolve(_ mapping: IDNAMappingData.UnicodeData.Mapping?, at offset: UInt32) -> MappedScalar {
      switch mapping {
      case .single(let single):
        // ✅ When constructing the status table, we check every in-line scalar value.
        return .single(Unicode.Scalar(_unchecked: single))
      case .rebased(let origin):
        // ✅ When constructing the status table, we check every rebased mapping.
        return .single(Unicode.Scalar(_unchecked: origin &+ offset))
      case .table(let idx):
        return .multiple(idx)
      case .none:
        return .disallowed
      }
    }
  }

  /// Maps a Unicode scalar using the IDNA compatibility mapping table.
  ///
  /// The mapping is always performed with `Transitional_Processing=false` and `UseSTD3ASCIIRules=false`.
  ///
  @inlinable @inline(__always)
  internal static func mapScalar(_ scalar: Unicode.Scalar) -> MappedScalar {

    switch _idna_db[scalar] {
    case .ascii(let entry):
      if entry.isMapped {
        return .single(entry.replacement)
      } else {
        return .single(scalar)
      }
    case .nonAscii(let entry, startCodePoint: let startingCodePointOfEntry):
      switch entry.status {
      case .valid, .deviation, .disallowed_STD3_valid:
        return .single(scalar)
      case .mapped, .disallowed_STD3_mapped:
        let offset = scalar.value &- startingCodePointOfEntry
        return .resolve(entry.mapping, at: offset)
      case .ignored:
        return .ignored
      case .disallowed:
        return .disallowed
      }
    }
  }

  /// Whether the given scalar is valid for use in a domain label.
  ///
  /// From UTS46:
  ///
  /// > 4.1 Validity Criteria
  /// >
  /// > `6`. Each code point in the label must only have certain status values according to Section 5, IDNA Mapping Table:
  /// >    - For Nontransitional Processing, each value must be either valid or deviation.
  ///
  /// https://www.unicode.org/reports/tr46/#Validity_Criteria
  ///
  /// This implementation performs **Nontransitional Processing**, so it returns `true` if the scalar's mapping status
  /// is `valid` or `deviation`, and scalars with status `disallowed_STD3_valid` are considered valid
  /// if `useSTD3ASCIIRules` is `false`. STD3 rules are more restrictive, so turning them off
  /// means to be more lenient.
  ///
  @inlinable
  internal static func _isValidForDomainNT(
    _ scalar: Unicode.Scalar, useSTD3ASCIIRules: Bool
  ) -> Bool {

    switch _idna_db[scalar] {
    case .ascii(let entry):
      switch entry.status {
      case .valid:
        return true
      case .disallowed_STD3_valid:
        return !useSTD3ASCIIRules
      case .mapped:
        return false
      }
    case .nonAscii(let entry, _):
      switch entry.status {
      case .valid, .deviation:
        return true
      case .disallowed_STD3_valid:
        return !useSTD3ASCIIRules
      case .mapped, .disallowed_STD3_mapped, .ignored, .disallowed:
        return false
      }
    }
  }
}

extension Unicode.Scalar {

  @inlinable
  internal init(_unchecked v: UInt32) {
    self = unsafeBitCast(v, to: Unicode.Scalar.self)
  }
}


// --------------------------------------------
// MARK: - 3 - Break
// --------------------------------------------


extension IDNA {

  /// Consumes an iterator of Unicode scalars, gathering its contents in to a buffer which is yielded
  /// at each occurrence of the domain label separator `U+002E FULL STOP (".")`.
  ///
  /// When the source iterator terminates, the `checkSourceError` closure is invoked to check whether
  /// the stream finished due to an error. If so, the function returns `false`.
  ///
  /// The `needsTrailingDot` parameter to the `writer` closure communicates whether the label is being yielded
  /// due to a label separator, or whether it is the remainder. This can be used to write label separators at
  /// the appropriate locations and hence reconstruct the full, normalized domain.
  ///
  @inlinable
  internal static func _breakLabels<Scalars>(
    consuming source: inout Scalars,
    checkSourceError: (Scalars) -> Bool = { _ in false },
    writer: (_ buffer: inout Array<Unicode.Scalar>, _ needsTrailingDot: Bool) -> Bool
  ) -> Bool where Scalars: IteratorProtocol, Scalars.Element == Unicode.Scalar {

    // TODO: Stack allocation? Sometimes?
    var buffer = [Unicode.Scalar]()
    buffer.reserveCapacity(64)

    while let scalar = source.next() {
      if scalar != "." {
        buffer.append(scalar)
      } else {
        guard writer(&buffer, /* needsTrailingDot: */ true) else { return false }
        buffer.removeAll(keepingCapacity: true)
      }
    }
    guard !checkSourceError(source) else {
      return false
    }
    return buffer.isEmpty ? true : writer(&buffer, /* needsTrailingDot: */ false)
  }
}


// --------------------------------------------
// MARK: - 4(a) - Convert
// --------------------------------------------


extension IDNA {

  /// If the given buffer contains a Punycode-encoded domain label, decodes it in-place.
  /// A `nil` result means failure (e.g. nonsense Punycode).
  ///
  @inlinable
  internal static func _decodePunycodeIfNeeded<Buffer>(
    _ buffer: inout Buffer
  ) -> (count: Int, wasDecoded: Bool)?
  where Buffer: RandomAccessCollection & MutableCollection, Buffer.Element == Unicode.Scalar {

    switch Punycode.decodeInPlace(&buffer) {
    case .success(let count):
      return (count, wasDecoded: true)
    case .notPunycode:
      return (buffer.count, wasDecoded: false)
    case .failed:
      return nil
    }
  }
}


// --------------------------------------------
// MARK: - 4(b) - Validate
// --------------------------------------------


@usableFromInline
internal let _validation_db = CodePointDatabase<IDNAValidationData>(
  asciiData: _idna_validate_ascii,
  bmpIndex: _idna_validate_bmp_index,
  bmpData: (_idna_validate_bmp_codepoint, _idna_validate_bmp_data),
  nonbmpData: _idna_validate_nonbmp
)

extension IDNA {

  @usableFromInline
  internal struct DomainValidationState {

    @usableFromInline
    internal var isBidiDomain = false

    @usableFromInline
    internal var hasBidiFailure = false

    @inlinable
    internal init() {
    }

    @inlinable
    internal func hasFailure() -> Bool {
      if isBidiDomain {
        return hasBidiFailure
      }
      return false
    }
  }

  @usableFromInline
  enum Bidi_LabelDirection {
    case LTR
    case RTL
  }

  /// Returns whether a domain label satisfies the conditions specified by [UTS46, 4.1 Validity Criteria][uts46].
  ///
  /// This function uses the same parameter values as used by the "domain to ASCII" and "domain to Unicode"
  /// functions in the WHATWG URL Standard:
  ///
  /// - `CheckHyphens` is `false`
  /// - `CheckBidi` is `true`
  /// - `CheckJoiners` is `true`
  /// - `Transitional_Processing` is `false`
  ///
  /// The label is assumed to already be split on U+002E FULL STOP, so that aspect of the validation
  /// criteria is only checked in debug builds.
  ///
  /// [uts46]: https://www.unicode.org/reports/tr46/#Validity_Criteria
  ///
  /// - parameters:
  ///   - label:                      The label to check, as a collection of Unicode code-points.
  ///   - isKnownMappedAndNormalized: If `true`, declares that the label's code-points have not changed since
  ///                                 undergoing compatibility mapping and normalization, so their status
  ///                                 will be assumed valid. **Important:** If the label has been decoded
  ///                                 from Punycode, this must be `false`.
  ///   - useSTD3ASCIIRules:          If a label has _not_ already been mapped and normalized, its code-points
  ///                                 will be checked and must be considered 'valid' by the mapping table.
  ///                                 If this parameter is `true`, code-points with the status `disallowed_STD3_valid`
  ///                                 will be considered **disallowed**; if `false`, they are considered **valid**.
  ///
  @inlinable
  internal static func _validate<Label>(
    label: Label, isKnownMappedAndNormalized: Bool, useSTD3ASCIIRules: Bool, state: inout DomainValidationState
  ) -> Bool where Label: BidirectionalCollection, Label.Element == UnicodeScalar {

    // Parameters.

    let checkHyphens = FixedParameter(false)
    let checkBidi = FixedParameter(true)
    let checkJoiners = FixedParameter(true)

    //  4.1 Validity Criteria
    //
    //  Each of the following criteria must be satisfied for a label:
    //
    //  1. The label must be in Unicode Normalization Form NFC.

    guard isKnownMappedAndNormalized || isNFC(label) else { return false }

    //  2. If CheckHyphens, the label must not contain a U+002D HYPHEN-MINUS character
    //     in both the third and fourth positions.
    //  3. If CheckHyphens, the label must neither begin nor end with a U+002D HYPHEN-MINUS
    //     character.

    if checkHyphens {
      fatalError("CheckHyphens is not supported")
    }

    //  4. The label must not contain a U+002E ( . ) FULL STOP.

    assert(!label.contains("."), "Labels should already be split on U+002E")

    // <5. is checked later>
    //
    //  6. Each code point in the label must only have certain status values
    //     according to Section 5, IDNA Mapping Table: [ ... ]
    //     - For Nontransitional Processing, each value must be either valid or deviation.
    //
    //   Impl. Notes:
    //   -----------
    //
    //   - For things which have been mapped, folded, and NFC-ed already, we don't need to do this
    //     (unless we're doing it to enforce STD3 ASCII rules; see below).
    //
    //   - UseSTD3ASCIIRules should also be considered as part of step 6.
    //     UTS46 doesn't actually say explicitly _where_ you are supposed to enforce UseSTD3ASCIIRules.
    //     We enforce it here, which makes sense and seems to pass all of the tests, so that's good.
    //     Have asked Unicode for clarification.

    if !isKnownMappedAndNormalized || useSTD3ASCIIRules {
      guard label.allSatisfy({ _isValidForDomainNT($0, useSTD3ASCIIRules: useSTD3ASCIIRules) }) else {
        return false
      }
    }

    // -

    var previousScalarInfo = Optional<IDNAValidationData.ValidationFlags>.none
    var bidi_labelDirection = Bidi_LabelDirection.LTR
    var bidi_infoBeforeTrailingNSMs = Optional<IDNAValidationData.ValidationFlags>.none
    var bidi_hasEN = false
    var bidi_hasAN = false

    var idx = label.startIndex
    while idx < label.endIndex {

      let scalar = label[idx]
      let scalarInfo = _validation_db[scalar].value
      defer {
        previousScalarInfo = scalarInfo
        label.formIndex(after: &idx)
      }

      //  5. The label must not begin with a combining mark, that is: General_Category=Mark.

      if idx == label.startIndex, scalarInfo.isMark {
        return false
      }

      //  7. If CheckJoiners, the label must satisfy the ContextJ rules from Appendix A,
      //     in The Unicode Code Points and Internationalized Domain Names for Applications (IDNA) [IDNA2008].
      //     https://www.rfc-editor.org/rfc/rfc5892.html#appendix-A

      joiners: if checkJoiners {

        if scalar.value == 0x200C /* ZERO WIDTH NON-JOINER */ || scalar.value == 0x200D /* ZERO WIDTH JOINER */ {
          guard let previousScalarInfo = previousScalarInfo else {
            return false
          }
          // [Both]: `If Canonical_Combining_Class(Before(cp)) .eq.  Virama Then True;`
          if previousScalarInfo.isVirama {
            break joiners
          }
          // [ZWNJ]: Check contextual rules.
          if scalar.value == 0x200C, _validateContextOfZWNJ(at: idx, in: label) {
            break joiners
          }
          return false
        }

      }

      //  8. If CheckBidi, and if the domain name is a  Bidi domain name, then the label must satisfy
      //     all six of the numbered conditions in [IDNA2008] RFC 5893, Section 2.

      bidi: if checkBidi {

        // A Bidi domain name is a domain name containing at least one character with Bidi_Class R, AL, or AN.
        // See [IDNA2008] RFC 5893, Section 1.4.

        if !state.isBidiDomain {
          switch scalarInfo.bidiInfo {
          case .RorAL, .AN: state.isBidiDomain = true
          default: break
          }
        }

        // "The Bidi Rule" is six rules:
        //
        // 1.  The first character must be a character with Bidi property L, R,
        //     or AL.  If it has the R or AL property, it is an RTL label; if it
        //     has the L property, it is an LTR label.
        //
        // 2.  In an RTL label, only characters with the Bidi properties R, AL,
        //     AN, EN, ES, CS, ET, ON, BN, or NSM are allowed.
        //
        // 3.  In an RTL label, the end of the label must be a character with
        //     Bidi property R, AL, EN, or AN, followed by zero or more
        //     characters with Bidi property NSM.
        //
        // 4.  In an RTL label, if an EN is present, no AN may be present, and
        //     vice versa.
        //
        // 5.  In an LTR label, only characters with the Bidi properties L, EN,
        //     ES, CS, ET, ON, BN, or NSM are allowed.
        //
        // 6.  In an LTR label, the end of the label must be a character with
        //     Bidi property L or EN, followed by zero or more characters with
        //     Bidi property NSM.

        if idx == label.startIndex {

          // [Bidi 1].
          switch scalarInfo.bidiInfo {
          case .L:
            bidi_labelDirection = .LTR
          case .RorAL:
            bidi_labelDirection = .RTL
          default:
            state.hasBidiFailure = true
          }

        } else {

          // (Used by [Bidi 3] and [Bidi 6] later).
          if case .NSM = scalarInfo.bidiInfo {
            if bidi_infoBeforeTrailingNSMs == nil { bidi_infoBeforeTrailingNSMs = previousScalarInfo }
          } else {
            bidi_infoBeforeTrailingNSMs = nil
          }
          switch bidi_labelDirection {
          // [Bidi 5].
          case .LTR:
            switch scalarInfo.bidiInfo {
            case .L, .EN, .ESorCSorETorONorBN, .NSM: break
            default: state.hasBidiFailure = true
            }
          // [Bidi 2].
          case .RTL:
            switch scalarInfo.bidiInfo {
            case .RorAL, .ESorCSorETorONorBN, .NSM: break
            case .AN: bidi_hasAN = true
            case .EN: bidi_hasEN = true
            default: state.hasBidiFailure = true
            }
          }

        }
      }
    }  // while idx < label.endIndex

    bidi: if checkBidi {

      if let lastNonNSM = (bidi_infoBeforeTrailingNSMs ?? previousScalarInfo)?.bidiInfo {
        switch bidi_labelDirection {
        // [Bidi 6].
        case .LTR:
          switch lastNonNSM {
          case .L, .EN: break
          default: state.hasBidiFailure = true
          }
        // [Bidi 3].
        case .RTL:
          switch lastNonNSM {
          case .RorAL, .EN, .AN: break
          default: state.hasBidiFailure = true
          }
        }
      }
      // [Bidi 4].
      if case .RTL = bidi_labelDirection {
        if bidi_hasEN && bidi_hasAN {
          state.hasBidiFailure = true
        }
      }

    }

    // X. Label validation complete.

    return true
  }

  /// Checks contextual rules for `U+200C ZERO WIDTH NON-JOINER`.
  ///
  @inlinable
  internal static func _validateContextOfZWNJ<Label>(
    at joinerIndex: Label.Index, in label: Label
  ) -> Bool where Label: BidirectionalCollection, Label.Element == UnicodeScalar {

    // If RegExpMatch(
    //   (Joining_Type:{L,D})(Joining_Type:T)*\u200C(Joining_Type:T)*(Joining_Type:{R,D})
    // ) Then True;
    // https://www.rfc-editor.org/rfc/rfc5892.html#appendix-A

    var cursor = joinerIndex

    searchForLD: do {
      guard cursor > label.startIndex else { return false }
      while cursor > label.startIndex {
        label.formIndex(before: &cursor)
        switch _validation_db[label[cursor]].value.joiningType {
        case .L, .D: break searchForLD
        case .T: continue
        default: return false
        }
      }
      return false
    }

    cursor = label.index(after: joinerIndex)

    searchForRD: do {
      guard cursor < label.endIndex else { return false }
      while cursor < label.endIndex {
        switch _validation_db[label[cursor]].value.joiningType {
        case .R, .D: return true  // Success ✅
        case .T: break
        default: return false
        }
        label.formIndex(after: &cursor)
      }
      return false
    }
  }
}


// --------------------------------------------
// MARK: - SPIs
// --------------------------------------------
// Technically this whole module is SPI, but these are especially obscure and even less supported.


extension IDNA {

  /// Special-purpose APIs intended for WebURL's support libraries.
  ///
  /// > Important:
  /// > This type, any nested types, and all of their static/member functions, are not considered
  /// > part of this module's supported API. Please **do not use** these APIs.
  /// > They may disappear, or their behavior may change, at any time.
  ///
  public struct _SPIs {}
}

extension IDNA._SPIs {

  /// Whether or not the given scalar has mapping status `disallowed_STD3_valid`.
  ///
  /// > Important:
  /// > This function is not considered part of the module's supported API.
  /// > Please **do not use** it. It may disappear, or its behavior may change, at any time.
  ///
  public static func _isDisallowed_STD3_valid(_ s: Unicode.Scalar) -> Bool {
    switch _idna_db[s] {
    case .ascii(let ascii):
      if case .disallowed_STD3_valid = ascii.status { return true }
    case .nonAscii(let unicode, _):
      if case .disallowed_STD3_valid = unicode.status { return true }
    }
    return false
  }
}
