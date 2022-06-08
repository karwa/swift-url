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

public enum UTS46Conformance {}


// --------------------------------------------
// MARK: - Test Suite
// --------------------------------------------
// See IdnaTestV2.txt for more information.
// For example: https://www.unicode.org/Public/idna/15.0.0/IdnaTestV2.txt


extension UTS46Conformance: TestSuite {

  public typealias Harness = _UTS46ConformanceTests_Harness

  public struct TestCase: Hashable, CustomReflectable {

    /// The source string, expressed as a collection of UTF-8 code-units.
    /// This data should exactly match the relevant bytes of the test files.
    ///
    public var source: ArraySlice<UInt8>

    /// The expected result of applying `toUnicode` to the source, with `Transitional_Processing=false`.
    /// Other parameters (such as `CheckHyphens`) may be implementation-defined.
    ///
    public var toUnicode: ExpectedResult

    /// The expected result of applying `toASCII` to the source, with `Transitional_Processing=false`.
    /// Other parameters (such as `CheckHyphens`) may be implementation-defined.
    ///
    public var toAsciiN: ExpectedResult

    public struct ExpectedResult: Hashable, CustomReflectable {

      /// The expected result string, expressed as a collection of UTF-8 code-units.
      /// This data should exactly match the relevant bytes of the test files.
      ///
      public var result: ArraySlice<UInt8>

      /// The status-code string, expressed as a collection of UTF-8 code-units.
      /// Contains a serialized list of `FailableValidationSteps`.
      ///
      public var status: ArraySlice<UInt8>

      public var customMirror: Mirror {
        Mirror(
          self,
          children: [
            ("result", String(decoding: result, as: UTF8.self)),
            ("status", String(decoding: status, as: UTF8.self)),
          ])
      }
    }

    /// Parses a TestCase from a line, provided as UTF-8 bytes.
    ///
    /// For more information on the format, see `IdnaTestV2.txt`. Examples of lines which can be parsed:
    ///
    /// ```
    /// bücher.de; ; ; xn--bcher-kva.de; ; ;  # bücher.de
    /// BÜCHER.DE; bücher.de; ; xn--bcher-kva.de; ; ;  # bücher.de
    /// BÜCHER.DE; bücher.de; ; xn--bcher-kva.de; ; ;  # bücher.de
    /// xn--bcher-kva.de; bücher.de; ; xn--bcher-kva.de; ; ;  # bücher.de
    ///
    /// xn--xpb149k.4; ≯ݭ.4; [B1, V6]; xn--xpb149k.4; ; ;  # ≯ݭ.4
    /// ᡲ-𝟹.ß-‌-; ᡲ-3.ß-‌-; [C1, V3]; xn---3-p9o.xn-----fia9303a; ; xn---3-p9o.ss--; [V2, V3] # ᡲ-3.ß--
    /// ᡲ-3.ß-‌-; ; [C1, V3]; xn---3-p9o.xn-----fia9303a; ; xn---3-p9o.ss--; [V2, V3] # ᡲ-3.ß--
    /// ᡲ-3.SS-‌-; ᡲ-3.ss-‌-; [C1, V3]; xn---3-p9o.xn--ss---276a; ; xn---3-p9o.ss--; [V2, V3] # ᡲ-3.ss--
    /// ```
    ///
    public init?(utf8: ArraySlice<UInt8>) {
      let pieces = utf8.split(separator: UInt8(ascii: ";"), maxSplits: 8, omittingEmptySubsequences: false)
      guard pieces.count == 7 else { return nil }

      // Source:
      self.source = pieces[0].trimmingASCIISpaces

      // ToUnicode:
      do {
        // A blank value means the same as the source value.
        var toUnicode = pieces[1].trimmingASCIISpaces
        if toUnicode.isEmpty { toUnicode = source }
        // A blank value means `[]` (no errors).
        var toUnicodeStatus = pieces[2].trimmingASCIISpaces
        if toUnicodeStatus.isEmpty { toUnicodeStatus = ArraySlice("[]".utf8) }
        self.toUnicode = ExpectedResult(result: toUnicode, status: toUnicodeStatus)
      }

      // ToAsciiN:
      do {
        // A blank value means the same as the toUnicode value.
        var toAsciiN = pieces[3].trimmingASCIISpaces
        if toAsciiN.isEmpty { toAsciiN = self.toUnicode.result }
        // A blank value means the same as the toUnicodeStatus value.
        // An explicit [] means no errors.
        var toAsciiNStatus = pieces[4].trimmingASCIISpaces
        if toAsciiNStatus.isEmpty { toAsciiNStatus = self.toUnicode.status }
        self.toAsciiN = ExpectedResult(result: toAsciiN, status: toAsciiNStatus)
      }

      // testcaseString[5], testcaseString[6] contain data for ToAsciiT (Transitional_Processing=true),
      // but we don't care about that.
    }

