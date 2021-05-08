# WebURL

This package contains a new URL type for Swift, written in Swift. 

- The [Getting Started](GettingStarted.md) guide contains an overview of how to use the `WebURL` type.
- The [Full documentation](https://karwa.github.io/swift-url/) contains a detailed information about at the API.

You may be interested in:

- This prototype port of [async-http-client](https://github.com/karwa/async-http-client), which allows you to perform http(s)
  requests using `WebURL`, and shows how easy it can be to adopt in your library.

This URL type is compatible with the [URL Living Standard](https://url.spec.whatwg.org/) developed by the WHATWG, meaning it more closely
matches how modern web browsers behave. It has a fast and efficient implementation, and an API designed to meet the needs of Swift developers.

## Using WebURL in your project

To use `WebURL` in a SwiftPM project, add the following line to the dependencies in your Package.swift file:

```swift
.package(url: "https://github.com/karwa/swift-url", from: "0.0.1"),
```

## Project Goals

<details><summary><b>1. For parsing to match the URL Living Standard.</b></summary>
  <br/>

  The URL parser included in this project is derived from the reference parser implementation described by the standard, and should
  be fully compatible with it. The programmatic API for reading and manipulating URL components (via the `WebURL` type) may contain
  minor deviations from the JavaScript API defined in the standard in order to suit the expectations of Swift developers,
  (e.g. the `query` property does not contain the leading "?" as it does in JavaScript, setters are stricter about invalid inputs, etc).
  The full JavaScript API is available via the `JSModel` type, which is implemented entirely in terms of the Swift API.

  The list of differences between the `WebURL` API and the JavaScript `URL` class are documented [here](https://karwa.github.io/swift-url/WebURL_JSModel/).
  
  Conformance to the standard is tested via the common [Web Platform Tests](https://github.com/web-platform-tests/wpt/tree/master/url)
  used by browser developers to validate their implementations. Currently this consists of close to 600 parser tests, and about 200 tests
  for setting individual properties. The project also contains additional test databases which are validated against the JSDOM reference 
  implementation, with the intention to upstream them in the future.
  
  Conformance to a modern URL standard is the "killer feature" of this project, and other than the documented differences in APIs,
  any mismatch between this parser and the standard is, categorically, a bug (please report them if you see them!). Foundation's `URL` type
  conforms to RFC-1738, from 1994, and `URLComponents` conforms to a different standard, RFC-3986 from 2005. The 1994 standard contains many issues
  which subsequent standards have defined or fixed; this project allows Swift to match the behaviour of modern web browsers.
</details>

<details><summary><b>2. To be safe, fast, and memory-efficient.</b></summary>
  <br/>

  Swift is designed to be a safe language, free of undefined behaviour and memory-safety issues. The APIs exposed by this library use
  a combination of static and runtime checks to ensure memory-safety, and use of unsafe pointers internally is kept to a minimum.

  Performance is also very important to this project, but communicating comparisons is tricky. The obvious comparison would be against our existing
  URL type, `Foundation.URL`; but as mentioned above, it conforms to an entirely different standard. The new standard's parser is very permissive
  and components are normalized and percent-encoded during parsing in order to cast as wide a compatibility net as possible and harmonize their representation.
  So it some sense comparing `WebURL` and `Foundation.URL` is apples-to-oranges, but it can be argued that parsing time is an important metric for developers,
  regardless.
  
  Despite the extra processing, the "AverageURLs" benchmark in this repository demonstrates performance that is slightly faster than Foundation,
  on an Intel Mac (Ivy Bridge). Depending on their size and structure, improvements for other URLs can range from 15% (IPv6 addresses) 
  to 66% (very long query strings), while using less memory. Additionally, common operations such as hashing and testing for equality can be more
  than twice as fast as `Foundation.URL`. We'll also be exploring some ideas which could further increase parsing performance.
  
  On lower-end systems, such as a Raspberry Pi 4 8GB running 64-bit Ubuntu and the [swift-arm64 community toolchain (5.4)](https://github.com/futurejones/swift-arm64),
  the same benchmarks can demonstrate even greater improvements; "AverageURLs" going from about 1.85s using Foundation, to only 62.67ms with `WebURL`.

  As with all benchmark numbers, YMMV.
 
  Additionally:
 
  - The API supports efficient in-place mutation, so `URLComponents` is no longer needed in order to modify a component's value.
  - The API offers views of the URL's path components and query parameters which share the URL's storage, allowing fast and efficient iteration
    and inspection.
  - These views _also_ support in-place mutation, so when appending a path-component or setting a query parameter,
    the operation should be as fast, if not faster, than the equivalent string manipulation.
  
  _(Note that benchmarking and optimizing the setters is still a work-in-progress.)_
</details>

<details><summary><b>3. To leverage Swift's language features in order to provide a clean, convenient, and powerful API.</b></summary>
  <br/>

  This library makes extensive use of generics; almost every API which accepts a `String`, from the parser to the component setters,
  also have variants which accept user-defined `Collection`s of UTF-8 code-units. This can be valuable in performance-sensitive scenarios,
  such as when parsing large numbers of URLs from data files or network packets.
  
  It also makes extensive use of wrappers which share a URL's storage, for example to provide a `Collection` interface to a URL's path components.
  These wrappers also showcase the power of `_modify` accessors, allowing for a clean API with namespaced operations, which retain the ability to modify
  a URL in-place:
  
  ```swift
  var url = WebURL("file:///usr/foo")!
  url.pathComponents.removeLast()
  url.pathComponents += ["lib", "swift"]
  print(url) // file:///usr/lib/swift
  ```
  
  The view of a URL's form-encoded query parameters also supports `@dynamicMemberLookup` for concise get- and set- operations:
  
  ```swift
  var url = WebURL("http://example.com/currency/convert?amount=20&from=EUR&to=USD")!
  print(url.formParams.amount) // "20"
  url.formParams.to = "GBP"
  print(url) // http://example.com/currency/convert?amount=20&from=EUR&to=GBP
  ```
 
  Setters that can fail also have throwing sister methods, which provide rich error information about why a particular operation did not succeed.
  These error descriptions do not capture any part of the URL, so they do not contain any privacy-sensitive data.

  Take a look at the [Getting Started](GettingStarted.md) guide for a tour of this package's core API.
</details>
<br/>

## Roadmap

The implementation is extensively tested, but the interfaces have not had time to stabilise.

While the package is in its pre-1.0 state, it may be necessary to make source-breaking changes. 
I'll do my best to keep these to a minimum, and any such changes will be accompanied by clear documentation explaining how to update your code.

I'd love to see this library adopted by as many libraries and applications as possible, so if there's anything I can add to make that easier,
please file a GitHub issue or write a post on the Swift forums.

Aside from stabilising the API, the other priorities for v1.0 are:

1. file URL <-> file path conversion

   Having a port of `async-http-client` is a good start for handling http(s) requests, but file URLs also require attention.

   It would be great to add a way to create a file path from a file URL and vice-versa. This should be relatively straightforward;
   we can look to cross-platform browsers for a good idea of how to handle this. Windows is the trickiest case (UNC paths, etc),
   but since Microsoft Edge is now using Chromium, we can look to [their implementation](https://chromium.googlesource.com/chromium/src/net/+/master/base/filename_util.cc)
   for guidance. It's also worth checking to see if WebKit or Firefox do anything different.

2. Converting to/from `Foundation.URL`.

   This is a delicate area and needs careful consideration of the use-cases we need to support. Broadly speaking, there are 2 ways to approach it:

   - Re-parsing the URL string.

     This is what [WebKit does](https://github.com/WebKit/WebKit/blob/99f5741f2fe785981f20fb1fee5869a2863d16d6/Source/WTF/wtf/cocoa/URLCocoa.mm#L79).
     The benefit is that it is straightforward to implement. The drawbacks are that Foundation refuses to accept a lot of URLs which the modern standards consider valid,
     so support could be limited. In at least one case that I know of, differences between the parsers have lead to exploitable security vulnerabilities
     (when conversion changes the URL's origin, which is why WebKit's conversion routine now includes a specific same-origin check).

     Something like this, with appropriate checks on the re-parsed result, may be acceptable as an MVP, but ideally we'd want something more robust with better support
     for non-http(s) URLs in non-browser contexts.

   - Re-writing the URL string based on `Foundation.URL`'s _components_.

     This should ensure that the resulting URL contains semantically equivalent values for its username, password, hostname, path, query, etc., with the conversion
     procedure adding percent-encoding as necessary to smooth over differences in allowed characters (e.g. Foundation appears to refuse "{" or "}" in hostnames or 
     query strings, while newer standards allow them, so we'd need to percent-encode those). 
     
     The `WebURL` parser has been designed with half an eye on this; in theory we should be able to construct a `ScannedRangesAndFlags` over Foundation's URL string,
     using the range information from Foundation's parser, and `URLWriter` will take care of percent-encoding the components, simplifying the path, and assembling the
     components in to a URL string. That said, URLs are rarely so simple, and this process will need a _very thorough_ examination and database of tests.

   Even after this is done, my intuition is that it would be unwise for developers to assume seamless conversions between `Foundation.URL` and `WebURL`.
   It should be okay to do it once at an API boundary - e.g. for an HTTP library built using `WebURL` to accept requests using `Foundation.URL` -
   but such libraries should convert to one URL type as soon as possible, and use that single type to provide all information used to make the request.
  
   As an example of the issues that may arise: if the conversion process adds percent-encoding, performing multiple conversions such as `WebURL -> URL -> WebURL`,
   or `URL -> WebURL -> URL`, will result in an object with the same type, but a different URL string (including a different hash value, and comparing as `!=` to the starting URL).
   That would be a problem for developers who expect a response's `.url` property to be the same as the URL they made the request with. That's why it's better to stick to
   a single type conversion; when a developer sees that the response's `.url` property has a different type, there is more of a signal that the content may have changed slightly.

3. Benchmarking and optimizing setters, including modifications via `pathComponents` and `formParams` views.

Post-1.0:
  
4. Non-form-encoded query parameters.

   Like the `formParams` view, this would interpret the `query` string as a string of key-value pairs, but _without_ assuming that the query should be form-encoded.
   Such an API [was pitched](https://github.com/whatwg/url/issues/491) for inclusion in the URL standard, but is not included since the key-value pair format was
   only ever codified by the form-encoding standard; its use for non-form-encoded content is just a popular convention.

   That said, it would likely be valuable to add library-level support to make this convention easier to work with.
  
5. Relative URLs.

   Have repeatedly [been pitched](https://github.com/whatwg/url/issues/531) for inclusion in the standard. Support can be emulated to some extent by
   using the `thismessage:` scheme reserved by IANA for this purpose, but it is still a little cumbersome, and is common enough outside of browser contexts to
   warrant its own type and independent test-suite. Implementation may be as simple as wrapping a `WebURL` with the `thismessage:` scheme, or as complex as the 
   Saturn V rocket; it is really quite hard to tell, because URLs.
  
6. IDNA

   By far the biggest thing. See the FAQ for details.

## Sponsorship

I'm creating this library because I think that Swift is a great language, and it deserves a high-quality, modern library for handling URLs.
It has taken a lot of time to get things to this stage, and there is an exciting roadmap ahead.

It demands a lot of careful study, a lot of patience, and a lot of motivation to bring something like this together. So if you
(or the company you work for) benefit from this project, do consider donating to show your support and encourage future development.
Maybe it saves you some time on your server instances, or saves you time chasing down weird bugs in your URL code.

In any case, thank you for stopping by and checking it out.

## FAQ

### What is the WHATWG URL Living Standard?

It may be surprising to learn that there isn't a single way to interpret URLs. There have been several attempts to create such a thing,
beginning with the IETF documents [RFC-1738](https://www.ietf.org/rfc/rfc1738.txt) in 1994, and the revised version
[RFC-3986](https://www.ietf.org/rfc/rfc3986.txt) in 2005.

Unfortunately, it's rare to find an application or URL library which completely abides by those specifications, and the specifications
themselves contain ambiguitites which lead to divergent behaviour across implementations. Some of these issues were summarised
in a draft [working document](https://tools.ietf.org/html/draft-ruby-url-problem-01) by Sam Ruby and Larry Masinter. As the web 
continued to develop, the WHATWG and W3C required a new definition of "URL" which matched how browsers _actually_ behaved.
That effort eventually became the WHATWG's URL Living Standard. 

The WHATWG is an industry association led by the major browser developers (currently, the steering committee consists of 
representatives from Apple, Google, Mozilla, and Microsoft), and there is high-level approval for their browsers to align with the 
standards developed by that group. The standards developed by the WHATWG are "living standards":

> Despite the continuous maintenance, or maybe we should say as part of the continuing maintenance, a significant effort is placed on
getting the standard and the implementations to converge — the parts of the standard that are mature and stable are not changed 
willy nilly. Maintenance means that the days where the standard are brought down from the mountain and remain forever locked,
even if it turns out that all the browsers do something else, or even if it turns out that the standard left some detail out and the browsers
all disagree on how to implement it, are gone. Instead, we now make sure to update the standard to be detailed enough that all the
implementations (not just browsers, of course) can do the same thing. Instead of ignoring what the browsers do, we fix the standard
to match what the browsers do. Instead of leaving the standard ambiguous, we fix the the standard to define how things work.

From [WHATWG.org FAQ: What does "Living Standard" mean?](https://whatwg.org/faq#living-standard)

While the WHATWG has [encountered criticism](https://daniel.haxx.se/blog/2016/05/11/my-url-isnt-your-url/) for being overly concerned with
browsers over all other users of URLs (a criticism which, to be fair, is not _entirely_ without merit), I've personally found the process to
be remarkably open, with development occurring in the open on GitHub, and the opportunity for anybody to file issues or submit improvements via pull-requests.
While their immediate priority is, of course, to unify browser behaviour, it's still the industry's best starting point to fix the issues
previous standards have faced and develop a modern interpretation of URLs. Not only that, but it seems to me that any future URL standards will have to
consider consistency with web browsers to have any realistic chance of describing how other applications should interpret them.

### Does this library support IDNA?

Not yet.
It is important to note that IDNA is _not (just) Punycode_ (a lot of people seem to mistake the two).

Actually supporting IDNA involves 2 main steps (well, actually more, but for this discussion we can pretend it's only 2):

1. Unicode normalization

  IDNA also requires a unique flavour of unicode normalization and case-folding, [defined by the Unicode Consortium](https://unicode.org/reports/tr46/).
  Part of this is just NFC normalization, but there are additional, domain-specific mapping tables as well (literally, specific to networking domains).
  The latest version of that mapping table can be found [here](https://www.unicode.org/Public/idna/latest/IdnaMappingTable.txt).
  
2. Punycode

  It is the result of this normalization procedure which is encoded to ASCII via Punycode. In this respect, Punycode acts just like percent-encoding:
  it takes a Unicode string in, and outputs an ASCII string which can be used to recover the original content.

  Why not just use percent-encoding? Because percent-encoding is seriously inefficient; it turns every non-ASCII byte from the input in to 3 bytes from the output.
  DNS imposes limits on the maximum length of domain names (253 bytes total, 63 bytes per label), so a more space-efficient encoding was needed.
  Only the hostname uses IDNA, because it is the only part affected by this DNS restriction.

That Unicode normalization step is really crucial - unforuntately, Swift's standard library doesn't expose its Unicode algorithms or data tables at the moment,
meaning the only viable way to implement this would be to ship our own copy of ICU or introduce a platform dependency on the system's version of ICU.

As it stands, this URL library doesn't contain _any_ direct dependencies on system libraries, and I would dearly like to keep it that way. At the same time, it has
long been recognised that the Swift standard library needs to provide access to these algorithms. So once this project has settled down a bit, my plan is to turn my attention
towards the Swift standard library - at least to implement NFC and case-folding, and possibly even to expose IDNA as a standard-library feature, if the core team are amenable to that.
I suspect that will largely be influenced by how well we can ensure that code which doesn't use IDNA doesn't pay the cost of loading those data tables. We'll see how it goes.

For the time being, we detect non-ASCII and Punycode domains, and the parser fails if it encounters them. 
Of those ~600 URL constructor tests in the WPT repository, we only fail 10, and all of them are because we refused to parse an address that would have required IDNA.

We will support it eventually, but it's just not practical at this very moment.
