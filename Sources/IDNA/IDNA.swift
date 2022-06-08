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

/// Functions relating to Internationalizing Domain Names for Applications (IDNA).
///
/// IDNA is a way of normalizing and encoding Unicode text as ASCII in a way that is optimized for domain names,
/// compatible with existing DNS infrastructure, and is able to support the important security-related decisions
/// made by inspecting domains.
///
/// The resulting ASCII form is not entirely human-readable, and instead, IDNs must be converted
/// to presentation/Unicode form for display. For example, the string `你好你好` becomes `xn--6qqa088eba` in ASCII form.
/// Note that it is not always safe to display a decoded IDN, and it is wise to include context-specific logic
/// as part of a more sophisticated display strategy.
///
/// This type is a namespace for two APIs, exposed as static functions:
///
/// - ``toUnicode(utf8:writer:)`` performs IDNA compatibility processing, normalization, decoding, validation, etc -
///   in order to produce a domain's Unicode form. This is how you would turn `xn--6qqa088eba.com` in to `你好你好.com`.
///
///   This function visits each label of the domain as a buffer of Unicode scalars, allowing for presentation logic
///   to decide how best to display the label (for example, if the label contains scripts the user does not appear to
///   be familiar with, or mixes scripts, it may be wise to display in Punycode or show some other warning in the UI).
///
/// - ``toASCII(utf8:beStrict:writer:)`` performs the same IDNA compatibility processing as ``toUnicode(utf8:writer:)``,
///   with an additional `beStrict` parameter (not used by URLs). After being normalized, and validated by
///   this processing, the labels are converted to their ASCII form. This turns `你好你好.com` in to `xn--6qqa088eba.com`.
///
/// Both of these APIs are idempotent, so running them on already-normalized output returns the same data.
/// This makes it very convenient to pass a domain through `toUnicode` or `toASCII` as part of existing workflows.
///
/// These APIs follow definitions in the WHATWG URL Standard, which follow definitions in
/// [Unicode Technical Standard #46](https://www.unicode.org/reports/tr46/). See each function's documentation
/// for details on how it relates to UTS46.
///
public enum IDNA {}


// --------------------------------------------
// MARK: - ToUnicode/ToASCII
// --------------------------------------------


extension IDNA {

  /// Converts a domain to its Unicode representation.
  ///
  /// This function performs IDNA Compatibility Processing on the given domain, including
  /// applying a compatibility mapping, normalization, and splitting in to domain labels.
  /// Punycode labels are decoded in to Unicode, and all labels are validated.
  ///
  /// This processing is idempotent, so it may be reapplied without changing the result.
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
  /// // This is how you would Punycode "cafe\u{0301}"
  /// // but that isn't normalized, so it doesn't pass validation.
  /// toUnicode("xn--cafe-yvc.fr")  // ✅ <nil> - Not a valid IDN!
  /// ```
  ///
  /// When rendering a domain for UI, the IDNA Compatibility Processing standard (UTS46)
  /// recommends considering carefully which domain presentation is appropriate for the context:
  ///
  /// > Implementations are advised to apply additional tests to these labels,
  /// > such as those described in [Unicode Technical Report #36][UTR36] and
  /// > [Unicode Technical Standard #39][UTS39], and take appropriate actions.
  /// >
  /// > For example, a label with mixed scripts or confusables may be called out in the UI.
  /// > Note that the use of Punycode to signal problems may be counter-productive,
  /// > as described in [UTR36][UTR36].
  ///
  /// Some sophisticated presentation strategies consider information such as which scripts
  /// the user is familiar with when deciding how to display a domain.
  ///
  /// To facilitate that kind of high-level processing, this function visits each label of the domain
  /// using a callback closure. Labels are provided to the closure as a buffer of Unicode scalars.
  /// After deciding how to present the label, the closure can construct the full domain by appending it
  /// to a String or encoding it with UTF-8/UTF-16/etc, followed by ASCII full-stops (U+002E)
  /// where instructed.
  ///
  /// Let's say we have a function, `DecidePresentationStrategyForLabel`, which decides the best way to render
  /// a domain label in our UI, given our user's locale preferences and other heuristics. Here's how we
  /// could integrate it:
  ///
  /// ```swift
  /// func RenderDomain(_ input: String) -> String? {
  ///
  ///   var result = ""
  ///   let success = IDNA.toUnicode(utf8: input.utf8) { label, needsTrailingDot in
  ///     switch DecidePresentationStrategyForLabel(label) {
  ///     // Unicode presentation.
  ///     case .unicode:
  ///       result.unicodeScalars.append(contentsOf: label)
  ///     // The checker think the Unicode presentation is potentially misleading,
  ///     // and we should write it as Punycode instead.
  ///     case .punycode:
  ///       Punycode.encode(label) { ascii in
  ///         result.unicodeScalars.append(Unicode.Scalar(ascii))
  ///       }
  ///     // Other strategies, beyond Punycode...?
  ///     case .highlightConfusableWithKnownBrand:
  ///       /* ... Maybe use AttributedString to flag it for UI code? */
  ///       /* ... Maybe an extra warning for certain actions, like making a purchase/entering a password? */
  ///     }
  ///
  ///     // Remember the dot :)
  ///     if needsTrailingDot { result += "." }
  ///     return true
  ///   }
  ///   return success ? result : nil
  /// }
  ///
  /// RenderDomain("x.example.com")
  /// // ✅ "x.example.com" (ASCII)
  ///
  /// RenderDomain("shop.xn--igbi0gl.com")
  /// // ✅ "shop.أهلا.com"
  ///
  /// RenderDomain("xn--pple-poa.com")
  /// // ✅ "xn--pple-poa.com", NOT "åpple.com"
  ///
  /// RenderDomain("岍岊岊岅岉岎.com")
  /// // ✅ "岍岊岊岅岉岎.com" NOT "xn--citibank.com"
  /// ```
  ///
  /// If an error occurs, the function will stop processing the domain and return `false`,
  /// and any previously-written data should be discarded. The callback closure can also ask
  /// for processing to stop by returning `false`.
  ///
  /// ### UTS46 Parameters
  ///
  /// This function is defined by the [WHATWG URL Standard][WHATWG-ToUnicode] as `"domain to Unicode"`.
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
  ///   - utf8:   A domain to convert to Unicode, as a Collection of UTF-8 code-units.
  ///   - writer: A closure which receives the labels of the domain emitted by this function.
  ///             The labels should be written in the order they are visited, and if `needsTrailingDot` is true,
  ///             should be followed by U+002E FULL STOP ("."). If this closure returns `false`,
  ///             processing will stop and the function will return `false`.
  ///
  /// - returns: Whether or not the operation was successful.
  ///            If `false`, any data previously yielded to `writer` should be discarded.
  ///
  @inlinable
  public static func toUnicode<Source>(
    utf8 source: Source, writer: (_ label: AnyRandomAccessCollection<Unicode.Scalar>, _ needsTrailingDot: Bool) -> Bool
  ) -> Bool where Source: Collection, Source.Element == UInt8 {
    return process(utf8: source, useSTD3ASCIIRules: false) { label, needsTrailingDot in
      writer(AnyRandomAccessCollection(label), needsTrailingDot)
    }
  }

