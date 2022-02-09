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

import Benchmark
import Foundation
import WebURL
import WebURLFoundationExtras

/// Benchmarks of WebURL-Foundation interoperability features.
///
internal enum FoundationCompat {}


// --------------------------------------------
// MARK: - NSURLToWeb
// --------------------------------------------


extension FoundationCompat {

  /// Benchmarks the `WebURL.init?(Foundation.URL)` constructor.
  ///
  internal static var NSURLToWeb: BenchmarkSuite {
    BenchmarkSuite(name: "FoundationCompat.NSURLToWeb") { suite in

      let AverageHTTPURLs_Foundation = SampleURLs.AverageHTTPURLs.map { URL(string: $0)! }

      suite.benchmark("AverageURLs") { state in
        blackHole(AverageHTTPURLs_Foundation)
        try state.measure {
          for url in AverageHTTPURLs_Foundation {
            blackHole(WebURL(url))
          }
        }
      }

      let ExoticIPv4URLs_Foundation = SampleURLs.ExoticIPv4URLs.map { URL(string: $0)! }

      suite.benchmark("IPv4") { state in
        blackHole(ExoticIPv4URLs_Foundation)
        try state.measure {
          for url in ExoticIPv4URLs_Foundation {
            blackHole(WebURL(url))
          }
        }
      }

      let IPv6URLs_Foundation = SampleURLs.IPv6URLs.map { URL(string: $0)! }

      suite.benchmark("IPv6") { state in
        blackHole(IPv6URLs_Foundation)
        try state.measure {
          for url in IPv6URLs_Foundation {
            blackHole(WebURL(url))
          }
        }
      }

      // End of suite.
    }
  }
}


// --------------------------------------------
// MARK: - WebToNSURL
// --------------------------------------------


extension FoundationCompat {

  /// Benchmarks the `Foundation.URL.init?(WebURL)` constructor.
  ///
  internal static var WebToNSURL: BenchmarkSuite {
    BenchmarkSuite(name: "FoundationCompat.WebToNSURL") { suite in

      let AverageHTTPURLs_Web = SampleURLs.AverageHTTPURLs.map { WebURL($0)! }

      suite.benchmark("AverageURLs") { state in
        blackHole(AverageHTTPURLs_Web)
        try state.measure {
          for url in AverageHTTPURLs_Web {
            blackHole(URL(url))
          }
        }
      }

      let ExoticIPv4URLs_Web = SampleURLs.ExoticIPv4URLs.map { WebURL($0)! }

      suite.benchmark("IPv4") { state in
        blackHole(ExoticIPv4URLs_Web)
        try state.measure {
          for url in ExoticIPv4URLs_Web {
            blackHole(URL(url))
          }
        }
      }

      let IPv6URLs_Web = SampleURLs.IPv6URLs.map { WebURL($0)! }

      suite.benchmark("IPv6") { state in
        blackHole(IPv6URLs_Web)
        try state.measure {
          for url in IPv6URLs_Web {
            blackHole(URL(url))
          }
        }
      }

      // End of suite.
    }
  }
}
