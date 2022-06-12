# Using WebURL with Foundation

Best practices when mixing URL standards


## Introduction


The WebURL package comes with a number of APIs to support using `WebURL` values with Foundation:

1. Conversion initializers.

    Convert values between `WebURL` and `Foundation.URL` simply by constructing the type you need.
    These initializers verify that both types have an equivalent interpretation of the URL value.

    ```swift    
    let sourceURL = WebURL("https://api.example.com/foo/bar?baz")!
    
    // WebURL -> Foundation.URL
    let nsURL = URL(sourceURL)  // ✅ "https://api.example.com/foo/bar?baz"    
    // Foundation.URL -> WebURL
    let webURL = WebURL(nsURL)  // ✅ "https://api.example.com/foo/bar?baz"
    ```

2. Convenience wrappers.

    Make requests using `URLSession` directly from a `WebURL` value, eliminating the conversion boilerplate.

    ```swift
    // 😌 Make a URLSession request using a WebURL.
    let webURL = WebURL("https://api.example.com/foo/bar?baz")!
    let dataTask = URLSession.shared.dataTask(with: webURL) { data, response, error in
      // ...
    }
    dataTask.resume()
    ```

> Note:
> For these APIs to be available, you must import the `WebURLFoundationExtras` module:
> 
> ```swift
> import Foundation
> import WebURL
> import WebURLFoundationExtras  // <--
> ```

These APIs enable you to use `WebURL` for more of your URL processing, while still supporting clients
or using libraries which require `Foundation.URL`.

For many applications, this will "just work". However, there are some subtleties you should 
generally be aware of. The issues we will be discussing are, in fact, defects in URLs themselves;
and they happen in every programming language, with every URL library, and can affect the security
and robustness of your code.


## URL Strings are Ambiguous


Almost all systems rely on URLs, often for vital communication with both local and remote services,
or processing requests from other devices; and data extracted from URLs is often used to make security-
and privacy-sensitive decisions. It may be surprising, then, to learn that **URL strings are ambiguous**.

URL standards have been revised many times over the decades, resulting in incompatibilities.
It is difficult to ensure that all code which processes a URL string interprets it in exactly the same way and
derives the same information from it. That is particularly true of networked clients, each of which might
use entirely different languages and libraries to process URLs, but even local applications
might expose data to multiple URL parsers, perhaps in dependencies of dependencies.

Moreover, web browsers (typically one of the most important clients) have not been able to conform to _any_ 
historical standards because they must maintain compatibility with the web. The result is a surprising amount
of variety in how URL strings are actually interpreted, and occasional disagreements; 
and given how much we rely on URLs, that can lead to unexpected behavior and even exploitable vulnerabilities.

Enter **WebURL**. WebURL conforms to the latest industry standard, which formally defines URL parsing
in a way that is compatible with the web platform. You should expect `WebURL` to work exactly as your browser does.
There is even a shared test-suite between `WebURL`, the major browsers, and other library implementations,
to help ensure consistency.

So what kind of disagreements and vulnerabilities are we talking about? Consider the following:

```swift
// Q: What is the hostname of this URL?
let urlString = "http://foo@evil.com:80@example.com/" 

WebURL(urlString)!.hostname  // "example.com"
URL(string: urlString)!.host // "evil.com"
```

Chrome, Safari, Firefox, Go, Python, NodeJS, and Rust all agree with WebURL - that this identifier
points to `"example.com"`. If you paste it in your browser, that's where it will go. 
But since Foundation's interpretation is based on an obsolete standard that is not web-compatible,
it would send a request to `"evil.com"` instead. 

