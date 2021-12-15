# ``WebURL/WebURL``

## Overview


Construct a `WebURL` by initializing a value with a URL String:

```swift
WebURL("https://github.com/karwa/swift-url")    // ✅ Typical HTTPS URL.
WebURL("file:///usr/bin/swift")                 // ✅ Typical file URL.
WebURL("my.app:/settings/language?debug=true")  // ✅ Typical custom URL.
```

`WebURL` aligns with the [latest URL Standard][URL-spec], which which governs how browsers and other
actors on the web platform should interpret URLs. To demonstrate, the following example includes a number of
syntax mistakes: leading spaces, a mixed-case scheme and domain name, incorrect number of leading slashes,
as well as unescaped internal spaces and Unicode characters. These sorts of mistakes are relatively common
not only in user input, but also in network responses and databases. Browsers and JavaScript are able to
interpret these, and supporting them is important for true compatibility with the web.

An important feature of the standard is that URLs are always normalized, so when constructing a `WebURL`,
the URL is automatically cleaned up and made easier for other systems and libraries to work with.
To see this in action, let's obtain the URL's string representation by calling the ``serialized(excludingFragment:)``
function.

```swift
let url = WebURL("  HTtpS:///MYAPP.COM/sendMessage?I saw a 🦆!")!
url.serialized() // ✅ "https://myapp.com/sendMessage?I%20saw%20a%20%F0%9F%A6%86!"
String(url)      // Same as above.
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

WebURL is always normalized, so modified components will be normalized automatically.

```swift
var url  = WebURL("https://github.com/")!
url.path = "/apple/swift/pulls/../../swift-package-manager"
String(url)  // ✅ "https://github.com/apple/swift-package-manager"
```

Whilst it may be familiar to work with URL components as strings, they do not fully capture everything that `WebURL`
knows about a particular component, and require navigating percent-encoding, which can be difficult. 
For some components which have additional formal/informal meaning, WebURL offers richer APIs which
are both more precise and more convenient than operating on string values directly:

- The ``host-swift.property`` property returns the URL's hostname as an enum.
  This allows request libraries to understand hostnames as the URL parser does, and to directly establish
  a network connection.

- The ``pathComponents-swift.property`` property returns a `Collection` view of a URL's path,
  and can even be used to add and remove path components. _(Demonstrated below)_

- The ``formParams`` property returns a view of a URL's query as a sequence of form-encoded key-value pairs,
  and offers dynamic properties to read and write query parameters. _(Demonstrated below)_


### Path Components and Query Parameters


The ``pathComponents-swift.property`` property is a mutable wrapper which provides a URL's path components
as a standard Swift `BidirectionalCollection`. It supports for-loops, slicing, map/reduce/filter and more,
but also adds methods like ``PathComponents-swift.struct/append(_:)``, ``PathComponents-swift.struct/insert(_:at:)``,
``PathComponents-swift.struct/removeLast(_:)``, which efficiently modify the URL in-place.

 ```swift
let url = WebURL("https://github.com/karwa/swift-url/issues/63")!
for component in url.pathComponents {
   // "karwa", "swift-url", "issues", "63"
}
if url.pathComponents.dropLast().last == "issues",
   let issueNumber = url.pathComponents.last.flatMap(Int.init) {
  // issueNumber: Int = 63
}

var url = WebURL("https://info.myapp.com")!
url.pathComponents += ["music", "bands" "AC/DC"]
// ✅ "https://info.myapp.com/music/bands/AC%2FDC"
//                           ^^^^^^^^^^^^^^^^^^^^
url.pathComponents.removeLast()
url.pathComponents.append("The Rolling Stones")
// ✅ "https://info.myapp.com/music/bands/The%20%Rolling%20Stones"
//                                        ^^^^^^^^^^^^^^^^^^^^^^^
```

The ``formParams`` property offers a similar interface for query parameters using form-encoding.
You can read and write the value for a key using the ``FormEncodedQueryParameters/get(_:)`` and 
``FormEncodedQueryParameters/set(_:to:)`` methods, or use Swift's dynamic-member syntax to access them
as properties.

 ```swift
let url = WebURL("https://example.com/search?category=food&sub=italian&client=mobile")!
url.formParams.category  // "food"
url.formParams.sub       // "italian"
url.formParams.client    // "mobile"

var url = WebURL("https://example.com/search")!
url.formParams += [
  "category" : "sports",
       "sub" : "cycling",
    "client" : "mobile"
]
// ✅ "https://example.com/search?category=sports&client=mobile&sub=cycling"
//                               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
url.formParams.format = "json"
// ✅ "https://example.com/search?category[...]&format=json"
//                                             ^^^^^^^^^^^^
```


### Integration Libraries


In addition to all of the above, WebURL offers integration libraries so it may be used with popular first-party and
third-party libraries.

- `WebURLSystemExtras` integrates with **swift-system** (and **System.framework** on Apple platforms) to offer
   conversion between `System.FilePath` and `WebURL`. It's the best way to work with file URLs.

- `WebURLFoundationExtras` integrates with **Foundation** to offer conversions between `Foundation.URL` and `WebURL`.
  This conversion is safe, but does not round-trip because it may add percent-encoding.
  We're investigating ways to improve that.

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

