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
import WebURL

/// Benchmarks percent encoding (using the `urlComponentSet`) and decoding without substitutions.
///
let PercentEncoding = BenchmarkSuite(name: "PercentEncoding") { suite in

  let urlEncoded_strings = [
    String(decoding: 0 ..< 128, as: UTF8.self), // Every ASCII character
    #"This 🦆 is 🐧 some 🦖 m!x€d%20cºnt£nt"#,
    #"""
    A very long string with the occassional 🦖 emoji thrown in for good measure!
    A very long string with the occassional 🦖 emoji thrown in for good measure!
    A very long string with the occassional 🦖 emoji thrown in for good measure!
    A very long string with the occassional 🦖 emoji thrown in for good measure!
    A very long string with the occassional 🦖 emoji thrown in for good measure!
    A very long string with the occassional 🦖 emoji thrown in for good measure!
    A very long string with the occassional 🦖 emoji thrown in for good measure!
    A very long string with the occassional 🦖 emoji thrown in for good measure!
    """#
  ]
  suite.benchmark("Encode.String") {
    for string in urlEncoded_strings {
      blackHole(string.percentEncoded(using: .urlComponentSet))
    }
  }

  let urlDecoded_strings = [
    #"%00%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13%14%15%16%17%18%19%1A%1B%1C%1D%1E%1F%20!%22%23%24%25%26'()*%2B%2C-.%2F0123456789%3A%3B%3C%3D%3E%3F%40ABCDEFGHIJKLMNOPQRSTUVWXYZ%5B%5C%5D%5E_%60abcdefghijklmnopqrstuvwxyz%7B%7C%7D~%7F"#, // Every ASCII character
    #"This%20%F0%9F%A6%86%20is%20%F0%9F%90%A7%20some%20%F0%9F%A6%96%20m!x%E2%82%ACd%2520c%C2%BAnt%C2%A3nt"#,
    #"A%20very%20long%20string%20with%20the%20occassional%20%F0%9F%A6%96%20emoji%20thrown%20in%20for%20good%20measure!%0AA%20very%20long%20string%20with%20the%20occassional%20%F0%9F%A6%96%20emoji%20thrown%20in%20for%20good%20measure!%0AA%20very%20long%20string%20with%20the%20occassional%20%F0%9F%A6%96%20emoji%20thrown%20in%20for%20good%20measure!%0AA%20very%20long%20string%20with%20the%20occassional%20%F0%9F%A6%96%20emoji%20thrown%20in%20for%20good%20measure!%0AA%20very%20long%20string%20with%20the%20occassional%20%F0%9F%A6%96%20emoji%20thrown%20in%20for%20good%20measure!%0AA%20very%20long%20string%20with%20the%20occassional%20%F0%9F%A6%96%20emoji%20thrown%20in%20for%20good%20measure!%0AA%20very%20long%20string%20with%20the%20occassional%20%F0%9F%A6%96%20emoji%20thrown%20in%20for%20good%20measure!%0AA%20very%20long%20string%20with%20the%20occassional%20%F0%9F%A6%96%20emoji%20thrown%20in%20for%20good%20measure!"#
  ]
  suite.benchmark("Decode.String") {
    for string in urlDecoded_strings {
      blackHole(string.percentDecoded())
    }
  }

  let urlDecoded_notEncoded_strings = [
    #"This string does not contain any percent-encoding"#,
    #"This is another string -- which also does not contain any percent-encoding"#,
    #"This 🧵 does not contain any ٪-encoding"#,
    #"This 🧵 does not contain any ٪-encoding -- This 🧵 does not contain any ٪-encoding -- This 🧵 does not contain any ٪-encoding"#
  ]
  suite.benchmark("Decode.String.NotEncoded") {
    for string in urlDecoded_notEncoded_strings {
      blackHole(string.percentDecoded())
    }
  }
}
