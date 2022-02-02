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
    public private(set) var reportedResultCount = 0

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

  public mutating func markSection(_ name: String) {
    report.markSection(name)
  }

  public mutating func reportTestResult(_ result: TestResult<Suite>) {
    reportedResultCount += 1
    if case .host = result.testCase.property {
      // 'host' setter is not implemented. Can't be XFAIL-ed because some setters are no-ops and actually pass.
      report.skipTest()
    } else {
      report.performTest { reporter in reporter.reportTestResult(result) }
    }
  }
}
