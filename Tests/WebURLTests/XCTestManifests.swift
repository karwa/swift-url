#if !canImport(ObjectiveC)
  import XCTest

  extension ASCIITests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__ASCIITests = [
      ("testASCIIDecimalPrinting", testASCIIDecimalPrinting),
      ("testLazyLowercase", testLazyLowercase),
      ("testLazyNewlineAndTabFilter", testLazyNewlineAndTabFilter),
    ]
  }

  extension AlgorithmsTestCase {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__AlgorithmsTestCase = [
      ("testCollectionLongestSubrange", testCollectionLongestSubrange),
      ("testCollectionTrim", testCollectionTrim),
    ]
  }

  extension IPv4AddressTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__IPv4AddressTests = [
      ("testBasic", testBasic),
      ("testInvalid", testInvalid),
      ("testRandom_Parsing", testRandom_Parsing),
      ("testRandom_Serialisation", testRandom_Serialisation),
      ("testTrailingDots", testTrailingDots),
      ("testTrailingZeroes", testTrailingZeroes),
    ]
  }

  extension IPv6AddressTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__IPv6AddressTests = [
      ("testBasic", testBasic),
      ("testCompression", testCompression),
      ("testInvalid", testInvalid),
      ("testRandom_Parsing", testRandom_Parsing),
      ("testRandom_Serialization", testRandom_Serialization),
    ]
  }

  extension ManagedArrayBufferTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__ManagedArrayBufferTests = [
      ("testAppend", testAppend),
      ("testCollectionConformance", testCollectionConformance),
      ("testEmpty", testEmpty),
      ("testHeaderCOW", testHeaderCOW),
      ("testMutableCollection", testMutableCollection),
      ("testReplaceSubrange_inplace", testReplaceSubrange_inplace),
      ("testReplaceSubrange_outOfPlace", testReplaceSubrange_outOfPlace),
      ("testReserveCapacity", testReserveCapacity),
    ]
  }

  extension OtherUtilitiesTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__OtherUtilitiesTests = [
      ("testForbiddenHostCodePoint", testForbiddenHostCodePoint),
      ("testNonURLCodePoints", testNonURLCodePoints),
    ]
  }

  extension PercentEncodingTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__PercentEncodingTests = [
      ("testDualImplementationEquivalence", testDualImplementationEquivalence),
      ("testEncodeSet_Component", testEncodeSet_Component),
      ("testLazyURLDecoded", testLazyURLDecoded),
      ("testTable", testTable),
      ("testURLDecoded", testURLDecoded),
      ("testURLEncoded", testURLEncoded),
      ("testURLFormDecoded", testURLFormDecoded),
      ("testURLFormEncoded", testURLFormEncoded),
    ]
  }

  extension QueryParametersTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__QueryParametersTests = [
      ("testAppend", testAppend),
      ("testAppendSequence", testAppendSequence),
      ("testAssignment", testAssignment),
      ("testDocumentationExamples", testDocumentationExamples),
      ("testEmptyAndNil", testEmptyAndNil),
      ("testGet_Contains", testGet_Contains),
      ("testKeyValuePairsSequence", testKeyValuePairsSequence),
      ("testRemove", testRemove),
      ("testRemoveAll", testRemoveAll),
      ("testSet", testSet),
    ]
  }

  extension SchemeKindTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__SchemeKindTests = [
      ("testDefaultPorts", testDefaultPorts),
      ("testParser", testParser),
    ]
  }

  extension WHATWGTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__WHATWGTests = [
      ("testURLConstructor", testURLConstructor),
      ("testURLSetters_additional", testURLSetters_additional),
      ("testURLSetters", testURLSetters),
    ]
  }

  extension WebURLTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__WebURLTests = [
      ("testCopyOnWrite_nonUnique", testCopyOnWrite_nonUnique),
      ("testCopyOnWrite_unique", testCopyOnWrite_unique),
      ("testDoesNotCreateCannotBeABaseURLs", testDoesNotCreateCannotBeABaseURLs),
      ("testFragment", testFragment),
      ("testHost", testHost),
      ("testHostname", testHostname),
      ("testJSModelSetters", testJSModelSetters),
      ("testOrigin", testOrigin),
      ("testPassword", testPassword),
      ("testPath", testPath),
      ("testPort", testPort),
      ("testQuery", testQuery),
      ("testSchemeSetter", testSchemeSetter),
      ("testURLConstructor", testURLConstructor),
      ("testUsername", testUsername),
    ]
  }

  public func __allTests() -> [XCTestCaseEntry] {
    return [
      testCase(ASCIITests.__allTests__ASCIITests),
      testCase(AlgorithmsTestCase.__allTests__AlgorithmsTestCase),
      testCase(IPv4AddressTests.__allTests__IPv4AddressTests),
      testCase(IPv6AddressTests.__allTests__IPv6AddressTests),
      testCase(ManagedArrayBufferTests.__allTests__ManagedArrayBufferTests),
      testCase(OtherUtilitiesTests.__allTests__OtherUtilitiesTests),
      testCase(PercentEncodingTests.__allTests__PercentEncodingTests),
      testCase(QueryParametersTests.__allTests__QueryParametersTests),
      testCase(SchemeKindTests.__allTests__SchemeKindTests),
      testCase(WHATWGTests.__allTests__WHATWGTests),
      testCase(WebURLTests.__allTests__WebURLTests),
    ]
  }
#endif
