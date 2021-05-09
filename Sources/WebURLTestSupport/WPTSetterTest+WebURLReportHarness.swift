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

import WebURL

extension WPTSetterTest {

  /// A harness for running a series of WPT URL setter tets with the `WebURL` JS model and accumulating the results in a `SimpleTestReport`.
  ///
  public struct WebURLReportHarness {
    public private(set) var report = SimpleTestReport()
    public private(set) var entriesSeen = 0

    public init() {}
  }
}

extension WPTSetterTest.WebURLReportHarness: WPTSetterTest.Harness {

  public typealias URLType = WebURL.JSModel

  public func parseURL(_ input: String) -> URLType? {
    WebURL(input)?.jsModel
  }

  public func setValue(_ newValue: String, forProperty property: URLModelProperty, on url: inout URLType) {
    switch property {
    case .href:
      url.href = newValue
    case .protocol:
      url.scheme = newValue
    case .username:
      url.username = newValue
    case .password:
      url.password = newValue
    case .hostname:
      url.hostname = newValue
    case .port:
      url.port = newValue
    case .pathname:
      url.pathname = newValue
    case .search:
      url.search = newValue
    case .hash:
      url.hash = newValue
    case .origin:
      assertionFailure("The URL Standard does not allow setting the origin directly")
    case .host:
      break  // 'host' setter is not implemented.
    }
  }

  public func urlValues(_ url: URLType) -> URLValues {
    url.urlValues
  }

  public mutating func reportTestResult(_ result: WPTSetterTest.Result) {
    if case .host = result.property {
      return  // 'host' setter is not implemented. Pass/failure isn't meaningful.
    }
    entriesSeen += 1
    report.performTest { reporter in
      reporter.capture(key: "Property", result.property.name)
      reporter.capture(key: "Testcase", result.testcase)
      if let actualValues = result.resultingValues {
        reporter.capture(key: "Result", actualValues)
      }

      if !result.failures.isEmpty {
        var remainingFailures = result.failures

        if let _ = remainingFailures.remove(.failedToParse) {
          reporter.fail("Starting URL failed to parse")
        }
        if let _ = remainingFailures.remove(.propertyMismatches), let actualValues = result.resultingValues {
          for (property, expectedValue) in result.testcase.expected {
            if actualValues[property] != expectedValue {
              reporter.fail(property.name)
            }
          }
        }
        if let _ = remainingFailures.remove(.notIdempotent) {
          reporter.fail("<idempotence>")
        }
        if !remainingFailures.isEmpty {
          assertionFailure("Unhandled failure condition")
          reporter.fail("unknown reason")
        }
      }
    }
  }
}