  /// Converts a domain to its ASCII representation.
  ///
  /// This function performs IDNA Compatibility Processing on the given domain, including
  /// applying a compatibility mapping, normalization, and splitting in to domain labels.
  /// Punycode labels are decoded in to Unicode, and all labels are validated.
  ///
  /// This processing is idempotent, so it may be reapplied without changing the result.
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
  /// // The '-yvc' version is how you would Punycode "cafe\u{0301}"
  /// // but that isn't normalized, so it doesn't pass validation.
  /// toASCII("xn--caf-dma.fr")   // ✅ "xn--caf-dma.fr" - valid IDN
  /// toASCII("xn--cafe-yvc.fr")  // ❎ <nil> - Not a valid IDN!
  /// ```
  ///
  /// Although the ASCII representation is less commonly used to render a domain,
  /// it is still worth considering carefully which domain presentation is appropriate for the context:
  ///
  /// > Implementations are advised to apply additional tests to these labels,
  /// > such as those described in [Unicode Technical Report #36][UTR36] and
  /// > [Unicode Technical Standard #39][UTS39], and take appropriate actions.
  /// >
  /// > For example, a label with mixed scripts or confusables may be called out in the UI.
  /// > Note that the use of Punycode to signal problems may be counter-productive,
  /// > as described in [UTR36][UTR36].
  ///
  /// In particular, note that in situations such as `"岍岊岊岅岉岎.com"` (or `"xn--citibank.com"`),
  /// the ASCII representation may do more to mislead than the Unicode representation. For more information
  /// about rendering domains for display, see ``toUnicode(utf8:writer:)``.
  ///
  /// This function visits the ASCII bytes of the result using a callback closure. To construct the full domain,
  /// the bytes can be converted to scalars and appended to a String, or written to a buffer.
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
  /// This function is defined by the [WHATWG URL Standard][WHATWG-ToASCII] as `"domain to ASCII"`.
  /// It is the same as the `ToASCII` function defined by [Unicode Technical Standard #46][UTS46-ToASCII],
  /// with parameters bound as follows:
  ///
  /// - `CheckHyphens` is `false`
  /// - `CheckBidi` is `true`
  /// - `CheckJoiners` is `true`
  /// - `UseSTD3ASCIIRules` is given by the parameter `beStrict`
  /// - `Transitional_Processing` is `false`
  ///
  /// `VerifyDnsLength` is not implemented, and so is effectively always `false`.
  /// URLs do not enforce DNS' length limits so it is not necessary for current users of this API,
  /// and limiting the length of the written domain can be composed on top of the current design.
  ///
  /// [WHATWG-ToASCII]: https://url.spec.whatwg.org/#concept-domain-to-ascii
  /// [UTS46-ToASCII]: https://www.unicode.org/reports/tr46/#ToASCII
  ///
  /// - parameters:
  ///   - utf8:      An Internationalized Domain Name (IDN) to encode, as a Collection of UTF-8 code-units.
  ///   - beStrict:  Limits allowed domain names as described by STD3/RFC-1122, such as limiting ASCII characters
  ///                to alphanumerics and hyphens. URLs tend to less strict than this, and have their own disallowed
  ///                characters sets (for example, they allow underscores, such as in `"some_hostname"`).
  ///   - writer:    A closure which receives the ASCII bytes emitted by this function.
  ///
  /// - returns: Whether or not the operation was successful.
  ///            If `false`, any data previously yielded to `writer` should be discarded.
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
