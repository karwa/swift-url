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

//@_spi(_Unicode) import Swift

/// A namespace for functions and types relating to Internationalized Domain Names for Applications (IDNA).
///
/// > One of the great strengths of domain names is universality. The URL `http://Apple.com` goes to Apple's website
/// > from anywhere in the world, using any browser.
/// >
/// > Initially, domain names were restricted to ASCII characters. This was a significant burden on people
/// > using other characters. Suppose, for example, that the domain name system had been invented by Greeks,
/// > and one could only use Greek characters in URLs. Rather than `apple.com`, one would have to write something
/// > like `αππλε.κομ`. An English speaker would not only have to be acquainted with Greek characters,
/// > but would also have to pick those Greek letters that would correspond to the desired English letters.
/// > One would have to guess at the spelling of particular words, because there are not exact matches between scripts.
/// >
/// > Most of the world’s population faced this situation until recently, because their languages
/// > use non-ASCII characters. A system was introduced in 2003 for internationalized domain names (IDN).
/// > This system is called Internationalizing Domain Names for Applications, or IDNA for short.
/// >
/// > \- [UTS 46](https://www.unicode.org/reports/tr46/)
///
/// IDNA works by encoding Unicode text as ASCII. The text is validated and case-folded as is typical for domains,
/// but also normalized so that simple ASCII equality of the result corresponds to Unicode canonical equivalence
/// of the presentation forms. Domains have rather severe length limitations stemming from the early days of
/// the internet, so a space-efficient "Punycode" encoding is used to turn the normalized, validated Unicode domain
/// in to an ASCII string.
///
/// The result is not human-readable, and instead, IDNs must be decoded to presentation form.
/// For example, the string `你好你好` becomes `xn--6qqa088eba` when encoded by IDNA. Note that it is not always safe
/// to display a decoded IDN, and developers should check for possible homograph/spoofing attacks before doing so.
/// If in doubt, display it in its Punycode-encoded form rather than decoding it.
///
/// The best thing about IDNA is that domains are encoded on a per-label basis, so `api.你好你好.com`
/// becomes `api.xn--6qqa088eba.com`, and as far as any routing/filtering or other network-related software/hardware
/// is concerned, that is just a standard ASCII domain. It has the same structure, and things like SSL certificates
/// can be matched simply without needing to consider Unicode equivalence of hostnames.
///
/// But despite computers seeing it as an ASCII domain, users can interact with it in their native language. Cool.
///
public enum IDNA {}


// --------------------------------------------
// MARK: - ToASCII
// --------------------------------------------


extension IDNA {

  /// Encodes a domain as an Internationalized Domain Name (IDN).
  ///
  /// The given domain may be in Unicode (or "presentation") form, or already encoded as an IDN string.
  /// This operation is idempotent, so encoding an already-encoded IDN string will simply return the same string,
  /// unchanged.
  ///
  /// This function is defined by the [WHATWG URL Standard][WHATWG-ToASCII], which defers to the function defined in
  /// [UTS #46][UTS46-ToASCII], with parameters bound as follows:
  ///
  /// - `Transitional_Processing` is `false`
  /// - `CheckHyphens` is `false`
  /// - `CheckBidi` is `true`
  /// - `CheckJoiners` is `true`
  /// - `UseSTD3ASCIIRules` is given by the parameter `beStrict`
  /// - `VerifyDnsLength` is given by the parameter `beStrict`
  ///
  /// [WHATWG-ToASCII]: https://url.spec.whatwg.org/#concept-domain-to-ascii
  /// [UTS46-ToASCII]: https://www.unicode.org/reports/tr46/#ToASCII
  ///
  public static func toASCII<Source>(
    utf8 source: Source, beStrict: Bool = false, writer: (UInt8) -> Void
  ) -> Bool where Source: Collection, Source.Element == UInt8 {

    var prepped = CompatibilityMappedAndNormalized(source: source.makeIterator(), useSTD3ASCIIRules: beStrict)
    return _bufferLabels(&prepped, capLength: beStrict) { iter, label, isLast in
      guard !iter.hasError, checkAndEncodeLabel(label, verifyDNSLength: beStrict, writer: writer) else {
        return false
      }
      if !isLast {
        writer(UInt8(ascii: "."))
      }
      return true
    }
  }
}


// --------------------------------------------
// MARK: - Mapping and Normlization
// --------------------------------------------


extension IDNA {

