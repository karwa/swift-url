# WebURL

This package contains a new URL type for Swift, written in Swift. Check out our [Getting Started](GettingStarted.md) guide for a brief overview of how to use the `WebURL` type.

## How to use

To use `WebURL` in a SwiftPM project, add the following line to the dependencies in your Package.swift file:

```swift
.package(url: "https://github.com/karwa/swift-url", branch: "main"),
```

`WebURL` isn't totally ready for a public release yet. In particular, I'm considering squashing the entire version history in to an "initial import"-style commit, so for now use a branch-based dependency and don't use it for anything super important.

Next, include "WebURL" as a dependency for your executable target:

```swift
let package = Package(
    // name, platforms, products, etc.
    dependencies: [
        .package(url: "https://github.com/karwa/swift-url", branch: "main"),
        // other dependencies
    ],
    targets: [
        .target(name: "<target>", dependencies: [
            .product(name: "WebURL", package: "WebURL"),
        ]),
        // other targets
    ]
)
```

Then import the package and go!

```swift
import WebURL

var my_url = WebURL("https://github.com/karwa/swift-url")!
```

Be sure to check out the [Getting Started](GettingStarted.md) guide for a brief overview of how to use the `WebURL` type.

## Goals

The goals for this project are, in order:

<details><summary>1. To be compliant with the latest WHATWG URL standard.</summary>

This is the killer feature. The [WHATWG URL standard](https://url.spec.whatwg.org/) is a fresh effort to standardise how URLs should be understood and manipulated. This URL parser included in this project aims to be fully compatible with the one described in the standard, and is tested against the common [Web Platform Tests](https://github.com/web-platform-tests/wpt/tree/master/url) to validate the implementation. Currently this consists of about 570 constructor tests - (input, base) string pairs and the resulting object's expected property values - and about 200 tests for property setters.

Additionally, this project contains additional test databases covering edge-cases under-tested by the WPT suite, which we are planning to upstream to ensure the project's correctness going forward.  There is also a [companion live-viewer tool](https://github.com/karwa/swift-url-tools), created with SwiftUI and inspired by the JSDOM [URL Live Viewer](https://jsdom.github.io/whatwg-url/), which allows comparisons between this project's output and the reference implementation in real-time. It's a really valuable utility in visualising how the various rules of the standard apply as a URL changes.

The benefits of having a shared understanding of URLs with browsers and URL libraries from other languages is clear: it allows us to write portable and robust applications, and makes our understanding of URLs portable across libraries and languages.

If you come across any occassions where `WebURL` gives you a surprising result, don't hesitate to file an issue. If you want to check what the standard thinks should occur, check the aforementioned JSDOM [URL Live Viewer](https://jsdom.github.io/whatwg-url/) for the reference result. Additionally, you can engage with the standards-setting process over at their [GitHub page](https://github.com/whatwg/url).
</details>

<details><summary>2. To be fast and memory efficient.</summary>

Being portable and standards-compliant is all well and good, but what about existing applications that appear to run just fine? Well, we also have something you might be interested in: speed.

Our parsing algorithm is designed to be compatible with the one described in the spec, but it is not _the same_ algorithm. Internally, a `WebURL` instance consists of its normalized, serialized output as a contiguous ASCII string, and a collection of indexes to the important components. This means that common operations such as equality checking and hashing are as fast as they can be, and probably the most common operation of all - getting the URL's contents as a `String` - is lightning fast. By comparison, Foundation's `URL` type internally stores both a relative URL string and its base URL separately, meaning it needs to combine them on-demand whenever it needs to consider what the overall URL looks like (e.g. when you call `.absoluteURL`).

Moreover, we are able to offer in-place mutation of URL components. That means you no longer need to go through Foundation's `URLComponents` type and can avoid a lot of the overheads that come with splitting each component in to an individually-allocated `String`.

The algorithm has been written with a focus on reducing allocations, even if it needs an extra pass of the input string to do it. We make use of Swift's generics to perform a dry-run when creating the normalized URL, meaning that parsing a URL string results in only a single allocation of precisely the correct size. Benchmarking is something we still need to improve, but currently we are competitive with MacOS Foundation on the (relatively old) x86 MacBook Pro I have available, and significantly faster than corelibs-foundation on a Raspberry Pi 4 running 64-bit Ubuntu. Again, our constructor also does significantly more work than Foundation's URL type, so direct comparisons are difficult. 
</details>

<details><summary>3. To leverage Swift's language features and develop a clean, efficient API that enables developers to read and manipulate URLs and understand precisely what is going on.</summary>

🚧 This part is still being developed. Currently, we expose basic getters/setters for the various URL components, as well as generic setter methods that throw descriptive errors when an operation fails. Path components and Query components are obvious candidates for some type of `Collection`, we have lazy percent-encoding and -decoding types that would be useful to expose, types for IP addresses, etc. PRs and ideas welcome!  
</details>

## IDNA

A quick note about IDNA. IDNA is _not (just) Punycode_ (a lot of people seem to mistake the two). Punycode is a way of encoding a Unicode string in an ASCII string, just like percent-encoding. IDNA also requires a unique flavour of unicode normalization and case-folding, [defined by the Unicode Consortium](https://unicode.org/reports/tr46/) specifically for domains, and it is _that result_ that is Punycode-encoded to produce the output. Unforuntately, Swift's exposure of unicode algorithms is a bit lacking at the moment, meaning that the only viable way we would have of implementing this would be to ship a copy of ICU or introduce a platform dependency on the system's version of ICU.

I don't want to do that. Instead, once this project settles down and has a great, Swifty API, I want to turn my attention to improving Swift's support of unicode algorithms. Sometimes it's good to have hurdles, because they motivate you to do something that ends up benefitting everyone. 

So for now, we fail to parse if a domain contains non-ASCII characters; attempting to parse `"http://🏆.com/"` will predictably return `nil`, rather than `"http://xn--3l8h.com/"`. Of those 570+ URL constructor tests in the common WPT repository, we only fail 11, and all of them are because we refuse to parse an address that would require us to use IDNA.

We will support it eventually, but it's just not practical right now.
