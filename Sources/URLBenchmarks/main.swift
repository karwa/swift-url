import Foundation
import WebURL

// This is a really simple benchmark.
// Really, it should include more things like IP addresses and such, but
// it seems like NSURL doesn't really try to parse and re-format those at all... so what's the point?

let testURLs = repeatElement(
  [
    "http://example.com/some/path/who/cares",
    "ftp://user:password@example.com:21/some/path/who/cares",
    "file:///usr/local/bin/swift",
    "https://example.com/some/path/who/cares?query=present&kettle=on#brewing",
    "http://chart.apis.google.com/chart?chs=500x500&chma=0,0,100,100&cht=p&chco=FF0000%2CFFFF00%7CFF8000%2C00FF00%7C00FF00%2C0000FF&chd=t%3A122%2C42%2C17%2C10%2C8%2C7%2C7%2C7%2C7%2C6%2C6%2C6%2C6%2C5%2C5&chl=122%7C42%7C17%7C10%7C8%7C7%7C7%7C7%7C7%7C6%7C6%7C6%7C6%7C5%7C5&chdl=android%7Cjava%7Cstack-trace%7Cbroadcastreceiver%7Candroid-ndk%7Cuser-agent%7Candroid-webview%7Cwebview%7Cbackground%7Cmultithreading%7Candroid-source%7Csms%7Cadb%7Csollections%7Cactivity|Chart",
  ], count: 10
).joined()


func doTest(iterations: Int, _ test: () -> Void) {
  let start = CFAbsoluteTimeGetCurrent()
  for _ in 0..<iterations {
    test()
  }
  let end = CFAbsoluteTimeGetCurrent()

  print(
    """
    Finished. \(iterations) iterations.
    Average time: \(((end - start)/Double(iterations)) * 1000) ms
    """)
}

sleep(1)
print("NSURL")
doTest(iterations: 1_000) {
  for str in testURLs {
    _ = URL(string: str)
  }
}
sleep(1)
print("WebURL")
doTest(iterations: 1_000) {
  for str in testURLs {
    _ = WebURL(str, base: nil)
  }
}
