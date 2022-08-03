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

import WebURLTestSupport
import XCTest

@testable import WebURL

final class DomainTests: XCTestCase {}


// --------------------------------------------
// MARK: - Protocol conformances
// --------------------------------------------


extension DomainTests {

  func testLosslessStringConvertible() {

    let asciiDomain = WebURL.Domain("example.com")!
    XCTAssertEqual(asciiDomain.description, "example.com")
    XCTAssertEqual(asciiDomain.description, asciiDomain.serialized)
    XCTAssertEqual(String(asciiDomain), asciiDomain.serialized)
    XCTAssertEqual(WebURL.Domain(asciiDomain.description), asciiDomain)

    let asciiDomain2 = WebURL.Domain("EX%61MPlE.cOm")!
    XCTAssertEqual(asciiDomain2.description, "example.com")
    XCTAssertEqual(asciiDomain2.description, asciiDomain2.serialized)
    XCTAssertEqual(String(asciiDomain2), asciiDomain2.serialized)
    XCTAssertEqual(WebURL.Domain(asciiDomain2.description), asciiDomain2)

    let idnDomain = WebURL.Domain("a.xn--igbi0gl.com")!
    XCTAssertEqual(idnDomain.description, "a.xn--igbi0gl.com")
    XCTAssertEqual(idnDomain.description, idnDomain.serialized)
    XCTAssertEqual(String(idnDomain), idnDomain.serialized)
    XCTAssertEqual(WebURL.Domain(idnDomain.description), idnDomain)

    let idnDomain2 = WebURL.Domain("a.أهلا.com")!
    XCTAssertEqual(idnDomain2.description, "a.xn--igbi0gl.com")
    XCTAssertEqual(idnDomain2.description, idnDomain2.serialized)
    XCTAssertEqual(String(idnDomain2), idnDomain2.serialized)
    XCTAssertEqual(WebURL.Domain(idnDomain2.description), idnDomain2)
  }

  func testCodable() throws {

    guard #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) else {
      throw XCTSkip("JSONEncoder.OutputFormatting.withoutEscapingSlashes requires tvOS 13 or newer")
    }

    func roundTripJSON<Value: Codable & Equatable>(
      _ original: Value, expectedJSON: String
    ) throws {
      // Encode to JSON, check that we get the expected string.
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
      let jsonString = String(decoding: try encoder.encode(original), as: UTF8.self)
      XCTAssertEqual(jsonString, expectedJSON)
      // Decode the JSON output, check we get the expected result.
      let decodedValue = try JSONDecoder().decode(Value.self, from: Data(jsonString.utf8))
      XCTAssertEqual(decodedValue, original)
    }

    func fromJSON(_ json: String) throws -> WebURL.Domain {
      try JSONDecoder().decode(WebURL.Domain.self, from: Data(json.utf8))
    }

    domain: do {
      // Values round-trip exactly.
      try roundTripJSON(
        WebURL.Domain("example.com")!,
        expectedJSON:
          #"""
          "example.com"
          """#
      )
      try roundTripJSON(
        WebURL.Domain("a.xn--igbi0gl.com")!,
        expectedJSON:
          #"""
          "a.xn--igbi0gl.com"
          """#
      )
      // When decoding, invalid domains are rejected.
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "hello world"
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "xn--cafe-dma.fr"
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "xn--caf-yvc.fr"
          """#
        )
      )
      // When decoding, values are normalized as domains.
      XCTAssertEqual(
        try fromJSON(
          #"""
          "EX%61MPLE.com"
          """#
        ),
        WebURL.Domain("example.com")
      )
      XCTAssertEqual(
        try fromJSON(
          #"""
          "a.أهلا.com"
          """#
        ),
        WebURL.Domain("a.xn--igbi0gl.com")
      )
    }

    do {
      // Strings which the host parser thinks are other kinds of hosts get rejected.
      // IPv4.
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "192.168.0.1"
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "0x7F.1"
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "0x𝟕f.1"
          """#
        )
      )
      // IPv6.
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "[2001:db8:85a3::8a2e:370:7334]"
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "[2001:0DB8:85A3:0:0:8a2E:0370:7334]"
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "2001:db8:85a3::8a2e:370:7334"
          """#
        )
      )
      // Empty.
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          ""
          """#
        )
      )
    }
  }
}

