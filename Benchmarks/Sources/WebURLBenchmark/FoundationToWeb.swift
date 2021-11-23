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

/// Benchmarks the `WebURL.init(Foundatoin.URL)` constructor.
///
let foundationToWeb = BenchmarkSuite(name: "FoundationToWeb") { suite in

  // Simple http(s) URLs which have the same basic structure:
  //
  // - A couple of path components of varying lengths, no '.' or '..' components.
  // - A query parameter with a couple of key-value pairs.
  // - Nothing needs percent-encoding, path does not need simplifying.
  // - Less than 255 characters.
  // - Essentially, the average URL you might find on a webpage like reddit or Wikipedia.

  let average_urls = [
    #"http://example.com/foo/bar/baz?a=b&c=d&e=f"#,
    #"http://foobar.net/bar?baz=qux&search=nothing#top"#,
    #"http://localhost/one/two?coffee"#,
    #"http://127.0.0.1:8080/one/two?coffee"#,
    #"http://[::1]:8080/one/two?coffee"#,

    #"https://www.reddit.com/r/mildlyinteresting/comments/lwhnig/locals_in_puerto_rico_painted_this_mural_they/gphk84q?utm_source=share&utm_medium=web2x&context=3"#,
    #"https://www.reddit.com/r/mildlyinteresting/comments/lvbc3u/i_found_a_mushroom_that_looks_like_a_fried_egg/gpc49is?utm_source=share&utm_medium=web2x&context=3"#,
    #"https://www.reddit.com/r/mildlyinteresting/comments/lwm6zn/my_friend_drunkenly_bought_sunglasses_for_their/gpiaigr?utm_source=share&utm_medium=web2x&context=3"#,
    #"https://www.reddit.com/r/mildlyinteresting/comments/lwtlsi/this_tree_that_grew_into_an_old_gate/gpj3g0e?utm_source=share&utm_medium=web2x&context=3"#,
    #"https://www.reddit.com/r/mildlyinteresting/comments/lwpcvh/this_redfleshed_apple/gpinqsj?utm_source=share&utm_medium=web2x&context=3"#,
    #"https://www.reddit.com/r/mildlyinteresting/comments/lrct3m/this_mini_evolution_i_saw_in_london/gokxoqv?utm_source=share&utm_medium=web2x&context=3"#,
    #"https://www.reddit.com/r/mildlyinteresting/comments/lw2um3/this_rock_that_looks_like_a_strawberry/gpf7sfb?utm_source=share&utm_medium=web2x&context=3"#,
    #"https://www.reddit.com/r/mildlyinteresting/comments/lwcdhf/4_layers_of_flooring_in_this_house_im_remodeling/gpglqx9?utm_source=share&utm_medium=web2x&context=3"#,
    #"https://www.reddit.com/r/mildlyinteresting/comments/lwo5qh/terracotta_piggy_from_poliochni_greece_23002500_bc/gpig723?utm_source=share&utm_medium=web2x&context=3"#,
    #"https://www.reddit.com/r/mildlyinteresting/comments/lw8b67/this_set_of_stair_cases_that_you_cant_access_one/gpftyox?utm_source=share&utm_medium=web2x&context=3"#,
    #"https://www.reddit.com/r/mildlyinteresting/comments/lwhcrk/shhh_hes_sleeping/gphd357?utm_source=share&utm_medium=web2x&context=3"#,
    #"https://www.reddit.com/r/mildlyinteresting/comments/lvns4s/this_imported_salmon_so_tightly_wrapped_in/gpcw2uu?utm_source=share&utm_medium=web2x&context=3"#,
  ].map{ URL(string: $0)! }

  suite.benchmark("AverageURLs") {
    for url in average_urls {
      blackHole(WebURL(url))
    }
  }

  let ipv4_urls = [
    #"http://0xbadf00d/"#,
    #"http://127.0.0.1/"#,
    #"http://10.9.9.8/"#,
    #"http://217.234.090/"#,
    #"http://0xbe.0xfc9409"#,
    #"http://0xc239994e"#,
    #"http://0346.0212.0x2e.0242"#,
    #"http://0323.0xf3.0x37.0x1f"#,
    #"http://773488775"#,
    #"http://0xe1.0245.237.217"#,
    #"http://0123.0x70646e"#,

    #"http://0437125212"#,
    #"http://032.2148585"#,
    #"http://031032371445"#,
    #"http://0x48d25db9"#,
    #"http://0377.5601714"#,
    #"http://0171.0250.153.57"#,
    #"http://86.0217.0x7dea"#,
    #"http://0xd0.0111.230.04"#,
    #"http://0xde.0x3e.0111.0xba"#,
    #"http://155.0xc8.54099"#,

    #"http://0x7d.0x86b0be"#,
    #"http://034.232.0260.0x4f"#,
    #"http://0x38.0351.0301.180"#,
    #"http://0115.102.0x34e"#,
    #"http://250.0x158115"#,
    #"http://0x34.0304.072342"#,
    #"http://10.0x28.0376.0x10"#,
    #"http://012215540245"#,
    #"http://0xe8.12776487"#,
    #"http://0120.163.15898"#,
    #"http://052.0xaa.0113352"#,
  ].map { URL(string: $0)! }

  suite.benchmark("IPv4") {
    for url in ipv4_urls {
      blackHole(WebURL(url))
    }
  }

  let ipv6_urls = [
    #"http://[7225:7eb:d838:cc21:c3a4:dba8:1fad:1f46]"#,
    #"http://[0:0:0:0:0:0:78b9:301c]"#,
    #"http://[::21.37.66.27]"#,
    #"http://[0:0:0:0:0:0:355a:62a8]"#,
    #"http://[d979:0:0:0:0:0:0:0]"#,
    #"http://[::48.79.54.144]"#,
    #"http://[ed8d:4670:6d0a:ee7f:78b:eb09:904d:b44]"#,
    #"http://[5a3c:bd64::1bcf:d69f:4b8]"#,
    #"http://[0:0:0:0:0:0:dfa7:5ce3]"#,
    #"http://[::75.33.222.220]"#,

    #"http://[::155.147.186.251]"#,
    #"http://[::48.161.242.105]"#,
    #"http://[0:0:0:0:0:0:a523:d264]"#,
    #"http://[b6ea:cd3e:ca43:6fe3:aceb::]"#,
    #"http://[::476c:c763]"#,
    #"http://[977:2aa0:6bf5:1507:77ba:dfe1:2976:77ca]"#,
    #"http://[::167.126.187.247]"#,
    #"http://[::53.197.134.182]"#,
    #"http://[6880:1845:26e0:6df1:f7e6:9e4b:7b7:7bc4]"#,
    #"http://[1f09:bebc:131f:3de7:8bfb:3192:9f6a:fc64]"#,
    #"http://[::9bc8:da85]"#,

    #"http://[3ba8:7206:a9ab:83b1:e38e:7bc5:e83d:af51]"#,
    #"http://[f821:b719:3fc6:5bd1:b000:d00c:1edb:75e8]"#,
    #"http://[93fc:aedd:a15:50fb:dc62::]"#,
    #"http://[3285:c199:3e58:6c80:d1:70be:f65a:19fd]"#,
    #"http://[b631:b446:5572:4548:f13d:979e:18a4:34b5]"#,
    #"http://[0:0:0:0:0:0:a2ba:91e0]"#,
    #"http://[cd58:be56:ede0:d2c3:2d5:0:0:7712]"#,
    #"http://[::15.185.11.7]"#,
    #"http://[472b:2877:0:0:0:0:236e:e76b]"#,
    #"http://[::8462:4e04]"#,
    #"http://[985e:e239:3599:6ad8:0:0:1326:b995]"#,
  ].map { URL(string: $0)! }

  suite.benchmark("IPv6") {
    for url in ipv6_urls {
      blackHole(WebURL(url))
    }
  }
}
