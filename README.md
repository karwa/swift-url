# **WebURL**

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkarwa%2Fswift-url%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/karwa/swift-url)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkarwa%2Fswift-url%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/karwa/swift-url)

A new URL type for Swift. 

<h3>🌐&nbsp;&nbsp;Standards Compliant</h3>

WebURL fully supports the [latest URL Standard](https://url.spec.whatwg.org/), which specifies how modern browsers such as Safari and Chrome interpret URLs. It includes support for Unicode domain names (IDNA). 

Foundation's `URL` and `URLComponents` each conform to different standards (about 20 years old) and _neither_ of them match how browsers and other modern software such as NodeJS processes URLs. WebURL does.
<br/>

<h3>🍭&nbsp;&nbsp;Delightful to Use</h3>

We take full advantage of Swift to offer a rich, expressive API that encourages modern best practices and ways of working with URLs. Common tasks like reading or modifying a URL's path or query are easier to do, more efficient, and help you avoid subtle mistakes. 

Even asking whether two URLs are `==` is full of surprising edge-cases when working with Foundation's `URL`. WebURL has greatly simplified semantics, which helps make your applications more robust and matches how you probably think about URLs. 
<br/>

<h3>🔗&nbsp;&nbsp;🧳&nbsp;&nbsp;Portable, Interoperable</h3>

The core WebURL library has no external dependencies or platform-specific behavior. Everything works the same everywhere, and <ins>**everything fully back-deploys**</ins>.

And thanks to integration libraries that come with this package, WebURL still works seamlessly with `Foundation` and `swift-system`. We've also ported `async-http-client` to use WebURL, which shows how easy it is for `swift-nio`-based projects to adopt.
<br/>

<h3>⚡️&nbsp;&nbsp;Fast</h3>

Despite offering very high-level APIs, WebURL _also_ delivers great performance and low memory use. Extra effort has been spent on optimizing common operations such as converting URLs to/from strings (such as from JSON), or making efficient in-place modifications.

The API uses the concept of write-through views to expose its lower-level generic implementation in a separate scope, without polluting the rest of the API. This allows high-volume workflows to achieve minimal overheads (for example, applications which parse lists of URLs or scan data can do so directly from the bytes of a file).
<br/>

_(and it's written in **100% Swift**)_.

<br/>

📚 **Check out the [Documentation][weburl-docs] to learn more** 📚

<br/>

# Using WebURL in your project

To use this package in a SwiftPM project, you need to set it up as a package dependency:

```swift
// Add the package as a dependency.
dependencies: [
  .package(url: "https://github.com/karwa/swift-url", .upToNextMinor(from: "0.4.0"))
]

// Then add the WebURL library as a target dependency.
targets: [
  .target(
    name: "<Your target>",
    // 👇 Add this line 👇
    dependencies: [ .product(name: "WebURL", package: "swift-url") ]
  )
]
```

And with that, you're ready to start using `WebURL`:

```swift
import WebURL

var url = WebURL("https://github.com/karwa/swift-url")!
url.scheme   // "https"
url.hostname // "github.com"
url.path     // "/karwa/swift-url"

url.pathComponents.removeLast(2)
// "https://github.com/"

url.pathComponents += ["apple", "swift"]
// "https://github.com/apple/swift"
```

📚 Check out the [Documentation][weburl-docs] to learn about WebURL's API 📚
<br/>
<br/>

## 🔗 Integration with Foundation

The `WebURLFoundationExtras` compatibility library allows you to convert between WebURL and Foundation `URL` values, including making URLSession requests with WebURLs.

To make `WebURLFoundationExtras` available, add it to your target dependencies and import it from your code.

```swift
targets: [
  .target(
    name: "<Your target>",
    dependencies: [
      .product(name: "WebURL", package: "swift-url"),
      // 👇 Add this line 👇
      .product(name: "WebURLFoundationExtras", package: "swift-url")
    ]
  )
]
```

With that, you can take full advantage of `WebURL`, while keeping compatibility with existing clients. Again, since WebURL is a fully portable package solution, you can even take advantage of features such as Unicode domain names (IDNA), and <ins>it all back-deploys, effortlessly</ins>.

```swift
import Foundation
import WebURL
import WebURLFoundationExtras

// Make URLSession requests using WebURL, including IDNA support.
let task = 
  URLSession.shared.dataTask(with: WebURL("https://😀.example.com/")!) {
    data, response, error in
    // Works!
  }

// Also supports Swift concurrency.
let (data, _) = 
  try await URLSession.shared.data(from: WebURL("https://数据.example.com/")!)

// URL <-> WebURL conversion allows incremental adoption.
public func connect(to url: Foundation.URL) throws {
  guard let webURL = WebURL(url) else {
    throw InvalidURLError()
  }
  // Internal code uses WebURL...
}
```

For more information about why `WebURL` is a great choice even for applications and libraries using Foundation, and a discussion about how to safely work with multiple URL standards, read: [Using WebURL with Foundation][using-weburl-with-foundation].
<br/>
<br/>

## 🔗 Integration with swift-system

The `WebURLSystemExtras` library allows you to convert between `file:` URLs and `FilePath`s. That's actually quite a complex operation because it has never been standardized and there are lots of legacy issues to understand, but we took the time and created a **great** implementation. The trickiest platform is always Windows, so we based our implementation on Chromium rather than Foundation, with extra security filters inspired by `rust-url` and our own research, and built a [comprehensive test database](/Sources/WebURLTestSupport/TestFilesData/file_url_path_tests.json) to make sure we handled all the known edge-cases.

That means WebURL has excellent support for both POSIX (Apple/Linux/etc) and Windows paths, including legacy, pre-Unicode file URLs. There are _a lot_ of documents whose names use pre-Unicode text encodings (e.g. SHIFT-JIS in Japan, or EUC-KR in South Korea), and they still need their URLs to work. It's tricky (Unicode is definitely better), but we should support them just as well as Chrome does. We're making a big effort to be the best way to work with `file:` URLs, on all platforms Swift supports.

 To make `WebURLSystemExtras` available, add it to your target dependencies and import it from your code.

```swift
.target(
  name: "<Your target>",
  dependencies: [
    .product(name: "WebURL", package: "swift-url"),
    // 👇 Add this line 👇
    .product(name: "WebURLSystemExtras", package: "swift-url")
  ]
)
```

And that's it - you're good to go! It does a lot, but it's super easy to use!

```swift
import System
import WebURL
import WebURLSystemExtras

func openFile(at url: WebURL) throws -> FileDescriptor {
  // WebURL -> FilePath
  let path = try FilePath(url: url)
  return try FileDescriptor.open(path, .readOnly)
}
```
<br/>

## 🧪 async-http-client Port

Our port of [async-http-client](https://github.com/karwa/async-http-client) uses WebURL for _all_ of its internal URL handling. It's the best Swift library for ensuring your HTTP requests use web-compatible URL processing, and is a great demonstration of how to adopt WebURL in a library using `swift-nio`. It keeps all the features and even (mostly) keeps compatibility with the existing `Foundation.URL` API.

The port also has an experimental mode which allows it to be built without any Foundation dependency at all. This relies on a non-public standard library API to replace the one call we use from Foundation, so for now it is an **opt-in** feature, but everything works and there are some significant performance advantages from it. Lots of developers have been trying to look beyond Foundation for next-generation, pure Swift libraries, but until now URLs have been an obstacle; they're not trivial, and since they get passed around a lot as a currency type, any replacement needs to meet or exceed the capabilities and ergonomics of `URL`, `URLComponents`, and related APIs for things like percent-encoding. WebURL does all of that.

**Note:** We'll be updating this port periodically, so if you wish to use it in an application we recommend making a fork and pulling in changes as you need.

```swift
import AsyncHTTPClient
import WebURL

let client = HTTPClient(eventLoopGroupProvider: .createNew)

// The async API uses WebURL behind the scenes (in our port).
do {
  let request = HTTPClientRequest(url: "https://github.com/karwa/swift-url/raw/main/README.md")
  let response = try await client.execute(request, timeout: .seconds(30)).body.collect()
  print(String(decoding: response.readableBytesView, as: UTF8.self))
  // "# WebURL A new URL type for Swift..."
}

// Also supports the traditional NIO EventLoopFuture API.
do {
  let url = WebURL("https://github.com/karwa/swift-url/raw/main/README.md")!

  let response = try client.execute(request: try HTTPClient.Request(url: url))
    .map { response in
      response.body.map { String(decoding: $0.readableBytesView, as: UTF8.self) }
    }
    .wait()
  print(response)
  // "# WebURL A new URL type for Swift..."
}
```
<br/>

# 🗺 Project Status & Roadmap

## Standards Compliance

WebURL fully implements the latest version of the URL Standard.

We validate conformance using the [shared `web-platform-tests`](https://github.com/web-platform-tests/wpt/) used by the major browsers and other libraries. All constructor, setter, and IDNA tests pass ([code](Tests/WebURLTests/WebPlatformTests.swift)), and our implementation of IDNA is validated by these and Unicode's UTS46 conformance test suite ([code](Tests/IDNATests/UTS46ConformanceTests.swift)).

If you find any situations where WebURL is not producing the correct result, please open a GitHub issue.

## API Stability and Roadmap

While the package is still pre-1.0, there are only limited API stability guarantees.

> **Important**:
>
> The 0.x.x versions treat MINOR version numbers like MAJOR version numbers. 
>
> That means there will be no source-breaking changes between 0.3.x and 0.3.y,
> but we want the ability to make source-breaking changes between 0.3.x to 0.4.0 if necessary.
>
> For stability, use a `.upToNextMinor(from: ...)` version constraint.<br/>
> For the latest release, use `.upToNextMajor(from: ...)`.

Version 1.0 is coming soon. I think the current API has the correct shape and scope, and its behavior should be relatively uncontroversial. 

The one API I'm less sure about is `formParams` (for working with the URL's query). It has some nice ideas, but its behavior comes from Javascript's `URLSearchParams` class. That class has a number of quirks that even JS developers don't really love, so we should rethink how we want to approach query parameters before locking down the API.

There are also some areas where the language falls short. The URL Standard is a _living standard_, so we need to be careful about locking-in details that might realistically change. One issue is that they might support new kinds of host one day (currently it is only domains/ipv4/ipv6), and we _really_ want to expose this data as a Swift enum - [`WebURL.Host`][weburl-docs-host]. But enums in Swift are exhaustive, so if we added a new case to that enum in an update, that would be a source-breaking change. The result is that we can only support new kinds of host together with major version increments (e.g. 1.x -> 2.0).

Swift [_has_ non-exhaustive enums][swift-nonfrozen-enum], which force `switch` statements to handle `@unknown default:` patterns and allowing libraries to add new cases later. You see that in SDK libraries, but unfortunately, it is not available to source packages. This API really needs to be an enum to be usable though; so, painful as it is, we're accepting that limitation. We consider it unlikely that the URL Standard would add new kinds of host any time soon, though; it's not a common occurrence.

Other than that, I'm relatively happy with how things are.

If there's anything _you think_ could be improved, this is a great time to let me know! Open a GitHub issue or post to the [Swift forums][swift-forums-weburl].
<br/>
<br/>

# 💝 Sponsorship

I'm creating this library because I think that Swift is a great language, but it lacked a high-quality, modern library for handling URLs. It has taken a lot of time to get WebURL to this stage, and there is still a lot that can be done with it. If you'd like to show support for the project, consider donating a coffee or something.
<br/>
<br/>

# ℹ️ FAQ

## How do I leave feedback?

Open a GitHub issue or post to the [Swift forums][swift-forums-weburl].

## Are pull requests/review comments/questions welcome?

Most definitely!

## Is this production-ready?

I think so. With the caveat that the API is not yet stable across minor versions, only patch versions.

Testing and reliability have been taken extremely seriously from the beginning. The implementation is extensively tested, including against the shared `web-platform-tests` and Unicode conformance tests, used by the major browsers and other libraries. Having those shared test suites is a really valuable resource and should give you confidence that WebURL is actually interpreting the standard as other projects such as WebKit do.

The other library features are also extensively tested, with ~90% coverage, and many difficult-to-test assertions are checked using fuzz-testing (for example, that parsing and serialization are idempotent, that Foundation/WebURL conversions are safe, etc), so the behavior is well understood.

The benchmarks package available in this repository helps ensure we have consistent performance across a variety of devices and can measure any regressions. We are also mindful of code-size and do what we can to keep it down, while implementing the entire standard.

## Why the name `WebURL`?

1. `WebURL` is short but still distinct enough from Foundation's `URL`.

2. The WHATWG works on technologies for the web platform. By following the WHATWG URL Standard, `WebURL` could be considered a kind of "Web-platform URL".


[swift-forums-weburl]: https://forums.swift.org/c/related-projects/weburl/73
[weburl-docs]: https://karwa.github.io/swift-url/main/documentation/weburl/
[using-weburl-with-foundation]: https://karwa.github.io/swift-url/main/documentation/weburl/foundationinterop
[weburl-docs-host]: https://karwa.github.io/swift-url/main/documentation/weburl/weburl/host-swift.enum
[swift-nonfrozen-enum]: https://docs.swift.org/swift-book/ReferenceManual/Statements.html#ID602