These are the sorts of differences we're talking about - "regular" URLs work like you'd expect, of course
(again - WebURL works just like your browser; **adopting WebURL won't break everything**), but there are these
little details which can and have been exploited by attackers in surprising ways. And as you can see,
generally WebURL's interpretation is the more compatible one, because it matches the web.

> Important:
>
> Using multiple URL standards safely is a difficult problem, but in a sense it's a problem we already live with. 
> We've devised a few simple guidelines to help your code deal with this situation more robustly:
>
> - Store and communicate URLs using URL types. Avoid passing them around as strings.
> - Each URL string should be interpreted by **only one** parser.
> - If you must store or communicate a URL as a string (e.g. in JSON),
>   document which parser should be used to interpret it.
> - If no parser is specified, `WebURL` is a good default.
>
> The lack of alignment in URL standards is an issue that is being actively exploited, particularly in 
> Server-Side Request Forgery (SSRF) vulnerabilities. In the following sections, we'll discuss the above advice
> in more detail, including examples of actual exploits and how these practices could have avoided them.


## URL Types are Unambiguous


The first guideline is to prefer storing and communicating URLs using URL types, rather than as strings.
The meaning of a plain string can be ambiguous, but a value with a type such as `Foundation.URL` or `WebURL`
communicates precisely how it should be interpreted, and this enables initializers which verify that semantics
are maintained across a conversion. 

For example, consider the demonstration URL from the previous section. Both `Foundation.URL` and `WebURL` were able
to parse the raw URL string, but saw different components from it. Now, let's try parsing the string as a
`Foundation.URL`, and converting it to a `WebURL`:

```swift
let urlString = "http://foo@evil.com:80@example.com/" 

let nsURL = URL(string: urlString)!
print(nsURL.host) // "evil.com"
WebURL(nsURL)     // ✅ nil - URL is ambiguous
```

The initializer checks that both types agree about what the URL means. In this case, they don't,
so the conversion fails. This is a **much better outcome** than accidentally sending data to the wrong server!

Something interesting happens if we try this conversion the other way around. Parsing a URL string with `WebURL`
also _normalizes_ it, so it cleans up ambiguous syntax and makes the web-compatible interpretation more obvious
to other software and systems. This means that converting a `WebURL` to a `Foundation.URL` will almost always succeed,
even in cases where the reverse order of operations would have failed.

```swift
let urlString = "http://foo@evil.com:80@example.com/" 

let webURL = WebURL(urlString)!
print(webURL.hostname)  // "example.com"
print(webURL)           // "http://foo%40evil.com:80@example.com/"
//                                    ^^^
//               Problematic '@' sign has been encoded by WebURL,
//                  making the web-compatible interpretation
//                                more obvious.

URL(webURL)?.host  // ✅ "example.com"
```

Successful conversion does **not** necessarily mean that the URLs have identical strings or components.
The conversion initializers are based on careful study of both standards, and although they are careful
not to permit different interpretations, they are lenient in certain cases when both standards allow it.

That means they won't get in your way rejecting irrelevant differences (many times, even a force-unwrap
would not be unreasonable), but they still catch those edge cases where there are genuine mismatches,
as we've seen in the previous few examples.

