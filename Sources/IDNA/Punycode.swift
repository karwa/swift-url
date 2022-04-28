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

/// Punycode is a simple and efficient transfer encoding syntax designed for use with Internationalized Domain Names
/// in Applications (IDNA). It uniquely and reversibly transforms a Unicode string into an ASCII string.
///
/// Punycode is defined by [RFC-3492][rfc-3492].
///
/// > Note:
/// >
/// > Punycode is only an implementation detail of IDNA, and Punycode encoding or decoding
/// > alone is **not sufficient** to transform an IDN to/from its Unicode presentation.
/// > The functions ``IDNA/IDNA/toASCII(utf8:beStrict:writer:)`` and ``IDNA/IDNA/toUnicode(utf8:beStrict:writer:)``
/// > should be used instead, and their implementation makes use of Punycode where appropriate.
///
/// [rfc-3492]: https://datatracker.ietf.org/doc/html/rfc3492
///
public enum Punycode {}

extension Punycode {

  // Parameters defining the "Punycode" variant of the Bootstring format.

  @inlinable internal static var Base: UInt32 { 36 }
  @inlinable internal static var TMin: UInt32 { 1 }
  @inlinable internal static var TMax: UInt32 { 26 }
  @inlinable internal static var Damp: UInt32 { 700 }
  @inlinable internal static var Skew: UInt32 { 38 }
  @inlinable internal static var InitialDecoderState: (codePoint: UInt32, bias: UInt32) { (codePoint: 0x80, bias: 72) }

  /// Whether this scalar is a 'basic' code-point.
  ///
  /// Basic codepoints are ASCII and may be written directly in a Punycode-encoded label.
  ///
  @inlinable
  internal static func isBasic(_ codepoint: Unicode.Scalar) -> Bool {
    codepoint.value < 0x80
  }

  /// Encodes a number within the range `0..<36` to the ASCII characters `a-z,0-9`.
  ///
  /// For example, `0 => a`, `10 => k`, and `30` returns the ASCII character `"4"` in this number system.
  /// This function returns lowercase characters.
  ///
  /// The given number is assumed to already be within the range `0..<36`. If it is not within that range,
  /// the return value is not specified.
  ///
  @inlinable
  internal static func encode_digit(_ number: UInt32) -> UInt8 {
    let table: StaticString = "abcdefghijklmnopqrstuvwxyz0123456789"
    return table.withUTF8Buffer { $0[Int(min(number, 35))] }
  }

  /// Decodes an ASCII alphanumeric codepoint as a number within the range `0..<36`
  ///
  /// For example, `a => 0`, `K => 10`, and the character `"4"` returns the number `30`.
  /// This function also decodes uppercase ASCII alphas, even though that is not strictly required by IDNA
  /// (domain labels are case-folded before they are decoded anyway).
  ///
  @inlinable
  internal static func decode_digit(_ character: Unicode.Scalar) -> UInt32? {
    switch character {
    case "a"..."z":
      return character.value &- Unicode.Scalar("a").value
    case "0"..."9":
      return 26 &+ (character.value &- Unicode.Scalar("0").value)
    case "A"..."Z":
      return character.value &- Unicode.Scalar("A").value
    default:
      return nil
    }
  }

  // https://datatracker.ietf.org/doc/html/rfc3492#section-6.1
  @inlinable
  internal static func calculateAdjustedBias(
    delta: UInt32, countProcessedScalars: UInt32, isFirstAdjustment: Bool
  ) -> UInt32 {
    // Since most things here are constants, the compiler can provide away most traps by itself.
    assert(countProcessedScalars > 0, "countProcessedScalars should be incremented before adjusting the bias")
    var delta = isFirstAdjustment ? delta / Damp : delta / 2
    delta += delta.dividedReportingOverflow(by: countProcessedScalars).partialValue

    var k = UInt32.zero
    while delta > ((Base - TMin) * TMax) / 2 {
      delta = delta / (Base - TMin)
      k &+= Punycode.Base
    }
    return k &+ (((Base - TMin + 1) &* delta) / (delta + Skew))
  }
}


// --------------------------------------------
// MARK: - Encoding
// --------------------------------------------


extension Punycode {

