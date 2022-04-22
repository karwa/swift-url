# Contents


- [Welcome to WebURL](#welcome-to-weburl)
- [A brief overview of URLs](#a-brief-overview-of-urls)
- [The WebURL Type](#the-weburl-type)
  * [A Closer Look At: Parsing and Web Compatibility](#a-closer-look-at-parsing-and-web-compatibility)
- [Reading And Writing URL Components](#reading-and-writing-url-components)
  * [A Closer Look At: Percent Encoding](#a-closer-look-at-percent-encoding)
- [Relative References](#relative-references)
  * [A Closer Look At: The Foundation URL object model vs. WebURL](#a-closer-look-at-the-foundation-url-object-model-vs-weburl)
- [Path Components](#path-components)
- [Query Items](#query-items)
- [File URLs](#file-urls)
- [Wrapping up](#wrapping-up)

_Estimated reading time: About 30 minutes._


# Welcome to WebURL


Welcome! WebURL is a new URL library for Swift, featuring:

- A modern URL model **compatible with the web**,

- An intuitive, expressive API **designed for Swift**, and

- A **fast** and memory-efficient implementation.

This guide will introduce the core WebURL API, share some insights about how working with `WebURL` is different from Foundation's `URL`, and explain how WebURL helps you write more robust, interoperable, and performant code. After reading this guide, you should feel just as comfortable using `WebURL` as you are with Foundation's familiar `URL` type.

WebURL is a model-level library, meaning it handles parsing and manipulating URLs. It comes with an integration library for `swift-system` and Apple's `System.framework` for processing file URLs, and we maintain a [fork]((https://github.com/karwa/async-http-client)) of `async-http-client` for making http(s) requests. We hope to expand this in the near future with support for Foundation's `URLSession`.

To use WebURL in a SwiftPM project, begin by adding the package as a dependency:

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


# A brief overview of URLs


Most of us can recognize a URL when we see one, but let's briefly go in to a bit more detail about what they are and how they work.

The standard describes a URL as "a universal identifier". It's a very broad definition, because URLs have a lot of diverse uses. They are used for identifying resources on networks (such as this document on the internet), for identifying files on your computer, locations within an App, books, people, places, and everything in-between.

A URL may be split in to various _components_:

```
          userinfo     hostname    port
          ┌──┴───┐ ┌──────┴──────┐ ┌┴┐
  https://john.doe@www.example.com:123/forum/questions/?tag=networking&order=newest#top
  └─┬─┘   └───────────┬──────────────┘└───────┬───────┘ └───────────┬─────────────┘ └┬┘
  scheme          authority                  path                 query           fragment
```

The most important of these are:

- The **scheme**. Identifies the type of URL and can be used to dispatch the URL for further processing. For example, `http` URLs should be processed in requests according to the HTTP protocol, but `file` URLs map to a local filesystem. Your application might use a custom scheme with bespoke URL processing. All URLs **must** have a scheme.

- The **hostname** and **port**. Typically a hostname is a network address, but is sometimes an opaque identifier in URLs where a network address is not necessary. `www.swift.org`, `192.168.0.1`, and `living-room-pc` are all examples of hostnames. Together with the userinfo components (**username** and **password**), they make up the URL's _authority_ section.

- The **path** is either an opaque string or a list of zero or more strings, usually identifying a location. List-style paths begin with a forward-slash ("/"), and their internal components are delimited by forward-slashes.

- The **query** and **fragment** are opaque strings, whose precise structure is not standardized. A common convention is to include a list of key-value pairs in the query string, and some protocols reserve the fragment for client-side information and ignore its value when servicing requests.

To process this URL, we look at the scheme ("https") and hand it off to a request library that knows how to deal with https URLs. That request library knows that HTTPS is a network protocol, so it will read the hostname and port from the URL and attempt to establish a connection to the network address they describe. The HTTP protocol requires that requests specify a "request target", which it says is made by joining a URL's path ("/forum/questions/") with its query string ("?tag=networking&order=newest"), and discarding the fragment. This results in a request such as the following being issued over the connection:

`GET /forum/questions/?tag=networking&order=newest HTTP/1.1`

Note that most of the process from URL to request is scheme/protocol specific; HTTP(S) works like this, but URLs with other schemes may be processed in a very different way. This flexibility is very important; URLs are, after all, "universal", which means that for the most part they work at an abstract level. By itself, a URL doesn't know what it points to, how it will be processed, or what its components mean to whoever processes them.

Almost all URLs identify a location _hierarchically_, meaning they have:

- A hostname, and/or
- A list-style path (a path starting with "/")

For example, let's imagine a simple URL scheme for identifying places by their postal addresses. In our scheme, the address:

```
221b Baker St,
London NW1 6XE,
UK
```

Might become:

`postal-address://UK/London/NW1 6XE/Baker St/221b`

Here, the components are:

- **hostname:** `UK`
- **path:** `/London/NW1 6XE/Baker St/221b`

This describes a simple hierarchical structure - with a country being at the top level, followed by the city, post-code, street, and finally building number. If we wanted to resolve a neighboring address on the same street, we could change the final component to "222" or "239". To process this URL, we would follow a similar set of steps to processing an HTTP URL: firstly, examining the scheme, then contacting the resource's authority ("UK"), and asking it to resolve the path "/London/NW1 6XE/Baker St/221b". 

Less commonly, a URL may have an _opaque path_. For example:

- `mailto:bob@example.com`
- `data:image/png;base64,iVBORw0KGgoAAA...`
- `javascript:alert("hello, world!")`

These URLs do not identify their locations hierarchically: they lack an authority, and their paths are simple opaque strings rather than a list of components. You can recognize them by noting that the character after the scheme delimiter (":") is not a forward-slash. Whilst the lack of hierarchy limits what we can do with the path, these URLs are processed in a familiar way: use the scheme to figure out which kind of URL it is, and interpret the other components based on their meaning for that scheme.

OK, so that's a _very, very_ brief look at what URLs are, how they're used, and which flavors they come in.


# The WebURL Type


A URL is represented by a type also named `WebURL`. You can create a `WebURL` value by parsing a string:

```swift
import WebURL

let url = WebURL("https://github.com/karwa/swift-url")!
url.scheme   // "https"
url.hostname // "github.com"
url.path     // "/karwa/swift-url"
```

`WebURL` supports both URLs with hierarchical, and opaque paths:

```swift
let url = WebURL("mailto:bob@example.com")!
url.scheme   // "mailto"
url.hostname // nil
url.path     // "bob@example.com"
url.hasOpaquePath // true
```

`WebURL` is a value type, meaning that each variable is isolated from changes made to other variables. They are light-weight, inherently thread-safe, and conform to many protocols from the standard library you may be familiar with:

 - `Equatable` and `Hashable`, so they may be used as keys in a `Dictionary` or as members of a `Set`,
 - `Comparable`, so they may be sorted,
 - `Codable`, so they may be serialized/deserialized from JSON and other formats,
 - `Sendable`, as they are thread-safe,
 - `LosslessStringConvertible`, as `WebURL` objects can be converted to a `String` and back without losing information.

Next, we're going to take a closer look at how parsing behaves, and how it differs from Foundation's `URL`.


## A Closer Look At: Parsing and Web Compatibility


The previous section introduced parsing a `WebURL` from a URL string. 

The URL Standard defines how URL strings are parsed to create an object, and how that object is later serialized to a URL string. This means that constructing a `WebURL` from a string doesn't only parse - it also _normalizes_ the URL, based on how the parser interpreted it. There are some significant benefits to this; whilst parser is very lenient (literally, as lenient as a web browser), the result is a clean, simplified URL, free of many of the "quirks" required for web compatibility.

This is a very different approach to Foundation's `URL`, which tries hard to preserve the string exactly as you provide it (even if it ends up being needlessly strict), and offers operations such as `.standardize()` to clean things up later. Let's take a look at some examples which illustrate this point:

```swift
import Foundation
import WebURL

// Foundation requires your strings to be properly percent-encoded in advance.
// WebURL is more lenient, adds encoding where necessary.

URL(string: "http://example.com/some path/") // nil, fails to parse
WebURL("http://example.com/some path/")      // "http://example.com/some%20path/

// This can be a particular problem for developers if their strings might contain
// Unicode characters.

URL(string: "http://example.com/search?text=банан") // nil, fails to parse
WebURL("http://example.com/search?text=банан")      // "http://example.com/search?text=%D0%B1%D0%B0%D0%BD%D0%B0%D0%BD"

// Common syntax error: too many slashes. Browsers are quite forgiving about this,
// because HTTP URLs with empty hosts aren't even valid.
// WebURL is as lenient as a browser.

URL(string: "http:///example.com/foo") // "http:///example.com/foo", .host = nil
WebURL("http:///example.com/foo")      // "http://example.com/foo",  .host = "example.com"

// Lots of normalization:
// - IP address rewritten in canonical form,
// - Default port removed,
// - Path simplified.
// The results look nothing alike.

URL(string: "http://0x7F.1:80/some_path/dir/..") // "http://0x7F.1:80/some_path/dir/.."
WebURL("http://0x7F.1:80/some_path/dir/..")      // "http://127.0.0.1/some_path/"
```

One of the issues developers sometimes discover (after hours of debugging!) is that while types like Foundation's `URL` conform to _a_ URL standard, there are actually **multiple, incompatible URL standards**(!). Whichever URL library you are using, whether Foundation's `URL`, cURL, or Python's urllib, may not match how your server, browser, or Java/Rust/C++/etc clients interpret URLs.

"Running different parsers and assuming that they end up with the exact same result is futile and, unfortunately, naive" says Daniel Steinberg, lead developer of the cURL library. It sounds incredible, but it's absolutely true, and it should surprise nobody that these varying and ambiguous standards lead to bugs - some of which are just annoying, but others can be catastrophic, [exploitable](https://www.youtube.com/watch?v=voTHFdL9S2k) vulnerabilities.

And multiple, incompatible standards are just part of the problem; the other part is that those standards fail to match reality on the web today, meaning browsers can't conform to them without _breaking the web_. The quirks shown above (e.g. being lenient about spaces and slashes) aren't limited to user input via the address bar - there are reports of servers sending URLs in HTTP redirects which include spaces, have too many slashes, or which include non-ASCII characters. Browsers are fine with those things, but then you try the same in your App and it doesn't work.

All of this is why most URL libraries abandoned formal standards long ago - "Not even curl follows any published spec very closely these days, as we’re slowly digressing for the sake of 'web compatibility'" (Steinberg). To make things worse, each library incorporated different ad-hoc compatibility hacks, because there wasn't any standard describing what, precisely, "web compatibility" even meant.

So URLs are in a pretty sorry state. But how do we fix them? Yet another standard? Well, admittedly, yes 😅 - **BUT** one developed for the web, as it really is, which browsers can also conform to. No more guessing or ad-hoc compatibility hacks.

`WebURL` brings web-compatible URL parsing to Swift. It conforms to the new URL standard developed by major browser vendors, its author is an active participant in the standard's development, and it is validated using the shared web-platform-tests browsers use to test their own standards compliance. That means we can say with confidence that `WebURL` precisely matches how the new URL parser in Safari 15 behaves, and Chrome and Firefox [are working to catch up](https://wpt.fyi/results/url/url-constructor.any.html?label=experimental&label=master&aligned). This standard is also used by JavaScript's native `URL` class (including NodeJS), and new libraries are being developed for many other languages which also align to the new standard.

By using `WebURL` in your application (especially if your request library uses `WebURL` for all URL handling, as [our `async-http-client` fork](https://github.com/karwa/async-http-client) does), you can guarantee that your application handles URLs just like a browser, with the same, high level of interoperability with legacy and "quirky" systems. The lenient parsing and normalization behavior shown above is a huge part of it; this is what "web compatibility" means.

So that's a look at parsing, web compatibility, and how important they both are. Next, let's take a look at what you can do once you've successfully parsed a URL string.


# Reading And Writing URL Components


Once you have created a `WebURL` value, the core components you need to process it can be accessed as properties:

```swift
import WebURL

let url = WebURL("https://john.doe@www.example.com:123/forum/questions/?tag=networking&order=newest#top")!

url.scheme      // "https"
url.username    // "john.doe"
url.password    // nil
url.hostname    // "www.example.com"
url.port        // 123
url.path        // "/forum/questions/"
url.query       // "tag=networking&order=newest"
url.fragment    // "top"
```

Furthermore, the URL's string representation is available by calling the `serialized()` function or by simply constructing a `String`:

```swift
import WebURL

let url = WebURL("https://github.com/karwa/swift-url")!
url.hostname // "github.com"
url.path     // "/karwa/swift-url/"

url.serialized() // "https://github.com/karwa/swift-url/"
String(url)      // "https://github.com/karwa/swift-url/"
```

As well as reading the value of a component, you may also use these properties to modify a component's value:

```swift
import WebURL

var url = WebURL("http://github.com/karwa/swift-url/")!

// Upgrade to https:
url.scheme = "https"
url // "https://github.com/karwa/swift-url/"

// Change the path:
url.path = "/apple/swift/"
url // "https://github.com/apple/swift/"
```

`WebURL` is always in a normalized state, so any values you modify are parsed and normalized in the same way that the URL string parser does. Note that when you set a value to these core URL properties, `WebURL` assumes the value you set is also percent-encoded. We'll take a closer look at what this means in the next section.

```swift
var url = WebURL("http://example.com/my_files/")!

// Change the hostname using a non-canonical IPv4 address format:
url.hostname = "0x7F.1"
url // "http://127.0.0.1/my_files/"

// Change the path:
url.path = "/some path/dir/.."
url // "http://127.0.0.1/some%20path/"

// Set a partially percent-encoded value:
url.path = "/swift%2Durl/some path"
url // "http://127.0.0.1/swift%2Durl/some%20path"
```

Although the setters are very permissive, they can sometimes fail if an operation is not valid:

```swift
var url = WebURL("https://example.com/")!
url.hostname = ""
url // "https://example.com/" - didn't change
```

> Note: The silent failure is something we'd like to improve in the future. Ideally, Swift would support throwing property setters, but until it does, it's still worth keeping this convenient syntax because failure is generally quite rare.

If you need to respond to setter failures, WebURL provides throwing setter methods as an alternative. The errors thrown by these methods provide helpful diagnostics about why the failure occurred - in this case, "https" URLs are not allowed to have an empty hostname, and this is enforced at the URL level.

```swift
var url = WebURL("https://example.com/")!
try url.setHostname(to: "") // Throws. Error description:
// "Attempt to set the hostname to the empty string, but the URL's scheme requires a non-empty hostname..."
```

> Note: WebURL **never** includes specific URL details in error descriptions, so you may log errors without compromising user privacy.

That covers the basics of getting/setting a URL's components. But there's still an important piece we haven't touched on yet, and that is percent-encoding. Let's take a closer look at how `WebURL` handles that in the next section.


## A Closer Look At: Percent Encoding


Because URLs are a string format, certain characters may have special meaning depending on their position in the URL: for example, a "/" in the path is used to separate the path's components, and the first "?" in the string marks the start of the query. Additionally, some characters (like NULL bytes or newlines) could be difficult to process if used directly in a URL string. This poses an interesting question: what it I have a path component that needs to contain a _literal_ forward-slash?

```
https://example.com/music/bands/AC/DC // "AC/DC" should be a single component!
```

When these situations occur, we need to encode (or "escape") our path component's slash, so it won't be confused with the other slashes around it. The encoding URLs use is called **percent-encoding**, because it replaces the character with one or more "%XX" sequences, where "XX" is a byte value in hexadecimal. For the ASCII forward-slash character, the byte value is 2F, so the URL shown above would become:

```
https://example.com/music/bands/AC%2FDC
```

Of course, the machine processing this request will have to decode the path component to recover its intended value. The set of characters which need to be encoded depends on the component, although it is sometimes necessary to encode additional characters if you are embedding the URL within a larger document.

`WebURL` returns the core URL components described in the previous section (`scheme`, `username`, `password`, `hostname`, `port`, `path`, `query`, and `fragment`) as they appear in the URL string, including percent-encoding (sometimes called the "raw" value). However, the library also includes a number of extensions to types and protocols from the Swift standard library, so you can encode and decode values as needed. For example, to decode a percent-encoded `String`, use the `.percentDecoded()` function:

```swift
import WebURL

// Note: "%20" is a percent-encoded space character.
let url = WebURL("https://github.com/karwa/swift%20url/")!

url.path                  // "/karwa/swift%20url/"
url.path.percentDecoded() // "/karwa/swift url/"
```

> Tip: The `scheme` is never percent-encoded (the standard forbids it), and neither is the port `port` (it's just a number, not a string).

Since the values returned by these properties are percent-encoded, if you set these properties to a new value, that value must also be percent-encoded. When constructing a component value using arbitrary strings at runtime, we need to consider that it might contain a forward-slash, or the substring "%2F", which should be interpreted _literally_ and not as a path separator or percent-encoding. That means we need to encode values ourselves as we build the URL component's value, which we can do by using the `.percentEncoded(using:)` function and specifying the set of characters to encode:

```swift
import WebURL

// If we don't percent-encode 'bandName', it might be misinterpreted
// once we set the URL's path.

func urlForBand_bad(_ bandName: String) -> WebURL {
  var url  = WebURL("https://example.com/")!
  url.path = "/music/bands/" + bandName
  return url
}

urlForBand_bad("AC/DC")       // "https://example.com/music/bands/AC/DC" ❌
urlForBand_bad("Blink-%182")  // "https://example.com/music/bands/Blink-%182" ❌

// Percent-encoding allows us to preserve 'bandName' exactly.
// Note: "%25" is a percent-encoded ASCII percent sign.

func urlForBand_good(_ bandName: String) -> WebURL {
  var url  = WebURL("https://example.com/")!
  url.path = "/music/bands/" + bandName.percentEncoded(using: .urlComponentSet)
  return url
}

urlForBand_good("AC/DC")       // "https://example.com/music/bands/AC%2FDC" ✅
urlForBand_good("Blink-%182")  // "https://example.com/music/bands/Blink-%25182" ✅
```

> Note: The `.pathComponents` and `.formParams` views (discussed later) handle percent-encoding for you, and are the preferred way to construct URL paths and query strings. In this example, we're building a URL component using string concatenation, so we need to encode the pieces manually as we build the string.

The URL standard defines several percent-encode sets, and you can also define your own. `.urlComponentSet` is usually a good choice, since it encodes all special characters used by all URL components. Strings encoded with the component set can be spliced in to any other component string without affecting the component's structure, and preserve the encoded value exactly. It is equivalent to encoding using the JavaScript function `encodeURIComponent()`.

This behavior, where getting a component includes its percent-encoding, matches most other URL libraries including JavaScript's URL class, rust-url, Python's urllib, etc. However, it's important to point out that it does **not** match Foundation, which automatically decodes URL components:

```swift
import Foundation

let url = URL(string: "https://example.com/music/bands/AC%2FDC")!

url.path // "/music/bands/AC/DC"
```

When transitioning from Foundation to `WebURL`, this is an area where you may need to think carefully and make some adjustments to your code, so you deserve a full explanation of what's happening here, and why `WebURL` has decided not to match Foundation's behavior.

As we explained at the start of this section, URLs percent-encode their components in order to maintain an unambiguous structure - but decoding is a lossy process which can erase vital structural information. Look at the returned path in the above example; it's impossible to tell that "AC/DC" should actually be a single path component. That information is lost forever, and the value returned by Foundation.URL's `.path` property is just _not the same_ as the path actually represented by the URL. It's just wrong.

This doesn't just apply to the path; it applies to any component which can have internal structure (which is basically _every component_). The query and fragment are just opaque strings, and can have any internal structure you like (e.g. key-value pairs), and technically there's nothing stopping you doing the same for the username, password, hostname, or even the port number. As explained in [A brief overview of URLs](#a-brief-overview-of-urls), custom schemes have wide authority to interpret URL components as they see fit.

The correct way to handle percent-encoded URL components is to: (i) keep the encoding intact, (ii) parse the component in to its smallest units, and (iii) percent-decode each unit. For example, when splitting a path, split the percent-encoded path and decode each path component individually; or when splitting a query in to key-value pairs, split the percent-encoded query and decode each key and value separately.

If decoding is automatic, it can be really easy to forget that it's happening -- so easy, in fact, that `URL` itself sometimes forgets! The following example demonstrates a bug in the implementation of `URL.pathComponents` (macOS 11.6, Xcode 13 GM), which was discovered while writing this guide. Internally, the `URL.pathComponents` property [gets the URL's `.path`](https://github.com/apple/swift-corelibs-foundation/blob/dab95988ca12904e320975c7ed3c4f435552f14e/Sources/Foundation/NSURL.swift#L41), and splits it at each forward-slash. Unfortunately, since `URL.path` is automatically decoded, the values returned by `URL.pathComponents` do not match the components seen by other methods on `URL`, which correctly use the raw path:

```swift
// filed as: https://bugs.swift.org/browse/SR-15363
import Foundation
var url = URL(string: "https://example.com/music/bands/AC%2FDC")!

// URL.pathComponents splits the percent-decoded path.

for component in url.pathComponents {
  component // "/", "music", "bands", "AC", "DC"
}

// URL.deleteLastPathComponent() uses the raw path instead.
// It looks like it deleted 2 components.

url.deleteLastPathComponent() // "https://example.com/music/bands/"
```

Consider also what happens if you want to write something like `urlA.path = urlB.path`. The following example demonstrates a simple file server; it accepts a request URL, simplifies the path using Foundation's `.standardize()` method (to resolve ".." components), authenticates the request, and fetches the file from an internal server:

```swift
import Foundation

var requestedUrl = URL(string: "https://example.com/karwa/files/..%2F..%2Fmonica/files/")!

// Normalize the path and check authentication for the subtree.
requestedUrl.standardize()
guard isAuthenticated(for: requestedUrl.pathComponents.first) else { throw InvalidAccess() }

// Build the internal URL.
var internalUrl = URLComponents(string: "https://data.internal/")!
internalUrl.path = requestedUrl.path
```

Let's examine the result, in `internalUrl`:

```swift
// The "%2F" became a real slash when it was automatically decoded.

internalUrl.url // "https://data.internal/karwa/files/../../monica/files"

// Normalization (which intermediate software/caches/routers/etc are allowed to do)
// may simplify this.

internalUrl.url?.standardized // "https://data.internal/monica/files"
```

The system authenticated for one user, but ends up requesting a file belonging to a different user. This sort of bug is not uncommon, and can be used to bypass software filters and access internal services or configuration files.

`WebURL`'s model ensures that setting `urlA.path = urlB.path` does not add or remove percent-encoding. It keeps the component's structure intact, and makes these kinds of mistakes a lot more difficult.

```swift
import WebURL

let requestedUrl = WebURL("https://example.com/karwa/files/..%2F..%2Fmonica/files/")!

// WebURL is already standardized =)
// Check authentication for the subtree.
guard isAuthenticated(for: requestedUrl.pathComponents.first) else { throw InvalidAccess() }

// Build the internal URL.
var internalUrl = WebURL("https://data.internal/")!
internalUrl.path = requestedUrl.path

// WebURL keeps the percent-encoding intact.
internalUrl // "https://data.internal/karwa/files/..%2F..%2Fmonica/files/"
```

Okay, so - this was a bit of a long section, but I hope you found it useful. Percent-encoding can be difficult to get right, so don't worry if you didn't quite understand everything. If you find yourself unsure what to do while working on your application/library, refer back to this section or ask a question on the [Swift forums](https://forums.swift.org/c/related-projects/weburl/73) and we'll be happy to help.

Now might be a good time to have a little break or make a cup of tea. Next stop is relative references.


# Relative References


Previously, we saw that we could construct a `WebURL` value by parsing a URL string. Another way to construct a `WebURL` is by resolving a relative reference using an existing `WebURL` as its "base". You can think of this as modelling where an HTML `<a>` hyperlink on the base URL's 'page' would lead - for example, resolving the relative reference "/search?q=test" against the base URL "https://www.example.com/" produces "https://www.example.com/search?q=test".

```swift
let base = WebURL("https://github.com/karwa/swift-url/")!

base.resolve("pulls/39")            // "https://github.com/karwa/swift-url/pulls/39"
base.resolve("/apple/swift/")       // "https://github.com/apple/swift/"
base.resolve("..?tab=repositories") // "https://github.com/karwa/?tab=repositories"
base.resolve("https://swift.org/")  // "https://swift.org"
```

Relative references can be resolved against any URL, including file URLs or URLs with custom schemes:

```swift
let appData = WebURL("file:///tmp/my_app/data/")!  // "file:///tmp/my_app/data/"
appData.resolve("metrics.json")                    // "file:///tmp/my_app/data/metrics.json"
appData.resolve("../other_data/map.json")          // "file:///tmp/my_app/other_data/map.json"

let deeplink = WebURL("my-app:/profile/settings/language")! // "my-app:/profile/settings/language"
deeplink.resolve("payment")                                 // "my-app:/profile/settings/payment"
```

References are resolved using the algorithm specified by the URL standard, meaning it matches what a browser would do. They are a powerful feature, with a wide variety of applications ranging from navigation to resolving HTTP redirects.

One particular use-case is in server frameworks, where relative references can be used for routing. Currently, `WebURL` does not contain functionality for calculating the relative difference between 2 URLs, and is limited to references in string form. We'd like to explore adding this functionality and a richer object type in future releases.

In the "closer look" section, we'll discuss some of the profound differences in how WebURL and Foundation approach relative references, and how these allow `WebURL` to be simpler, faster, and more intuitive.


## A Closer Look At: The Foundation URL object model vs. WebURL


This topic gets to the heart of the `WebURL` object model, and some of its biggest differences from Foundation. According to the URL standard (hence `WebURL`), URLs must be absolute, and relative references themselves are not URLs. This makes intuitive sense; a set of directions, such as "second street on the right" only describes a location if you know where to start from, and a familial relative, such as "brother", only identifies that person if we know who the description is relative to ("my brother", "your brother", or "his/her brother"). Similarly, a relative URL reference, such as `"..?tab=repositories"`, is just a bag of components that doesn't point to or identify anything until it has been resolved using a base URL.

Once again, Foundation's `URL` has a significantly different model, which combines both absolute URLs and relative references in a single type. This leads to a situation where even strings which look nothing like URLs still parse successfully:

```swift
import Foundation

URL(string: "foo") // "foo"
```

Consider what developers likely expect when they declare a variable or function argument to have the type "`URL`". They probably expect that the value contains something they can request - something which points to, or identifies something. By combining relative references with absolute URLs, Foundation's semantic guarantees are dramatically weakened, to the extent that they basically defeat the reason developers want a URL type in the first place. "foo" is not a URL.

Moreover, if you initialize a Foundation `URL` by resolving a relative reference against a base URL, the resulting object _presents_ its components as being joined, but remembers that they are separate, storing separate `relativeString` and `baseURL` values which you can access later:

```swift
import Foundation
let url = URL(string: "b/c", relativeTo: URL(string: "http://example.com/a/")!)!

// The URL components appear to be joined.

url.host  // "example.com"
url.path  // "/a/b/c"

// But underneath, the parts are stored separately.

url.relativeString  // "b/c"
url.baseURL         // "http://example.com/a/"
```

These decisions have serious detrimental effects to _almost every aspect_ of Foundation's `URL` API and performance: 

- **The baseURL is an independent object, with its own memory allocation and lifetime.**

  Even if you don't use relative URLs, you still pay for them (another pointer to store, another release/destroy on deinit).
  The base URL may even have its own side-allocations (e.g. for URLResourceKeys on Apple platforms).

  And what if the baseURL has its own baseURL? Should we make a linked-list of every URL you visited on the way?
  It turns out that Foundation caps chains of baseURLs to avoid this, but at the cost of allocating yet more objects.

- **Resolving URL components and strings on-demand is slow.**

  So `URL` sometimes allocates additional storage to cache the resolved string. Again, this means higher overheads and greater complexity; you effectively store the URL twice.

- **The relativeString-baseURL split is fragile.**

  Since the split is not really part of the URL string (it's just a stored property in Foundation's URL object), it is lost if you perform a simple task like encoding the URL to JSON.

  What is even more interesting is that there is a specific hack in Foundation's `JSONEncoder/JSONDecoder` to accommodate this, but even that is not perfect - it [can fail](https://forums.swift.org/t/url-fails-to-decode-when-it-is-a-generic-argument-and-genericargument-from-decoder-is-used/36238) if you wrap the URL in a generic type, and places third-party `Encoder` and `Decoder`s in a position where they need to decide between a lossy encoding or serializing URLs as 2 strings. But that's not even the worst of it...

- **URLs with a different relativeString-baseURL split are not interchangeable**. 

  This is huge. 2 `URL`s, with the same `.absoluteString` can appear as `!=` to each other; it depends on how you created each specific URL object.
  This has a lot of ripple effects - for example, if you place a URL in a `Dictionary` or `Set`, it might not be found again unless you test it with a URL that was created using the exact same steps.

Let's take a look at some code:

```swift
import Foundation

let urlA = URL(string: "http://example.com/a/b/c")!
let urlB = URL(string: "/a/b/c", relativeTo: URL(string: "http://example.com")!)!
let urlC = URL(string: "b/c", relativeTo: URL(string: "http://example.com/a/")!)!

// All of these URLs have the same .absoluteString.

urlA.absoluteString == urlB.absoluteString // true
urlB.absoluteString == urlC.absoluteString // true

// But they are not interchangeable.

urlA == urlB // false (!)
urlB == urlC // false (!)
URL(string: urlB.absoluteString) == urlB // false (!)

// Let's imagine an application using URLs as keys in a dictionary:

var operations: [URL: TaskHandle] = [:]
operations[urlA] = TaskHandle { ... }
operations[urlA] // TaskHandle
operations[urlB] // nil (!)
```

The cost of Foundation's object model is high, indeed; it results in unintuitive semantics, requires a much heavier object with several side allocations, and makes it more complex to deliver more valuable features like in-place mutation efficiently.

`WebURL` takes a completely different approach.

As mentioned previously, `WebURL`s are always absolute. They are always normalized, and are _entirely_ defined by their string representation, rather than their object representation or other side-data. It does not matter how you create a `WebURL` - you can parse an absolute URL string, resolve a relative reference, build it up in pieces using property setters, or decode a URL from JSON - if two `WebURL`s have the same serialized string, they are the same, and turning a `WebURL` in to a string and back results in lossless. As you would expect.

This simpler model enables a raft of other improvements. `WebURL`s use less memory, have more predictable lifetimes, and are cheaper to create and destroy because they just _are_ simpler. Common operations like sorting, hashing and comparing URLs can be many times faster with `WebURL`, and have more intuitive semantics:

```swift
import WebURL

let urlA = WebURL("http://example.com/a/b/c")!
let urlB = WebURL("http://example.com")!.resolve("/a/b/c")!
let urlC = WebURL("http://example.com/a/")!.resolve("b/c")!

// All of these URLs have the same serialization.

urlA.serialized() == urlB.serialized() // true
urlB.serialized() == urlC.serialized() // true

// And they are interchangeable, as you would expect.

urlA == urlB // true
urlB == urlC // true
WebURL(urlB.serialized()) == urlB // true

var operations: [WebURL: TaskHandle] = [:]
operations[urlA] = TaskHandle { ... }
operations[urlA] // TaskHandle
operations[urlB] // TaskHandle
```

All of this leads to more robust code. It's delightfully boring; stuff just works, and you don't need to study a bunch of edge-cases to get the behavior you expect.


# Path Components


We've covered quite a lot already, and so far it's been pretty intense - deep discussions about percent-encoding, object models, etc. Thankfully, it's a bit lighter from here.

We discussed earlier that a URL's path can represent locations hierarchically using a list of strings; but properly handling percent-encoding can be deceptively tricky. To make this easier, `WebURL` provides a convenient `.pathComponents` view which efficiently shares storage with the URL object, and conforms to Swift's `Collection` and `BidirectionalCollection` protocols so you can use it in `for` loops and generic algorithms.

```swift
let url = WebURL("file:///Users/karl/My%20Files/data.txt")!

for component in url.pathComponents {
  ... // component = "Users", "karl", "My Files", "data.txt".
}

if url.pathComponents.last!.hasSuffix(".txt") {
  ...
}
```

Additionally, you can modify a URL's path components through this view.

```swift
var url = WebURL("file:///swift-url/Sources/WebURL/WebURL.swift")!

url.pathComponents.removeLast() 
// url = "file:///swift-url/Sources/WebURL"
  
url.pathComponents.append("My Folder")
// url = "file:///swift-url/Sources/WebURL/My%20Folder"

url.pathComponents.removeLast(3)
// url = "file:///swift-url"

url.pathComponents += ["Tests", "WebURLTests", "WebURLTests.swift"]
// url = "file:///swift-url/Tests/WebURLTests/WebURLTests.swift"
```

In contrast to top-level URL components such as the `.path` and `.query` properties, the elements of the `.pathComponents` view are automatically percent-decoded, and any inserted path components are encoded to preserve their contents _exactly_. Previously, we mentioned how to correctly handle percent-encoding when dealing with an entire URL component:

> The correct way to handle percent-encoded URL components is to: (i) keep the encoding intact, (ii) parse the component in to its smallest units, and (iii) percent-decode each unit. For example, when splitting a path, split the percent-encoded path and decode each path component individually

This is what `.pathComponents` (and other views) do for you.

```swift
// Remember that %2F is an encoded forward-slash.
var url = WebURL("https://example.com/music/bands/AC%2FDC")

for component in url.pathComponents {
  ... // component = "music", "bands", "AC/DC".
}

// Inserted components are automatically encoded, 
// so they will be preserved exactly.

url.pathComponents.removeLast()
url.pathComponents.append("blink-%182")
// url = "https://example.com/music/bands/blink-%25182"

url.pathComponents.last // "blink-%182"
```

In short, the `.pathComponents` view is the best way to read or modify a URL's path at the path-component level. It's efficient, and Swift's Collection protocols give it a large number of convenient operations out-of-the-box (such as map/reduce, slicing, pattern matching).


# Query Items


Just as a URL's `path` may contain a list of path components, the `query` often contains a list of key-value pairs. WebURL provides a `.formParams` view which allows you to efficiently read and modify key-value pairs in a URL's query string.

Formally the query is just an opaque string; even if a URL has a query component, there is no guarantee that interpreting it as a list of key-value pairs makes sense, or which style of encoding they might use. The key-value pair convention began with HTML forms, which used an early version of percent-encoding (`application/x-www-form-urlencoded` or "form encoding"). As tends to be the way with these things, form-encoding looks very similar to, but is incompatible with, percent-encoding as we know it today, due to substituting spaces with the "+" character. These days, the convention has spread far beyond HTML forms, although other applications sometimes use percent-encoding rather than strictly form-encoding. It's up to you to know which sort of encoding applies to your URLs. This is... just life on the web, I'm afraid 😔.

As with the `.pathComponents` view, returned keys and values are automatically decoded, and any inserted keys or values will be encoded so their contents are preserved exactly. The `.formParams` view assumes form-encoding, and writes values using form-encoding. In the future, we'll likely add a variant which uses percent-encoding (probably named `.queryParams` or something like that). The current implementation matches the `.searchParams` object from JavaScript's URL class.

To read the value for a key, use the `get` function or access the value as a property:

```swift
let url = WebURL("https://example.com/currency/convert?amount=20&from=EUR&to=USD")!

url.formParams.amount    // "20"
url.formParams.from      // "EUR"
url.formParams.get("to") // "USD"
```

Additionally, you can iterate all key-value pairs using the `allKeyValuePairs` property, which conforms to Swift's `Sequence` protocol:

```swift
for (key, value) in url.formParams.allKeyValuePairs {
  ... // ("amount", "20"), ("from", "EUR"), ("to", "USD").
}
```

To modify a value, assign to its property or use the `set` method. Setting a key that does not already exist insert a new key-value pair, and setting a key's value to `nil` will remove it from the query. 

```swift
var url = WebURL("https://example.com/currency/convert?amount=20&from=EUR&to=USD")!

url.formParams.from = nil
url.formParams.to   = nil
// url = "https://example.com/currency/convert?amount=20"

url.formParams.amount = "56"
url.formParams.from   = "USD"
url.formParams.to     = "Pound Sterling"
// url = "https://example.com/currency/convert?amount=56&from=USD&to=Pound+Sterling"

url.formParams.set("format", to: "json")
// url = "https://example.com/currency/convert?amount=56&from=USD&to=Pound+Sterling&format=json"
```


# File URLs


Integration with the `swift-system` package (and Apple's `System.framework`) allows you to create file paths from URLs and URLs from file paths, and supports both POSIX and Windows-style paths. To enable this integration, add the `WebURLSystemExtras` product to your target's dependencies:

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
        .product(name: "WebURL", package: "swift-url"),
        .product(name: "WebURLSystemExtras", package: "swift-url"),  // <---- This.
      ]
    )
  ]
)
```

Next, import the integration library. We'll be using Apple's built-in `System.framework` here, but the API is exactly the same if using `swift-system` as a package:

```swift
import System
import WebURL
import WebURLSystemExtras

// - Create a WebURL from a file path:
var fileURL = try WebURL(filePath: NSTemporaryDirectory())
fileURL.pathComponents += ["My App", "cache.dat"]
// fileURL = "file:///var/folders/ds/msp7q0jx0cj5mm9vjf766l080000gn/T/My%20App/cache.dat"

// - Create a System.FilePath from a WebURL:
let path = try FilePath(url: fileURL)
// path = "/var/folders/ds/msp7q0jx0cj5mm9vjf766l080000gn/T/My App/cache.dat"

let descriptor = try FileDescriptor.open(path, .readWrite)
try descriptor.write(....)
```

The `WebURL(filePath:)` and `FilePath(url:)` initializers throw detailed errors which you can use to provide users with detailed diagnostics should their file URLs not be appropriate for the platform.

There are lots of misconceptions about file URLs. Using URLs instead of file paths does **not** make your application/library more portable; ultimately, the URL still needs to represent a valid path for the specific system you want to use it with. Windows paths require a drive letter and refer to remote files using servers and shares, and there are special rules for how to manipulate and normalize them (for example, ".." components should not escape the drive root or share). POSIX paths work entirely differently; they don't have drive letters and tend to mount remote filesystems as though they were local folders.

URLs work using URL semantics, which has to be very generic because URLs are used for so many things on all kinds of platforms. A URL's path has some passing resemblance to a POSIX-style filesystem path, and the parser includes some (platform-independent) compatibility behavior, but it isn't a replacement for a true file path type.

File URLs are still useful as a currency format when you support both local and remote resources (e.g. opening a local file in a web browser), but within your application, if you know you're dealing with a file path, you should prefer to store and manipulate it using a domain-expert such as swift-system's `FilePath`. This is different to the advice given by Foundation, but it is what the editors of the URL Standard recommend, and it makes sense. I've seen a fair few bug reports in the URL standard from people disappointed that URLs don't always normalize like file paths do (e.g. [this one, from the Node.js team](https://github.com/whatwg/url/issues/552)).

So WebURL's APIs for file URLs are intentionally limited to converting to/from the `FilePath` type. No [`.resolveSymlinksInPath()`](https://developer.apple.com/documentation/foundation/url/1780208-resolvesymlinksinpath) over here. Of course, you can still use the full set of APIs with file URLs (including `.pathComponents` and even `.formParams`) but for the best, most accurate file path handling, we recommend `FilePath` (or similar type from the library of your choice).


# Wrapping up


And that's it for this guide! We've covered a lot here:

- Creating a WebURL, by parsing a String or resolving a relative reference,
- Reading and modifying the WebURL's top-level components,
- How to correctly handle percent-encoding,
- Working with path components and form parameters, and
- File URLs and file paths

Hopefully having read this, you feel confident that you understand how to use `WebURL`, and the benefits it can bring to your application:

- URLs based on the latest industry standard, aligning with modern web browsers,
- An API that is more intuitive and helps avoid subtle mistakes,
- An API which more closely matches libraries in other languages whilst leveraging the full expressive power of Swift,
- A blazing fast implementation with better memory efficiency and simpler object lifetimes.

And there's even more advanced topics that we didn't cover, like the `Host` enum, _lazy_ percent-encoding and decoding, `Origin`s, and more. If you'd like to continue reading about the APIs available in the `WebURL` package, see the [official documentation](https://karwa.github.io/swift-url/), or just go try it out for yourself!

If you have any questions or comments, please [file an issue on GitHub](https://github.com/karwa/swift-url/issues), or [post a thread on the Swift forums](https://forums.swift.org/c/related-projects/weburl/73), or send the author a private message (`@Karl` on the Swift forums). We're constantly looking to improve the API as we push towards a 1.0 release, so your feedback is very much appreciated!