    public var customMirror: Mirror {
      Mirror(
        self,
        children: [
          ("source", String(decoding: source, as: UTF8.self)),
          ("toUnicode", toUnicode),
          ("toAsciiN", toAsciiN),
        ] as [Mirror.Child])
    }
  }

  public struct CapturedData: Hashable {

    /// The actual result of applying `toUnicode` to the source, with `Transitional_Processing=false`
    /// and other options as specified by the implementation.
    ///
    public var toUnicodeResult: String?

    /// The actual result of applying `toASCII` to the source, with `Transitional_Processing=false`
    /// and other options as specified by the implementation.
    ///
    public var toAsciiNResult: String?
  }

  public enum TestFailure: String, Hashable, CustomStringConvertible {
    case toUnicode = "toUnicode"
    case toAsciiN = "toAsciiN"
  }
}

/// An implementation to be tested using the UTS46 conformance suite.
///
/// The way the Unicode algorithms are structured, all inputs (even erroneous ones) produce a
/// complete output string, and an error flag to indicate that the string is somehow invalid.
/// Operations such as `ToUnicode` and `ToAscii` may also be customized with various parameters
/// (for example, `CheckHyphens`, `CheckBidi`, `CheckJoiners`, and `VerifyDnsLength`), so whether
/// or not an operation produces an error depends on which validation policies the implementation applies.
///
/// Each test case in the conformance test suite does _not_ simply specify an input, parameter values,
/// and expected output (that would require us to implement every unused parameter); instead, it specifies inputs,
/// the complete output string, and a list of processing steps where the domain may/may not fail validation,
/// depending on the implementation.
///
/// This harness works slightly differently: operations such as `toUnicode` and `toAscii` either
/// complete successfully and return a valid string, or return nothing. If they return a result,
/// any validation checks that were expected to fail must be declared "non-applicable". If they do not
/// return a result, there must similarly be an applicable validation check which can be blamed.
///
/// For example, the URL standard does not enforce `VerifyDnsLength`. When applying `toAscii` to a string,
/// if a result is returned, the test database must either not mark `VerifyDnsLength` as a potential problem,
/// or the harness must communicate that `VerifyDnsLength` does not apply to this implementation.
/// If the `toAscii` operation were to fail and the only error the test database expects is from `VerifyDnsLength`,
/// we know to flag this as an overall test failure, because that cannot be the reason this test case failed.
///
public protocol _UTS46ConformanceTests_Harness: TestHarnessProtocol where Suite == UTS46Conformance {

  static var ToUnicode_NonApplicableValidationSteps: Set<UTS46Conformance.FailableValidationSteps> { get }

  func toUnicode<UTF8Bytes>(
    utf8: UTF8Bytes
  ) -> String? where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8

  static var ToAsciiN_NonApplicableValidationSteps: Set<UTS46Conformance.FailableValidationSteps> { get }

  func toAsciiN<UTF8Bytes>(
    utf8: UTF8Bytes
  ) -> String? where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8
}

extension UTS46Conformance {

  // The list of errors in the test file can be found most easily by looking at the Unicode org's generation code:
  //
  // https://github.com/unicode-org/unicodetools/blob/e0437866c91eb1b447b7728c9054c6ed83a3a95b/unicodetools/src/main/java/org/unicode/idna/Uts46.java#L394

  // swift-format-ignore
  /// A step in the toUnicode/toASCII algorithms where an error might be flagged.
  /// See `IdnaTestV2.txt` for more information.
  ///
  public enum FailableValidationSteps: String {
    // Bidi rules.
    case B1 = "B1"
    case B2 = "B2"
    case B3 = "B3"
    case B4 = "B4"
    case B5 = "B5"
    case B6 = "B6"
    // ContextJ rules.
    case C1 = "C1"
    case C2 = "C2"
    // "Processing" steps.
    case P1 = "P1"      // UIDNA_ERROR_DISALLOWED
    case P4 = "P4"      // UIDNA_ERROR_INVALID_ACE_LABEL
    // "Validation" steps.
    case V1 = "V1"      // UIDNA_ERROR_INVALID_ACE_LABEL
    case V2 = "V2"      // UIDNA_ERROR_HYPHEN_3_4
    case V3 = "V3"      // UIDNA_ERROR_LEADING_HYPHEN | UIDNA_ERROR_TRAILING_HYPHEN
    case V4 = "V4"      // UIDNA_ERROR_LABEL_HAS_DOT
    case V5 = "V5"      // UIDNA_ERROR_LEADING_COMBINING_MARK
    case V6 = "V6"      // UIDNA_ERROR_INVALID_ACE_LABEL
    // ToAscii.
    case A3   = "A3"    // UIDNA_ERROR_PUNYCODE
    case A4_1 = "A4_1"  // UIDNA_ERROR_DOMAIN_NAME_TOO_LONG
    case A4_2 = "A4_2"  // UIDNA_ERROR_EMPTY_LABEL | UIDNA_ERROR_LABEL_TOO_LONG
    // Other.
    case NV8  = "NV8"   // UIDNA_NOT_IDNA2008
    case X3   = "X3"    // UIDNA_ERROR_EMPTY_LABEL
    case X4_2 = "X4_2"  // UIDNA_ERROR_EMPTY_LABEL