  /// An iterator of mapped and normalized Unicode.Scalars, decoded from a source collection of UTF-8 bytes.
  ///
  /// This iterator performs the first 2 steps of IDNA Compatibility Processing, as defined by UTS#46 section 4
  /// <https://www.unicode.org/reports/tr46/#Processing>. The input is expressed as UTF-8 code-units, which will be
  /// decoded in to Unicode code-points, mapped according to the IDNA mapping table, normalized to NFC, and
  /// yielded individually as a stream of Unicode code-points.
  ///
  /// This is approximately what RFC-3491 (IDNA-2003) calls "Nameprep". It essentially NFKC-CaseFolds
  /// the string, although it does have some additional mappings and ignored/disallowed code-points.
  ///
  /// Should stage of the processing pipeline encounter an error (for example, if the source contains invalid UTF-8
  /// or disallowed code-points), the iterator's `hasError` flag will be set.
  ///
  /// > Important:
  /// > The iterator may _or may not_ terminate on encountering an error, so this flag should always be checked.
  ///
  internal struct CompatibilityMappedAndNormalized<Source>: IteratorProtocol
  where Source: IteratorProtocol, Source.Element == UInt8 {

    internal var source: Source
    internal var useSTD3ASCIIRules: Bool

    internal var hasError = false

    internal var _state = State.decodeFromSource
    internal var _decoder = UTF8()

    internal init(source: Source, useSTD3ASCIIRules: Bool) {
      self.source = source
      self.useSTD3ASCIIRules = useSTD3ASCIIRules
    }

    internal enum State {
      case decodeFromSource
      case map(Unicode.Scalar)
      case normalize([Unicode.Scalar])

      case serialize([Unicode.Scalar], index: Int)
      case end
    }

    internal mutating func next() -> Unicode.Scalar? {
      switch _state {

      // 0. Decode another scalar from the source bytes.
      //
      case .decodeFromSource:
        switch _decoder.decode(&source) {
        case .scalarValue(let scalar):
          self._state = .map(scalar)
          return next()
        case .error:
          self.hasError = true
          fallthrough
        case .emptyInput:
          self._state = .end
          return nil
        }

      // 1. Map the code-points using the IDNA mapping table.
      //
      case .map(let decodedScalar):
        switch IDNA.getScalarMapping(decodedScalar, useSTD3ASCIIRules: useSTD3ASCIIRules) {
        case .valid:
          self._state = .normalize([decodedScalar])
        case .mapped(let replacements):
          self._state = .normalize(replacements)
        case .skipped:
          self._state = .decodeFromSource
        case .invalid:
          self.hasError = true
          self._state = .end
          return nil
        }
        return next()

      // 2. Normalize the resulting string to NFC.
      //
      case .normalize(let mappedScalars):
        // TODO: Use standard library's NFC normalization. It will allocate a buffer, but perhaps we can pre-allocate it?
        self._state = .serialize(mappedScalars, index: 0)
        return next()

      // X. Yield each of the resulting scalar(s), then decode a new one from the source.
      //
      case .serialize(let scalars, index: let position):
        if position < scalars.endIndex {
          self._state = .serialize(scalars, index: position + 1)
          return scalars[position]
        } else {
          self._state = .decodeFromSource
          return next()
        }

      // X. End state. Always return nil and remains in the end state.
      case .end:
        return nil
      }
    }
  }
}

extension IDNA {

  internal enum Mapping {
    case valid
    case skipped
    case mapped([Unicode.Scalar])
    case invalid

    static func mapped(_ v: [UInt32]) -> Self {
      // FIXME: Array Map.
      .mapped(v.map { Unicode.Scalar($0)! })
    }
  }

  internal static func getScalarMapping(_ scalar: Unicode.Scalar, useSTD3ASCIIRules: Bool) -> Mapping {

    // Flags.
    let transitionalProcessing = false && unused_option

    // TODO: optimized table lookup. For now linear search, lol.

    lookup: for (codepoints, status, mapping) in _idna_mapping_data_subs.joined() {
      if codepoints.lowerBound > scalar.value {
        return .invalid  // Not found. Assume invalid.
      }
      if codepoints.contains(scalar.value) {
        switch status {
        case .valid:
          return .valid
        case .ignored:
          return .skipped
        case .mapped:
          return .mapped(mapping!)
        case .deviation:
          return transitionalProcessing ? .mapped(mapping!) : .valid
        case .disallowed:
          return .invalid
        case .disallowed_STD3_valid:
          return useSTD3ASCIIRules ? .invalid : .valid
        case .disallowed_STD3_mapped:
          return useSTD3ASCIIRules ? .invalid : .mapped(mapping!)
        }
      }
    }
    fatalError("Did not find a mapping for scalar: \(scalar.value) (\(scalar))")
  }
}


// --------------------------------------------
// MARK: - Label Buffering
// --------------------------------------------