#if swift(>=5.5) && canImport(_Concurrency)

  extension DomainTests {

    func testSendable() {
      // Since Sendable only exists at compile-time, it's enough to just ensure that this type-checks.
      func _requiresSendable<T: Sendable>(_: T) {}

      let domain = WebURL.Domain("example.com")!
      _requiresSendable(domain)
    }
  }

#endif


// --------------------------------------------
// MARK: - Parsing
// --------------------------------------------


extension DomainTests {

  func testParsing() {

    // Simple ASCII domains.
    test: do {
      var domain = WebURL.Domain("example.com")
      XCTAssertEqual(domain?.serialized, "example.com")
      XCTAssertEqual(domain?.isIDN, false)

      domain = WebURL.Domain("nodots")
      XCTAssertEqual(domain?.serialized, "nodots")
      XCTAssertEqual(domain?.isIDN, false)
    }

    // IDNA.
    test: do {
      var domain = WebURL.Domain("💩.com")
      XCTAssertEqual(domain?.serialized, "xn--ls8h.com")
      XCTAssertEqual(domain?.isIDN, true)

      domain = WebURL.Domain("www.foo。bar.com")
      XCTAssertEqual(domain?.serialized, "www.foo.bar.com")
      XCTAssertEqual(domain?.isIDN, false)

      domain = WebURL.Domain("xn--cafe-dma.com")
      XCTAssertNil(domain)

      domain = WebURL.Domain("xn--caf-yvc.com")
      XCTAssertNil(domain)

      domain = WebURL.Domain("has a space.com")
      XCTAssertNil(domain)
    }

    // IPv4 addresses.
    test: do {
      var domain = WebURL.Domain("11.173.240.13")
      XCTAssertNil(domain)

      domain = WebURL.Domain("0xbadf00d")
      XCTAssertNil(domain)

      domain = WebURL.Domain("0x𝟕f.1")
      XCTAssertNil(domain)

      domain = WebURL.Domain("11.173.240.13.4")
      XCTAssertNil(domain)
    }

    // IPv6 addresses.
    test: do {
      var domain = WebURL.Domain("[::127.0.0.1]")
      XCTAssertNil(domain)

      domain = WebURL.Domain("[blahblahblah]")
      XCTAssertNil(domain)
    }

    // Empty strings.
    test: do {
      let domain = WebURL.Domain("")
      XCTAssertNil(domain)

      // IDNA-mapped to the empty string.
      XCTAssertNil(WebURL.Domain("\u{AD}"))
    }

    // Percent-encoding.
    test: do {
      var domain = WebURL.Domain("www.foo%E3%80%82bar.com")
      XCTAssertEqual(domain?.serialized, "www.foo.bar.com")
      XCTAssertEqual(domain?.isIDN, false)

      domain = WebURL.Domain("%F0%9F%92%A9.com")
      XCTAssertEqual(domain?.serialized, "xn--ls8h.com")
      XCTAssertEqual(domain?.isIDN, true)

      domain = WebURL.Domain("0x%F0%9D%9F%95f.1")
      XCTAssertNil(domain)
    }

    // Localhost.
    do {
      let strings = [
        "localhost",
        "loCAlhost",
        "loc%61lhost",
        "loC𝐀𝐋𝐇𝐨𝐬𝐭",
      ]
      for string in strings {
        let domain = WebURL.Domain(string)
        XCTAssertEqual(domain?.serialized, "localhost")
        XCTAssertEqual(domain?.isIDN, false)
      }
    }

    // Windows drive letters.
    do {
      XCTAssertNil(WebURL.Domain("C:"))
      XCTAssertNil(WebURL.Domain("C|"))
      XCTAssertNil(WebURL.Domain("C%3A"))
      XCTAssertNil(WebURL.Domain("C%7C"))
    }
  }
}


// --------------------------------------------
// MARK: - Rendering
// --------------------------------------------


extension DomainTests {

