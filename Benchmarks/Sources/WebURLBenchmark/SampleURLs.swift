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

/// A collection of sample URLs shared by several benchmark suites.
///
enum SampleURLs {}


// --------------------------------------------
// MARK: - Average HTTP(S) URLs
// --------------------------------------------


extension SampleURLs {

  /// 20 "Average" HTTP(S) URLs.
  ///
  /// The broad pattern is that these URLs:
  ///
  /// - Have a couple of path components of varying lengths, no '.' or '..' components which need to be simplified.
  /// - Have hostnames which are domains, do not require IDNA, and do not specify a port.
  /// - Are less than 255 characters.
  /// - Do not need percent-encoding.
  /// - Sometimes have a fragment, or query string with a couple of key-value pairs.
  ///
  /// Essentially, these are the kind of URLs you might find on a web page like reddit or Wikipedia.
  ///
  internal static let AverageHTTPURLs: [String] = [
    #"http://example.com/foo/bar/baz?a=b&c=d&e=f"#,
    #"http://foobar.net/bar?baz=qux&search=nothing#top"#,
    #"http://localhost/one/two?coffee"#,

    #"https://en.m.wikipedia.org/wiki/Swift_(programming_language)"#,
    #"https://en.wikipedia.org/w/index.php?title=Swift_(programming_language)&action=edit"#,
    #"https://en.wikipedia.org/w/index.php?title=Swift_programming_language&redirect=no"#,
    #"https://en.wikipedia.org/wiki/Swift_(parallel_scripting_language)"#,
    #"https://en.wikipedia.org/wiki/Swift_programming_language#cite_note-wikidata-403842b15ffe0c0f31409930a70ef25d8e065888-v3-3"#,

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
  ]

  /// The same 20 URLs as `AverageHTTPURLs`, but with some tabs and newlines thrown in.
  ///
  /// Each URL includes 5 tabs and 3 newlines.
  ///
  internal static let AverageHTTPURLs_TabsAndNewlines: [String] = [
    "htt\t\tp:\n//exa\nmpl\te.com/foo/bar/\tbaz?\na\t=b\n&c=d&e=f",
    "\t\nhttp\t://fooba\nr.net\t/bar?baz=q\tux&search=nothing#top\n\t",
    "\nhttp\n:\t/\t/localho\ns\tt/one/two\t?co\tffee",

    #"https://e\tn.m\t\n.wikipedia.org\n/w\tiki\t/Swift_\t(programming_language)\n"#,
    #"h\nttps\t:\t/\t/en.wikipedia\n.org/w/index.php\t?\ntitle\t=Swift_(programming_language)&action=edit"#,
    #"https\n:\n/\n/en.wikipedia\t.org/w\t/index.php\t?title=\tSwift_programming_language\t&redirect=no"#,
    #"\n\thttps\t\n://en.wikipedia.org\t/wiki\n/Swift_\t(parallel_scripting_language)\t"#,
    #"https://en.wikipedia.org/\nwiki/Swift_programming_language\t#\ncite_note-\twikidata-40\n3842b15ffe0c0f31409930a70ef25d8e065888-\tv3-3"#,

    "ht\ttps://ww\tw.reddit.com/r/mildlyinteresting/com\tments/lwhnig\n/lo\tcals_in_puerto_rico_painted_this_mural_they/gphk84q\n?utm_source\t=share&utm_medium\n=web2x&context=3",
    "https\t\t://ww\nw.reddit.com/r\t/mildlyinteresting/com\nments/lvbc3u/i_found_a_mushroom_that_looks_like_a_fried_egg/gpc49is?\tutm_source=share&utm_medium\t=web2x&cont\next=3",
    "http\ns://www.r\teddit.com/r/mildlyinte\nresting\t/comments/lwm6zn/my_friend_drunkenly_bought_sunglasses_\tfor_their/gpiaigr?\tutm_source=share&\tutm_medium\n=web2x&context=3",
    "https:/\t/www\n.reddit.com/r/mil\tdlyinterestin\tg/\ncomments/lwtlsi/this_tree_that_grew_into_an_old_gate\t/gpj3g0e?utm_source=share&utm_medium=web2x&\ncon\ttext=3",
    "https\t://www.reddit.com/r/mildlyinterest\ting/comments\t/lwpcvh/t\nhis_redfleshed_apple\t/gpinqsj?utm_sou\trce=share&utm_medium\n\n=web2x&context=3",
    "\nhtt\tp\ts:/\t/www.reddit.com/r/mildlyinteresting/com\tments/lrct3m/\tthis_mini_evolution_i_saw_in_london/gokxoqv?utm_source\n=share&utm_medium=web2x&context=3\n",
    "htt\nps://\twww.reddit.com/r/mi\tldlyintere\nsting/\tcomments/lw2um3/this_rock_that_looks_like_a_strawberry\t\n/gpf7sfb?utm_source=share&utm_medium=we\tb2x&context=3",
    "https:/\t/www\n.reddit.com/r/mildlyinterestin\tg/\tcomments/\tlwcdhf/4_layers_of_flooring_in_this_house_im_remodelin\ng/gpglqx9?utm_source=share&\nutm_medium=web2x&\tcontext=3",
    "https:\n//w\tww.reddit.com/r/mildlyint\teres\nting/\tcomments/lwo5qh/terracotta_piggy_from_poliochni_greece_23002500_bc\t/gpig723?utm_source\t=share&utm_medium=web\n2x&context=3",
    "\t\t\t\nhttps://www.reddit.com/r/mildlyinteresting/comments/lw8b67/this_set_of_stair_cases_that_you_cant_access_one/gpftyox?utm_source=share&utm_medium=web2x&context=3\t\t\n\n",
    "https://ww\nw.redd\tit.c\nom/r/\tmildlyinteresting/comment\ts/lwhcrk/shhh_hes_sleeping\t/gphd357?utm_source=\tshare&utm_medium=web2x&context=\n3",
    "http\ts://ww\n\tw.reddit.com/r/mildlyinteres\tti\nng/comments/lvns4s\t/this_imported_salmon_so_tightly_wrapped_in/gpcw2uu?\tutm_source=share&utm_medium=web2x&\ncontext=3",
  ]
}


