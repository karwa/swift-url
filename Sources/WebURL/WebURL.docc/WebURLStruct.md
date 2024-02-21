# ``WebURL/WebURL``

## Overview


Construct a `WebURL` from a URL string:

```swift
WebURL("https://github.com/karwa/swift-url")    // ✅ Typical HTTPS URL.
WebURL("file:///usr/bin/swift")                 // ✅ Typical file URL.
WebURL("my.app:/settings/language?debug=true")  // ✅ Typical custom URL.

WebURL("https://例子.cn/")!         // ✅ "https://xn--fsqu00a.cn/" (IDNA)
WebURL("https://😀.example.com/")  // ✅ "https://xn--e28h.example.com/" (IDNA)
```

WebURL conforms to the [latest URL Standard][URL-spec], which specifies how browsers and other actors
on the web platform interpret URLs. The parser is very forgiving, so it has great compatibility with
real-world URLs. It also supports a number of modern features, such as Unicode domain names (IDNA).

WebURL values are entirely defined by their string representation (their _serialization_); at any time,
you can convert a URL to a string and back (for example, encoding to JSON) and the result will be an identical URL.

To obtain a URL's serialization, call the ``serialized(excludingFragment:)`` function
or simply construct a `String`.

```swift
let url = WebURL("https://github.com/karwa/swift-url")!
url.serialized() // ✅ "https://github.com/karwa/swift-url"
String(url)      // Same as above.
```


### URL Components


URLs have structure - they can be split in to components such as a ``scheme``, ``hostname``, and ``path``.
The scheme identifies the kind of URL, and determines how the other components should be interpreted.

```
                  authority
          ┌───────────┴──────────────┐                  
  https://john.doe@www.example.com:123/forum/questions/?tag=networking&order=newest#top
  └─┬─┘   └──┬───┘ └──────┬──────┘ └┬┘└───────┬───────┘ └───────────┬─────────────┘ └┬┘
  scheme  username     hostname    port      path                 query           fragment
```
 
You can read and write a component's string value using its respective property.
The documentation page for each property contains more information about its URL component.

```swift
var url = WebURL("https://www.example.com/forum/questions/?tag=networking&order=newest")!
url.scheme   // "https"
url.hostname // "www.example.com"
url.path     // "/forum/questions/"
url.query    // "tag=networking&order=newest"

url.hostname = "github.com"
url.path     = "/karwa/swift-url/search"
url.query    = "q=struct"
String(url)  // ✅ "https://github.com/karwa/swift-url/search?q=struct"
             //     └─┬─┘   └───┬────┘└──────────┬──────────┘ └───┬──┘
             //     scheme   hostname           path            query     
```

Just as URLs have structure, some components can have their own internal structure -
such as path components (`"/forum/questions"`) and query parameters (`"tag=networking&order=newest"`).
WebURL also offers rich, expressive APIs for reading and modifying this substructure.

- ``host-swift.property`` explains how the standard interprets the URL's hostname.
  It communicates precisely which _kind_ of host is expressed by the URL,
  and includes network address values that can be used to directly establish a connection.

- ``pathComponents-swift.property`` is a `Collection` view, containing the segments in the URL's path.
  It includes APIs to add, remove, or replace any part of the path. _(Demonstrated below)_

- ``queryParams`` is also a `Collection` view, containing the list of key-value pairs in the URL's query.
  It includes APIs to work with pairs as a list, map, or multi-map. _(Demonstrated below. Requires Swift 5.7+)_


### Path Components and Query Parameters


``pathComponents-swift.property`` is a view of the URL's path segments as a `BidirectionalCollection`.
It has a comprehensive, familiar API - including `for` loops, slices, and generic algorithms such as
`starts(with:)` and `reduce()`. It transparently handles percent-encoding, so you can process paths naturally.

```swift
func resolveNotesURL(_ url: WebURL) -> Note? {
  // 🚩 Works well with familiar Collection APIs,
  //    such as slices, .first/.last, .starts(with:), etc.
  var remaining = url.pathComponents[...]
  switch remaining.popFirst() {
  case "note":
    return resolveNotePath(remaining) // ✅ remaining = ["416", "Grocery list"]
  case "collection":
    guard let collectionName = remaining.popFirst() else { return nil }
    return resolveCollection(collectionName)?.resolvePath(remaining)
  case "_debug" where remaining.first == "support_info":
    return generateSupportIDNote()  // ✅
  default:
    return nil
  }
}
resolveNotesURL(WebURL("my.notes:/note/416/Grocery%20list")!)
resolveNotesURL(WebURL("my.notes:/_debug/support_info")!)

func resolvePath(_ path: some Collection<String>) -> Node? {
  // 🚩 Algorithms such as 'reduce' can be very effective 
  //    at processing paths/slices.
  return try? path.reduce(Node.root) {
    node, childName in try node.getChild(childName)
  }
}
```

