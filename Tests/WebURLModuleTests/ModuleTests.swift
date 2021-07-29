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
import XCTest

final class ModuleTests: XCTestCase {}

extension ModuleTests {

  func testWebURLTypesAreAvailable() {
    // Validates packaging.
    // Ensures the 'WebURL' type (and other types defined in WebURLCore) are accessible via 'import WebURL'.
    // If something goes wrong with the packaging, this test will fail to compile rather than failing at runtime.
    let url = WebURL("")
    let _: WebURL.Host? = url?.host
    let _: WebURL.PathComponents? = url?.pathComponents
    let _: WebURL.UTF8View? = url?.utf8
    let _: WebURL.FormEncodedQueryParameters? = url?.formParams

    let ipv4 = IPv4Address("")
    let _: IPv4Address.Octets? = ipv4?.octets
    if let addr = ipv4 {
      let _: WebURL.Host = .ipv4Address(addr)
    }

    let ipv6 = IPv6Address("")
    let _: IPv6Address.Octets? = ipv6?.octets
    if let addr = ipv6 {
      let _: WebURL.Host = .ipv6Address(addr)
    }
  }
}