    public static func parse(_ utf8: ArraySlice<UInt8>) -> [FailableValidationSteps] {
      var utf8 = utf8
      // Trim square brackets, if present.
      if utf8.first == UInt8(ascii: "[") {
        assert(utf8.last == UInt8(ascii: "]"))
        utf8 = utf8.dropFirst().dropLast()
      }
      // Parse each comma-separated value as a step.
      return utf8.split(separator: UInt8(ascii: ",")).map {
        FailableValidationSteps(rawValue: String(decoding: $0.trimmingASCIISpaces, as: UTF8.self))!
      }
    }
  }
}

extension UTS46Conformance.Harness {

  public func _runTestCase(_ testcase: Suite.TestCase, _ result: inout TestResult<Suite>) {

    var captures = Suite.CapturedData()

    // ToUnicode.
    let unicodeResult = Self._runTestCaseSingleOperation(
      sourceUTF8: testcase.source,
      operation: { toUnicode(utf8: $0) },
      nonApplicableValidationErrors: Self.ToUnicode_NonApplicableValidationSteps,
      expected: testcase.toUnicode
    )
    switch unicodeResult {
    case .none:
      break  // OK.
    case .some((failingResult: .some(let actualUnicodeResult), _)):
      captures.toUnicodeResult = actualUnicodeResult
      result.failures.insert(.toUnicode)
    case .some((failingResult: .none, _)):
      captures.toUnicodeResult = nil
      result.failures.insert(.toUnicode)
    }

    // ToAsciiN.
    let asciiNResult = Self._runTestCaseSingleOperation(
      sourceUTF8: testcase.source,
      operation: { toAsciiN(utf8: $0) },
      nonApplicableValidationErrors: Self.ToAsciiN_NonApplicableValidationSteps,
      expected: testcase.toAsciiN
    )
    switch asciiNResult {
    case .none:
      break  // OK.
    case .some((failingResult: .some(let actualAsciiNResult), _)):
      captures.toAsciiNResult = actualAsciiNResult
      result.failures.insert(.toAsciiN)
    case .some((failingResult: .none, _)):
      captures.toAsciiNResult = nil
      result.failures.insert(.toAsciiN)
    }

    result.captures = captures
  }

  private static func _runTestCaseSingleOperation(
    sourceUTF8: ArraySlice<UInt8>,
    operation: (ArraySlice<UInt8>) -> String?,
    nonApplicableValidationErrors: Set<UTS46Conformance.FailableValidationSteps>,
    expected: UTS46Conformance.TestCase.ExpectedResult
  ) -> (failingResult: String?, x: Void)? {

    let steps = UTS46Conformance.FailableValidationSteps.parse(expected.status)
    let isExpectedFailure = steps.contains { !nonApplicableValidationErrors.contains($0) }

    switch operation(sourceUTF8) {
    case .some(let actualResult):
      // Operation returned a result, so to be a success:
      // - All failable validation steps must be non-applicable to this implementation.
      // - The result must equal the expected result.
      guard !isExpectedFailure, expected.result.elementsEqual(actualResult.utf8) else {
        return (failingResult: actualResult, x: ())
      }
      return nil  // Success.
    case .none:
      // Operation failed to return a result, so to be a success:
      // - There must be at least one failable validation step applicable to this implementation.
      guard isExpectedFailure else {
        return (failingResult: nil, x: ())
      }
      return nil  // Success.
    }
  }
}

extension TestHarnessProtocol where Suite == UTS46Conformance {

  public mutating func runTests<Lines>(_ lines: Lines) where Lines: Collection, Lines.Element == ArraySlice<UInt8> {
    var index = 0
    for line in lines {
      // Lines which begin with a '#' are comments.
      guard line.first != UInt8(ascii: "#") else {
        // This is not official, but sometimes there are section dividers.
        // There isn't really a way to distinguish them, except that they are comment lines
        // and are all uppercase ASCII or spaces (e.g. "# BIDI TESTS").
        let comment = line.dropFirst()
        let uppercaseAlphas = (UInt8(ascii: "A")...UInt8(ascii: "Z"))
        if !comment.isEmpty, comment.allSatisfy({ $0 == UInt8(ascii: " ") || uppercaseAlphas.contains($0) }) {
          markSection(String(decoding: comment, as: UTF8.self))
        }
        continue
      }

      // Note: each line also includes a trailing comment after a '#',
      // but since TestCase is only going to use the first 5 segments,
      // we don't even need to bother stripping it.

      guard let testcase = Suite.TestCase(utf8: line) else {
        fatalError("Failed to parse test case: \(line)")
      }
      var result = TestResult<Suite>(testNumber: index, testCase: testcase)
      _runTestCase(testcase, &result)
      reportTestResult(result)
      index += 1
    }
  }
}
