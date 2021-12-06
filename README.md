# WebURL

A new URL type for Swift.

- **Compliant** with the [URL Living Standard](https://url.spec.whatwg.org/) for web compatibility. WebURL matches modern browsers and popular libraries in other languages.
  
- **Fast**. Tuned for high performance and low memory use.

- **Swifty**. The API makes liberal use of generics, in-place mutation, zero-cost abstractions, and other Swift features. It's a big step up from Foundation's `URL`.

- **Portable**. The core WebURL library has no dependencies other than the Swift standard library.

- **Memory-safe**. WebURL uses carefully tuned bounds-checking techniques which the compiler is better able to reason about.

And of course, it's written in **100% Swift**.

> [**NEW**] The documentation is currently being rewritten for DocC. You can check out the preview [here](https://karwa.github.io/swift-url-docs-test/documentation/weburl/).
>  It's still being worked on, but it's already much better than the existing docs.

- The [Getting Started](GettingStarted.md) guide contains an overview of how to use the `WebURL` type.
- The [API Reference](https://karwa.github.io/swift-url/) contains more detail about specific functionality.

# Using WebURL in your project

To use this package in a SwiftPM project, you need to set it up as a package dependency:

```swift
// swift-tools-version:5.3
import PackageDescription

let package = Package(
  name: "MyPackage",
  dependencies: [
    .package(
      url: "https://github.com/karwa/swift-url",
      .upToNextMajor(from: "0.2.0") // or `.upToNextMinor`
    )
  ],
  targets: [
    .target(
      name: "MyTarget",
      dependencies: [
        .product(name: "WebURL", package: "swift-url")
      ]
    )
  ]
)
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

Make sure to read the [Getting Started](GettingStarted.md) guide for an overview of what you can do with `WebURL`.

## Integration with swift-system

WebURL 0.2.0 includes a library called `WebURLSystemExtras`, which integrates with `swift-system` and Apple's `System.framework`. This allows you to create `file:` URLs from `FilePath`s, and to create `FilePath`s from `file:` URLs. It supports both POSIX and Windows paths.

```swift
.target(
  name: "MyTarget",
  dependencies: [
    .product(name: "WebURL", package: "swift-url"),
    .product(name: "WebURLSystemExtras", package: "swift-url") // <--- Add this.
  ]
)
```

```swift
import WebURL
import System
import WebURLSystemExtras

func openFile(at url: WebURL) throws -> FileDescriptor {
  let path = try FilePath(url: url)
  return try FileDescriptor.open(path, .readOnly)
}
```

## Prototype port of async-http-client

We have a prototype port of [async-http-client](https://github.com/karwa/async-http-client), based on version 1.7.0 (the latest release as of writing), which uses WebURL for _all_ of its URL handling. It allows you to perform http(s) requests with WebURL, including support for HTTP/2, and is a useful demonstration of how to adopt WebURL in your library.

We'll be updating the port periodically, so if you wish to use it in an application we recommend making a fork and pulling in changes as you need.

```swift
import AsyncHTTPClient
import WebURL

let client = HTTPClient(eventLoopGroupProvider: .createNew)

func getTextFile(url: WebURL) throws -> EventLoopFuture<String?> {
  let request = try HTTPClient.Request(url: url, method: .GET, headers: [:])
  return client.execute(request: request, deadline: .none).map { response in
    response.body.map { String(decoding: $0.readableBytesView, as: UTF8.self) }
  }
}

let url = WebURL("https://github.com/karwa/swift-url/raw/main/README.md")!
try getTextFile(url: url).wait() // "# WebURL A new URL type for Swift..."
```

# Project Status

WebURL is a complete URL library, implementing the latest version of the URL Standard (as of writing, that is the August 2021 review draft). It is tested against the [shared `web-platform-tests`](https://github.com/web-platform-tests/wpt/) used by major browsers, and passes all constructor and setter tests other than those which rely on IDNA. The library includes a comprehensive set of APIs for working with URLs: getting/setting basic components, percent-encoding/decoding, reading and writing path components, form parameters, file paths, etc. Each has their own extensive sets of tests in addition to the shared web-platform-tests.

The project is regularly benchmarked using the suite available in the `Benchmarks` directory and fuzz-tested using the fuzzers available in the `Fuzzers` directory.

Being a pre-1.0 package, the interfaces have not had time to stabilize. If there's anything you think could be improved, your feedback is welcome - either open a GitHub issue or post to the [Swift forums](https://forums.swift.org/c/related-projects/weburl/73).

Prior to 1.0, it may be necessary to make source-breaking changes. 
I'll do my best to keep these to a minimum, and any such changes will be accompanied by clear documentation explaining how to update your code.

## Roadmap

Aside from stabilizing the API, the other priorities for v1.0 are:

1. `Foundation` interoperability.

   Foundation's `URL` type is the primary type used for URLs on Swift today, and Foundation APIs such as `URLSession` are critical for many applications, in particular because of their system integration on Apple platforms.

   We will provide a compatibility library which allows these APIs to be used together with `WebURL`.

Looking beyond v1.0, the other features I'd like to add are:

2. Better APIs for `data:` URLs.

   WebURL already supports them as generic URLs, but it would be nice to add APIs for extracting the MIME type and decoding base64-encoded data.
  
3. Non-form-encoded query parameters.

   A URL's `query` component is often used as a string of key-value pairs. This usage appears to have originated with HTML forms, which WebURL supports via its `formParams` view, but popular convention these days is also to use keys and values that are not _strictly_ form-encoded. This can lead to decoding issues.

   Additionally, we may want to consider making key lookup Unicode-aware. It makes sense, but AFAIK is unprecedented in other libraries and so may be surprising. But it does make a lot of sense.
  
4. APIs for relative references.

   All `WebURL`s are absolute URLs (following the standard), and relative references are currently only supported as strings via the [`WebURL.resolve(_:)` method](https://karwa.github.io/swift-url/WebURL/#weburl.resolve(_:)).

   It would be valuable to a lot of applications (e.g. server frameworks) to add a richer API for reading and manipulating relative references, instead of using only strings. We may also want to calculate the difference between 2 URLs and return the result as a relative reference.
  
5. IDNA

   This is part of the URL Standard, and its position on this list shouldn't be read as downplaying its importance. It is a high-priority item, but is currently blocked by other things.

   There is reason to hope this may be implementable soon. Native Unicode normalization was [recently](https://github.com/apple/swift/pull/38922) implemented in the Swift standard library for String, and there is a desire to expose this functionality to libraries such as this one. Once those APIs are available, we'll be able to use them to implement IDNA.

# Sponsorship

I'm creating this library because I think that Swift is a great language, and it deserves a high-quality, modern library for handling URLs. It has taken a lot of time to get things to this stage, and there is an exciting roadmap ahead. so if you
(or the company you work for) benefit from this project, do consider donating to show your support and encourage future development. Maybe it saves you some time on your server instances, or saves you time chasing down weird bugs in your URL code.

# FAQ

## How do I leave feedback?

Either open a GitHub issue or post to the [Swift forums](https://forums.swift.org/c/related-projects/weburl/73).

## Are pull requests/code reviews/comments/questions welcome?

Most definitely!

## Is this production-ready?

Yes, it is being used in production.

The implementation is extensively tested (including against the shared `web-platform-tests` used by the major browsers, which we have also made contributions to, and by fuzz-testing), so we have confidence that the behavior is reliable.

Additionally, the benchmarks package available in this repository helps ensure the performance is well-understood, and that operations maintain a consistent performance profile. Benchmarks are run on a variety of devices, from high-end modern x64 computers to the raspberry pi.

## Why the name `WebURL`?

1. `WebURL` is short but still distinct enough from Foundation's `URL`.

2. The WHATWG works on technologies for the web platform. By following the WHATWG URL Standard, `WebURL` could be considered a kind of "Web-platform URL".

## What is the WHATWG URL Living Standard?

It may be surprising to learn that there many interpretations of URLs floating about - after all, you type a URL in to your browser, and it just works! Right? Well, sometimes...

This [memo](https://tools.ietf.org/html/draft-ruby-url-problem-01) from the IETF network working group has a good overview of the history. In summary, URLs were first specified in 1994, and there were a lot of hopeful concepts like URIs, URNs, and scheme-specific syntax definitions. Most of those efforts didn't get the attention they would have needed and were revised by later standards such as [RFC-2396](https://datatracker.ietf.org/doc/html/rfc2396) in 1998, and [RFC-3986](https://www.ietf.org/rfc/rfc3986.txt) in 2005. Also, URLs were originally defined as ASCII, and there were fears that Unicode would break legacy systems, hence yet more standards and concepts such as IRIs, which also ended up not getting the attention they would have needed. So there are all these different standards floating around.

In the mean time, browsers had been doing their own thing. The RFCs are not only ambiguous in places, but would _break the web_ if browsers adopted them. For URL libraries (e.g. cURL) and their users, web compatibility is really important, so over time they also began to diverge from the standards. These days it's rare to find any application/library which strictly follows any published standard -- and that's pretty bad! When you type your URL in to a browser or use one in your application, you expect that everybody involved understands it the same way. Because when they don't, stuff doesn't work and it may even open up [exploitable bugs](https://www.youtube.com/watch?v=voTHFdL9S2k).

So we're at a state where there are multiple, incompatible standards. Clearly, there was only one answer: another standard! 😅 But seriously, this time, it had to be web-compatible, so browsers could adopt it. For a URL standard, matching how browsers behave is kinda a big deal, you know?

This is where the WHATWG comes in to it. The WHATWG is an industry association led by the major browser developers (currently, the steering committee consists of representatives from Apple, Google, Mozilla, and Microsoft), and there is high-level approval for their browsers to align with the standards developed by the group.

The WHATWG URL Living Standard defines how actors on the web platform should understand and manipulate URLs - how browsers process them, how code such as JavaScript processes them, etc. 

By aligning to the URL Living Standard, this project aims to provide the behavior you expect, with better reliability and interoperability, sharing a standard and test-suite with your browser, and engaging with the web standards process. And by doing so, we hope to make Swift an even more attractive language for both servers and client applications.