  /// Encodes the given Unicode domain label as an ASCII Punycode string.
  ///
  /// The encoded label is written by means of the given closure, which is invoked with each ASCII byte
  /// of the result. If the label already consists only of ASCII codepoints, it does not require encoding and
  /// will be passed through unchanged. This also applies to labels that are already Punycode-encoded;
  /// they will not be decoded or valiated by this function and will simply be passed through as they are.
  ///
  /// If the label _does_ require Punycode encoding, the closure will also be invoked to write
  /// the ACE prefix (`"xn--"`).
  ///
  /// ```swift
  /// func encodeDomainLabel(_ input: String) -> String? {
  ///   var asciiString = [UInt8]()
  ///   let success = Punycode.encode(input.unicodeScalars) { byte in
  ///     asciiString.append(byte)
  ///   }
  ///   return success ? String(decoding: asciiString, as: UTF8.self) : nil
  /// }
  ///
  /// encodeDomainLabel("你好你好")  // "xn--6qqa088eba"
  /// ```
  ///
  /// > Note:
  /// >
  /// > Punycode is only an implementation detail of IDNA, and Punycode encoding
  /// > alone is **not sufficient** to construct an Internationalized Domain Name
  /// > from its Unicode presentation. If that is what you are looking to do,
  /// > use the ``IDNA/IDNA/toASCII(utf8:beStrict:writer:)`` function instead.
  ///
  /// - parameters:
  ///   - source:     The string to encode, as a collection of Unicode scalars.
  ///   - writeASCII: A closure which is invoked with each ASCII character of the result.
  ///
  /// - returns: Whether or not the string was successfully encoded.
  ///            If `false`, any data written by `writeASCII` should be discarded.
  ///
  @inlinable
  public static func encode<Source>(
    _ source: Source, into writeASCII: (UInt8) -> Void
  ) -> Bool where Source: Collection, Source.Element == Unicode.Scalar {

    // 1. Make sure there is at least one non-basic codepoint for us to encode.
    //    Otherwise it is empty/ASCII-only and should be passed-through.

    guard !source.isEmpty, source.contains(where: { !isBasic($0) }) else {
      for basicScalar in source { writeASCII(UInt8(truncatingIfNeeded: basicScalar.value)) }
      return true
    }

    // 2. Write the "xn--" ACE prefix.

    writeASCII(UInt8(ascii: "x"))
    writeASCII(UInt8(ascii: "n"))
    writeASCII(UInt8(ascii: "-"))
    writeASCII(UInt8(ascii: "-"))

    // 3. Write the basic code-points and delimiter.

    var countBasicScalars = UInt32.zero
    var countAllScalars = UInt32.zero

    for scalar in source {
      countAllScalars &+= 1
      if isBasic(scalar) {
        writeASCII(UInt8(truncatingIfNeeded: scalar.value))
        countBasicScalars &+= 1
      }
    }

    if countBasicScalars > 0 {
      writeASCII(UInt8(ascii: "-"))
    }

    // From the RFC:
    //
    //  > For example, if the encoder were to verify that no
    //  > input code points exceed M and that the input length does not exceed
    //  > L, then no delta could ever exceed (M - initial_n) * (L + 1), and
    //  > hence no overflow could occur if integer variables were capable of
    //  > representing values that large.
    //  https://datatracker.ietf.org/doc/html/rfc3492#section-6.4
    //
    // The RFC prefers to detect overflow rather than enforcing limits which rule it out,
    // but since the Unicode.Scalar type is already validated, M is already set at 0x10FFFF.
    // Using 32-bit integers, we find (L + 1) = 0xFOF, or L = 3854 scalars to rule out overflow.
    // Every scalar needs at least 1 ASCII char in the output, and we are limited to 63 chars in IDNA anyway,
    // so this is easily enough.

    guard countAllScalars < 0xF0F else {
      return false
    }

    // 3. Write the tail, encoding the non-basic code-points.

    // Punycode works with a { codepoint, offset } state, which starts at an initial { 0x80, 0 }
    // and is incremented by a series of deltas, each of which describes an offset at which to insert the code-point.
    //
    // The deltas are written in codepoint order - i.e. the offsets at which to insert every "a", then every "b",
    // "j", "z", etc..., but for every Unicode code-point in the string. Also, to advance the codepoint, it encodes
    // a big enough delta to wrap around the string N times -- accounting for the fact that the string is actually
    // growing between every delta as we insert codepoints.
    //
    // To encode, we basically simulate that process. Finding codepoints to insert and writing how many steps
    // it took us to get there.

    var delta = UInt32.zero
    var countProcessedScalars = countBasicScalars
    var (codePoint, bias) = InitialDecoderState

    while countProcessedScalars < countAllScalars {

      // i. Find the smallest codepoint we haven't processed yet,
      //    then calculate the delta which advances the state's codepoint to { nextCodePoint, 0 }.

      do {
        var nextCodePoint = UInt32(0x10FFFF)
        for scalar in source {
          if scalar.value >= codePoint, scalar.value < nextCodePoint {
            nextCodePoint = scalar.value
          }
        }
        let stateIncrement = (nextCodePoint &- codePoint) &* (countProcessedScalars &+ 1)
        delta &+= stateIncrement
        codePoint = nextCodePoint
      }

      // ii. Find the offsets at which the decoder should insert this codepoint.
      //     - For each offset it already decoded (value < codepoint),
      //       increment delta to tell it to skip.
      //     - At each offset where the new codepoint occurs (value == codepoint), we want to insert a value.
      //       So write the current value of delta as a variable-length integer, then reset delta to 0.

      for scalar in source {
        if scalar.value < codePoint {
          delta &+= 1
        } else if scalar.value == codePoint {
          var q = delta
          var k = Base
          while true {
            let t = (k <= bias) ? TMin : min(k &- bias, TMax)
            if q < t {
              writeASCII(Punycode.encode_digit(q))
              break
            }
            let digit: UInt32
            (q, digit) = (q &- t).quotientAndRemainder(dividingBy: Base &- t)
            writeASCII(Punycode.encode_digit(digit &+ t))
            k &+= Punycode.Base
          }
          // Adjust the bias, reset delta, etc. For the next offset/codepoint.
          bias = calculateAdjustedBias(
            delta: delta,
            countProcessedScalars: countProcessedScalars &+ 1,
            isFirstAdjustment: countProcessedScalars == countBasicScalars
          )
          delta = 0
          countProcessedScalars &+= 1
        }
      }

      // iii. Finished processing this codepoint. On to the next one.

      delta &+= 1
      codePoint &+= 1
    }
    return true
  }
}


