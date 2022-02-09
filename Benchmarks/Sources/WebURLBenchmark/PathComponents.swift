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

/// Benchmarks the WebURL `.pathComponents` view.
///
let PathComponents = BenchmarkSuite(name: "PathComponents") { suite in

  // Iteration.

  suite.benchmark("Iteration.Small.Forwards") { state in
    var url = WebURL("http://example.com/hello/this/a/path/with/a/couple/of/components")!
    try state.measure {
      for component in url.pathComponents {
        blackHole(component)
      }
    }
    blackHole(url)
  }

  suite.benchmark("Iteration.Small.Reverse") { state in
    var url = WebURL("http://example.com/hello/this/a/path/with/a/couple/of/components")!
    try state.measure {
      for component in url.pathComponents.reversed() as ReversedCollection {
        blackHole(component)
      }
    }
    blackHole(url)
  }

  suite.benchmark("Iteration.Long.Forwards") { state in
    var url = WebURL("http://example.com/hello/this/a/path/with/a/couple/of/components/hello/this/a/path/with/a/couple/of/components/hello/this/a/path/with/a/couple/of/components/hello/this/a/path/with/a/couple/of/components//hello/this/a/path/with/a/couple/of/components")!
    try state.measure {
      for component in url.pathComponents {
        blackHole(component)
      }
    }
    blackHole(url)
  }

  suite.benchmark("Iteration.Long.Reverse") { state in
    var url = WebURL("http://example.com/hello/this/a/path/with/a/couple/of/components/hello/this/a/path/with/a/couple/of/components/hello/this/a/path/with/a/couple/of/components/hello/this/a/path/with/a/couple/of/components//hello/this/a/path/with/a/couple/of/components")!
    try state.measure {
      for component in url.pathComponents.reversed() as ReversedCollection {
        blackHole(component)
      }
    }
    blackHole(url)
  }

  // Append.

  suite.benchmark("Append.Single") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.pathComponents.append("foo")
    }
    blackHole(url)
  }

  suite.benchmark("Append.Multiple") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.pathComponents += ["foo", "bar", "baz"]
    }
    blackHole(url)
  }

  // RemoveLast.

  suite.benchmark("RemoveLast.Single") { state in
    var url = WebURL("http://example.com/foo/bar/baz")!
    try state.measure {
      url.pathComponents.removeLast()
    }
    blackHole(url)
  }

  suite.benchmark("RemoveLast.Multiple") { state in
    var url = WebURL("http://example.com/foo/bar/baz/qux")!
    try state.measure {
      url.pathComponents.removeLast(3)
    }
    blackHole(url)
  }

  // ReplaceSubrange.

  suite.benchmark("ReplaceSubrange.Shrink") { state in
    var url = WebURL("http://example.com/foo/bar/baz/qux/")!
    let start = url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 1)
    let end   = url.pathComponents.index(start, offsetBy: 2)
    try state.measure {
      url.pathComponents.replaceSubrange(start..<end, with: ["test"])
    }
    blackHole(url)
  }

  suite.benchmark("ReplaceSubrange.Grow") { state in
    var url = WebURL("http://example.com/foo/bar/baz/qux/")!
    let start = url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 1)
    let end   = url.pathComponents.index(start, offsetBy: 2)
    try state.measure {
      url.pathComponents.replaceSubrange(start..<end, with: ["test", "with", "more", "components"])
    }
    blackHole(url)
  }
}
