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

import XCTest

@testable import WebURL

final class IPv4AddressTests_Deprecated: XCTestCase {

  func testParseWithParseResult() {

    // Regular, well-formed addresses work.
    do {
      let hostStrings = [
        "127.0.0.1",
        "192.168.0.1",
        "123.456",
        "0xBADF00D",
        "0xBADF00D.",
        "045.0xFE",
        "045.0xFE.",
      ]
      for hostString in hostStrings {
        switch IPv4Address.parse(utf8: hostString.utf8) {
        case .success(_):
          break
        default:
          XCTFail()
        }
      }
    }

    // These should return .notAnIPAddress, not .failure
    do {
      let hostStrings = [
        "example.com",
        "123.example.com",
        "9999999999.com",
        "9999999999..",
        "1.2.3.0xFG",
      ]
      for hostString in hostStrings {
        switch IPv4Address.parse(utf8: hostString.utf8) {
        case .notAnIPAddress:
          break
        default:
          XCTFail()
        }
      }
    }

    // These should return .failure, not .notAnIPAddress
    do {
      let hostStrings = [
        "9999999999",
        "9999999999.",
        "123.com.456",  // This is a change which follows the URL standard update. Numeric TLDs are not valid.
        "123.com.456.",
        "0xFFFFFFFFF",
      ]
      for hostString in hostStrings {
        switch IPv4Address.parse(utf8: hostString.utf8) {
        case .failure:
          break
        default:
          XCTFail()
        }
      }
    }
  }
}
