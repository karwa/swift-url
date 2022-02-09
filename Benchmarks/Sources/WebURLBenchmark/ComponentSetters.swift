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

/// Benchmarks WebURL component setters (e.g. `url.query = "..."`).
///
let ComponentSetters = BenchmarkSuite(name: "ComponentSetters") { suite in

  // Scheme.

  suite.benchmark("Unique.Scheme") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.scheme = "hTtPs"
      url.scheme = "wSs"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Scheme.Long") { state in
    var url = WebURL("foo://example.com/")!
    try state.measure {
      url.scheme = "thisisaverylongschemebutistechnicallyvalid-ihopenobodyisusingschemesthislongthough-welltheymight-buticantthinkofareasonto"
    }
    blackHole(url)
  }

  // Username.

  suite.benchmark("Unique.Username") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.username = "username"
      url.username = "karl"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Username.PercentEncoding") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.username = "some username"
      url.username = "🦆"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Username.Long") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.username = "thisisaverylongusernamewhichisalmostcertainlynotusedbyanybodybutitsworthbenchmarkingthebehaviourtoseehowitshandled"
    }
    blackHole(url)
  }

  // Password.

  suite.benchmark("Unique.Password") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.password = "password"
      url.password = "somesecret"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Password.PercentEncoding") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.password = "some password"
      url.password = "🦆🦆🦆"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Password.Long") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.password = "thisisaverylongpasswordwhichisalmostcertainlynotusedbyanybodybutitsworthbenchmarkingthebehaviourtoseehowitshandled"
    }
    blackHole(url)
  }

  // Hostname.

  suite.benchmark("Unique.Hostname.Domain.ASCII") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.hostname = "foo.bar.net"
      url.hostname = "m.cash.somebank.net"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Hostname.IPv4") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.hostname = "192.168.0.34"
      url.hostname = "0xBADF00D"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Hostname.IPv6") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.hostname = "[2608::3:5]"
      url.hostname = "[2001:0db8:85a3:0000:0000:8a2e:0370:7334]"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Hostname.Opaque") { state in
    var url = WebURL("foo://example.com/")!
    try state.measure {
      url.hostname = "some-hostname"
      url.hostname = "m.cash.somebank.net"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Hostname.Domain.ASCII.Long") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.hostname = "this.is.a.very.long.domain.which.totally.isnt.valid.because.dns.has.length.restrictions.but.those.arent.considered.at.the.url.level"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Hostname.Opaque.Long") { state in
    var url = WebURL("foo://example.com/")!
    try state.measure {
      url.hostname = "this-is-a-very-long-hostname-which-is-probably-wildly-unrealistic-and-not-used-by-anybody-but-we-have-to-handle-it-so-might-as-well-see-how-it-fares"
    }
    blackHole(url)
  }

  // Path.

  suite.benchmark("Unique.Path.Simple") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.path = "/some/path/with/a/bunch/of/components.txt"
      url.path = "/how/much/wood/would/a/woodchuck/chuck/if/a/woodchuck/could/chuck/wood"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Path.DotDot") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.path = "/some/../path/./with/./dot/../components/"
      // Despite the length, this only results in 10 components.
      url.path =
        "/a/./woodchuck/../would/../chuck/../as/much/wood/../as/a/./woochuck/../could/../chuck/../if/a/../woochuck/could/chuck/wood/.."
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Path.PercentEncoding") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.path = "/a/🐢/path/🦖/./🦆/"
      url.path = "/👶/🙍‍♂️/👨/👴"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Path.Simple.Long") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.path = "/this/is/a/long/path/which/unlike/the/other/long/tests/might/actually/be/kinda/sorta/realistic/although/probably/not/at/the/length/were/going/to"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Path.PercentEncoding.Long") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.path = "/there once was a 👨 from Nantucket/who kept all his 💵 in a bucket/but his 👧, named Nan/🏃‍♀️ away with a 🙍‍♂️/and as for the bucket? nantucket."
    }
    blackHole(url)
  }

  // Query

  suite.benchmark("Unique.Query") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.query = "from=EUR&to=USD&amount=500"
      url.query = "utm_source=share&utm_medium=web2x&context=3"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Query.PercentEncoding") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.query = #"Quoth the 🐧 “Nevermore.”"#
      url.query = "Gotta love them spaces!"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Query.Long") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.query = "chs=500x500&chma=0,0,100,100&cht=p&chco=FF0000%2CFFFF00%7CFF8000%2C00FF00%7C00FF00%2C0000FF&chd=t%3A122%2C42%2C17%2C10%2C8%2C7%2C7%2C7%2C7%2C6%2C6%2C6%2C6%2C5%2C5&chl=122%7C42%7C17%7C10%7C8%7C7%7C7%7C7%7C7%7C6%7C6%7C6%7C6%7C5%7C5&chdl=android%7Cjava%7Cstack-trace%7Cbroadcastreceiver%7Candroid-ndk%7Cuser-agent%7Candroid-webview%7Cwebview%7Cbackground%7Cmultithreading%7Candroid-source%7Csms%7Cadb%7Csollections%7Cactivity|Chart"
    }
    blackHole(url)
  }

  // Fragment

  suite.benchmark("Unique.Fragment") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.fragment = "title-of-some-heading"
      url.fragment = "not-too-big-not-too-small"
    }
    blackHole(url)
  }

  suite.benchmark("Unique.Fragment.PercentEncoding") { state in
    var url = WebURL("http://example.com/")!
    try state.measure {
      url.fragment = #"Quoth the 🐧 “Nevermore.”"#
      url.fragment = "Gotta love them spaces!"
    }
    blackHole(url)
  }
}
