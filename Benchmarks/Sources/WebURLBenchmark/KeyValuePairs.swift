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

#if swift(>=5.7)

  /// Benchmarks the WebURL `KeyValuePairs` view.
  ///
  let KeyValuePairs = BenchmarkSuite(name: "KeyValuePairs") { suite in

    // Iteration.

    suite.benchmark("Iteration.Small.Forwards") { state in
      var url = WebURL("http://example.com/?foo=bar&baz=qux&format=json&client=mobile")!
      try state.measure {
        for component in url.queryParams {
          blackHole(component)
        }
      }
      blackHole(url)
    }

    // Get (non-encoded).

    suite.benchmark("Get.NonEncoded") { state in
      var url = WebURL("http://example.com/?foo=bar&baz=qux&format=json&client=mobile")!
      try state.measure {
        blackHole(url.queryParams["format"]!)
      }
      blackHole(url)
    }

    // Get2 (non-encoded).

    suite.benchmark("Get2.NonEncoded") { state in
      var url = WebURL("http://example.com/?foo=bar&baz=qux&format=json&client=mobile")!
      try state.measure {
        blackHole(url.queryParams["format", "client"])
      }
      blackHole(url)
    }

    // Get3 (non-encoded).

    suite.benchmark("Get3.NonEncoded") { state in
      var url = WebURL("http://example.com/?foo=bar&baz=qux&format=json&client=mobile")!
      try state.measure {
        blackHole(url.queryParams["format", "client", "baz"])
      }
      blackHole(url)
    }

    // Get4 (non-encoded).

    suite.benchmark("Get4.NonEncoded") { state in
      var url = WebURL("http://example.com/?foo=bar&baz=qux&format=json&client=mobile")!
      try state.measure {
        blackHole(url.queryParams["format", "client", "baz", "client"])
      }
      blackHole(url)
    }

    // Get (encoded).

    suite.benchmark("Get.Encoded") { state in
      var url = WebURL("http://example.com/?foo=bar&baz=qux&form%61t=json&client=mobile")!
      try state.measure {
        blackHole(url.queryParams["format"]!)
      }
      blackHole(url)
    }

    // Get2 (encoded).

    suite.benchmark("Get2.Encoded") { state in
      var url = WebURL("http://example.com/?foo=bar&baz=qux&form%61t=json&cli%65nt=mobile")!
      try state.measure {
        blackHole(url.queryParams["format", "client"])
      }
      blackHole(url)
    }

    // Get3 (encoded).

    suite.benchmark("Get3.Encoded") { state in
      var url = WebURL("http://example.com/?foo=bar&%62az=qux&form%61t=json&cli%65nt=mobile")!
      try state.measure {
        blackHole(url.queryParams["format", "client", "baz"])
      }
      blackHole(url)
    }

    // Get4 (encoded).

    suite.benchmark("Get4.Encoded") { state in
      var url = WebURL("http://example.com/?foo=bar&%62az=qux&form%61t=json&cli%65nt=mobile")!
      try state.measure {
        blackHole(url.queryParams["format", "client", "baz", "client"])
      }
      blackHole(url)
    }

    // Get (long-keys)(non-encoded).

    suite.benchmark("Get.LongKeys.NonEncoded") { state in
      var url = WebURL("http://example.com/?foofoofoofoofoofoo=bar&bazbazbazbazbaz=qux&formatformatformatformat=json&clientclientclientclientclient=mobile")!
      try state.measure {
        blackHole(url.queryParams["formatformatformatformat"]!)
      }
      blackHole(url)
    }

    // Get2 (long-keys)(non-encoded).

    suite.benchmark("Get2.LongKeys.NonEncoded") { state in
      var url = WebURL("http://example.com/?foofoofoofoofoofoo=bar&bazbazbazbazbaz=qux&formatformatformatformat=json&clientclientclientclientclient=mobile")!
      try state.measure {
        blackHole(url.queryParams["formatformatformatformat", "clientclientclientclientclient"])
      }
      blackHole(url)
    }

    // Get (long-keys)(encoded).

    suite.benchmark("Get.LongKeys.Encoded") { state in
      var url = WebURL("http://example.com/?foofoofoofoofoofoo=bar&bazbazbazbazbaz=qux&form%61tform%61tform%61tform%61t=json&clientclientclientclientclient=mobile")!
      try state.measure {
        blackHole(url.queryParams["formatformatformatformat"]!)
      }
      blackHole(url)
    }

    // Get2 (long-keys)(encoded).

    suite.benchmark("Get2.LongKeys.Encoded") { state in
      var url = WebURL("http://example.com/?foofoofoofoofoofoo=bar&bazbazbazbazbaz=qux&form%61tform%61tform%61tform%61t=json&client%63lientclientclientclient=mobile")!
      try state.measure {
        blackHole(url.queryParams["formatformatformatformat", "clientclientclientclientclient"])
      }
      blackHole(url)
    }

    // Append One.

    suite.benchmark("Append.One.Encoded") { state in
      var url = WebURL("http://example.com/#f")!
      try state.measure {
        url.queryParams.append(key: "format", value: "🦆")
      }
      blackHole(url)
    }

    suite.benchmark("Append.One.NonEncoded") { state in
      var url = WebURL("http://example.com/#f")!
      try state.measure {
        url.queryParams.append(key: "format", value: "json")
      }
      blackHole(url)
    }

    // Append Many.

    suite.benchmark("Append.Many.Encoded") { state in
      var url = WebURL("http://example.com/#f")!
      try state.measure {
        url.queryParams += [
          ("foo", "bar"),
          ("format", "🦆"),
          ("client", "mobile")
        ]
      }
      blackHole(url)
    }

    suite.benchmark("Append.Many.NonEncoded") { state in
      var url = WebURL("http://example.com/#f")!
      try state.measure {
        url.queryParams += [
          ("foo", "bar"),
          ("format", "json"),
          ("client", "mobile")
        ]
      }
      blackHole(url)
    }

    // Remove All Where.

    suite.benchmark("RemoveAllWhere") { state in
      var url = WebURL("http://example.com/?foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple#f")!
      try state.measure {
        url.queryParams.removeAll(where: { $0.key.hasPrefix("f") })
      }
      blackHole(url)
    }

    suite.benchmark("RemoveAllWhere-2") { state in
      var url = WebURL("http://example.com/?foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple&foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple#f")!
      try state.measure {
        url.queryParams.removeAll(where: { $0.key.hasPrefix("f") })
      }
      blackHole(url)
    }

    suite.benchmark("RemoveAllWhere-4") { state in
      var url = WebURL("http://example.com/?foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple&foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple&foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple&foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple#f")!
      try state.measure {
        url.queryParams.removeAll(where: { $0.key.hasPrefix("f") })
      }
      blackHole(url)
    }

    suite.benchmark("RemoveAllWhere-8") { state in
      var url = WebURL("http://example.com/?foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple&foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple&foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple&foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple&foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple&foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple&foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple&foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple#f")!
      try state.measure {
        url.queryParams.removeAll(where: { $0.key.hasPrefix("f") })
      }
      blackHole(url)
    }


    // Set.

    suite.benchmark("Set.Single") { state in
      var url = WebURL("http://example.com/?foo=bar&client=mobile&format=json&cream=cheese&fish&chips&fruit=apple#f")!
      try state.measure {
        url.queryParams.set(key: "format", to: "xml")
      }
      blackHole(url)
    }

    suite.benchmark("Set.Multiple") { state in
      var url = WebURL("http://example.com/?foo=bar&client=mobile&format=json&cream=cheese&fish&chips&format=plist&format#f")!
      try state.measure {
        url.queryParams.set(key: "format", to: "xml")
      }
      blackHole(url)
    }

    suite.benchmark("Set.Append") { state in
      var url = WebURL("http://example.com/?foo=bar&client=mobile&format=json&cream=cheese&fish&chips&format=plist&format#f")!
      try state.measure {
        url.queryParams.set(key: "new", to: "appended")
      }
      blackHole(url)
    }

    suite.benchmark("Set.Remove.Single") { state in
      var url = WebURL("http://example.com/?foo=bar&client=mobile&format=json&cream=cheese&fish&chips&format=plist&format#f")!
      try state.measure {
        url.queryParams["cream"] = nil
      }
      blackHole(url)
    }

    suite.benchmark("Set.Remove.Multiple") { state in
      var url = WebURL("http://example.com/?foo=bar&client=mobile&format=json&cream=cheese&fish&chips&format=plist&format#f")!
      try state.measure {
        url.queryParams["format"] = nil
      }
      blackHole(url)
    }

    suite.benchmark("Set.Remove.None") { state in
      var url = WebURL("http://example.com/?foo=bar&client=mobile&format=json&cream=cheese&fish&chips&format=plist&format#f")!
      try state.measure {
        url.queryParams["doesNotExist"] = nil
      }
      blackHole(url)
    }
  }

#endif
