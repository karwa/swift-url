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

    // 3. Break.
    return _breakLabels(consuming: &preppedScalarsStream, checkSourceError: { $0.hasError }) {
      encodedLabel, needsTrailingDot in

      // TODO: Fast paths.

      // 4(a). Convert.
      guard let (label, wasDecoded) = _decodePunycodeIfNeeded(&encodedLabel) else { return false }

      // 4(b). Validate.
      guard _validate(label: label, isKnownMappedAndNormalized: !wasDecoded) else { return false }

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
  /// <https://www.unicode.org/reports/tr46/#Processing>. Similar procesing is sometimes referred to as "nameprep".
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

    @usableFromInline
    internal enum _State {
      case decodeFromSource

      case map(Unicode.Scalar)

      case normalize([Unicode.Scalar])
      case end
      case serialize([Unicode.Scalar], index: Int)
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
          switch IDNA._getScalarMapping(decodedScalar, useSTD3ASCIIRules: _useSTD3ASCIIRules) {
          case .valid:
            self._state = .normalize([decodedScalar])
          case .mapped(let replacements):
            self._state = .normalize(replacements)
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
        // FIXME: Neither the standard library nor Foundation give us the interface we want here.
        // We end up having to buffer all the mapped scalars as a String just for normalization!
        //
        // === HACK HACK HACK ===

        // a. Gather the mapped scalars in to a String.
        //    Eventually, '.decodeFromSource' will consume all scalars and go to '.end'.
        //
        case .normalize(let mappedScalars):
          if IDNA_MappingAndNormalization_UseStringBufferForNormalization {
            _normalizationBuffer.unicodeScalars.append(contentsOf: mappedScalars)
            self._state = .decodeFromSource
          } else {
            // Normalization disabled!
            self._state = .serialize(mappedScalars, index: 0)
          }

        // b. End state. This is *SUPPOSED* to always return nil and remain in the end state.
        //    But if we have an unprocessed "normalization buffer" (String from [a]), we have to flush it.
        //
        case .end:
          if !self.hasError && !_normalizationBuffer.isEmpty {
            self._state = .serialize(toNFC(_normalizationBuffer), index: 0)
            _normalizationBuffer = ""
            continue
          }
          return nil

        // c. Yield each of the resulting NFC scalar(s), then go back to '.decodeFromSource'.
        //
        case .serialize(let scalars, index: let position):
          if position < scalars.endIndex {
            self._state = .serialize(scalars, index: position + 1)
            return scalars[position]
          } else {
            assert(_normalizationBuffer.isEmpty)
            self._state = .decodeFromSource
          }

        // === END HACK HACK HACK (for now) ===
        }
      }
    }
  }
}

// TODO: This needs to actually have a sophisticated implementation.
// - We shouldn't have mappings stored as arrays; they should be offets in to some static data.
// - The lookup table itself needs work. Maybe use the stdlib's MPH stuff? Maybe something else?

extension IDNA {

  @usableFromInline
  internal enum Mapping {
    case disallowed
    case ignored
    case mapped([Unicode.Scalar])
    // (deviation is resolved from transitional_processing)
    case valid

    static func mapped(_ v: [UInt32]) -> Self {
      // FIXME: Array Map.
      .mapped(v.map { Unicode.Scalar($0)! })
    }
  }

  @usableFromInline
  internal static func _getScalarMapping(_ scalar: Unicode.Scalar, useSTD3ASCIIRules: Bool) -> Mapping {
    // Parameters.
    let transitionalProcessing = FixedParameter(false)

    // Lookup.
    // TODO: optimized table lookup. For now linear search, lol.
    lookup: for (codepoints, status, mapping) in _idna_mapping_data_subs.joined() {
      if codepoints.lowerBound > scalar.value {
        return .disallowed  // Not found. Assume invalid.
      }
      if codepoints.contains(scalar.value) {
        switch status {
        case .valid:
          return .valid
        case .ignored:
          return .ignored
        case .mapped:
          return .mapped(mapping!)
        case .deviation:
          return transitionalProcessing ? .mapped(mapping!) : .valid
        case .disallowed:
          return .disallowed
        case .disallowed_STD3_valid:
          return useSTD3ASCIIRules ? .disallowed : .valid
        case .disallowed_STD3_mapped:
          return useSTD3ASCIIRules ? .disallowed : .mapped(mapping!)
        }
      }
    }
    fatalError("Did not find a mapping for scalar: \(scalar.value) (\(scalar))")
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
  internal static func _validateStatus(_ scalar: Unicode.Scalar, transitionalProcessing: Bool) -> Bool {
    precondition(transitionalProcessing == false, "transition processing not implemented")
    // FIXME: It seems that useSTD3ASCIIRules perhaps should be true, as the standard doesn't say to forward it.
    //        But implementations seem to do so.
    //        In any case, we should make it a parameter like getScalarMapping does.
    guard case .valid = _getScalarMapping(scalar, useSTD3ASCIIRules: false) else { return false }
    return true
  }
}


// --------------------------------------------
// MARK: - 3 - Break
// --------------------------------------------


extension IDNA {

