# **WebURL**

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkarwa%2Fswift-url%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/karwa/swift-url)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkarwa%2Fswift-url%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/karwa/swift-url)

A new URL type for Swift.

- 🌍 **Compliant**. WebURL conforms to the [latest URL Standard](https://url.spec.whatwg.org/), which specifies how modern browsers such as Safari and Chrome interpret URLs.
  
- ⚡️ **Fast**. Tuned for high performance and low memory use.

- 🍭 **Delightful**. The API is designed around modern best practices, and liberal use of Swift features such as generics and zero-cost abstractions make it really expressive and powerful. It's not _just_ easier to use than Foundation's `URL` - more importantly, it's easier to use _correctly_.

- 🧳 **Portable**. The core WebURL library has no dependencies other than the Swift standard library, and no platform-specific behavior.

- 🔗 **Interoperable**. Compatibility libraries allow you to use WebURL's modern, standards-compliant parser and API together with `Foundation` and `swift-system`, and our port of `async-http-client` demonstrates how to use WebURL together with `swift-nio`.

_(and of course, it's written in **100% Swift**)_.

📚 Check out the [Documentation][weburl-docs] to learn more 📚
<br/>
<br/>

# Using WebURL in your project

To use this package in a SwiftPM project, you need to set it up as a package dependency:

```swift
// Add the package as a dependency.
dependencies: [
  .package(
    url: "https://github.com/karwa/swift-url",
    .upToNextMinor(from: "0.3.1")
  )
]

// Then add the WebURL library as a target dependency.
targets: [
  .target(
    name: "<Your target>",
    dependencies: [
      .product(name: "WebURL", package: "swift-url")
    ]
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
url.pathComponents += ["apple", "swift"]
url // "https://github.com/apple/swift"
```

📚 Check out the [Documentation][weburl-docs] to learn about WebURL's API 📚
<br/>
<br/>

## 🔗 Integration with Foundation

The `WebURLFoundationExtras` compatibility library allows you to convert between `WebURL` and Foundation `URL` values, and includes convenience wrappers for many Foundation APIs (such as `URLSession`), allowing them to be used directly with `WebURL` values.

To enable Foundation integration, add the compatibility library to your target dependencies and import it from your code.

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

Now, you can take advantage of `WebURL`'s modern, standards-compliant parser and faster, more convenient API, all while keeping compatibility with existing clients and using `URLSession` to make requests (as is required on Apple platforms).

```swift
import Foundation
import WebURL
import WebURLFoundationExtras

// ℹ️ Make URLSession requests using WebURL.
func makeRequest(to url: WebURL) -> URLSessionDataTask {
  return URLSession.shared.dataTask(with: url) {
    data, response, error in
    // ...
  }
}

// ℹ️ Also supports Swift concurrency.
func processData(from url: WebURL) async throws {
  let (data, _) = try await URLSession.shared.data(from: url)
  // ...
}

// ℹ️ For libraries: move to WebURL without breaking
// compatibility with clients using Foundation's URL.
public func processURL(_ url: Foundation.URL) throws {
  guard let webURL = WebURL(url) else {
    throw InvalidURLError()
  }
  // Internal code uses WebURL...
}
```

For more information about why `WebURL` is a great choice even for applications and libraries using Foundation, and a discussion about how to safely work with multiple URL standards, we **highly recommend** reading: [Using WebURL with Foundation][using-weburl-with-foundation].
<br/>
<br/>

## 🔗 Integration with swift-system

The `WebURLSystemExtras` compatibility library allows you to convert between `file:` URLs and `FilePath`s, using the `swift-system` package or Apple's `System` framework. It has excellent support for both POSIX and Windows paths, with features for security and legacy compatibility (e.g. non-Unicode file names) modelled on Chrome's implementation.
 
To enable `swift-system` integration, add the compatibility library to your target dependencies and import it from your code.

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

And that's it - you're good to go!

```swift
import System
import WebURL
import WebURLSystemExtras

func openFile(at url: WebURL) throws -> FileDescriptor {
  let path = try FilePath(url: url)
  return try FileDescriptor.open(path, .readOnly)
}
```
<br/>

## 🧪 async-http-client Port

Our prototype port of [async-http-client](https://github.com/karwa/async-http-client) uses WebURL for _all_ of its internal URL handling, including processing HTTP redirects. It's the best library available in Swift to ensure your HTTP requests use web-compatible URL processing, and is also a great demonstration of how to adopt WebURL in a library built upon `swift-nio`.

By default, the port uses WebURL's Foundation compatibility for ease of integration, so you can make requests using either URL type, but it can also be built without any Foundation dependency at all - meaning smaller binaries and faster startup times. 

**Note:** We'll be updating the port periodically, so if you wish to use it in an application we recommend making a fork and pulling in changes as you need.

```swift
import AsyncHTTPClient
import WebURL

let client = HTTPClient(eventLoopGroupProvider: .createNew)

// ℹ️ Supports the traditional NIO EventLoopFuture API.
do {
  let url = WebURL("https://github.com/karwa/swift-url/raw/main/README.md")!

  let request = try HTTPClient.Request(url: url)
  let response = try client.execute(request: request).map { response in
    response.body.map { String(decoding: $0.readableBytesView, as: UTF8.self) }
  }.wait()
  print(response)  
  // "# WebURL A new URL type for Swift..."
}

// ℹ️ Also supports Swift concurrency.
do {
  let request = HTTPClientRequest(url: "https://github.com/karwa/swift-url/raw/main/README.md")
  let response = try await client.execute(request, timeout: .seconds(30)).body.collect()
  print(String(decoding: response.readableBytesView, as: UTF8.self))
  // "# WebURL A new URL type for Swift..."
}
```
<br/>

# 📰 Project Status

WebURL is a complete URL library, implementing the latest version of the URL Standard. It currently does not support Internationalized Domain Names (IDNA), but that support is planned.

It is tested against the [shared `web-platform-tests`](https://github.com/web-platform-tests/wpt/) used by the major browsers and other libraries, and passes all constructor and setter tests (other than those which require IDNA). We pool our implementation experience to ensure there is no divergence, and the fact that WebURL passes these tests should give you confidence that it interprets URLs just like the latest release of Safari or `rust-url`.

WebURL also includes a comprehensive set of APIs for working with URLs: getting/setting components, percent-encoding and decoding, manipulating path components, query strings, file paths, etc. Each has these come with additional, very comprehensive sets of tests. The project is regularly benchmarked and fuzz-tested using the tools available in the `Benchmarks` and `Fuzzers` directories respectively.

Being a pre-1.0 package, we reserve the right to make source-breaking changes before committing to a stable API. We'll do our best to keep those to a minimum, and of course, any such changes will be accompanied by clear documentation explaining how to update your code.

If there's anything you think could be improved, this is a great time to let us know! Either open a GitHub issue or post to the [Swift forums][swift-forums-weburl].


## 🗺 Roadmap

Aside from stabilizing the API, the other priorities for v1.0 are:

1. More APIs for query parameters.

   A URL's `query` component is often used as a string of key-value pairs. This usage appears to have originated with HTML forms, and WebURL has excellent support for it already via the `formParams` view -- but these days, by popular convention, it is also used with keys and values that are _not strictly_ form-encoded. This can lead to decoding issues, so we should offer a variant of `formParams` that allows for percent-encoding, not just form-encoding.

   Additionally, we may want to consider making key lookup Unicode-aware. It makes sense, but AFAIK is unprecedented in other libraries and so may be surprising. But it does make a lot of sense. Feedback is welcome.

Looking beyond v1.0, the other features I'd like to add are:

2. Better APIs for `data:` URLs.

   WebURL already supports them as generic URLs, but it would be nice to add specialized APIs for extracting the MIME type and decoding base64-encoded data.
   
3. APIs for relative references.

   All `WebURL`s are absolute URLs (following the standard), and relative references are currently only supported as strings via the [`WebURL.resolve(_:)` method][weburl-resolve].

   It could be valuable to some applications to add richer APIs for reading and manipulating relative references, instead of using only strings. We may also want to calculate the difference between 2 URLs and return the result as a relative reference. It depends on what people actually need, so please do leave feedback.
  
4. Support Internationalized Domain Names (IDNA).

   This is part of the URL Standard, and its position on this list shouldn't be read as downplaying its importance. It is a high-priority item, but is currently blocked by other things.

   There is reason to hope this may be implementable soon. Native Unicode normalization was [recently](https://github.com/apple/swift/pull/38922) implemented in the Swift standard library for String, and there is a desire to expose this functionality to libraries such as this one. Once those APIs are available, we'll be able to use them to implement IDNA.
<br/>
<br/>

# 💝 Sponsorship

I'm creating this library because I think that Swift is a great language, and it deserves a high-quality, modern library for handling URLs. I think it's a really good, production-quality implementation, it has taken a lot of time to get to this stage, and there is still an exciting roadmap ahead. So if you (or the company you work for) benefit from this project, consider donating a coffee to show your support. You don't have to; it's mostly about letting me know that people appreciate it. That's ultimately what motivates me.
<br/>
<br/>

# ℹ️ FAQ

## How do I leave feedback?

Either open a GitHub issue or post to the [Swift forums][swift-forums-weburl].

## Are pull requests/review comments/questions welcome?

Most definitely!

## Is this production-ready?

Yes. With the caveat that the API might see some minor adjustments between now and 1.0.

The implementation is extensively tested, including against the shared `web-platform-tests` used by the major browsers and other libraries, and which we've made _a lot_ of contributions to. As mentioned above, having that shared test suite across the various implementations is a really valuable resource and should give you confidence that WebURL will actually interpret URLs according to the standard.

We also verify a lot of things by regular fuzz-testing (e.g. that parsing and serialization are idempotent, that Foundation conversions are safe, etc), so we have confidence that the behavior is well understood.

Additionally, the benchmarks package available in this repository helps ensure we deliver consistent, excellent performance across a variety of devices.

We've taken testing and reliability extremely seriously from the very beginning, which is why we have confidence in claiming that this is the best-tested URL library available for Swift. To be quite frank, Foundation does not have anything even close to this.

## Why the name `WebURL`?

1. `WebURL` is short but still distinct enough from Foundation's `URL`.

2. The WHATWG works on technologies for the web platform. By following the WHATWG URL Standard, `WebURL` could be considered a kind of "Web-platform URL".

## What is the WHATWG URL Living Standard?

It may be surprising to learn that there many interpretations of URLs floating about - after all, you type a URL in to your browser, and it just works! Right? Well, sometimes...

URLs were first specified in 1994, and were repeatedly revised over the years, such as by [RFC-2396](https://datatracker.ietf.org/doc/html/rfc2396) in 1998, and [RFC-3986](https://www.ietf.org/rfc/rfc3986.txt) in 2005. So there are all these different standards floating around - and as it turns out, they're **not always compatible** with each other, and are sometimes ambiguous.

While all this was going on, browsers were doing their own thing, and each behaved differently to the others. The web in the 90s was a real wild west, and standards-compliance wasn't a high priority. Now, that behavior has to be maintained for compatibility, but having all these different standards can lead to severe misunderstandings and even exploitable security vulnerabilities. Consider these examples from [Orange Tsai's famous talk](https://www.youtube.com/watch?v=voTHFdL9S2k) showing how different URL parsers (sometimes even within the same application) each think these URLs point to a different server.

![](abusing-url-parsers-example-orange-tsai.png) ![](abusing-url-parsers-example-orange-tsai-2.png)

_Images are Copyright Orange Tsai_

So having all these incompatible standards is a problem. Clearly, there was only one answer: yet another standard! 😅 But seriously, this time, it had to have browsers adopt it. For a URL standard, matching how browsers behave is kinda a big deal, you know? And they're not going to break the web, so it needs to document what it means to be "web compatible". It turns out, most URL libraries already include ad-hoc collections of hacks to try to guess what web compatibility means.

This is where the WHATWG comes in to it. The WHATWG is an industry association led by the major browser developers (currently, the steering committee consists of representatives from Apple, Google, Mozilla, and Microsoft), and there is high-level approval for their browsers to align with the standards developed by the group. The latest WebKit (Safari 15) is already in compliance. The WHATWG URL Living Standard defines how **actors on the web platform** should understand and manipulate URLs - how browsers process them, how code such as JavaScript's `URL` class interprets them, etc. And this applies at all levels, from URLs in HTML documents to HTTP redirect requests. This is the web's URL standard. 

By aligning to the URL Living Standard, this project aims to provide the behavior you expect, with better reliability and interoperability, sharing a standard and test-suite with your browser, and engaging with the web standards process. And by doing so, we hope to make Swift an even more attractive language for both servers and client applications.





[swift-forums-weburl]: https://forums.swift.org/c/related-projects/weburl/73
[weburl-docs]: https://karwa.github.io/swift-url/main/documentation/weburl/
[weburl-resolve]: https://karwa.github.io/swift-url/main/documentation/weburl/weburl/resolve(_:)
[using-weburl-with-foundation]: https://karwa.github.io/swift-url/main/documentation/weburl/foundationinterop
