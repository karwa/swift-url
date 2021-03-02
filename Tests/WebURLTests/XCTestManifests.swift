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

  extension PercentEncodingTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__PercentEncodingTests = [
      ("testEncodeSet_Component", testEncodeSet_Component),
      ("testLazyURLDecoded", testLazyURLDecoded),
      ("testURLDecoded", testURLDecoded),
      ("testURLEncoded", testURLEncoded),
      ("testURLFormDecoded", testURLFormDecoded),
      ("testURLFormEncoded", testURLFormEncoded),
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
      ("testHostname", testHostname),
      ("testJSModelSetters", testJSModelSetters),
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
      testCase(IPv4AddressTests.__allTests__IPv4AddressTests),
      testCase(IPv6AddressTests.__allTests__IPv6AddressTests),
      testCase(PercentEncodingTests.__allTests__PercentEncodingTests),
      testCase(SchemeKindTests.__allTests__SchemeKindTests),
      testCase(WHATWGTests.__allTests__WHATWGTests),
      testCase(WebURLTests.__allTests__WebURLTests),
    ]
  }
#endif