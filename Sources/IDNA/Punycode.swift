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

public enum Punycode {}

extension Punycode {

  internal static var Base: UInt32 { 36 }
  internal static var TMin: UInt32 { 1 }
  internal static var TMax: UInt32 { 26 }
  internal static var Damp: UInt32 { 700 }
  internal static var Skew: UInt32 { 38 }

  internal static var initial_encode_state: (n: UInt32, bias: UInt32) {
    (n: 0x80, bias: 72)
  }

  /// Returns the encoded value of this scalar, if it is a 'basic' code-point.
  ///
  internal static func basicEncoding(for codepoint: Unicode.Scalar) -> UInt8? {
    codepoint.value < 0x80 ? UInt8(truncatingIfNeeded: codepoint.value) : nil
  }

  internal static func encode_digit(_ val: UInt32) -> UInt8 {
    val < 26 ? (UInt8(ascii: "a") + UInt8(val)) : (UInt8(ascii: "0") + UInt8(val - 26))
    /*  0..25 map to ASCII a..z */
    /* 26..35 map to ASCII 0..9 */
  }

  internal static func calculateAdjustedBias(
    delta: UInt32, countProcessedScalars: UInt32, isFirstAdjustment: Bool
  ) -> UInt32 {

    var delta = delta
    delta = isFirstAdjustment ? delta / Punycode.Damp : delta >> 1
    delta += delta / countProcessedScalars

    var k = UInt32.zero
    while delta > ((Punycode.Base - Punycode.TMin) * Punycode.TMax) / 2 {
      delta /= Punycode.Base - Punycode.TMin;
      k += Punycode.Base
    }
    return k + (Base - TMin + 1) * delta / (delta + Skew)
  }
}

extension Punycode {

  /// Writes the given Unicode string as an ASCII string using the Punycode algorithm.
  ///
  /// Note that it will include the `xn--` prefix if needed.
  ///
  public static func encode<Input>(
    _ input: Input, writer: (UInt8) -> Void
  ) -> Bool where Input: Collection, Input.Element == Unicode.Scalar {

    guard input.contains(where: { basicEncoding(for: $0) == nil }) else {
      for basicScalar in input { writer(UInt8(truncatingIfNeeded: basicScalar.value)) }
      return true
    }

    // 0. Write the "xn--" prefix. Technically this isn't part of Punycode, but whatever.

    writer(UInt8(ascii: "x"))
    writer(UInt8(ascii: "n"))
    writer(UInt8(ascii: "-"))
    writer(UInt8(ascii: "-"))

    // 1. Write the basic code-points and delimiter.

    /// The number of basic (ASCII) code-points in the input string.
    var countBasic = UInt32.zero

    /// The total number of code-points in the input string.
    var countAllScalars = UInt32.zero

    for scalar in input {
      countAllScalars &+= 1
      if let asciiValue = basicEncoding(for: scalar) {
        writer(asciiValue)
        countBasic &+= 1
      }
    }

    if countBasic > 0 {
      writer(UInt8(ascii: "-"))
    }

    // 3. Write the tail encoding the non-basic code-points.

    /// The number of code-points that have been processed.
    var countProcessedScalars = countBasic

    var (n, bias) = initial_encode_state
    var delta     = UInt32.zero

    while countProcessedScalars < countAllScalars {

      // Punycode works with a <codepoint, offset> state, which starts at an initial position
      // and is incremented by a series of deltas, which describe which codepoints to insert at which offsets.

      // i. Find the next smallest codepoint we have to encode, then calculate the delta
      //    which advances the decoder state from <n, 0> (i.e. its current value) to <newCodePoint, 0>.

      do {
        var newCodePoint = UInt32.max
        for scalar in input {
          if scalar.value >= n, scalar.value < newCodePoint {
            newCodePoint = scalar.value
          }
        }
        let fastForwardAmount = (newCodePoint &- n) &* (countProcessedScalars &+ 1)
        let overflow: Bool
        (delta, overflow) = delta.addingReportingOverflow(fastForwardAmount)
        guard !overflow else { return false }
        n = newCodePoint
      }

      // ii. Find the offsets at which the decoder should insert this codepoint when decoding the string.
      //     - For each offset we skip, increment delta.
      //     - For each offset we want to insert, append delta as a 'generalized variable-length integer'
      //       and reset delta to 0.

      for scalar in input {
        if scalar.value < n {
          let overflow: Bool
          (delta, overflow) = delta.addingReportingOverflow(1)
          guard !overflow else { return false }
        }
        if scalar.value == n {
          // Write 'delta' as a base-36 variable length integer using [a-z0-9].
          var q = delta
          var k = Punycode.Base
          while true {
            let t = (k <= bias) ? Punycode.TMin : min(k &- bias, Punycode.TMax)
            if q < t {
              writer(Punycode.encode_digit(q))
              break
            }
            /// The numeric value for the digit, between `0..<36`.
            let digit = t &+ (q &- t) % (Punycode.Base &- t)
            q = (q &- t) / (Punycode.Base &- t)
            k &+= Punycode.Base
            writer(Punycode.encode_digit(digit))
          }
          // Adjust the bias, reset delta, etc. For the next offset/codepoint.
          bias = calculateAdjustedBias(
            delta: delta,
            countProcessedScalars: countProcessedScalars &+ 1,
            isFirstAdjustment: countProcessedScalars == countBasic
          )
          delta = 0
          countProcessedScalars &+= 1
        }
      }

      // iii. Finished processing this codepoint. On to the next one.

      delta &+= 1
      n &+= 1
    }
    return true
  }
}