  /// Consumes an iterator of Unicode scalars, gathering its contents in to a buffer which is yielded
  /// at each occurence of the domain label separator `U+002E FULL STOP (".")`.
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


extension IDNA {

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
  ///   - label:                      The label to check, as a collection of Unicod code-points.
  ///   - isKnownMappedAndNormalized: If `true`, declares that the label's code-points have not changed since
  ///                                 undergoing compatibility mapping and normalization, so their status
  ///                                 will be assumed valid. **Important:** If the label has been decoded
  ///                                 from Punycode, this must be `false`.
  ///
  @inlinable
  internal static func _validate<Label>(
    label: Label, isKnownMappedAndNormalized: Bool
  ) -> Bool where Label: BidirectionalCollection, Label.Element == UnicodeScalar {

    assert(!Punycode.hasACEPrefix(label), "Punycode labels should be decoded already")

    // Parameters.

    let checkHypens = FixedParameter(false)
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

    if checkHypens {
      preconditionFailure("CheckHyphens is not supported")
    }

    //  4. The label must not contain a U+002E ( . ) FULL STOP.

    assert(!label.contains("."), "Labels should already be split on U+002E")

    //  5. The label must not begin with a combining mark, that is: General_Category=Mark.

    switch label.first?.properties.generalCategory {
    case .spacingMark, .nonspacingMark, .enclosingMark:
      return false
    default:
      break
    }

    //  6. Each code point in the label must only have certain status values
    //     according to Section 5, IDNA Mapping Table:
    //     - For Transitional Processing, each value must be valid.
    //     - For Nontransitional Processing, each value must be either valid or deviation.

    guard
      isKnownMappedAndNormalized
        || label.allSatisfy({ _validateStatus($0, transitionalProcessing: transitionalProcessing) })
    else {
      return false
    }

    var idx = label.startIndex
    while idx < label.endIndex {
      let scalar = label[idx]
      defer { label.formIndex(after: &idx) }

      //  7. If CheckJoiners, the label must satisify the ContextJ rules from Appendix A,
      //     in The Unicode Code Points and Internationalized Domain Names for Applications (IDNA) [IDNA2008].
      //     https://www.rfc-editor.org/rfc/rfc5892.html#appendix-A

      if checkJoiners {
        if scalar.value == 0x200C /* ZERO WIDTH NON-JOINER */ {

          if idx > label.startIndex {
            let previousScalar = label[label.index(before: idx)]
            if case .virama = previousScalar.properties.canonicalCombiningClass { continue }
          }
          // TODO: We also need to add joining data from the UCD.
          // https://www.unicode.org/Public/UCD/latest/ucd/extracted/DerivedJoiningType.txt
          // If RegExpMatch(
          //   (Joining_Type:{L,D})(Joining_Type:T)*\u200C(Joining_Type:T)*(Joining_Type:{R,D})
          // ) Then True;
          return false

        } else if scalar.value == 0x200D /* ZERO WIDTH JOINER */ {

          if idx > label.startIndex {
            let previousScalar = label[label.index(before: idx)]
            if case .virama = previousScalar.properties.canonicalCombiningClass { continue }
          }
          return false
        }
      }

      //  8. If CheckBidi, and if the domain name is a  Bidi domain name, then the label must satisfy
      //     all six of the numbered conditions in [IDNA2008] RFC 5893, Section 2.

      if checkBidi {
        // A Bidi domain name is a domain name containing at least one character with Bidi_Class R, AL, or AN.
        // See [IDNA2008] RFC 5893, Section 1.4.

        // FIXME: We can't do this, but we might be able to unblock some stuff by rejecting Bidi domain names.
        // R = Right-to-left, AL = Right-to-Left Arabic, AN = Arabic Number
        // So we "only" need to detect and reject those codepoints.

        // https://www.unicode.org/Public/UCD/latest/ucd/extracted/DerivedBidiClass.txt
      }
    }

    // X. Validation complete.

    return true
  }
}


// --------------------------------------------
// MARK: - Utils and Shims.
// --------------------------------------------


@inlinable @inline(__always)
internal func FixedParameter(_ value: Bool) -> Bool { value }

// The standard library doesn't currently expose NFC normalization algorithms or data.
//
// Also, the current implementation uses String as its Unicode codepoint source, but
// it is actually written generically and should be able to consume our scalars directly.
// That means we currently have to buffer everything in to a string, but really we'd rather not.

@inlinable @inline(__always)
internal var IDNA_MappingAndNormalization_UseStringBufferForNormalization: Bool { true }

#if USE_SWIFT_STDLIB_UNICODE

  @_spi(_Unicode) import Swift

  @usableFromInline
  func isNFC<C: Collection>(_ scalars: C) -> Bool where C.Element == Unicode.Scalar {
    var s = ""
    s.unicodeScalars.append(contentsOf: scalars)
    if #available(macOS 9999, *) {
      return s._nfc.elementsEqual(scalars)
    } else {
      fatalError()
    }
  }

  @usableFromInline
  func toNFC(_ string: String) -> [Unicode.Scalar] {
    if #available(macOS 9999, *) {
      return Array(string._nfc)
    } else {
      fatalError()
    }
  }

#else

  import Foundation

  @usableFromInline
  func isNFC<C: Collection>(_ scalars: C) -> Bool where C.Element == Unicode.Scalar {
    var str = ""
    str.unicodeScalars.append(contentsOf: scalars)
    return str.precomposedStringWithCanonicalMapping.unicodeScalars.elementsEqual(scalars)
  }

  @usableFromInline
  func toNFC(_ string: String) -> [Unicode.Scalar] {
    Array(string.precomposedStringWithCanonicalMapping.unicodeScalars)
  }

#endif
