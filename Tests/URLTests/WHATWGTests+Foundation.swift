import Foundation

extension WHATWGTests {

  /// Attempts to map Foundation's URL API to the WHATWG model for constructor tests.
  /// Just for fun.
  ///
  func _justforfun_testURLConstructor_NSURL() throws {
    let url = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("urltestdata.json")
    let data = try Data(contentsOf: url)
    let array = try JSONSerialization.jsonObject(with: data, options: []) as! NSArray
    assert(array.count == 627, "Incorrect number of test cases.")

    var report = WHATWG_TestReport()
    report.expectedFailures = [
      // These test failures are due to us not having implemented the `domain2ascii` transform,
      // often in combination with other features (e.g. with percent encoding).
      //
      272,  // domain2ascii: (no-break, zero-width, zero-width-no-break) are name-prepped away to nothing.
      276,  // domain2ascii: U+3002 is mapped to U+002E (dot).
      286,  // domain2ascii: fullwidth input should be converted to ASCII and NOT IDN-ized.
      294,  // domain2ascii: Basic IDN support, UTF-8 and UTF-16 input should be converted to IDN.
      295,  // domain2ascii: Basic IDN support, UTF-8 and UTF-16 input should be converted to IDN.
      312,  // domain2ascii: Fullwidth and escaped UTF-8 fullwidth should still be treated as IP.
      412,  // domain2ascii: Hosts and percent-encoding.
      413,  // domain2ascii: Hosts and percent-encoding.
      621,  // domain2ascii: IDNA ignored code points in file URLs hosts.
      622,  // domain2ascii: IDNA ignored code points in file URLs hosts.
      626,  // domain2ascii: Empty host after the domain to ASCII.
    ]
    for item in array {
      if let sectionName = item as? String {
        report.recordSection(sectionName)
      } else if let rawTestInfo = item as? [String: Any] {
        let expected = URLConstructorTestCase(from: rawTestInfo)
        report.recordTest { report in
          let _parserResult = URL(string: expected.base!)
            .flatMap { URL(string: expected.input!, relativeTo: $0) }?
            .jsModel
          // Capture test data.
          report.capture(key: "expected", expected)
          report.capture(key: "actual", _parserResult?.href as Any)
          // Compare results.
          guard let parserResult = _parserResult else {
            report.expectTrue(expected.failure == true)
            return
          }
          report.expectFalse(expected.failure == true)
          report.expectEqual(parserResult.scheme, expected.protocol, "Scheme")
          report.expectEqual(parserResult.href, expected.href, "Href")
          report.expectEqual(parserResult.host, expected.host, "Host")
          report.expectEqual(parserResult.port.map { Int($0) }, expected.port, "Port")
          report.expectEqual(parserResult.username, expected.username, "User")
          report.expectEqual(parserResult.password, expected.password, "Password")
          report.expectEqual(parserResult.pathname, expected.pathname, "Path")
          report.expectEqual(parserResult.search, expected.search, "Query")
          report.expectEqual(parserResult.fragment, expected.hash, "Fragment")
          // The test file doesn't include expected `origin` values for all entries.
          //                     if let expectedOrigin = expected.origin {
          //                        report.expectEqual(parserResult., expectedOrigin)
          //                     }
        }
      } else {
        assertionFailure("👽 - Unexpected item found. Type: \(type(of: item)). Value: \(item)")
      }
    }

    let reportString = report.generateReport()
    let reportPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      "url_whatwg_constructor_report.txt")
    try reportString.data(using: .utf8)!.write(to: reportPath)
    print("ℹ️ Report written to \(reportPath)")
  }

}

struct JSObjectModel {
  var url: URL

  /// A stringifier that returns a `String` containing the whole URL.
  ///
  public var href: String {
    return url.absoluteString
  }

  /// A `String` containing the protocol scheme of the URL, including the final ':'.
  /// Called `protocol` in JavaScript.
  ///
  public var scheme: String {
    return url.scheme.map { $0 + ":" } ?? ""
  }

  /// A `String` containing the username specified before the domain name.
  ///
  public var username: String {
    return url.user ?? ""
  }

  /// A `String` containing the password specified before the domain name.
  ///
  public var password: String {
    return url.password ?? ""
  }

  /// A `String` containing the domain (that is the hostname) followed by (if a port was specified) a ':' and the port of the URL.
  ///
  public var host: String {
    guard let host = url.host else { return "" }
    guard let port = url.port else { return host }
    return "\(host):\(port)"
  }

  /// A `String` containing the domain of the URL.
  ///
  public var hostname: String {
    return url.host ?? ""
  }

  /// The port number of the URL
  ///
  public var port: UInt16? {
    return url.port.flatMap { UInt16(exactly: $0) }
  }

  /// A `String` containing an initial '/' followed by the path of the URL.
  ///
  public var pathname: String {
    return url.path.starts(with: "/") ? url.path : "/" + url.path
  }

  /// A `String` indicating the URL's parameter string; if any parameters are provided,
  /// this string includes all of them, beginning with the leading '?' character.
  ///
  public var search: String {
    return url.query.map { "?" + $0 } ?? ""
  }

  /// A `String` containing a '#' followed by the fragment identifier of the URL.
  /// Called `hash` in JavaScript.
  ///
  public var fragment: String {
    return url.fragment.map { "#" + $0 } ?? ""
  }
}

extension URL {
  var jsModel: JSObjectModel { return JSObjectModel(url: self.absoluteURL.standardized) }
}