extension IDNA {

  /// Consumes an iterator of Unicode scalars, collecting each domain label in to a buffer which is processed
  /// by the given closure.
  ///
  internal static func _bufferLabels<Source>(
    _ source: inout Source, capLength: Bool,
    writer: (_ source: Source, _ label: [Unicode.Scalar], _ isLast: Bool) -> Bool
  ) -> Bool where Source: IteratorProtocol, Source.Element == Unicode.Scalar {

    // TODO: When capLength = true, we could use a fixed-size stack buffer.

    var labelBuffer = [Unicode.Scalar]()
    while let scalar = source.next() {
      // 3. Break in to domain labels at U+002E FULL STOP (".").
      guard scalar != "." else {
        guard writer(source, labelBuffer, false) else { return false }
        labelBuffer.removeAll(keepingCapacity: true)
        continue
      }
      if capLength {
        guard labelBuffer.count < 63 else { return false }
      }
      labelBuffer.append(scalar)
    }
    return writer(source, labelBuffer, true)
  }
}


// --------------------------------------------
// MARK: - Label Validation
// --------------------------------------------


extension IDNA {

  internal static func checkAndEncodeLabel<Label>(
    _ label: Label, verifyDNSLength: Bool, writer: (UInt8) -> Void
  ) -> Bool where Label: BidirectionalCollection, Label.Element == Unicode.Scalar {

    // 4. Validate each label (checkHypens, checkJoiners, checkBidi, etc).
    //
    guard checkLabel(label, verifyDNSLength: verifyDNSLength) else { return false }

    // 5. Encode each label to ASCII with Punycode, write to result.
    //
    guard Punycode.encode(label, writer: writer) else { return false }

    return true
  }

  private static func checkLabel<Source>(
    _ label: Source, verifyDNSLength: Bool
  ) -> Bool where Source: BidirectionalCollection, Source.Element == UnicodeScalar {

    if label.starts(with: ["x", "n", "-", "-"]) {
      // TODO: Decode from Punycode
      // TODO: Validate decoded code-points, but do not map them.

      // > With either Transitional or Nontransitional Processing, sources already in Punycode are validated without mapping.
      // > In particular, Punycode containing Deviation characters, such as href="xn--fu-hia.de" (for fuß.de) is not remapped.
      // > This provides a mechanism allowing explicit use of Deviation characters even during a transition period.

      return false
    }

    // Flags.
    let transitionalProcessing = false && unused_option

    let checkHypens = false && unused_option
    let checkBidi = true && unused_option
    let checkJoiners = true && unused_option

    //  4.1 Validity Criteria
    //
    //  Each of the following criteria must be satisfied for a label:
    //
    //  1. The label must be in Unicode Normalization Form NFC. ✅
    //  2. If CheckHyphens, the label must not contain a U+002D HYPHEN-MINUS character in both the third and fourth positions.
    //  3. If CheckHyphens, the label must neither begin nor end with a U+002D HYPHEN-MINUS character.

    if checkHypens {
      guard label.first != "-", label.last != "-" else {
        return false
      }
      guard !label.dropFirst(2).starts(with: ["-", "-"]) else {
        return false
      }
    }

    //  4. The label must not contain a U+002E ( . ) FULL STOP. ✅
    //  5. The label must not begin with a combining mark, that is: General_Category=Mark.

    switch label.first?.properties.generalCategory {
    case .spacingMark?, .nonspacingMark?, .enclosingMark?: return false
    default: break
    }

    //  6. Each code point in the label must only have certain status values according to Section 5, IDNA Mapping Table: ✅
    //     - For Transitional Processing, each value must be valid.
    //     - For Nontransitional Processing, each value must be either valid or deviation.
    if transitionalProcessing {
      fatalError("We only use non-transitional processing. For transitional processing, further validation is required.")
    }

    //  7. If CheckJoiners, the label must satisify the ContextJ rules from Appendix A,
    //     in The Unicode Code Points and Internationalized Domain Names for Applications (IDNA) [IDNA2008].
    //     https://www.rfc-editor.org/rfc/rfc5892.html#appendix-A

    if checkJoiners {
      for idx in label.indices {
        let scalar = label[idx]
        if scalar.value == 0x200C /* ZERO WIDTH NON-JOINER */ {

          if idx > label.startIndex {
            let previousScalar = label[label.index(before: idx)]
            if previousScalar.properties.canonicalCombiningClass == .virama { continue }
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
            if previousScalar.properties.canonicalCombiningClass == .virama { continue }
          }
          return false

        }
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

    return true
  }
}







// MARK: - Utils



internal var unused_option: Bool { true }