// --------------------------------------------
// MARK: - IPv4 Addresses
// --------------------------------------------


extension SampleURLs {

  /// 20 HTTP URLs whose hostnames are exotic IPv4 addresses.
  ///
  /// They have no paths or other components.
  ///
  internal static let ExoticIPv4URLs: [String] = [
    #"http://0xbadf00d/"#,
    #"http://127.0.0.1/"#,
    #"http://10.9.9.8/"#,
    #"http://0120.163.15898"#,
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
  ]

  /// The same 20 URLs as `ExoticIPv4URLs`, but with some tabs and newlines thrown in.
  ///
  /// Each URL includes 3 tabs and 2 newlines.
  ///
  internal static let ExoticIPv4URLs_TabsAndNewlines: [String] = [
    "http://0\nxba\t\tdf0\t0d\n/",
    "http://1\n27.\t\t0.0\t.1\n/",
    "http://1\n0.9\t\t.9.\t8/\n",
    "http://\n0120.\t\t163\t.1\n5898",
    "http://0\nxbe\t\t.0x\tfc\n9409",
    "http://0\nxc2\t\t399\t94\ne",
    "http://0\n346\t\t.02\t12\n.0x2e.0242",
    "http://0\n323\t\t.0x\tf3\n.0x37.0x1f",
    "http://7\n734\t\t887\t75\n",
    "http://0\nxe1\t\t.02\t45\n.237.217",

    "http://0\n123\t\t.0x\t70\n646e",
    "http://04\n371\t\n2521\t2",
    "http://03\n2.2\t\n1485\t85",
    "http://03\n103\t\n2371\t445",
    "http://0x\n48d\t\n25db\t9",
    "http://03\n77.\t\n5601\t714",
    "http://01\n71.\t\n0250\t.153.57",
    "http://86\n.02\t\n17.0\tx7dea",
    "http://0x\nd0.\t\n0111\t.230.04",
    "http://0x\nde.\t\n0x3e\t.0111.0xba",
  ]
}

extension SampleURLs {