  func testUncheckedUnicodeString() {

    XCTAssertEqual(WebURL.Domain("localhost")?.render(.uncheckedUnicodeString), "localhost")
    XCTAssertEqual(WebURL.Domain("example.com")?.render(.uncheckedUnicodeString), "example.com")
    XCTAssertEqual(WebURL.Domain("foo.bar.example.com.")?.render(.uncheckedUnicodeString), "foo.bar.example.com.")

    XCTAssertEqual(WebURL.Domain("api.xn--ls8h.com")?.render(.uncheckedUnicodeString), "api.💩.com")
    XCTAssertEqual(WebURL.Domain("api.xn--igbi0gl.com.")?.render(.uncheckedUnicodeString), "api.أهلا.com.")
    // These are spoofs.
    XCTAssertEqual(WebURL.Domain("xn--16-1ik.com")?.render(.uncheckedUnicodeString), "16კ.com")
    XCTAssertEqual(WebURL.Domain("xn--pal-vxc83d5c.com")?.render(.uncheckedUnicodeString), "раγpal.com")

    XCTAssertEqual(
      Array(WebURL.Domain("xn--caf-dma")!.render(.uncheckedUnicodeString).unicodeScalars),
      ["c", "a", "f", "\u{E9}"] as [Unicode.Scalar]
    )
    XCTAssertEqual(
      Array(WebURL.Domain("cafe\u{301}")!.render(.uncheckedUnicodeString).unicodeScalars),
      ["c", "a", "f", "\u{E9}"] as [Unicode.Scalar]
    )
  }

  func testRenderer_earlyExit() {

    // The render function processes domains in 2 phases:
    //
    // 1. Full-domain
    // 2. Per-label
    //
    // If 'readyToReturn' is true after full-domain processing, no labels will be processed.

    struct FullDomainEarlyExit: WebURL.Domain.Renderer {
      var readyToReturn = false
      var result = false

      mutating func processDomain(_ domain: WebURL.Domain) {
        result = true
        readyToReturn = true
      }
      mutating func processLabel(_ label: inout Label, isEnd: Bool) {
        result = false
        XCTFail("Should not be called")
      }
    }

    XCTAssertEqual(WebURL.Domain("example.com")?.render(FullDomainEarlyExit()), true)
    XCTAssertEqual(WebURL.Domain("bar.foo.example.com")?.render(FullDomainEarlyExit()), true)
    XCTAssertEqual(WebURL.Domain("xn--16-1ik.com")?.render(FullDomainEarlyExit()), true)

    // During (2), 'readyToReturn' is checked before every call to processLabel/processASCIILabel.

    struct LabelsEarlyExit: WebURL.Domain.Renderer {
      var maxLabels: UInt
      var result: [String] = []

      var readyToReturn: Bool {
        maxLabels == 0
      }
      mutating func processLabel(_ label: inout Label, isEnd: Bool) {
        XCTAssertGreaterThan(maxLabels, 0)
        maxLabels -= 1
        result.insert(String(label.ascii), at: 0)
      }
    }

    do {
      let domain = WebURL.Domain("bar.xn--e28h.foo.example.com")
      XCTAssertEqual(domain?.render(LabelsEarlyExit(maxLabels: 8)), ["bar", "xn--e28h", "foo", "example", "com"])
      XCTAssertEqual(domain?.render(LabelsEarlyExit(maxLabels: 3)), ["foo", "example", "com"])
      XCTAssertEqual(domain?.render(LabelsEarlyExit(maxLabels: 2)), ["example", "com"])
      XCTAssertEqual(domain?.render(LabelsEarlyExit(maxLabels: 1)), ["com"])
      XCTAssertEqual(domain?.render(LabelsEarlyExit(maxLabels: 0)), [])
    }
  }

