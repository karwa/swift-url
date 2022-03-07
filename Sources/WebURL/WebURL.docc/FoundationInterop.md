# Using WebURL with Foundation

Best practices when mixing URL standards


## Introduction


The WebURL package comes with a number of APIs to support using `WebURL` with Foundation:

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

This makes it easier to use `WebURL` for more of your URL processing, while still supporting clients
or using libraries which require `Foundation.URL`.


For many applications, this will "just work". However, if you are developing a library which parses a URL string
(including from a JSON document or XPC message), there are some additional subtleties which you should be aware of.
These subtleties are, in fact, defects in URLs themselves; they happen in every programming language, with every
URL library, and can affect the security and robustness of your code.


## URL Strings are Ambiguous


Almost all systems rely on URLs, often for vital operations such as making requests to remote services,
processing requests from remote clients, locating files, determining who "owns" a particular resource, and more.
It may be surprising, then, to learn that **URL strings are ambiguous**.

URL standards have been revised many times over the decades, introducing subtle differences in how they are interpreted.
It is difficult to ensure that all code which processes a URL string interprets it in exactly the same way and
derives the same information from it - and that applies not only to networked clients, each of which might
use entirely different languages and libraries to process URLs, but also local applications.
Moreover, web browsers (typically one of the most important clients) have not been able to conform to any 
historical standards due to compatibility constraints. There is a surprising amount of variety in how URL strings
can be interpreted, and sometimes they disagree with each other; and given how much we rely on URLs, that can lead
to unexpected behavior and even exploitable vulnerabilities.

This is the problem `WebURL` was created to help with; `WebURL` conforms to the latest industry standard,
which formally defines URL parsing in a way that is compatible with the web platform. You should expect `WebURL`
to work exactly as your browser does. There is even a shared test-suite which `WebURL`, the major browsers,
and other libraries all contribute to, which ensures that implementations do not diverge.

Since `Foundation.URL` conforms to an older standard that is **not** web-compatible, parsing the same string
with `WebURL` or `Foundation.URL` can expose some of those differences mentioned earlier. Consider the following:

```swift
// What is the hostname of this URL?
let urlString = "http://foo@evil.com:80@example.com/" 

WebURL(urlString)!.hostname  // "example.com"
URL(string: urlString)!.host // "evil.com"
```

Chrome, Safari, Firefox, Go, Python, NodeJS, and Rust all agree that this URL points to `"example.com"`. 
Try it - if you paste it in your browser, that's where it will go. But since Foundation's interpretation
is based on an obsolete standard, it would send a request to `"evil.com"` instead. 

There are many subtle differences similar to this - after all, that is what it means for these types to implement
different URL standards. This is the main way in which `WebURL` and `Foundation.URL` differ, and why you may
wish to use `WebURL`'s web-compatible URL interpretation together with software that requires `Foundation.URL` values.

> Important:
>
> Using multiple URL standards safely requires a holistic understanding of how an application/library treats URLs.
> We propose the following guidelines, to be taken as best practices:
>
> - Store and communicate URLs using URL types. Avoid passing them around as strings.
> - Each URL string should be interpreted by **only one** parser.
> - If you must store or communicate a URL as a string (e.g. in JSON),
>   document which parser should be used to interpret it.
> - If no parser is explicitly specified, prefer `WebURL` as the default.
>
> The proliferation of URL standards is an issue that is being actively exploited, particularly by 
> Server-Side Request Forgery (SSRF) vulnerabilities. The following sections discuss this advice in detail,
> including examples of exploits and how these practices could have avoided them.


## URL Types are Unambiguous


The first guideline is to prefer storing and communicating URLs using URL types, rather than using strings.
Unlike a raw URL string, which can be ambiguous, values with a type such as `Foundation.URL` or `WebURL` communicate
precisely how they should be interpreted, and this enables conversion initializers to protect you from ambiguous URLs.

For example, consider the demonstration URL from the previous section. Both `Foundation.URL` and `WebURL` can parse
the raw URL string, but see different components from it. But if we first parse the string as a `Foundation.URL` value
and try to convert it to a `WebURL`, the conversion initializer will check that the source and destination types have
an equivalent interpretation of the URL. In this case, they don't: `WebURL` sees the hostname `"example.com"`, 
but `Foundation.URL` sees `"evil.com"`, so the conversion fails. 
This is a **much better outcome** than accidentally sending data to the wrong server!