  /// 20 HTTP URLs whose hostnames are IPv6 addresses.
  ///
  /// The addresses have a range of formats - including compressed addresses, addresses which could be compressed,
  /// embedded IPv4 addresses, etc. They have no paths or other components.
  ///
  internal static let IPv6URLs: [String] = [
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
    #"http://[::9bc8:da85]"#,
    #"http://[0:0:0:0:0:0:a523:d264]"#,
    #"http://[b6ea:cd3e:ca43:6fe3:aceb::]"#,
    #"http://[::476c:c763]"#,
    #"http://[977:2aa0:6bf5:1507:77ba:dfe1:2976:77ca]"#,
    #"http://[::167.126.187.247]"#,
    #"http://[::53.197.134.182]"#,
    #"http://[6880:1845:26e0:6df1:f7e6:9e4b:7b7:7bc4]"#,
    #"http://[1f09:bebc:131f:3de7:8bfb:3192:9f6a:fc64]"#,
  ]

  /// The same 20 URLs as `IPv6URLs`, but with some tabs and newlines thrown in.
  ///
  /// Each URL includes 3 tabs and 2 newlines.
  ///
  internal static let IPv6URLs_TabsAndNewlines: [String] = [
    "ht\ntp://[\t7225\t:7eb\n:\td838:cc21:c3a4:dba8:1fad:1f46]",
    "ht\ntp://[\t0:0:\t0:0:\n0\t:0:78b9:301c]",
    "ht\ntp://[\t::21\t.37.\n6\t6.27]",
    "ht\ntp://[\t0:0:\t0:0:\n0\t:0:355a:62a8]",
    "ht\ntp://[\td979\t:0:0\n:\t0:0:0:0:0]",
    "ht\ntp://[\t::48\t.79.\n5\t4.144]",
    "ht\ntp://[\ted8d\t:467\n0\t:6d0a:ee7f:78b:eb09:904d:b44]",
    "ht\ntp://[\t5a3c\t:bd6\n4\t::1bcf:d69f:4b8]",
    "ht\ntp://[\t0:0:\t0:0:\n0\t:0:dfa7:5ce3]",
    "ht\ntp://[\t::75\t.33.\n2\t22.220]",

    "http:/\t/\t[:\n:155\n.147.186.251]",
    "http:/\t/\t[:\n:9bc\n8:da85]",
    "http:/\t/\t[0\n:0:0\n:0:0:0:a523:d264]",
    "http:/\t/\t[b\n6ea:\ncd3e:ca43:6fe3:aceb::]",
    "http:/\t/\t[:\n:476\nc:c763]",
    "http:/\t/\t[9\n77:2\naa0:6bf5:1507:77ba:dfe1:2976:77ca]",
    "http:/\t/\t[:\n:167\n.126.187.247]",
    "http:/\t/\t[:\n:53.\n197.134.182]",
    "http:/\t/\t[6\n880:\n1845:26e0:6df1:f7e6:9e4b:7b7:7bc4]",
    "http:/\t/\t[1\nf09:\nbebc:131f:3de7:8bfb:3192:9f6a:fc64]",
  ]
}


// --------------------------------------------
// MARK: - IDNA
// --------------------------------------------


extension SampleURLs {

  /// 10 HTTP(S) URLs with IDNs.
  ///
  /// These are basically like the AverageURLs, with IDNs.
  ///
  internal static let IDNAURLs: [String] = [
    #"http://ₓn--fa-hia.example/foo/bar/baz?a=b&c=d&e=f"#,
    #"http://caf\u{00E9}.fr/bar?baz=qux&search=nothing#top"#,
    #"http://xn--caf-dma.fr/one/two?coffee"#,
    #"https://a.xn--igbi0gl.com/wiki/Swift_(programming_language)"#,
    #"https://a.xn--mgbet1febhkb.com/w/index.php?title=Swift_(programming_language)&action=edit"#,

    #"https://xn--b1abfaaepdrnnbgefbadotcwatmq2g4l/w/index.php?title=Swift_programming_language&redirect=no"#,
    #"https://xn--1ch.com/wiki/Swift_(parallel_scripting_language)"#,
    #"https://국립중앙도서관.한국/foo/bar?baz"#,
    #"https://日本語.jp/foo/bar?baz"#,
    #"http://中国移动.中国/foo/bar?baz"#,
  ]
}