  func testRenderLabel_bufferState() {

    // Neither scalar not UTF8 buffers should be allocated unless we access the public '.unicodeScalars'
    // or '.unicode' properties. Even if the domain is an IDN.

    struct BuffersNotAllocated: WebURL.Domain.Renderer {
      var result: Void { () }
      func processLabel(_ label: inout Label, isEnd: Bool) {
        XCTAssert(!label.ascii.isEmpty)
        XCTAssertEqual(label._scalarBufferState, .unreserved)
        XCTAssertEqual(label._scalarBuffer.capacity, 0)
        XCTAssertEqual(label._utf8BufferState, .unreserved)
        XCTAssertEqual(label._utf8Buffer.isEmpty, true)
      }
    }

    WebURL.Domain("bar.xn--e28h.foo.example.com")!.render(BuffersNotAllocated())

    // Check that the buffer is allocated on-demand, that it remains allocated after we asked for it,
    // but that its state gets reset to 'reserved' rather than 'decodedContents'
    // (indicating that the content hasn't been updated)

    struct ScalarBufferAllocatedOnRequest: WebURL.Domain.Renderer {
      // Whether or not the label is expected to be an IDN.
      // The buffer will be allocated at the first IDN label.
      var expected: AnyIterator<Bool>
      var hasAllocated = false
      var result = ""
      mutating func processLabel(_ label: inout Label, isEnd: Bool) {
        guard let nextIsUnicode = expected.next() else {
          XCTFail("Unexpected label - \(label.ascii)")
          return
        }
        XCTAssertEqual(nextIsUnicode, label.isIDN)
        XCTAssert(!label.ascii.isEmpty)
        if hasAllocated {
          XCTAssertEqual(label._scalarBufferState, .reserved)
          XCTAssertGreaterThan(label._scalarBuffer.capacity, 0)
        } else {
          XCTAssertEqual(label._scalarBufferState, .unreserved)
          XCTAssertEqual(label._scalarBuffer.capacity, 0)
        }

        if label.isIDN {
          result.unicodeScalars += label.unicodeScalars
          XCTAssertEqual(label._scalarBufferState, .decodedContents)
          XCTAssertGreaterThan(label._scalarBuffer.capacity, 0)
          hasAllocated = true
        }
      }
    }

    do {
      let result = WebURL.Domain("xn--16-1ik.baz.bar.xn--e28h.foo.example.com")!.render(
        ScalarBufferAllocatedOnRequest(
          expected: AnyIterator([true, false, false, true, false, false, false].reversed().makeIterator())
        ))
      XCTAssertEqual(result, "😀16კ")
    }

    // Same as above, but accessing the '.unicode' UTF8 buffer.

    struct UTF8BufferAllocatedOnRequest: WebURL.Domain.Renderer {
      // Whether or not the label is expected to be an IDN.
      // The buffer will be allocated at the first IDN label.
      var expected: AnyIterator<Bool>
      var hasAllocated = false
      var result = ""
      mutating func processLabel(_ label: inout Label, isEnd: Bool) {
        guard let nextIsUnicode = expected.next() else {
          XCTFail("Unexpected label - \(label.ascii)")
          return
        }
        XCTAssertEqual(nextIsUnicode, label.isIDN)
        XCTAssert(!label.ascii.isEmpty)
        if hasAllocated {
          XCTAssertEqual(label._scalarBufferState, .reserved)
          XCTAssertGreaterThan(label._scalarBuffer.capacity, 0)
          XCTAssertEqual(label._utf8BufferState, .reserved)
          XCTAssertEqual(label._utf8Buffer.isEmpty, false)
        } else {
          XCTAssertEqual(label._scalarBufferState, .unreserved)
          XCTAssertEqual(label._scalarBuffer.capacity, 0)
          XCTAssertEqual(label._utf8BufferState, .unreserved)
          XCTAssertEqual(label._utf8Buffer.isEmpty, true)
        }

        if label.isIDN {
          result += label.unicode + "-"
          XCTAssertEqual(label._scalarBufferState, .decodedContents)
          XCTAssertGreaterThan(label._scalarBuffer.capacity, 0)
          XCTAssertEqual(label._utf8BufferState, .decodedContents)
          XCTAssertEqual(label._utf8Buffer.isEmpty, false)
          hasAllocated = true
        }
      }
    }

    let result = WebURL.Domain("xn--16-1ik.baz.bar.xn--e28h.foo.example.com")!.render(
      UTF8BufferAllocatedOnRequest(
        expected: AnyIterator([true, false, false, true, false, false, false].reversed().makeIterator())
      ))
    XCTAssertEqual(result, "😀-16კ-")
  }

