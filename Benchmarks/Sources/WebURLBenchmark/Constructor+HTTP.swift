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

/// Benchmarks constructing a WebURL from a String.
///
/// This covers parsing the String, as well as allocating and writing a normalized URL to storage.
///
internal enum Constructor {}

extension Constructor {

  /// Benchmarks the `WebURL.init(String)` constructor for http(s) URLs.
  /// The same performance trends should apply across http, https, ftp, ws, wss, schemes.
  ///
  internal static var HTTP: BenchmarkSuite {
    BenchmarkSuite(name: "Constructor.HTTP") { suite in

      // AverageURLs.

      suite.benchmark("AverageURLs") {
        for string in SampleURLs.AverageHTTPURLs {
          blackHole(WebURL(string))
        }
      }
      suite.benchmark("AverageURLs.filtered") {
        for string in SampleURLs.AverageHTTPURLs_TabsAndNewlines {
          blackHole(WebURL(string))
        }
      }

      // IDNA.

      suite.benchmark("IDNA") {
        for string in SampleURLs.IDNAURLs {
          blackHole(WebURL(string))
        }
      }

      // IPv4.

      suite.benchmark("IPv4") {
        for string in SampleURLs.ExoticIPv4URLs {
          blackHole(WebURL(string))
        }
      }
      suite.benchmark("IPv4.filtered") {
        for string in SampleURLs.ExoticIPv4URLs_TabsAndNewlines {
          blackHole(WebURL(string))
        }
      }

      // IPv6.

      suite.benchmark("IPv6") {
        for string in SampleURLs.IPv6URLs {
          blackHole(WebURL(string))
        }
      }
      suite.benchmark("IPv6.filtered") {
        for string in SampleURLs.IPv6URLs_TabsAndNewlines {
          blackHole(WebURL(string))
        }
      }

      // Components requiring percent-encoding.

      let percent_encoding_strings = [
        #"http://example.com/🦆/🦆/goose/🦆/🦆/goose/🦆/🦆/goose/🦆/🦆/goose/🦆/🦆/goose/🦆/🦆/goose/🦆/🦆/goose/🦆/🦆/goose/🦆/🦆/goose/🦆/🦆/goose/"#,
        #"http://example.com/🦆/🦆/../../🦆/🦆/../../🦆/🦆/../../🦆/🦆/../../🦆/🦆/../../🦆/🦆/../../🦆/🦆/../../🦆/🦆/../../🦆/🦆/../../🦆/🦆/../../"#,
        #"http://example.com?🦆=1️⃣&🐶=2️⃣&🦁=3️⃣&now=break&🐧=4️⃣&🦕=5️⃣&🦆=1️⃣&🐶=2️⃣&🦁=3️⃣&now=break&🐧=4️⃣&🦕=5️⃣&🦆=1️⃣&🐶=2️⃣&🦁=3️⃣&now=break&🐧=4️⃣&🦕=5️⃣&🛑"#,
        #"http://example.com#🦆=1️⃣&🐶=2️⃣&🦁=3️⃣&now=break&🐧=4️⃣&🦕=5️⃣&🦆=1️⃣&🐶=2️⃣&🦁=3️⃣&now=break&🐧=4️⃣&🦕=5️⃣&🦆=1️⃣&🐶=2️⃣&🦁=3️⃣&now=break&🐧=4️⃣&🦕=5️⃣&🛑"#,
      ]
      suite.benchmark("Percent-encoding components") {
        for string in percent_encoding_strings {
          blackHole(WebURL(string))
        }
      }

      // Hostnames requiring percent-decoding.

      let percent_encoded_hostname_strings = [
        #"http://ex%61mple.com"#,
        #"http://loc%61lhost"#,
        #"http://%74%68%69%73%69%73%61%76%65%72%79%6C%6F%6E%67%65%6E%63%6F%64%65%64%68%6F%73%74%6E%61%6D%65%61%63%74%75%61%6C%6C%79%74%6F%6F%6C%6F%6E%67%74%6F%72%65%61%6C%6C%79%62%65%75%73%61%62%6C%65%62%75%74%77%68%61%74%65%76%65%72%77%65%73%74%69%6C%6C%6E%65%65%64%74%6F%64%65%63%6F%64%65%69%74%2E%63%6F%6D"#,
        // Percent-encoded IPv4 addresses.
        #"http://%31%30%2E%30%2E%30%2E%31"#,
        #"http://%30%78%62%61%64%66%30%30%64"#,
        #"http://%30%78%64%30%2E%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%31%31%31%2E%32%33%30%2E%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%30%34"#,
      ]
      suite.benchmark("Percent-encoded hostnames") {
        for string in percent_encoded_hostname_strings {
          blackHole(WebURL(string))
        }
      }

      // HTTP URLs with very long paths.

      suite.benchmark("Long paths") {
        // Small (<255 chars).
        blackHole(WebURL(#"http://example.com/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/"#))
        blackHole(WebURL(#"http://example.com////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////"#))
        blackHole(WebURL(#"http://example.com//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//"#))
        // Large.
        blackHole(WebURL(#"http://example.com/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/"#))
        blackHole(WebURL(#"http://example.com/////////////////////////////////////////////////////////x/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////x/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////x/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////x/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////x/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////x/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////x/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////x/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////x/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////x//////////////////////////////"#))
        blackHole(WebURL(#"http://example.com//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//"#))
      }

      suite.benchmark("Complex paths 1") {
        blackHole(WebURL(#"http://example.com/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../"#))

      }
      suite.benchmark("Complex paths 2") {
        blackHole(WebURL(#"http://example.com//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../..../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../..//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//a//b//c//d//e//f//g//h//i//j//k//l//m//n//o//p//q//r//s//t//u//v//w//x//y//z//../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../../"#))
      }

      suite.benchmark("Long query 1") {
        blackHole(WebURL(#"http://chart.apis.google.com/chart?chs=500x500&chma=0,0,100,100&cht=p&chco=FF0000%2CFFFF00%7CFF8000%2C00FF00%7C00FF00%2C0000FF&chd=t%3A122%2C42%2C17%2C10%2C8%2C7%2C7%2C7%2C7%2C6%2C6%2C6%2C6%2C5%2C5&chl=122%7C42%7C17%7C10%7C8%7C7%7C7%7C7%7C7%7C6%7C6%7C6%7C6%7C5%7C5&chdl=android%7Cjava%7Cstack-trace%7Cbroadcastreceiver%7Candroid-ndk%7Cuser-agent%7Candroid-webview%7Cwebview%7Cbackground%7Cmultithreading%7Candroid-source%7Csms%7Cadb%7Csollections%7Cactivity|Chart"#))
      }
      suite.benchmark("Long query 2") {
        blackHole(WebURL(#"https://opentimestamps.org/info.html?ots=004f70656e54696d657374616d7073000050726f6f6600bf89e2e884e892940108b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553f0103af65c768ff047f5459d5b00be93ca2308fff01055ec009d3160b3b47df85addd4a4be4f08f02078db964aa8198a7b11c4c8f6cc40b66a8f7a11be3ecc762c10166a8dad6c07a208f10459f6e401f008ea8c7f8cade256c5ff0083dfe30d2ef90c8e2c2b68747470733a2f2f626f622e6274632e63616c656e6461722e6f70656e74696d657374616d70732e6f726708f0206dc515c8e66c1f185e5618bbc613cd0d8e9bea75ac3a3da047c53be2c6e1f1c608f020c712209464c9e1ed3a4b504750e7283d5a1be1f407ac496a391f2bcc969b580808f120d9d4e70f4f7bec078c3dda08272eace468fbb81e75fbc7ae1e20bc7e8db1425908f020a6669aa9fb0dc6155bb709913b6bae1bf1109c2251a9b6aa4fd848098b05210d08f120d8341043f84b2899e4606f4303aec21127340387c760df2e3b1088546969e0ae08f120e1638308abd4f0b2c844abc80afa2ba15681b566a9ef764c318d671b5630257308f0205323029f6bbb2e38e2581ccc03c2c4b4c0ca5d38b202d2215045832e99924c1908f0209e69d42f395e0cbc5ff7ced095d5bc8de5559dbd3b531574feb7771016efd83b08f0208d6948f8407d5ec643a129848fc358bde10ff21b2cf512a031ffaf7374081b0f08f020bdd67a080b1e917fc579aca2b60c1f6e18c5ed1e1752c2b77faf7b64426b0dee08f12030adcd755ce5d5e5c5ddf3a72ce3cde847950de074313b38c4d3845f102d387208f020f33e65c3425fbac1e453930b0d447b776ba56a9ae86e777f7c78d6a973f1ac2408f120a66fd1d059c783875bb08cf3ad0a27d836ab1cdc019e8ea238b72379250d6b5a08f159010000000103e11d4dafc11a60859d0bd33b55f6fd3bdf3f7d659b04fd2057a7d77d2071230000000000fdffffff0252d59200000000001600140db84d3cb80e3fe685834583d6216d0736bc12660000000000000000226a20f004218307000808f120dabddf003dc5a38416cba755881afbbc7d181bbbe74833a84d3fae9b0a4c6de60808f120742f880216b42f611fdf4b1421b9875a8c29002c4398104ba83a74a81dc0b84e0808f12035a5f19dcc35fdd3da008fc7c8ce6a00e8410a99f334a8f924574f8db973a8460808f020e968af2ee61b31a0b54e0c5515c2636b7f78d7e853f10cc1c46a0f25bd53ad1c0808f0204063f5a7601f4a1b114b780df5ca991296b4e77093c86d2e56c185ee131b63860808f020c44ede80587fd3e75cf083a0f870bd8ce92b5348972adccfd8ed7b929aabc8db0808f120d01b19249a54f0ba87b5d6f784bf8183a660d1e325fc58fd853008f1cbf723f50808f1201eac00c289371d96816dd1f38a69f9e6bb619a5738b0ce6858f785dd2ae1c1e50808f12049c1b3f01c3b9a295a4eae854fb8f56d8a2b08daee4ffceb808f035ded1cb4580808f0203089de16209b3cd42abdb18ee74324f1f22e61c05a1d8c52b503a06d781a4c540808f0207668971306f71e72a2096f41881704655d34936e407d3620b0f2428f6923ae870808000588960d73d7190103a2861efff01086707b19020de86aff1e49cb646ec5f808f10459f6e400f008275c0b61c93b4bdaff0083dfe30d2ef90c8e2e2d68747470733a2f2f616c6963652e6274632e63616c656e6461722e6f70656e74696d657374616d70732e6f726708f02089a1ff4781938b7d98e83c06d91c5b6a9017c1e82eb3bcfc68c8df2d96b0c92f08f0200cfaf8ff9bafd231b8b0a97c721b76211bea1383d172f3d2166784dbba307dca08f1203c9c6341f5847addbc077f9261a75faa68722995152655251e742baa7b83f45c08f120f5c40fb9e9a4bb66e9c8fe91b281cad0239a94804c54f97f75a12f57e0d8e92808f1209e2770b5be815578c07c07de9bc6dc10a1f578b55488cc97ffd95a1ce8d4dd8208f120524f5b1247ba14a8df609d8ee22d42efbcc7bde0727ccc95834ce46bb13d1b5708f120553a84fb1efe8a1699e8737f40d352e4defc6d231760416d61c5f0dcb19cfb6808f020d84f0c44052863ea0403dc57206b3e9c8595835a936de11ce24e3c8d6bb78a2708f1205abf406a4ab122b27f5f9a8234c5ff4f6d90789af6950424e8864cca53803c0208f120dd8b42e44fe5b8ae63e44f7612cf7a6ab384ca8543c16b097b5f25af7edb857f08f02049c23e0e98e7633798e242449aa76ac3fee6012e46897ad1a7eb08958b1565ed08f020f801e537dcf9761214a0e276bb2f9907bd834e0cafe9caeaee340180dfa3f7c208f1200088e5f5842df10e5869a363cc949715c5fbf86a4e4aa8b621efad6d1c2196df08f1590100000001c350bc30975e5c941cf3508e5302068e70bed189dca215752961c76c2524532a0000000000fdffffff02edf3510000000000160014e200dde45eb0529aebe86e16060fb9b109008b560000000000000000226a20f004238307000808f0209a7685c29057df8d5c1486942f794d24c1a3bd73497014644e232d4e60036b5d0808f0206d0a19463805ea0468537d4f4521edf91295bae46621ea67451dd3b56add29df0808f020e2183c0092ca5ead1dcbb9dde8a5e68adb80be25b28fc208914df7b3e47660f10808f020248dff2abbae8fa5f7ce87fabd6c941397cc1979c2b2161d1d0c51263468acb00808f1205c7fc70574a919eaa37257d5521ee82b1ba57c747d2a35bc5bbd8a1d370b4efd0808f120d8b61afb9b980a58a02845c3abb607eb72d3a47528f1a96d37da977ced48a6450808f020430119ebb726a3b9530d31f1110a3c67c0e0c4bdcf0b74d9d9dcaa91d0fcefe20808f0201d715d78659aac3fccea8a6a8cbcb6759dbcd851d1d919c72600d382b0bdae800808f120850d5c19809ade49c051cc27e308703087a7f2772aab43f4050ff260945468050808f1208a1c6db3604fef1d1be2d0404a65a2c1880fb0cd9621d18bc59fa8425543c90c0808f120a06b0bb4efae407b8dab28473a0783bb89e7663efbb8980326e7aaaf765e2ccd0808f020feff03e7f6ca0420fa92b1b8114c1961b76490ee88b09e4029838942379f35b00808000588960d73d7190103a4861ef010c4103e3a25d6ecc7243ae7802466616108f10459f6e400f008edafd20c9974932bff0083dfe30d2ef90c8e292868747470733a2f2f66696e6e65792e63616c656e6461722e657465726e69747977616c6c2e636f6d08f120856b81e3ec879b497a5e87c1638008bd9b4169c899fed24cd12ed3220b6bf74a08f120fa82b0ec2fa550365e1a3982924365ab6a38ed78e3efab1a41a8bad668e303ca08f12079cd28c92d707944dded2f768ee0d9d24e0c6621f443f7c1138e597f40c3f84f08f1205c92984825b9e4de3391e6f5f61f62dcd93a96087a54fd31de8231328fcea47508f020059ef220b8cde3d698e41c03ccce68cd933fdda037c4c42df486aa8b16c1823808f120527ac415d63c3568aa21bb9c3129cc8cbe0f1f60a034274b6d72fb46fa10e92d08f02063202c8a7fe2ccc746c36a671cc82d6c57c6ccd7e6a85ebd7983443eaeecff1908f1204da26285d0eab660de7a197a15227795d75da4ebf411ee588ea6167af42770e508f02030554533f33ba4185ccb2323a7edcdfbd43c7caf4984493c8b0cfa3408eac83a08f020efa635035eae5bfab2a01dd231cdcb40ceec233d4698a514398164ec09271bbe08f1205def3ea6346e21555aa3ef0a8ec59c6d94d1c16d7ea0f86082a4a7747fdd755808f02036f9858cc9571331faa13ec8d851df70a14b188e7b2bcba549a80b902866956a08f120ba24ea4c9d11a709038368225839a0e6af758a2d2a18d794996179368cb0d82d08f1ae010100000001c15f1985fa21e340ea5f12cad6528dc299acc41a3957566831e15f9e5710c2a80000000048473044022014cc04a47a7d45cc0ddf7b774f04877325ca4ad0e8b3e8c9fe1f4e8aca6ba4c2022051dc0ed24afe109ceaefdcfebf25abb8515ee77425e43d816a561efab19d162501fdffffff022530090000000000232103306be92d7bf2d8d57ac10d7773e69a5833e7f9495dc4bba78973144050211497ac0000000000000000226a20f004228307000808f020aaf914437aa8e53900a5c4226233effd210b170fa692aacc260ff51a9f8a05650808f02008d28698dbe824dfc16fe1809e59244e7a22f623719668a3dab2f42f2ea8fdcc0808f1200e7d1b9a340fae0b8d3ce59884e6ffc124be390f13f6f210cd97b8fbb612562e0808f020da2121dce81cd9f9e15434eefc46763c21ad26ebd2d7907698b7a6c013b376950808f0203236406de3c8f5723d6c6eeb43e92011c96e4d34d90200611053e88980ec49490808f0201057896f05e6887bcd21ba9004a09471a8efc56c34893281fee95d294357b4780808f0200002f00c6f81d8795c24575afc446a92b53c19d19b1e6c13d4348d6fd578e4df0808f12008ce44a1e21afe273be45ed6dfeb5430f763782dca2199222ae82aff2e082a460808f120701b4e3b2777b0ee82e627c4e6d180a39c32f3ac4e8fcc3fd3a7d0b6719580aa0808f0207085ed4a447f28d94dc89c4e2b7b0682ae78fd72c5d7eb95f3f55fbc93a0ff9b0808f120e9a20490f3b5ace95f2c2a56c07921c895bee371e87a7fd24e1789e2ef7d2da80808f020e7b5d791d1b118e9dd07a7c181b20dcf37ab5a9bb14970eebd04ffe03c9819430808000588960d73d7190103a3861e"#))
      }
    }
  }
}