// --------------------------------------------
// MARK: - Decoding
// --------------------------------------------


extension Punycode {

  /// The result of decoding an ASCII Punycode string to Unicode.
  ///
  public enum DecodingResult {

    /// The string was decoded successfully.
    case success

    /// The source string is invalid and could not be decoded.
    case failed

    /// The string lacks the Punycode ACE prefix ("xn--") and has not been decoded.
    case notPunycode
  }

  /// Decodes the given ASCII Punycode label to Unicode.
  ///
  /// The label is decoded in-place. The Punycode algorithm encodes Unicode text by describing a base string
  /// consisting of ASCII scalars; it then encodes a set of steps by which this decoder inserts Unicode scalars
  /// in to that base string.
  ///
  /// The label must contain the ACE prefix (`"xn--"`), otherwise no decoding will be performed
  /// and the function will return `.notPunycode`.
  ///
  /// ```swift
  /// func decodeDomainLabel(_ input: String) -> String? {
  ///   var decoded = Array(input.unicodeScalars)
  ///   if case .failed = Punycode.decodeInPlace(&decoded[...]) {
  ///     return nil  // Nonsense punycode.
  ///   }
  ///   var result = ""
  ///   result.unicodeScalars.append(contentsOf: decoded)
  ///   return result
  /// }
  ///
  /// decodeDomainLabel("xn--6qqa088eba")  // "你好你好"
  /// ```
  ///
  /// > Important:
  /// >
  /// > Punycode is just an implementation detail of IDNA, and decoding is not enough to properly handle
  /// > Internationalized Domain Names (IDNs). If you wish to decode an IDN to its Unicode/display form,
  /// > use the ``IDNA/IDNA/toUnicode(utf8:beStrict:writer:)`` function instead.
  ///
  public static func decodeInPlace(_ buffer: inout ArraySlice<Unicode.Scalar>) -> DecodingResult {
    _decodeInPlace(&buffer)
  }

