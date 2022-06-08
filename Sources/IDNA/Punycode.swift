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
  /// they will not be decoded or validated by this function and will simply be passed through as they are.
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

  /// The result of decoding an ASCII Punycode label to Unicode.
  ///
  public enum DecodeInPlaceResult {

    /// The string was decoded successfully.
    /// It can be found in the first `count` elements of the buffer.
    ///
    case success(count: Int)

    /// The string is invalid and could not be decoded.
    /// The contents of the buffer should be considered invalid and discarded.
    ///
    case failed

    /// The string lacks the Punycode ACE prefix (`"xn--"`) and so has not been decoded.
    ///
    case notPunycode
  }

  /// Whether or not the given buffer begins with the Punycode ACE prefix (`"xn--"`).
  /// This function checks for the prefix case-sensitively.
  ///
  @inlinable
  internal static func hasACEPrefix<Buffer>(
    _ buffer: Buffer
  ) -> Bool where Buffer: Collection, Buffer.Element == Unicode.Scalar {
    var iter = buffer.makeIterator()
    guard iter.next() == "x", iter.next() == "n", iter.next() == "-", iter.next() == "-" else {
      return false
    }
    return true
  }

  /// Decodes the given ASCII Punycode label to Unicode.
  ///
  /// The label, expressed as a buffer of Unicode codepoints, is decoded in-place over the existing contents.
  /// If decoding is successful, the return value ``DecodeInPlaceResult/success(count:)`` communicates
  /// the length of the decoded string within the buffer.
  ///
  /// The label must contain the ACE prefix (`"xn--"`), otherwise no decoding will be performed
  /// and the function will return ``DecodeInPlaceResult/notPunycode``.
  ///
  /// If the label contains the ACE prefix but is ill-formed, or is so long that it would cause
  /// internal calculations to overflow (~3800 scalars), the function will return ``DecodeInPlaceResult/failed``.
  /// The contents of the buffer should be considered invalid and discarded in that case.
  ///
  /// ```swift
  /// func decodeDomainLabel(_ input: String) -> String? {
  ///   var buffer = Array(input.unicodeScalars)
  ///   switch Punycode.decodeInPlace(&buffer) {
  ///   case .success(let count):
  ///     var result = ""
  ///     result.unicodeScalars.append(contentsOf: buffer.prefix(count))
  ///     return result
  ///   case .notPunycode:
  ///     return input // No "xn--" prefix.
  ///   case .failed:
  ///     return nil   // "xn--" prefix but nonsense punycode.
  ///   }
  /// }
  ///
  /// decodeDomainLabel("xn--6qqa088eba")  // "你好你好"
  /// ```
  ///
  /// > Note:
  /// >
  /// > Punycode is just an implementation detail of IDNA, and decoding a domain label is not enough
  /// > to properly handle Internationalized Domain Names (IDNs). If you wish to decode an encoded IDN
  /// > to its Unicode/display form, use the ``IDNA/IDNA/toUnicode(utf8:beStrict:writer:)`` function instead.
  ///
  @inlinable
  public static func decodeInPlace<Buffer>(
    _ buffer: inout Buffer
  ) -> DecodeInPlaceResult where Buffer: RandomAccessCollection & MutableCollection, Buffer.Element == Unicode.Scalar {

    // 1. Make sure there is something for us to decode.
    //    If there is no ACE prefix, we don't consider it a Punycode string.

    guard hasACEPrefix(buffer) else {
      return .notPunycode
    }

    // 2. Find the base string containing the basic (ASCII) codepoints, and copy them to the front.
    //    The rest is the tail, containing a sequence of encoded deltas.

    var tailCursor = buffer.index(buffer.startIndex, offsetBy: 4)
    var countProcessedScalars = UInt32.zero

    if let tailDelimiter = buffer[tailCursor...].lastIndex(of: "-") {
      var src = tailCursor
      var dst = buffer.startIndex
      while src < tailDelimiter {
        guard isBasic(buffer[src]) else { return .failed }
        buffer[dst] = buffer[src]
        buffer.formIndex(after: &src)
        buffer.formIndex(after: &dst)
      }
      tailCursor = buffer.index(after: tailDelimiter)
      countProcessedScalars = UInt32(buffer.distance(from: buffer.startIndex, to: dst))
    }

    // 3. Consume the tail, decoding deltas, which are instructions
    //    to insert a scalar at a "random" (non-sequential) location.

    var insertionPoint = buffer.startIndex
    var (codePoint, bias) = InitialDecoderState

    while tailCursor < buffer.endIndex {

      // 3a. Decode a variable-length integer into delta.

      var delta = UInt32.zero
      do {
        var (weight, k) = (UInt32(1), Base)
        while true {
          guard tailCursor < buffer.endIndex, let digit = decode_digit(buffer[tailCursor]) else { return .failed }
          buffer.formIndex(after: &tailCursor)

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

      // 3b. Process delta.
      //     Use it to adjust the bias for the next integer, then use it to increment our
      //     { codePoint, insertionPoint } state.

      do {
        // Increment 'countProcessedScalars' now even though it is actually written later;
        // it's how Punycode works, and it is important for this to never be zero.
        countProcessedScalars += 1
        bias = calculateAdjustedBias(
          delta: delta,
          countProcessedScalars: countProcessedScalars,
          isFirstAdjustment: insertionPoint == buffer.startIndex
        )

        let stepsToEnd = countProcessedScalars &- UInt32(buffer.distance(from: buffer.startIndex, to: insertionPoint))
        if delta < stepsToEnd {
          // Same codepoint, repeated at a different offset.
          buffer.formIndex(&insertionPoint, offsetBy: Int(delta))
        } else {
          // Different codepoint.
          delta &-= stepsToEnd
          let (codepointDelta, insertionOffset) = delta.quotientAndRemainder(dividingBy: countProcessedScalars)

          let codePoint_overflow: Bool
          (codePoint, codePoint_overflow) = codePoint.addingReportingOverflow(1 &+ codepointDelta)
          guard !codePoint_overflow else { return .failed }
          insertionPoint = buffer.index(buffer.startIndex, offsetBy: Int(insertionOffset))
        }
      }

      guard let scalarToInsert = Unicode.Scalar(codePoint) else { return .failed }

      // 3c. Insert the scalar.
      //     Since we consumed *at least* one scalar from the front of the tail to get this decoded scalar,
      //     we can just move everything after the insertion point down by 1 place, and overwrite the tail
      //     without growing.

      do {
        var src = buffer.index(buffer.startIndex, offsetBy: Int(countProcessedScalars))
        var dst = buffer.index(after: src)
        assert(dst <= tailCursor, "We only write over parts of the tail that have already been consumed")
        while src >= insertionPoint {
          buffer[dst] = buffer[src]
          buffer.formIndex(before: &dst)
          buffer.formIndex(before: &src)
        }
        buffer[insertionPoint] = scalarToInsert
      }

      buffer.formIndex(after: &insertionPoint)
    }

    // 4. Finished.
    //    MutableCollection does not allow us to remove the junk at the end, so return the new length
    //    and let the caller handle that problem.

    return .success(count: Int(countProcessedScalars))
  }
}