  func testMoreCustomRenderers() {

    // Demo renderer which displays labels containing math symbols in Punycode form.
    // 'isMath' just happens to be a convenient scalar property without standard library availability issues.

    struct NoMath: WebURL.Domain.Renderer {
      var result = ""
      mutating func processLabel(_ label: inout Label, isEnd: Bool) {
        if label.unicodeScalars.contains(where: { $0.properties.isMath }) {
          result.insert(contentsOf: label.ascii, at: result.startIndex)
        } else {
          result.insert(contentsOf: label.unicode, at: result.startIndex)
        }
        if !isEnd { result.insert(".", at: result.startIndex) }
      }
    }

    do {
      var domain = WebURL.Domain("example.com")
      XCTAssertEqual(domain?.render(.uncheckedUnicodeString), "example.com")
      XCTAssertEqual(domain?.render(NoMath()), "example.com")

      domain = WebURL.Domain("xn--ls8h.com")
      XCTAssertEqual(domain?.render(.uncheckedUnicodeString), "💩.com")
      XCTAssertEqual(domain?.render(NoMath()), "💩.com")

      domain = WebURL.Domain("xn--ls8h.⊈.com")
      XCTAssertEqual(domain?.render(.uncheckedUnicodeString), "💩.⊈.com")
      XCTAssertEqual(domain?.render(NoMath()), "💩.xn--6dh.com")
    }

    // Demo renderer which shortens domains using a list of suffix rules.
    //
    // Shortening domain names is very useful, but we need a list to gauge where the trust relationship is.
    // For example, it may be okay to shorten 'developer.apple.com' to just 'apple.com',
    // but it's likely not okay to shorten 'karwa.github.io' to just 'github.io'.
    // 'github.io' gives out subdomains, so all "{x}.github.io" sites should be treated as distinct.

    struct FakeRegistrableDomainPrinter: WebURL.Domain.Renderer {

      // Err, doesn't support overlapping rules. Just a barely-functional demo.
      static let rules: [String] = [
        "com",
        "co.uk",
        "*.github.io",
      ]

      var suffix: String = ""
      var suffixMatchState: MatchState = .unmatched
      var prefix: String? = nil

      enum MatchState {
        case unmatched
        case wildcardLabel
        case complete
      }

      mutating func processLabel(_ label: inout Label, isEnd: Bool) {

        if case .complete = suffixMatchState {
          // The registrable domain consists of 1 label plus the matched suffix.
          precondition(prefix == nil)
          prefix = String(label.unicode)
          return
        }

        // If we haven't matched a suffix, all labels get accumulated in to the suffix.
        suffix.insert(contentsOf: label.unicode, at: suffix.startIndex)

        // We don't need to bother matching the final label.
        guard !isEnd else { return }
        switch suffixMatchState {
        case .unmatched:
          if FakeRegistrableDomainPrinter.rules.contains(suffix) {
            suffixMatchState = .complete
            return
          }
          if FakeRegistrableDomainPrinter.rules.contains("*.\(suffix)") {
            suffixMatchState = .wildcardLabel  // The match is completed on the next label.
          }
          suffix.insert(".", at: suffix.startIndex)
        case .wildcardLabel:
          suffixMatchState = .complete
        case .complete:
          fatalError("completed suffix should have early-exited")
        }
      }

      var readyToReturn: Bool {
        suffixMatchState == .complete && prefix != nil
      }

      var result: String {
        if let prefix = prefix {
          return "\(prefix).\(suffix)"
        }
        return suffix
      }
    }

    do {
      let regDomain = FakeRegistrableDomainPrinter()

      // Unmatched

      var domain = WebURL.Domain("foo.bar.baz.qux")
      XCTAssertEqual(domain?.serialized, "foo.bar.baz.qux")
      XCTAssertEqual(domain?.render(regDomain), "foo.bar.baz.qux")

      // 2 labels, e.g. "x.com"

      domain = WebURL.Domain("example.com")
      XCTAssertEqual(domain?.serialized, "example.com")
      XCTAssertEqual(domain?.render(regDomain), "example.com")

      domain = WebURL.Domain("foo.example.com")
      XCTAssertEqual(domain?.serialized, "foo.example.com")
      XCTAssertEqual(domain?.render(regDomain), "example.com")

      domain = WebURL.Domain("bar.foo.example.com")
      XCTAssertEqual(domain?.serialized, "bar.foo.example.com")
      XCTAssertEqual(domain?.render(regDomain), "example.com")

      // 3 labels, e.g. "x.co.uk"

      domain = WebURL.Domain("example.co.uk")
      XCTAssertEqual(domain?.serialized, "example.co.uk")
      XCTAssertEqual(domain?.render(regDomain), "example.co.uk")

      domain = WebURL.Domain("foo.example.co.uk")
      XCTAssertEqual(domain?.serialized, "foo.example.co.uk")
      XCTAssertEqual(domain?.render(regDomain), "example.co.uk")

      domain = WebURL.Domain("bar.foo.example.co.uk")
      XCTAssertEqual(domain?.serialized, "bar.foo.example.co.uk")
      XCTAssertEqual(domain?.render(regDomain), "example.co.uk")

      // Wildcard.

      domain = WebURL.Domain("qux.baz.bar.foo.hello.io")
      XCTAssertEqual(domain?.serialized, "qux.baz.bar.foo.hello.io")
      XCTAssertEqual(domain?.render(regDomain), "qux.baz.bar.foo.hello.io")

      domain = WebURL.Domain("qux.baz.bar.foo.github.io")
      XCTAssertEqual(domain?.serialized, "qux.baz.bar.foo.github.io")
      XCTAssertEqual(domain?.render(regDomain), "bar.foo.github.io")

      // IDNA.

      domain = WebURL.Domain("qux.baz.xn--ls8h.foo.github.io")
      XCTAssertEqual(domain?.serialized, "qux.baz.xn--ls8h.foo.github.io")
      XCTAssertEqual(domain?.render(regDomain), "💩.foo.github.io")
    }

    // Composing renderers.
    //
    // It would be nice if renderers could be composed relatively efficiently - so you could
    // run multiple renderers over a domain in a single pass, while still being able to take advantage
    // of the fast-paths and early-exits each renderer implements.
    //
    // If the renderers are known, you can use any API you like to feed them data,
    // but if they are unknown (generic), we need to use the DomainRenderer API in a way that is compatible
    // with its normal flow. So it can't be too complex.

    struct CombinedRenderer<Left: DomainRenderer, Right: DomainRenderer>: DomainRenderer {

      var _left: Left
      var _right: Right

      typealias Output = (Left.Output, Right.Output)

      var readyToReturn: Bool {
        _left.readyToReturn && _right.readyToReturn
      }

      var result: (Left.Output, Right.Output) {
        (_left.result, _right.result)
      }

      mutating func processDomain(_ domain: WebURL.Domain) {
        assert(!_left.readyToReturn)
        _left.processDomain(domain)

        assert(!_right.readyToReturn)
        _right.processDomain(domain)
      }

      mutating func processLabel(_ label: inout Label, isEnd: Bool) {
        if !_left.readyToReturn {
          _left.processLabel(&label, isEnd: isEnd)
        }
        if !_right.readyToReturn {
          _right.processLabel(&label, isEnd: isEnd)
        }
      }
    }

    do {
      var domain = WebURL.Domain("xn--ls8h.⊈.example.com")
      let composed = CombinedRenderer(_left: NoMath(), _right: FakeRegistrableDomainPrinter())
      let composedResult = domain?.render(composed)
      XCTAssertEqual(composedResult?.0, "💩.xn--6dh.example.com")  // NoMath
      XCTAssertEqual(composedResult?.1, "example.com")  // FakeRegistrableDomainPrinter

      domain = WebURL.Domain("xn--ls8h.⊈.apple.com")
      let composedResult2 = domain?.render(CombinedRenderer(_left: UncheckedUnicodeDomainRenderer(), _right: composed))
      XCTAssertEqual(composedResult2?.0, "💩.⊈.apple.com")  // uncheckedUnicodeString
      XCTAssertEqual(composedResult2?.1.0, "💩.xn--6dh.apple.com")  // NoMath
      XCTAssertEqual(composedResult2?.1.1, "apple.com")  // FakeRegistrableDomainPrinter
    }

    // Lazy calculations and buffer reuse.
    //
    // Using the above, we can check whether the Label object is effective
    // at lazily computing and caching expensive properties,
    // and whether buffers are being reused by the render function.

    do {
      let domain = WebURL.Domain("xn--e28h.xn--ls8h.⊈.apple.com")

      struct ArrayAddressWatcher: WebURL.Domain.Renderer {
        var result: [(OpaquePointer, Int)] = []
        mutating func processLabel(_ label: inout Label, isEnd: Bool) {
          result.append(label.unicodeScalars.withUnsafeBufferPointer { (OpaquePointer($0.baseAddress!), $0.count) })
        }
      }

      let bigResult = domain?.render(
        CombinedRenderer(
          _left: CombinedRenderer(
            _left: UncheckedUnicodeDomainRenderer(),
            _right: CombinedRenderer(
              _left: CombinedRenderer(
                _left: NoMath(),
                _right: FakeRegistrableDomainPrinter()
              ),
              _right: ArrayAddressWatcher()
            )
          ),
          _right: ArrayAddressWatcher()
        )
      )

      XCTAssertEqual(bigResult?.0.0, "😀.💩.⊈.apple.com")  // uncheckedUnicodeString
      XCTAssertEqual(bigResult?.0.1.0.0, "😀.💩.xn--6dh.apple.com")  // NoMath
      XCTAssertEqual(bigResult?.0.1.0.1, "apple.com")  // FakeRegistrableDomainPrinter

      // Lazy computation/caching.
      // These two address watchers should have seen the same array buffers,
      // even though they made separate calls to '.unicodeScalars'.

      let arrayAddressList1 = bigResult!.1
      let arrayAddressList2 = bigResult!.0.1.1
      XCTAssertEqual(arrayAddressList1.count, 5)
      XCTAssertEqual(arrayAddressList2.count, 5)
      for labelIdx in 0..<5 {
        let left = arrayAddressList1[labelIdx]
        let right = arrayAddressList2[labelIdx]
        XCTAssertEqual(left.0, right.0)
        XCTAssertEqual(left.1, right.1)
      }

      // Buffer reuse.
      // Even though the content changes, the array shouldn't COW between labels;
      // the render function should reuse the allocation.

      let uniqueArrays = Set(arrayAddressList1.map { $0.0 })
      XCTAssertEqual(uniqueArrays.count, 1)
    }

    do {
      let domain = WebURL.Domain("xn--e28h.xn--ls8h.⊈.apple.com")

      struct StringAddressWatcher: WebURL.Domain.Renderer {
        var result: [(OpaquePointer?, Int)] = []
        mutating func processLabel(_ label: inout Label, isEnd: Bool) {
          let addrAndCount: (OpaquePointer?, Int) =
            label.unicode.base.utf8.withContiguousStorageIfAvailable {
              (OpaquePointer($0.baseAddress!), $0.count)
            } ?? (nil, 0)
          result.append(addrAndCount)
        }
      }

      let bigResult = domain?.render(
        CombinedRenderer(
          _left: CombinedRenderer(
            _left: UncheckedUnicodeDomainRenderer(),
            _right: CombinedRenderer(
              _left: CombinedRenderer(
                _left: NoMath(),
                _right: FakeRegistrableDomainPrinter()
              ),
              _right: StringAddressWatcher()
            )
          ),
          _right: StringAddressWatcher()
        )
      )

      // Lazy computation/caching.
      // These two address watchers should have seen the same string buffers,
      // even though they made separate calls to '.unicode'.

      let stringAddressList1 = bigResult!.1
      let stringAddressList2 = bigResult!.0.1.1
      XCTAssertEqual(stringAddressList1.count, 5)
      XCTAssertEqual(stringAddressList2.count, 5)
      for labelIdx in 0..<5 {
        let left = stringAddressList1[labelIdx]
        let right = stringAddressList2[labelIdx]
        XCTAssertEqual(left.0, right.0)
        XCTAssertEqual(left.1, right.1)
      }

      // Buffer reuse.
      // For String, the story is less excellent. This does not seem to work reliably (at -Onone).
    }
  }
}
