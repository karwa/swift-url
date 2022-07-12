# ``WebURL/WebURL``

## Overview


Construct a `WebURL` by initializing a value with a URL string:

```swift
WebURL("https://github.com/karwa/swift-url")    // ✅ Typical HTTPS URL.
WebURL("file:///usr/bin/swift")                 // ✅ Typical file URL.
WebURL("my.app:/settings/language?debug=true")  // ✅ Typical custom URL.
```

`WebURL` aligns with the [latest URL Standard][URL-spec], which governs how browsers and other actors
on the web platform should interpret URL strings. It is as lenient as a browser, and includes a number
of compatibility behaviors necessary for accurate URL processing on the web.

To obtain a `WebURL`'s string representation, call the ``serialized(excludingFragment:)`` function,
or simply construct a `String`:

```swift
let url = WebURL("https://github.com/karwa/swift-url")!
url.serialized() // ✅ "https://github.com/karwa/swift-url"
String(url)      // Same as above.
```

`WebURL`s are always normalized, so once a value has been parsed, any compatibility behaviors are "cleaned up" and
the URL can be more easily interpreted - both by your code, and by other systems. Consider the following,
ill-formatted URL string - it has an uppercase domain-name, a path containing `".."` components, and special characters
(including Unicode) which are not properly percent-encoded. `WebURL` can parse this string successfully,
and when we ask for its string representation or any of its components, we get values that are clear 
and easy to work with. 

```swift
let url = WebURL("https://MYAPP.COM/foo/../sendMessage?I saw a 🦆!")!
url.serialized() // ✅ "https://myapp.com/sendMessage?I%20saw%20a%20%F0%9F%A6%86!"

if url.hostname == "myapp.com", url.path == "/sendMessage" {
  url.query?.percentDecoded()  // ✅ "I saw a 🦆!"
}
```


### Accessing URL Components


URLs are made up of a series of components, such as their ``scheme``, ``hostname``, and ``path``.
You can read and write a URL component's string value using its respective property.

```swift
var url = WebURL("https://github.com/karwa/swift-url")!
url.scheme   // "https"
url.hostname // "github.com"
url.path     // "/karwa/swift-url"

url.path  = "/karwa/swift-url/search"
url.query = "q=struct"
String(url)  // ✅ "https://github.com/karwa/swift-url/search?q=struct"
```

Modified components are normalized automatically.

```swift
var url  = WebURL("https://github.com/")!
url.path = "/apple/swift/pulls/../../swift-package-manager"
String(url)  // ✅ "https://github.com/apple/swift-package-manager"
```

Although it may be familiar to work with URL components as strings, `WebURL` also offers richer APIs when
it knows more about how a component should be interpreted. These APIs are more convenient, expressive, and
more efficient than operating on string-typed components:

- The ``host-swift.property`` property returns the URL's hostname as an enum.
  This allows request libraries to understand which _kind of host_ is expressed by the URL,
  and provides a value which can be used to directly establish a network connection.

- The ``pathComponents-swift.property`` property returns a `Collection` view of a URL's path,
  and can even be used to add and remove path components at arbitrary locations. _(Demonstrated below)_

- The ``formParams`` property returns a view of a URL's query which supports reading and writing key-value pairs,
  accessed via a convenient dynamic property API. _(Demonstrated below)_


### Path Components and Query Parameters


The ``pathComponents-swift.property`` property is a mutable view of a URL's path components as a standard Swift
`BidirectionalCollection`, allowing you to easily process a URL's path using `for` loops, slices, map/reduce/filter,
and other generic algorithms all tuned for maximum performance.

 ```swift
let url = WebURL("https://github.com/karwa/swift-url/issues/63")!
for component in url.pathComponents {
   // ✅ component = "karwa", "swift-url", "issues", "63"
}

if url.pathComponents.dropLast().last == "issues",
   let issueNumber = url.pathComponents.last.flatMap(Int.init) {
  // ✅ issueNumber = 63
}
```

It also includes methods such as ``PathComponents-swift.struct/append(_:)`` (and the `+=` operator),
``PathComponents-swift.struct/insert(_:at:)``, and ``PathComponents-swift.struct/removeLast(_:)``,
which can be used for complex path manipulation while efficiently modifying the URL in-place.

```swift
var url = WebURL("https://info.myapp.com")!
url.pathComponents += ["music", "bands" "AC/DC"]
// ✅ "https://info.myapp.com/music/bands/AC%2FDC"
//                           ^^^^^^^^^^^^^^^^^^^^

url.pathComponents.removeLast()
url.pathComponents.append("The Rolling Stones")
// ✅ "https://info.myapp.com/music/bands/The%20%Rolling%20Stones"
//                                        ^^^^^^^^^^^^^^^^^^^^^^^
```

The ``formParams`` property is a mutable view of a URL's query parameters (using HTML form-encoding).
You can read and write the value for a key using the ``FormEncodedQueryParameters/get(_:)`` and 
``FormEncodedQueryParameters/set(_:to:)`` methods, or use Swift's dynamic-member feature to access keys
as though they were properties on the view.

 ```swift
let url = WebURL("https://example.com/search?category=food&client=mobile")!
url.formParams.category  // "food"
url.formParams.client    // "mobile"

var url = WebURL("https://example.com/search")!
url.formParams += [
  "category" : "sports",
    "client" : "mobile"
]
// '+=' appends a Dictionary of key-value pairs:
// ✅ "https://example.com/search?category=sports&client=mobile"
//                               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
url.formParams.format = "json"
// ✅ "https://example.com/search?category[...]&format=json"
//                                             ^^^^^^^^^^^^
```


### Integration Libraries


The WebURL package includes a number of integration libraries for popular first-party and third-party libraries.

- `WebURLSystemExtras` integrates with **swift-system** (and **System.framework** on Apple platforms) to offer
   conversions between `FilePath` and `WebURL`. It's the best way to work with file URLs.

- `WebURLFoundationExtras` integrates with **Foundation** to offer conversions between `Foundation.URL` and `WebURL`,
   as well as convenient interfaces for APIs such as `URLRequest` and `URLSession`. We **highly recommend** reading
   <doc:FoundationInterop> for a discussion of how to safely work with multiple URL standards.

[URL-spec]: https://url.spec.whatwg.org/


## Topics


### Creating a URL from a String

- ``WebURL/init(_:)``
- ``WebURL/init(utf8:)``
- ``WebURL/init(filePath:format:)``

### Obtaining a URL's String Representation

- ``serialized(excludingFragment:)``

### Resolving Relative References

- ``WebURL/resolve(_:)``

### Reading and Writing a URL's Components

- ``scheme``
- ``username``
- ``password``
- ``hostname``
- ``port``
- ``portOrKnownDefault``
- ``path``
- ``query``
- ``fragment``
- ``hasOpaquePath``

### Reading, Removing, and Appending Path Components

- ``pathComponents-swift.property``

### Reading and Modifying Query Parameters

- ``formParams``

### Network Hosts and Origins

- ``Host-swift.enum``
- ``host-swift.property``
- ``origin-swift.property``

### Responding to Setter Failures

- ``setScheme(_:)``
- ``setUsername(_:)``
- ``setPassword(_:)``
- ``setHostname(_:)``
- ``setPort(_:)``
- ``setPath(_:)``
- ``setQuery(_:)``
- ``setFragment(_:)``

### Special Interfaces

- ``utf8``
- ``jsModel-swift.property``

### Converting To and From Binary File Paths

- ``fromBinaryFilePath(_:format:)``
- ``binaryFilePath(from:format:nullTerminated:)``
- ``FilePathFormat``