```swift
let urlString = "http://foo@evil.com:80@example.com/" 

let nsURL = URL(string: urlString)!
print(nsURL.host) // "evil.com"
WebURL(nsURL)     // ✅ nil - URL is ambiguous
```

Something interesting happens if we try this conversion the other way around. Parsing a URL string with `WebURL`
also normalizes it, so it helps to clean up ambiguous syntax and web-compatibility quirks.
This means that converting a `WebURL` to a `Foundation.URL` will almost always succeed.

Considering the same URL string again, we see that `WebURL` automatically percent-encodes a problematic 
`"@"` character, which cleans up the ambiguity about what the hostname is. Once `WebURL` has normalized it,
there is no question that the URL string expresses a hostname of `"example.com"`, so the conversion to `Foundation.URL`
succeeds and the result agrees with browsers and other libraries.

```swift
let urlString = "http://foo@evil.com:80@example.com/" 

let webURL = WebURL(urlString)!
print(webURL.hostname)  // "example.com"
print(webURL)           // "http://foo%40evil.com:80@example.com/"
//                                    ^^^
//               Problematic '@' sign has been encoded by WebURL,
//                   resolving the ambiguity in favor of how
//                       WebURL interprets this string.

URL(webURL)?.host  // ✅ "example.com"
```

Successful conversion does **not** necessarily mean that the URLs have identical strings or components.
The conversion initializers are based on careful study of both standards, and permit certain normalization if the
result is a valid interpretation of the source value. 

In the following example, the standard used by `WebURL` requires that the URL's scheme and hostname be normalized
to lowercase. RFC-2396 (the standard used by `Foundation.URL`) says that this is allowed, so we consider that the
URL's meaning is preserved and allow the conversion.

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

This safe interoperability is only possible because we are converting URL types, rather than just parsing strings. 
In the next section, we'll discuss how important it is to apply this throughout an application at every level,
so we always know how each URL should be interpreted.


## Parse Strings Once


Consider the following program, demonstrating a simple proxy server. It accepts a URL as input, and makes
an authenticated request to it (including some private token) - of course, before making the request,
the target must be verified to ensure that the proxy only discloses its tokens to servers that are allowed to see them.

The implementation is split in to two functions - one function checks that the URL points to an approved server,
and the other which makes the authenticated HTTP request. Both functions accept URL parameters using strings:

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

// ⚠️                                vvvvvv
func checkHostIsAllowed(_ urlString: String) -> Bool {
  if let hostname = WebURL(urlString)?.hostname {
    return allowedHosts.contains(hostname)
  }
  return false
}
```

**Request Engine:**
```swift
// ⚠️                                      vvvvvv
func makeAuthenticatedRequest(_ urlString: String, completionHandler: <...>) throws -> URLSessionDataTask {
  guard let url = Foundation.URL(string: urlString) else {
    throw MyLibraryError.invalidURL
  }
  var request = URLRequest(url: url)
  request.allHTTPHeaderFields = ["Authorization" : "Bearer <...>"]
  return URLSession.shared.dataTask(with: request, completionHandler: completionHandler)
}
```

Each of these functions may look reasonable in isolation, but the effect of combining them is that a single URL string
is parsed twice, each time by a different parser, and possibly with inconsistent results. In other words,
the hostname verified by `checkHostIsAllowed` might _not_ be the host that `makeAuthenticatedRequest` actually
makes a request to!

A maliciously-crafted URL could exploit this difference to leak authentication tokens to the attacker's own server;
indeed, a [recently-disclosed vulnerability][gcp-ssrf] used a similar technique with just such a proxy in order to
gain unauthorized access to some internal Google Cloud Platform accounts. This is a good demonstration of how
the proliferation of URL standards leads to security vulnerabilities today, even outside of the Swift ecosystem.

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

It can be difficult to spot these sorts of issues: for instance, these functions may live in separate libraries
and you may not have access to their source code, or the URL string might not be a simple parameter, but instead
part of a JSON document or XPC message. The common feature is that URLs are communicated without using a URL type,
so it is difficult to ensure that all parts of the program/distributed system interpret them consistently.

For function calls and other, more straightforward examples of this bug, switching to URL types can help.
This effectively hoists URL parsing out of the leaf functions and moves it closer to the source of the string.
Generally, you should aim to parse each URL string **once** and only once, and only using one parser.
After parsing, the URL can be safely converted between `WebURL` and `Foundation.URL` as many times as needed
using the conversion initializers.

We can fix the above example by hoisting URL parsing out of `checkHostIsAllowed` and `makeAuthenticatedRequest`,
and moving it in to their shared caller, `checkHostAndMakeRequest`. We decide to parse using `WebURL`,
but `makeAuthenticatedRequest` safely converts that to a `Foundation.URL` in order to make the request
using `URLSession`.

**Fixed Allow-List Checker and Request Engine:**
```swift
// ✅                          vvvvvv
func checkHostIsAllowed(_ url: WebURL) -> Bool {
  if let hostname = url.hostname {
    return allowedHosts.contains(hostname)
  }
  return false
}

