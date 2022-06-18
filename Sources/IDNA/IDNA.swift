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
/// > such as zero-width joiners from developer names, otherwise somebody else could register "Go\{200C}ogle"
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
  ///
  /// // IDN validation.
  /// // Zero-width joiners are only allowed in certain contexts.
  /// // Other uses don't pass validation.
  /// let notApple = "a\u{200C}pple.com"     // 🤫 Psst! There's a zero-width joiner hiding there!
  /// print(notApple)           "a‌pple.com"  // To a human, it looks like "apple.com"
  /// print(notApple == "apple.com")  false  // A computer knows it ISN'T "apple.com"
  /// toUnicode("a\u{200C}pple.com")  <nil>  // ❎ Not a valid IDN!
  ///
  /// // "xn--cafe-yvc" is how you would Punycode "cafe\u{0301}" (the non-NFC "café")
  /// // but that doesn't pass validation.
  /// toUnicode("www.caf\u{00E9}.fr")  // ✅ "www.café.fr" ("caf\u{00E9}")
  /// toUnicode("xn--cafe-yvc.fr")     // ❎ <nil> - Not a valid IDN!
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
  /// toASCII("we❤️swift")       // ✅ "xn--weswift-z98d"
  /// toASCII("api.你好你好.com")  // ✅ "api.xn--6qqa088eba.com"
  ///
  /// // Idempotent.
  /// toASCII("api.xn--6qqa088eba.com") // ✅ "api.xn--6qqa088eba.com"
  ///
  /// // Normalizes Unicode domains.
  /// toASCII("caf\u{00E9}.fr")   // ✅ "xn--caf-dma.fr"
  /// toASCII("cafe\u{0301}.fr")  // ✅ "xn--caf-dma.fr"
  ///
  /// // IDN validation.
  /// // Zero-width joiners are only allowed in certain contexts.
  /// // Other uses don't pass validation.
  /// let notApple = "a\u{200C}pple.com"     // 🤫 Psst! There's a zero-width joiner hiding there!
  /// print(notApple)           "a‌pple.com"  // To a human, it looks like "apple.com"
  /// print(notApple == "apple.com")  false  // A computer knows it ISN'T "apple.com"
  /// toASCII("a\u{200C}pple.com")  <nil>    // ❎ Not a valid IDN!
  ///
  /// // "xn--cafe-yvc" is how you would Punycode "cafe\u{0301}" (the non-NFC "café")
  /// // but that doesn't pass validation.
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
    var preppedScalarsStream = _MappedAndNormalized(source: source.makeIterator(), useSTD3ASCIIRules: useSTD3ASCIIRules)

    var validationState = CrossLabelValidationState()

    // 3. Break.
    return _breakLabels(consuming: &preppedScalarsStream, checkSourceError: { $0.hasError }) {
      encodedLabel, needsTrailingDot in

      // TODO: Fast paths.

      // 4(a). Convert.
      guard let (label, wasDecoded) = _decodePunycodeIfNeeded(&encodedLabel) else { return false }

      // 4(b). Validate.
      guard
        _validate(
          label: label, isKnownMappedAndNormalized: !wasDecoded, useSTD3ASCIIRules: useSTD3ASCIIRules,
          state: &validationState)
      else { return false }

      guard validationState.checkFinalValidationState() else { return false }

      // Yield the label.
      return writer(label, needsTrailingDot)
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
    internal private(set) var _useSTD3ASCIIRules: Bool

    @usableFromInline
    internal private(set) var _normalizationBuffer = ""

    @inlinable
    internal init(source: UTF8Bytes, useSTD3ASCIIRules: Bool) {
      self._source = source
      self._useSTD3ASCIIRules = useSTD3ASCIIRules
    }

    @inlinable @inline(__always)
    internal static var DisableNFCNormalization: Bool { false }

    @usableFromInline
    internal enum _State {
      case decodeFromSource

      case map(Unicode.Scalar)

      case normalize(MappedScalar)
      case end
      case serializeNormalized([Unicode.Scalar], index: Int)
      case serializeUnnormalized(MappedScalar, index: Int)
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
            self._state = .end
          }

        // 1. Map the code-points using the IDNA mapping table.
        //
        case .map(let decodedScalar):
          let mappedScalar = IDNA.mapScalar(decodedScalar, useSTD3ASCIIRules: _useSTD3ASCIIRules)
          switch mappedScalar {
          case .single, .multiple:
            self._state = .normalize(mappedScalar)
          case .ignored:
            self._state = .decodeFromSource
          case .disallowed:
            self.hasError = true
            self._state = .end
          }

        // 2. Normalize the resulting stream of code-points to NFC.
        //

        // === HACK HACK HACK ===
        //
        // We have a couple of different paths here.
        //
        // A. Normalize to NFC (like we're supposed to).
        //
        //    There are 2 ways to get this: from an unstable standard library SPI, or from Foundation.
        //    In both cases, the functions accept a String, not a stream of Unicode scalars, so we need to consume
        //    the entire input source, mapping everything, normalize it, and serialize the result as a stream
        //    of scalars. It's a really ugly mess of states. Sorry.
        //
        //    The standard library's implementation is generic and could work directly with a stream of scalars.
        //    That's what this design is intended to work with. We would just feed it scalars on each call to 'next()',
        //    and forward its output.
        //
        // B. Don't normalize to NFC. (See DisableNFCNormalization)
        //
        //    This is not really valid, but is useful for testing because it doesn't force serialization.
        //    That means we process N labels, and might fail on the N+1'th label because of something like a UTF-8
        //    decoding error, which would have been caught much earlier if we serialized everything.
        //
        //    It means more ugly mess of states. Again, sorry.
        //
        // === HACK HACK HACK ===

        // A.i. Gather the mapped scalars in to a String.
        //      Eventually, '.decodeFromSource' will consume all scalars and go to '.end'.
        //
        case .normalize(let mappedScalar):
          guard !Self.DisableNFCNormalization else {
            self._state = .serializeUnnormalized(mappedScalar, index: 0)
            break
          }
          switch mappedScalar {
          case .single(let scalar, _): _normalizationBuffer.unicodeScalars.append(scalar)
          case .multiple(let idx): _normalizationBuffer.unicodeScalars += idx.get(table: _idna_map_replacements_table)
          default: fatalError()
          }
          self._state = .decodeFromSource

        // A.ii. End state. This is *SUPPOSED* to always return nil and remain in the end state.
        //       But if we have an unprocessed "normalization buffer" (String from [a]), we have to flush it.
        //
        case .end:
          if !self.hasError && !_normalizationBuffer.isEmpty {
            self._state = .serializeNormalized(toNFC(_normalizationBuffer), index: 0)
            _normalizationBuffer = ""
            continue
          }
          return nil

        // A.iii. Yield each of the resulting NFC scalar(s), then go back to '.decodeFromSource'.
        //
        case .serializeNormalized(let scalars, index: let position):
          if position < scalars.endIndex {
            self._state = .serializeNormalized(scalars, index: position + 1)
            return scalars[position]
          } else {
            assert(_normalizationBuffer.isEmpty)
            self._state = .decodeFromSource
          }

        // B. Yield non-normalized scalar(s) straight from the mapping table, then go back to '.decodeFromSource'.
        //
        case .serializeUnnormalized(let mappedScalar, index: let position):
          switch mappedScalar {
          case .single(let scalar, _):
            self._state = .decodeFromSource
            return scalar
          case .multiple(let idx):
            if position < idx.length {
              self._state = .serializeUnnormalized(mappedScalar, index: position + 1)
              return idx.get(table: _idna_map_replacements_table)[position]
            } else {
              self._state = .decodeFromSource
            }
          default: fatalError()
          }

        // === END HACK HACK HACK (for now) ===
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
    // TODO: IIRC, it's important for NFC checking to know if this was a deviation character.
    case single(Unicode.Scalar, wasMapped: Bool)
    case multiple(ReplacementsTable.Index)
    case ignored
    case disallowed

    @inlinable
    internal var originalScalarWasValid: Bool {
      if case .single(_, false) = self { return true }
      return false
    }
  }

  /// Maps a Unicode scalar using the IDNA compatibility mapping table.
  ///
  /// The mapping is always performed with `Transitional_Processing=false`.
  ///
  @inlinable @inline(__always)
  internal static func mapScalar(_ scalar: Unicode.Scalar, useSTD3ASCIIRules: Bool) -> MappedScalar {

    switch _idna_db[scalar] {
    case .ascii(let entry):
      if !entry.isMapped {
        if _slowPath(useSTD3ASCIIRules), case .disallowed_STD3_valid = entry.status { return .disallowed }
        return .single(scalar, wasMapped: false)
      } else {
        return .single(entry.replacement, wasMapped: true)
      }

    case .nonAscii(let entry, startCodePoint: let startingCodePointOfEntry):
      func resolve(_ mapping: IDNAMappingData.UnicodeData.Mapping?, at offset: UInt32) -> MappedScalar {
        switch mapping {
        case .single(let single):
          // ✅ When constructing the status table, we check every in-line scalar value.
          return .single(Unicode.Scalar(_unchecked: single), wasMapped: true)
        case .rebased(let origin):
          // ✅ When constructing the status table, we check every rebased mapping.
          return .single(Unicode.Scalar(_unchecked: origin &+ offset), wasMapped: true)
        case .table(let idx):
          return .multiple(idx)
        case .none:
          return .disallowed
        }
      }
      let offset = scalar.value &- startingCodePointOfEntry

      // Parameters.
      let transitionalProcessing = FixedParameter(false)
      // Resolve status.
      switch entry.status {
      case .valid:
        return .single(scalar, wasMapped: false)
      case .deviation:
        return transitionalProcessing && entry.mapping != nil
          ? resolve(entry.mapping, at: offset) : .single(scalar, wasMapped: false)
      case .disallowed_STD3_valid:
        return _slowPath(useSTD3ASCIIRules) ? .disallowed : .single(scalar, wasMapped: false)
      case .mapped:
        return resolve(entry.mapping, at: offset)
      case .disallowed_STD3_mapped:
        return _slowPath(useSTD3ASCIIRules) ? .disallowed : resolve(entry.mapping, at: offset)
      case .ignored:
        return .ignored
      case .disallowed:
        return .disallowed
      }
    }
  }

  /// Whether the code point is valid to be used in a domain label.
  ///
  /// From UTS46:
  ///
  /// > 4.1 Validity Criteria
  /// >
  /// > `6`. Each code point in the label must only have certain status values according to Section 5, IDNA Mapping Table:
  /// >    - For Transitional Processing, each value must be valid.
  /// >    - For Nontransitional Processing, each value must be either valid or deviation.
  /// >
  ///
  /// https://www.unicode.org/reports/tr46/#Validity_Criteria
  ///
  @inlinable
  internal static func _validateStatus(
    _ scalar: Unicode.Scalar, transitionalProcessing: Bool, useSTD3ASCIIRules: Bool
  ) -> Bool {
    precondition(transitionalProcessing == false, "transition processing not implemented")
    return mapScalar(scalar, useSTD3ASCIIRules: useSTD3ASCIIRules).originalScalarWasValid
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
  /// Otherwise, returns the given buffer, unchanged.
  ///
  @inlinable
  internal static func _decodePunycodeIfNeeded<Buffer>(
    _ buffer: inout Buffer
  ) -> (label: Buffer.SubSequence, wasDecoded: Bool)?
  where Buffer: RandomAccessCollection & MutableCollection, Buffer.Element == Unicode.Scalar {

    switch Punycode.decodeInPlace(&buffer) {
    case .success(let count):
      return (buffer.prefix(count), wasDecoded: true)
    case .notPunycode:
      return (buffer[...], wasDecoded: false)
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
  internal struct CrossLabelValidationState {

    @usableFromInline
    internal var isConfirmedBidiDomain = false

    @usableFromInline
    internal var hasBidiFailure = false

    @inlinable
    internal init() {
    }

    @inlinable
    internal func checkFinalValidationState() -> Bool {
      if isConfirmedBidiDomain {
        return !hasBidiFailure
      }
      return true
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
    label: Label, isKnownMappedAndNormalized: Bool, useSTD3ASCIIRules: Bool, state: inout CrossLabelValidationState
  ) -> Bool where Label: BidirectionalCollection, Label.Element == UnicodeScalar {

    // Parameters.

    let checkHyphens = FixedParameter(false)
    let checkBidi = FixedParameter(true)
    let checkJoiners = FixedParameter(true)
    let transitionalProcessing = FixedParameter(false)

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
      preconditionFailure("CheckHyphens is not supported")
    }

    //  4. The label must not contain a U+002E ( . ) FULL STOP.

    assert(!label.contains("."), "Labels should already be split on U+002E")

    // <5. is checked later when we query the validation data>

    //  6. Each code point in the label must only have certain status values
    //     according to Section 5, IDNA Mapping Table:
    //     - For Transitional Processing, each value must be valid.
    //     - For Nontransitional Processing, each value must be either valid or deviation.

    // Note: it is not clear whether or not UseSTD3ASCIIRules should be propagated to this point.
    //       I think so, and some implementations seem to. Have asked for clarification.
    //       https://github.com/whatwg/url/issues/341#issuecomment-1119193904
    guard
      isKnownMappedAndNormalized
        || label.allSatisfy({
          _validateStatus($0, transitionalProcessing: transitionalProcessing, useSTD3ASCIIRules: useSTD3ASCIIRules)
        })
    else {
      return false
    }

    // State for CheckJoiners.
    var previousScalarInfo: IDNAValidationData.ValidationFlags? = nil
    // State for CheckBidi.
    var bidi_labelDirection = Bidi_LabelDirection.LTR
    var bidi_trailingNSMs = 0
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

        if !state.isConfirmedBidiDomain {
          switch scalarInfo.bidiInfo {
          case .RorAL, .AN: state.isConfirmedBidiDomain = true
          default: break
          }
        }

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
          // 1.
          switch scalarInfo.bidiInfo {
          case .L: bidi_labelDirection = .LTR
          case .RorAL: bidi_labelDirection = .RTL
          default: state.hasBidiFailure = true
          }
        } else {
          switch bidi_labelDirection {
          case .LTR:
            // 5.
            switch scalarInfo.bidiInfo {
            case .L, .EN, .ESorCSorETorONorBN, .NSM: break
            default: state.hasBidiFailure = true
            }
          case .RTL:
            // 2.
            switch scalarInfo.bidiInfo {
            case .RorAL, .ESorCSorETorONorBN, .NSM: break
            case .AN: bidi_hasAN = true
            case .EN: bidi_hasEN = true
            default: state.hasBidiFailure = true
            }
          }
        }

        if case .NSM = scalarInfo.bidiInfo {
          bidi_trailingNSMs += 1
        } else {
          bidi_trailingNSMs = 0
        }
      }
    }  // while idx < label.endIndex

    if let lastNonSpace = label.dropLast(bidi_trailingNSMs).last {
      let scalarInfo = _validation_db[lastNonSpace].value.bidiInfo
      switch bidi_labelDirection {
      case .LTR:
        // 6.
        switch scalarInfo {
        case .L, .EN: break
        default: state.hasBidiFailure = true
        }
      case .RTL:
        // 3.
        switch scalarInfo {
        case .RorAL, .EN, .AN: break
        default: state.hasBidiFailure = true
        }
      }
    }

    if case .RTL = bidi_labelDirection {
      // 4.
      if bidi_hasEN && bidi_hasAN {
        state.hasBidiFailure = true
      }
    }

    // X. Validation complete.

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