Here is an example of the kind of differences that are allowed. The standard used by `WebURL` requires
that the URL's scheme and hostname be normalized to lowercase (`WebURL` has to do it; it has no choice).
Luckily, RFC-2396 (the standard used by `Foundation.URL`) explicitly allows that, so even if those parts
of the URL are upper/mixed-case (perhaps the user had caps-lock on and didn't notice), the conversion is allowed.

```swift
// Foundation's components:
let nsURL = URL(string: "HTTP://EXAMPLE.COM/")!
print(nsURL)         // "HTTP://EXAMPLE.COM/"
print(nsURL.scheme)  // "HTTP"
print(nsURL.host)    // "EXAMPLE.COM"

// WebURL normalizes the URL, but the meaning is preserved:
let convertedURL = WebURL(nsURL)!
print(convertedURL)           // ✅ "http://example.com/"
print(convertedURL.scheme)    // ✅ "http"
print(convertedURL.hostname)  // ✅ "example.com"
```

This safe interoperability, which allows as much as it can but also catches real ambiguities, is only possible
because we are converting URL types rather than simply parsing the string again. In the next section, we'll discuss
applying this idea throughout your application, so it is always clear how a URL is being interpreted.


## One Parser Per String


Consider the following program, demonstrating a simple proxy server. Here's how it works:

- 0️⃣ (Not shown) A client connects to us, says "make a request to this URL for me, please".
- 1️⃣ The server checks the provided URL.
- 2️⃣ If the hostname is allowed, the server makes the request, including some private token/key in the header.
- 3️⃣ (Not shown) The response is forwarded to the client.

The part we're interested in is split in to two functions - one gets a URL string and checks that it points
to an approved server, and the other makes the authenticated HTTP request:

**Application:**
```swift
func checkHostAndMakeRequest(_ urlString: String) throws -> URLSessionDataTask {
  // 1. Verify host.
  guard checkHostIsAllowed(urlString) else { 
    throw MyAppError.hostIsNotAllowed
  }
  // 2. Make request.
  return try makeAuthenticatedRequest(urlString, completionHandler: ...)
}
```

**Allow-List Checker:**
```swift
let allowedHosts: Set<String> = [ "example.com", /* ... */ ]

func checkHostIsAllowed(_ urlString: /* ⚠️ */ String) -> Bool {
  if let hostname = WebURL(urlString)?.hostname {
    return allowedHosts.contains(hostname)
  }
  return false
}
```

**Request Engine:**
```swift
func makeAuthenticatedRequest(_ urlString: /* ⚠️ */ String, completionHandler: <...>) throws -> URLSessionDataTask {
  guard let url = Foundation.URL(string: urlString) else {
    throw MyLibraryError.invalidURL
  }
  var request = URLRequest(url: url)
  request.allHTTPHeaderFields = ["Authorization" : "Bearer <...>"]
  return URLSession.shared.dataTask(with: request, completionHandler: completionHandler)
}
```

Each of these functions is reasonable by itself, but the effect of combining them is that a single URL string
is parsed **twice**, each time by a different parser, and the results may not be consistent. In other words,
the hostname verified by `checkHostIsAllowed` might _not_ be the host that `makeAuthenticatedRequest` actually
makes a request to! 😱

```swift
// The call:
let task = try checkHostAndMakeRequest("http://foo@evil.com:80@example.com/")

// What happens:
func checkHostAndMakeRequest(_ urlString: String) throws -> URLSessionDataTask {

  // ⚠️ 'checkHostIsAllowed' parses the string using WebURL,
  //     so it thinks the host is 'example.com'.
  guard checkHostIsAllowed(urlString) else { 
    throw MyAppError.hostIsNotAllowed
  }
  // ⚠️ But the request function parses the string using Foundation.URL,
  //    so it actually makes the request to 'evil.com' and leaks our token!
  return try makeAuthenticatedRequest(urlString, completionHandler: ...)
}
```

A maliciously-crafted string could exploit this difference to leak authentication tokens to the attacker's own server;
in fact, this demonstrates [a real vulnerability][gcp-ssrf] that was used to gain unauthorized access to internal
Google Cloud Platform accounts. Differences between modern and historic URL standards can cause security vulnerabilities,
even outside the Swift ecosystem. It's not just a Foundation.URL or WebURL thing - it's something **all developers**
need to be aware of. URL libraries often do not align to the same standard, and any data derived from one parser
might be inconsistent with another parser.

Spotting these interactions can be difficult - for instance, the functions may live in separate libraries
and you may not have access to their source code, or the URL string might be in a JSON document or XPC message.
The common feature is that URLs are communicated **without using a URL type**, so we can't ensure that everybody
who sees the string interprets it the same way.

We can fix the issue in this case by hoisting URL parsing out of `checkHostIsAllowed` and `makeAuthenticatedRequest`,
and moving it in to the caller. Now, instead of passing strings around and letting each function choose its own
parser, the caller parses the string, and passes around strongly-typed URL values (in this case `WebURL`).
Thanks to checked conversions, the receivers can safely convert to another URL type if they wish - in this case,
`makeAuthenticatedRequest` converts to a `Foundation.URL` and makes the request using `URLSession`.

**Fixed Allow-List Checker and Request Engine:**
```swift
func checkHostIsAllowed(_ url: /* ✅ */ WebURL) -> Bool {
  if let hostname = url.hostname {
    return allowedHosts.contains(hostname)
  }
  return false
}

func makeAuthenticatedRequest(_ url: /* ✅ */ WebURL, completionHandler: <...>) throws -> URLSessionDataTask {
  // ✅ checked WebURL -> Foundation.URL conversion.
  guard let convertedURL = Foundation.URL(url) else {
    throw MyLibraryError.invalidURL
  }
  var request = URLRequest(url: convertedURL)
  request.allHTTPHeaderFields = ["Authorization" : "Bearer <...>"]
  return URLSession.shared.dataTask(with: request, completionHandler: completionHandler)
}
```

> Tip:
>
> We're showing the explicit `WebURL -> Foundation.URL` conversions for clarity, but WebURL also
> includes convenience APIs so you can create `URLRequest`s directly. 
>
> ```swift
> func makeAuthenticatedRequest(_ url: WebURL, completionHandler: <...>) throws -> URLSessionDataTask {
>   // ✅ Create URLRequest directly from a WebURL
>   var request = URLRequest(url: url)
>   request.allHTTPHeaderFields = ["Authorization" : "Bearer <...>"]
>   return URLSession.shared.dataTask(with: request, completionHandler: completionHandler)
> }
> ```

Let's see what happens now that we've switched to using URL types rather than strings:

```swift
// The call:
let task = try checkHostAndMakeRequest("http://foo@evil.com:80@example.com/")

// What happens:
func checkHostAndMakeRequest(_ urlString: String) throws -> URLSessionDataTask {

  // ✅ The string is only parsed once.
  guard let url = WebURL(urlString) else {
    throw MyAppError.invalidURL
  }
  // ✅ 'checkHostIsAllowed' reads the host as 'example.com'.
  guard checkHostIsAllowed(url) else { 
    throw MyAppError.hostIsNotAllowed
  }
  // ✅ Typed conversion ensures the request is really made to 'example.com' 
  return try makeAuthenticatedRequest(url, completionHandler: ...)
}
```

We could even hoist URL parsing again, and make `checkHostAndMakeRequest` itself accept a URL value
instead of a string. By applying this process repeatedly, we reduce the number of raw URL strings
floating around the application, and can leverage the type system to ensure we always interpret values
correctly.

As we've seen, there can be subtle, security-sensitive interactions between URL parsers, but by applying
some reasonable best-practices, we can get what we want: web-compatible URL parsing and operations
(notice the request is made to `"example.com"`, not `"evil.com"`), with robustly Foundation interop.
The guiding rule is that each _string_ should be parsed by only one parser. 

For this reason, we **strongly recommend** that you use typed URL values and the conversion initializers
provided by `WebURLFoundationExtras`. For more complex situations, such as URLs in JSON documents or XPC messages,
document which parser should be used, and parse those values early or hide them behind typed APIs, 
so they do not spread as plain strings.

[gcp-ssrf]: https://bugs.xdavidhu.me/google/2021/12/31/fixing-the-unfixable-story-of-a-google-cloud-ssrf/


## Prefer Parsing Using WebURL


We've discussed how you can use the type system to ensure safe conversions, but what about the initial step? 
Which URL parser should you use to turn your strings in to objects?

Firstly, if the developer has specified which parser to use for a URL string, **use that parser**.
Otherwise, matching a web browser is generally a good choice, and probably a more reasonable choice
than the standard used by `Foundation.URL`, which has been officially obsolete for several decades.

> Tip:
> I know, this could all sound a bit scary; it's complexity you didn't ask for and would much rather do without.
> I get it. But I hope this document has helped to illustrate that the status quo has serious problems,
> and the complexity, annoying as it is, can be managed very well with some simple best-practices.

Using `WebURL` for parsing and URL manipulation comes with a lot of additional benefits:

1. 🌍 It's web-compatible.

   Actors on the web platform should use a web-compatible parser to interpret URLs. 
   `Foundation.URL` is not web-compatible. It's as simple as that.

   WebURL behaves just like a browser does, just like JavaScript's `URL` class does, and like many other libraries do. 
   In fact, the ``WebURL/WebURL/jsModel-swift.property`` property exposes the exact JS URL API for mixed Swift/JS
   code-bases - tested to browser standards, using the same shared test suite that the major browsers use. 

2. 🔩 It's always normalized.

   Parsing a string using `WebURL` cleans up a lot of ambiguous or ill-formatted URLs automatically.
   That means `WebURL` is easier to work with, and produces URL strings which are more interoperable
   with other libraries and systems.

   For example, when `async-http-client` needs to examine a scheme from a `Foundation.URL` 
   (like `"http"` or `"https+unix"`), it has to remember to manually normalize it to lowercase it first -
   like it does [here][ahc-nsurl-scheme-1] and again way over [here][ahc-nsurl-scheme-2], in another file.
   SwiftPM does the same thing [here][spm-nsurl-scheme-1] and [here][spm-nsurl-scheme-2] and other places.

   With WebURL, **none of that is necessary** - that boilerplate can just go. Schemes, hostnames, paths, etc
   are all normalized, all the time. Even if you modify the URL and set components - it is always normalized.

   Your code becomes more predictable. For example, I noticed that some parts of DocC [don't][docc-nsurl-scheme]
   manually normalize schemes to lowercase - is it intentional or not? Who knows! Like most people,
   they're probably unaware that URL schemes are case-insensitive. With WebURL, they wouldn't need to worry about it;
   their code could remain straightforward but still be correct and consistent. 

3. 😌 Rich, expressive APIs.

   `WebURL`'s `.pathComponents` and `.formParams` properties give you efficient access to the URL's path and query.
    The `.pathComponents` view conforms to `BidirectionalCollection`, so you have immediate access to a huge number of 
    features and algorithms - such as `map`, `filter`, and `reduce`, not to mention slicing, such as `dropLast()`.
    And you can even modify through this view, using indexes to perform complex operations super-efficiently. 
   
    ```swift
    let url = WebURL("https://github.com/karwa/swift-url/issues/63")!
    if url.pathComponents.dropLast().last == "issues",
      let issueNumber = url.pathComponents.last.flatMap(Int.init) {
     // ✅ issueNumber = 63
    }
    ```
    ```swift
    var url = WebURL("https://info.myapp.com")!
    url.pathComponents += ["music", "bands" "AC/DC"]
    // ✅ "https://info.myapp.com/music/bands/AC%2FDC"
    ```

    The `.formParams` view takes query parameters to the next level, with dynamic member lookup. 
    You just get and set values as if they were properties. Zero fuss:

    ```swift
    var url = WebURL("https://example.com/search?category=food&client=mobile")!
    url.formParams.category  // "food"
    url.formParams.client    // "mobile"

    url.formParams.format = "json"
    // ✅ "https://example.com/search?category=food&client=mobile&format=json"
    //                                                            ^^^^^^^^^^^
    ```

    Here's a challenge: with WebURL, that was 3 lines of super obvious code. 
    Now try doing that with `Foundation.URL`. Yeah.

    The `.host` API is less frequently used, but even here we can offer a breakthrough in expressive, robust code.
    With WebURL, the URL type tells applications _directly_ which computer the URL points to. I really love this.
    I think this is _exactly_ what a Swift URL API should be; it takes a complex, nebulous string
    and gives you simple, precise, structured values with strong guarantees. 

    ```swift
    let url = WebURL("http://127.0.0.1:8888/my_site")!

    guard url.scheme == "http" || url.scheme == "https" else {
      throw UnknownSchemeError()
    }
    switch url.host {
      case .domain(let name): ... // DNS lookup.
      case .ipv4Address(let address): ... // Connect to known address.
      case .ipv6Address(let address): ... // Connect to known address.
      case .opaque, .empty, .none: fatalError("Not possible for http")
    }
    ```

    Come for the web-compatible URL parsing, or backwards-deployable IDN support;
    stay because literally everything else is lightyears ahead as well.

    And you can still hand values over to legacy `Foundation.URL` code whenever you need to. 
    So you can take advantage of these APIs today, where you need them, without forcing everything to be rewritten. 

4. 📊 It's _really_ well tested.

   `WebURL` is extensively tested by the Web Platform Tests. The WPT is a shared test database
   used by the major browsers and other libraries; we pool our implementation experience to ensure that
   any ambiguities or divergence is spotted and eliminated (sometimes the standard is ambiguous; that gets corrected).
   The WebURL project has made a lot of contributions towards that effort, including finding and fixing issues
   in browsers and elsewhere.

   This whole process is a really valuable positive cycle, and helps give you confidence that WebURL will work
   just like, say, Safari. We literally use the same test suite.

   Unfortunately, `Foundation.URL` simply cannot participate in that process, or anything like it.
   Nobody's writing new implementations of the obsolete RFC-2396.

   The WPT alone is over 3x as large as Foundation's test database, and includes much better quality test-cases
   because it is exposed to the entire web and actively maintained. Foundation's tests actually include
   plenty of mistakes (!), so it actually tests incorrect behavior 🤦‍♂️. My guess is that Foundation is not able
   to fix those due to compatibility, but who knows? They don't respond at all to any of the dozen or so bug reports 
   I've filed, showing some pretty shocking bugs in `Foundation.URL`. That's not even to mention that lots of
   publicly-known URL exploits are actually monkey-patched in WebKit rather than being fixed at the source
   (which is the buggy CFURL parser). Perhaps they can't fix those, either? I don't like to mention that kind of thing
   due to responsible disclosure, but you deserve to know that your code might be vulnerable. The disclosure process
   happened years ago.
   
   In contrast, testing has been a major focus of `WebURL` since the beginning. As well as the WPT,
   WebURL is tested by _hundreds_ of additional tests, covering every aspect of its API. Our coverage is about 88%
   as of writing (generally regarded as excellent), and the gaps are mostly things that can't easily be tested
   in Swift (such as assertion failures). And if _all of that_ wasn't enough, `WebURL` is regularly fuzz-tested,
   as are the URL type conversions. Because our checked conversions actually _account for bugs in Foundation_
   to make sure nothing slips through the cracks.

   All of this means that you can have confidence adopting `WebURL` _right now_.
   Obviously nobody can guarantee zero bugs ever, but WebURL is a massive improvement - and as a Swift package,
   any fixes can be implemented and deployed immediately. No more chucking bug reports in to a void
   and being disappointed as year after year they go ignored and unfixed.

5. 🔥 It's blazing fast.

   `WebURL` is regularly benchmarked, and comes out faster than `Foundation.URL` for _every_ operation; 
   whether you're parsing URL strings, modifying components, iterating through the path, etc.
   In particular, it is **orders of magnitude** faster on low-end/IoT platforms like the Raspberry Pi,
   enabling applications which were previously so slow they'd be impractical. 
   

[ahc-nsurl-scheme-1]: https://github.com/swift-server/async-http-client/blob/0f21b44d1ad5227ccbaa073aa40cd37eb8bbc337/Sources/AsyncHTTPClient/DeconstructedURL.swift#L45
[ahc-nsurl-scheme-2]: https://github.com/swift-server/async-http-client/blob/0f21b44d1ad5227ccbaa073aa40cd37eb8bbc337/Sources/AsyncHTTPClient/Scheme.swift#L42
[spm-nsurl-scheme-1]: https://github.com/apple/swift-package-manager/blob/e25a590dc455baa430f2ec97eacc30257c172be2/Sources/PackageCollections/PackageCollections%2BValidation.swift#L35
[spm-nsurl-scheme-2]: https://github.com/apple/swift-package-manager/blob/e25a590dc455baa430f2ec97eacc30257c172be2/Sources/PackageCollections/Model/Collection.swift#L116
[docc-nsurl-scheme]: https://github.com/apple/swift-docc/blob/d94139a5e64e9ecf158214b1cded2a2880fc1b02/Sources/SwiftDocC/Model/TaskGroup.swift#L43-L44


## A Note on Round-Tripping


Round-tripping refers to taking a value (say, a `WebURL`), converting it to another type (`Foundation.URL`),
and then converting back to the original type (to `WebURL` again). Some libraries and data structures need 
strong guarantees about that situation, so here it is:

- A `WebURL` which can be converted to a `Foundation.URL` value can **always** be converted back to a `WebURL`.

- A `Foundation.URL` which can be converted to a `WebURL` can **almost always** be converted back to a `Foundation.URL`.

  > Note:
  >
  > There is one, very rare situation where a Foundation -> WebURL conversion cannot be converted back: 
  > HTTP URLs whose hostnames contain percent-encoded special characters. These will get decoded by `WebURL`,
  > but can't be re-encoded for the conversion back to Foundation.
  > 
  > ```swift
  > (Foundation "http://te%7Bs%7Dt/") -> (WebURL "http://te{s}t/") -> (Rejected by Foundation)
  >                       ^^^ ^^^                          ^ ^
  > ```
  > These are not valid DNS domain names, so this is mostly a theoretical concern.
  > Generally, you can assume that Foundation -> WebURL conversion means the result can be converted back
  > to a `Foundation.URL`.

Sometimes, when converting a `WebURL` to Foundation, we need to add percent-encoding; this means the round-trip
result will not be equal to the original `WebURL` value. However, you can use the `WebURL.encodedForFoundation`
property to add that percent-encoding in advance; if this pre-encoded URL can be converted to a `Foundation.URL`,
it is guaranteed to round-trip to exactly the same `WebURL` value.
  
```swift
func processURL(_ webURL: WebURL) throws {

  let encodedWebURL = webURL.encodedForFoundation
  // ℹ️                     ^^^^^^^^^^^^^^^^^^^^^
  // Percent-encoding is added by default when converting to Foundation.
  // If we do it now, we know the round-trip result will equal 'encodedWebURL'.

  guard let convertedURL = URL(encodedWebURL) else { throw InvalidURLError() }

  // Do whatever you needed to do with Foundation... 
  let dataTask = URLSession.shared.dataTask(from: convertedURL)
  let urlFromDataTask = dataTask.originalRequest!.url!

  // ✅ A converted WebURL can always convert back. 
  let roundtripWebURL = WebURL(urlFromDataTask)!

  // ✅ The round-trip result is equal to 'encodedWebURL'. 
  assert(encodedWebURL == roundtripWebURL)
}
```

It is not generally possible to know in advance what the result of a `{Foundation -> WebURL -> Foundation}` round-trip
will be. There is no equivalent of `WebURL.encodedForFoundation` which normalizes a `Foundation.URL`.