The path components view includes a full set of APIs for modifying the path, for instance:

- ``PathComponents-swift.struct/append(_:)`` and the `+=` operator,
- ``PathComponents-swift.struct/insert(_:at:)``, which is great for inserting prefixes,
- ``PathComponents-swift.struct/replaceSubrange(_:with:)`` for arbitrary replacements.   

These will be familiar to developers who have used the standard library's `RangeReplaceableCollection` protocol.
Together they offer a powerful set of tools, available at any time simply by accessing `.pathComponents`. 
By helping you better express your intent, it is also much easier to use them correctly.  

```swift
// 🚩 Consider how straightforward this code is.

let Endpoint = WebURL("https://api.myapp.com/v1")!

func URLForBand(_ bandName: String) -> WebURL {  
  var url = Endpoint
  url.pathComponents += ["music", "bands", bandName]
  url.queryParams["format"] = "json"
  return url
}

// 🚩 That was it.
//    And it handles all the encoding, etc., correctly.
//    It is very difficult (perhaps impossible?)
//    to replicate this using Foundation.URL.

URLForBand("Blur")
// ✅ "https://api.myapp.com/v1/music/bands/Blur?format=json"
//                              ^^^^^^^^^^^^^^^^
URLForBand("AC/DC")
// ✅ "https://api.myapp.com/v1/music/bands/AC%2FDC?format=json"
//                              ^^^^^^^^^^^^^^^^^^^
URLForBand("The Rolling Stones")
// ✅ "https://api.myapp.com/v1/music/bands/The%20Rolling%20Stones?format=json"
//                                          ^^^^^^^^^^^^^^^^^^^^^^
```

In the previous example, we used ``queryParams`` to add a key-value pair to the URL's query component.
`queryParams` is another write-through view, and allows us to easily read and write the URL's query parameters.

 ```swift
// 🚩 Use subscripts to get/set values associated with a key.

var url = WebURL("http://example.com/convert?from=EUR&to=USD")!

url.queryParams["from"] // ✅ "EUR"
url.queryParams["to"]   // ✅ "USD"

url.queryParams["from"] = "GBP"
// ✅ "http://example.com/convert?from=GBP&to=USD"
//                                ^^^^^^^^
url.queryParams["amount"] = "20"
// ✅ "http://example.com/convert?from=GBP&to=USD&amount=20"
//                                                ^^^^^^^^^

let (amount, from, to) = url.queryParams["amount", "from", "to"]
// ✅ ("20", "GBP", "USD")

// 🚩 Or build a query by appending key-value pairs.

var url = WebURL("http://example.com/convert")

url.queryParams += [
  ("amount", "200"),
  ("from", "EUR"),
  ("to", "GBP")
]
// ✅ "http://example.com/convert?amount=200&from=EUR&to=GBP"
//                                ^^^^^^^^^^^^^^^^^^^^^^^^^^
```


### Integration Libraries


To help you use WebURL in your projects _today_, the package includes a number of integration libraries
for popular first-party and third-party libraries.

- `WebURLSystemExtras` integrates with **swift-system** (and **System.framework** on Apple platforms) to offer
   conversions between `FilePath` and `WebURL`. It's the best way to work with file URLs.

- `WebURLFoundationExtras` integrates with **Foundation** so you can convert between `Foundation.URL` and `WebURL`,
   and use Foundation APIs such as `URLSession` with WebURL. We recommend reading <doc:FoundationInterop>
   for a discussion of how to safely work with multiple URL standards.

[URL-spec]: https://url.spec.whatwg.org/


## Topics


### URL Strings

- ``WebURL/init(_:)``
- ``WebURL/init(utf8:)``
- ``WebURL/init(filePath:format:)``
- ``serialized(excludingFragment:)``

### Relative References

- ``WebURL/resolve(_:)``

### URL Components

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

### Path Components

- ``pathComponents-swift.property``

### Query Parameters and Key-Value Pairs

- ``queryParams``
- ``keyValuePairs(in:schema:)``
- ``withMutableKeyValuePairs(in:schema:_:)``

### Host and Origin

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

### Other Views

- ``utf8``
- ``jsModel-swift.property``

### Binary File Paths

- ``fromBinaryFilePath(_:format:)``
- ``binaryFilePath(from:format:nullTerminated:)``
- ``FilePathFormat``