// ✅                                vvvvvv
func makeAuthenticatedRequest(_ url: WebURL, completionHandler: <...>) throws -> URLSessionDataTask {
  // ✅ WebURL -> Foundation.URL conversion preserves meaning.
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
> We're showing the explicit `WebURL -> Foundation.URL` conversions for the sake of clarity, but you can also
> create a `URLRequest` directly from a `WebURL`. It will do the same, safe conversion behind the scenes.
>
> ```swift
> func makeAuthenticatedRequest(_ url: WebURL, completionHandler: <...>) throws -> URLSessionDataTask {
>   // ✅ Create URLRequest directly from a WebURL
>   var request = URLRequest(url: url)
>   request.allHTTPHeaderFields = ["Authorization" : "Bearer <...>"]
>   return URLSession.shared.dataTask(with: request, completionHandler: completionHandler)
> }
> ```

Now that these leaf functions no longer parse URL strings, we don't need to worry about them using different parsers.
URL string parsing now happens once, in the caller:

```swift
// The call:
let task = try checkHostAndMakeRequest("http://foo@evil.com:80@example.com/")

// What happens:
func checkHostAndMakeRequest(_ urlString: String) throws -> URLSessionDataTask {

  // ✅ The string is only parsed once.
  //    Note: best practice would be to hoist this as well :)
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

For the sake of making this example easier to follow, we're only showing one level of hoisting, but best practice
would be to hoist URL parsing once again, out of `checkHostAndMakeRequest` and in to its own caller. If we apply that
hoisting as many times as we can, we can prevent that URL floating around the application as a raw string.

As we've seen, it can be difficult to ensure that URLs are always interpreted consistently, especially across
large applications using lots of third-party libraries. For function calls and other situations where Swift's
type system is available, we **strongly recommend** that you use typed URL values and the conversion initializers
provided by `WebURLFoundationExtras`. For other situations, such as URLs communicated via JSON documents 
or XPC messages, we also very much recommend documenting which parser or standard is required to interpret them,
and ensuring that is used consistently.

[gcp-ssrf]: https://bugs.xdavidhu.me/google/2021/12/31/fixing-the-unfixable-story-of-a-google-cloud-ssrf/


## Prefer Parsing Using WebURL


We've discussed the importance of parsing raw URL strings in to typed URL values as early as possible,
and that you should rely on type conversions to move between the different standards. But which URL parser
should you use for that initial step?

Firstly, if it is explicitly specified which parser to use for a URL string, **use that parser**.
If it is not specified, then matching a web browser is typically a good choice, and probably a more reasonable choice
than the standard used by `Foundation.URL`, which as mentioned previously has been officially obsolete for some time.

Using `WebURL` for parsing and URL manipulation comes with a lot of additional benefits:

1. 🌍 It's web-compatible.

   Actors on the web platform need to use a web-compatible parser to interpret URLs. 
   `Foundation.URL` is simply not web-compatible. It's a simple point, but it is quite compelling.

2. 🔩 It's always normalized.

   Parsing a string using `WebURL` cleans up many ambiguous or ill-formatted URLs automatically, according to its
   interpretation of the contents. That means `WebURL` is easier to work with, and produces URL strings which 
   are more interoperable with other libraries and systems. They can even be converted to `Foundation.URL` values
   even in situations where the reverse order of operations would be ambiguous.

   > Tip:
   >
   > Every single `WebURL` API ensures the URL is kept normalized - whether you're inserting path components
   > or query parameters via the ``WebURL/WebURL/pathComponents-swift.property`` or ``WebURL/WebURL/formParams`` views,
   > or setting entire URL components via properties or the ``WebURL/WebURL/utf8`` view.
   >
   > There is no `.standardize()` or `.normalize()` function in `WebURL` - it just always is.

3. 😌 It's easier to use (and to use correctly).

   `WebURL`'s `.pathComponents` and `.formParams` views give you simple and efficient ways to read/write the URL's
   path and query. There's no awkward `URLComponents`-like type to convert to - it all just works, directly.

   If you're on an Apple platform and need to make requests using `URLSession`, you can totally do that!
   And if you need to interoperate with code that still uses the legacy `Foundation.URL`, you can do that, too!

   So once you parse a string using `WebURL`, why not just keep like that? 
   Take advantage of `WebURL`'s great API as far as you can, and convert only when you really need to.

4. 📊 It's _really_ well tested.

   `WebURL` is extensively tested by the Web Platform Tests. This is a shared test database used by the major browsers,
   `WebURL`, and other implementations of the standard; we pool our implementation experience to ensure that
   any ambiguities or divergent behavior are eliminated. Since `WebURL`'s parser is highly customized and tuned 
   for performance, we discovered a number of gaps in its coverage and made significant contributions to improve it -
   often exposing browser bugs that were subsequently fixed. This whole process is an incredibly valuable and positive
   cycle, and helps give you confidence that all implementations are reliable and work the same way.

   Unfortunately, `Foundation.URL` simply cannot participate in that process, or anything like it.
   Nobody's writing new implementations of the obsolete RFC-2396.

   Testing has been a major focus of `WebURL` since the beginning. In addition to the Web Platform Tests database
   (which by itself is over 3x as large as Foundation's database), WebURL is supplemented by _hundreds_ of additional
   tests, covering every aspect of its API. Currently our coverage is about 88% (generally regarded as excellent),
   and the gaps are mostly things that can't easily be tested in Swift (assertion failures and the like).

   And if _all of that_ wasn't enough, `WebURL` is regularly fuzz-tested, as are the URL type conversions.
   Fuzzing is an incredibly powerful technique that discovers bugs programmers wouldn't typically think to search for.

   All of this means that you can have confidence adopting `WebURL` _right now_.
   It is everything you would expect from a production-quality URL library.

5. 🔥 It's blazing fast.

   `WebURL` is regularly benchmarked, and comes out faster than `Foundation.URL` for _every_ operation; 
   whether you're parsing URL strings, modifying components, iterating through the path, etc.
   In particular, it is orders of magnitude faster on low-end/IoT platforms like the Raspberry Pi,
   enabling applications which were previously so slow they'd be impractical.
   

## A Note on Round-Tripping


Round-tripping refers to taking a value in one type (say `WebURL`), converting it to another type (`Foundation.URL`),
and then converting back to the original type (to `WebURL` again). This is a useful property for some libraries
and data structures.

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
  > It is worth noting that these are not valid DNS domain names, so this is mostly a theoretical concern.
  > Generally, you should assume that Foundation -> WebURL conversions can be converted back to `Foundation.URL`s.

Sometimes, percent-encoding needs to be added when converting a `WebURL` to Foundation; this means the round-trip
result will not be equal to the original `WebURL` value. Use the `WebURL.encodedForFoundation` property to add
percent-encoding in advance; if the result of that property can be converted to a `Foundation.URL`, it is guaranteed
to round-trip to an identical `WebURL` value.
  
```swift
func processURL(_ webURL: WebURL) throws {

  let encodedWebURL = webURL.encodedForFoundation
  // ℹ️                     ^^^^^^^^^^^^^^^^^^^^^
  // Percent-encoding is added by default when converting to Foundation.
  // If we do it now, we know it will round-trip back to 'encodedWebURL'.

  guard let convertedURL = URL(encodedWebURL) else { throw InvalidURLError() }

  // Do some stuff with Foundation...
  let dataTask = URLSession.shared.dataTask(from: convertedURL)
  let urlFromDataTask = dataTask.originalRequest!.url!

  // ✅ A converted WebURL can always convert back. 
  let roundtripWebURL = WebURL(urlFromDataTask)!

  // ✅ The round-trip result is identical to 'encodedWebURL'. 
  assert(encodedWebURL == roundtripWebURL)
}
```

It is not generally possible to know in advance what the result of a `{Foundation -> WebURL -> Foundation}` round-trip
will be. There is no equivalent of `WebURL.encodedForFoundation` which normalizes a `Foundation.URL`.