  // TODO: This isn't ^really^ generic, because it relies on certain index behaviour when mutating.
  //       We need to slightly tweak the way codepoints are inserted so that it doesn't use RRC at all,
  //       and only relies on MutableCollection.

  internal static func _decodeInPlace<Buffer>(
    _ input: inout Buffer
  ) -> DecodingResult
  where
    Buffer: BidirectionalCollection & RangeReplaceableCollection & MutableCollection,
    Buffer.Element == Unicode.Scalar
  {

    // FIXME: (Performance) Move the 'basic' codepoints up manually and leave the tail where it is.
    guard input.starts(with: ["x", "n", "-", "-"]) else { return .notPunycode }
    input.removeFirst(4)

    var tailReadCursor: Buffer.Index
    var countProcessedScalars: UInt32
    let suffixScalarsToRemove: Int

    // Split the input in to 'basic' (ASCII) codepoints (if there are any), and the tail.

    if let tailDelimiter = input.lastIndex(of: "-") {
      tailReadCursor = input.index(after: tailDelimiter)
      countProcessedScalars = UInt32(input.distance(from: input.startIndex, to: tailDelimiter))
      suffixScalarsToRemove = input.distance(from: tailDelimiter, to: input.endIndex)
      // Validate the basic codepoints.
      guard !input.prefix(upTo: tailDelimiter).contains(where: { !isBasic($0) }) else {
        return .failed
      }

    } else {
      tailReadCursor = input.startIndex
      countProcessedScalars = 0
      suffixScalarsToRemove = input.count
    }

    // Consume the tail, inserting scalars among the basic codepoints where it tells us to.

    var insertionPoint = input.startIndex
    var (codePoint, bias) = InitialDecoderState

    while tailReadCursor < input.endIndex {

      // Decode a variable-length integer into delta.

      var delta = UInt32.zero
      do {
        var (weight, k) = (UInt32(1), Base)
        while true {
          guard tailReadCursor < input.endIndex, let digit = decode_digit(input[tailReadCursor]) else { return .failed }
          input.formIndex(after: &tailReadCursor)

          guard digit <= (.max &- delta).dividedReportingOverflow(by: weight).partialValue else { return .failed }
          delta &+= digit &* weight

          let t = (k <= bias) ? TMin : min(k &- bias, TMax)
          if digit < t { break }

          let weight_overflow: Bool
          (weight, weight_overflow) = weight.multipliedReportingOverflow(by: Base &- t)
          guard !weight_overflow else { return .failed }
          k &+= Base
        }
      }

      // Adjust bias for the next integer.

      countProcessedScalars += 1
      bias = calculateAdjustedBias(
        delta: delta,
        countProcessedScalars: countProcessedScalars,
        isFirstAdjustment: insertionPoint == input.startIndex
      )

      // Increment the { codePoint, insertionPoint } state by 'delta'.

      do {
        let distanceToEnd = countProcessedScalars &- UInt32(input.distance(from: input.startIndex, to: insertionPoint))
        if delta < distanceToEnd {
          // Same codepoint, repeated at a different offset.
          input.formIndex(&insertionPoint, offsetBy: Int(delta))
        } else {
          // Different codepoint.
          delta &-= distanceToEnd
          let (codepointDelta, insertionOffset) = delta.quotientAndRemainder(dividingBy: countProcessedScalars)

          let codePoint_overflow: Bool
          (codePoint, codePoint_overflow) = codePoint.addingReportingOverflow(1 &+ codepointDelta)
          guard !codePoint_overflow else { return .failed }
          insertionPoint = input.index(input.startIndex, offsetBy: Int(insertionOffset))
        }
      }
      guard let scalar = Unicode.Scalar(codePoint) else { return .failed }

      // Insert the scalar, advancing the tailReadIndex by 1 so it maintains position.
      // FIXME: This is incorrect; neither RRC nor MC allow this. Basically it only works for Array(Slice) and similar.
      // FIXME: Overwrite the tail region rather than insert. This should always result in fewer scalars IIUC.
      input.insert(scalar, at: insertionPoint)
      input.formIndex(after: &tailReadCursor)

      input.formIndex(after: &insertionPoint)
    }

    // Now that the tail has been decoded, it may be removed.
    input.removeLast(suffixScalarsToRemove)
    return .success
  }
}
