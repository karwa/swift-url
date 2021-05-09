# WebURL Quickstart Guide

WebURL is a new URL type for Swift which is compatible with the WHATWG's URL Living Standard.
To get started using WebURL, first add the package as a dependency (see the README for more information).

Next, import the `WebURL` package:

```swift
import WebURL
```

To parse a URL from a `String`, use the initializer:

```swift
let url = WebURL("https://github.com/karwa/swift-url/")!
```

Note that this initializer expects an _absolute_ URL string - i.e. something which begins with a scheme (`"http:"`, `"file:"`, `"myapp:"`, etc).

`WebURL` objects conform to many protocols from the standard library you may be familiar with:
 - `Equatable` and `Hashable`, so they may be used as keys in a `Dictionary` or as members of a `Set`,
 - `Comparable`, so they may be sorted,
 - `Codable`, so they may be serialized/deserialized from JSON or other formats, and
 - `LosslessStringConvertible`, as `WebURL` abides by the URL Standard's requirement that
    converting a URL to/from a `String` must never change how the URL is interpreted.

## Basic Components

Once you have constructed a `WebURL` object, you can inspect its components, such as its `scheme`, `hostname` or `path`. Additionally, the entire URL string (its "serialization") is available via the `serialized` property:

```swift
url.scheme // "https"
url.hostname // "github.com"
url.path // "/karwa/swift-url/"

url.serialized // "https://github.com/karwa/swift-url/"
```

Components are returned as they appear in the URL string, including any percent-encoding. The `WebURL` package includes a number of extensions to standard library types and protocols,
to help you add and remove percent-encoding from strings. To remove percent-encoding, use the `percentDecoded` property, which is made available to all `String`s:

```swift
let url = WebURL("https://github.com/karwa/swift%2Durl/")!
url.path // "/karwa/swift%2Durl/"
url.path.percentDecoded // "/karwa/swift-url/"
```

## Relative URLs

You can also create a URL by resolving a string relative to an existing, absolute URL (the "base URL").
The result of this is another absolute URL, pointing to the same location as an HTML `<a>` tag on the base URL's page:

```swift
let base = WebURL("https://github.com/karwa/swift-url/")!

base.resolve("pulls/39")! // "https://github.com/karwa/swift-url/pulls/39"
base.resolve("/apple/swift/")! // "https://github.com/apple/swift/"
base.resolve("..?tab=repositories")! // "https://github.com/karwa/?tab=repositories"
base.resolve("https://swift.org/")! // "https://swift.org"
```

This is not limited to http(s) URLs; it works for every URL, including "file" URLs:

```swift
let appData = WebURL("file:///tmp/")!.resolve("my_app/data/")!
// appData = "file:///tmp/my_app/data/"
let mapFile = appData.resolve("../other_data/map.json")!
// mapFile = "file:///tmp/my_app/other_data/map.json"
```

## Modifying URLs

`WebURL` does not need an intermediate type like `URLComponents`. Instead, components may be set directly.

Modifications are efficient, and occur in-place on the URL's existing storage object as capacity and value semantics allow.

```swift
var url = WebURL("http://github.com/karwa/swift-url/")!

// Upgrade to https:
url.scheme = "https"
url.serialized // "https://github.com/karwa/swift-url/"

// Change the path:
url.path = "/apple/swift/"
url.serialized // "https://github.com/apple/swift/"
```

When you modify a component, the value you set will automatically be percent-encoded if it contains any illegal characters.
This applies to the `username`, `password`, `path`, `query`, and `fragment` fields.
Notably, it does not apply to the `scheme` or `hostname` - attempting to set an invalid `scheme` or `hostname` will fail.

```swift
var url = WebURL("https://example.com/my_files/secrets.txt")!

url.username = "my username"
url.password = "🤫"
url.serialized // "https://my%20username:%F0%9F%A4%AB@example.com/my_files/secrets.txt"

url.hostname = "👾" // Fails, does not modify.
url.serialized // (unchanged)
```

In general, the setters are very permissive. However, if you do wish to detect and respond to failures to modify a component,
use the corresponding throwing setter method instead. The thrown `Error`s contain specific information about why the operation failed,
so it's easier for you to debug logic errors in your application.

## Path Components

You can access a URL's path components through the `pathComponents` property.
This returns an object which conforms to Swift's `Collection` protocol, so you can use it in `for` loops and
lots of other code directly, yet it efficiently shares storage with the URL it came from.

The components returned by this view are automatically percent-decoded from their representation in the URL string.

```swift
let url = WebURL("file:///Users/karl/My%20Files/data.txt")!

for component in url.pathComponents {
  ... // component = "Users", "karl", "My Files", "data.txt".
}

if url.pathComponents.last!.hasSuffix(".txt") {
  ...
}
```

Additionally, this view allows you to _modify_ a URL's path components.
Any inserted components will be automatically percent-encoded in the URL string.

```swift
var url = WebURL("file:///swift-url/Sources/WebURL/WebURL.swift")!

url.pathComponents.removeLast() 
// url = "file:///swift-url/Sources/WebURL"
  
url.pathComponents.append("My Folder")
// url = "file:///swift-url/Sources/WebURL/My%20Folder"

url.pathComponents.removeLast(3)

url.pathComponents += ["Tests", "WebURLTests", "WebURLTests.swift"]
// url = "file:///swift-url/Tests/WebURLTests/WebURLTests.swift"
```

Paths which end in a "/" (also called "directory paths"), are represented by an empty component at the end of the path.
However, if you append to a directory path, `WebURL` will automatically remove that empty component for you.
If you need to create a directory path, append an empty component, or use the `ensureDirectoryPath()` method.

```swift
var url = WebURL("https://api.example.com/v1/")!

for component in url.pathComponents {
  ... // component = "v1", "".
}

url.pathComponents += ["users", "karl"]
// url = "https://api.example.com/v1/users/karl"
// components = "v1", "users", "karl".

url.pathComponents.ensureDirectoryPath()
// url = "https://api.example.com/v1/users/karl/"
// components = "v1", "users", "karl", "".
```

## Form-Encoded Query Items

You can also access the key-value pairs in a URL's query string using the `formParams` property.
As with `pathComponents`, this returns an object which shares storage with the URL it came from.

You can use Swift's "dynamic member" feature to access query parameters as though they were properties.
For example, in the query string `"from=EUR&to=USD"`, accessing `url.formParams.from` will return `"EUR"`.
For parameters whose names cannot be used in Swift identifiers, the `get` method will also return the corresponding value for a key.

Additionally, all of the query's key-value pairs are available as a Swift `Sequence` via the `allKeyValuePairs` property.

This view assumes that the query string's contents are encoded using `application/x-www-form-urlencoded` ("form encoding"),
and all of the keys and values returned by this view are automatically decoded from form-encoding.

```swift
let url = WebURL("https://example.com/currency/convert?amount=20&from=EUR&to=USD")!

url.formParams.amount // "20"
url.formParams.from // "EUR"
url.formParams.get("to") // "USD"

for (key, value) in url.formParams.allKeyValuePairs {
  ... // ("amount", "20"), ("from", "EUR"), ("to", "USD").
}
```

And again, as with `pathComponent`, you can modify a URL's query string using `formParams`.
To set a parameter, assign a new value to its property or use the `set` method. Setting a key to `nil` will remove it from the query.

Also, any modification will re-encode the entire query string so that it is consistently encoded as `application/x-www-form-urlencoded`,
if it is not already.

```swift
var url = WebURL("https://example.com/currency/convert?amount=20&from=EUR&to=USD")!

url.formParams.amount // "20"
url.formParams.to // "USD

url.formParams.amount = "56"
url.formParams.to = "Pound Sterling"
// url = "https://example.com/currency/convert?amount=56&from=EUR&to=Pound+Sterling"

url.formParams.format = "json"
// url = "https://example.com/currency/convert?amount=56&from=EUR&to=Pound+Sterling&format=json"
```

## Further Reading

And that's your overview! We've covered creating, reading, and manipulating URLs using `WebURL`. Hopefully you agree that it makes
great use of the expressivity of Swift, and are excited to `WebURL` for:

- URLs based on the latest industry standard. 
- Better-defined behaviour, and better alignment with how modern web browsers behave.
- Speed and memory efficiency, as well as
- APIs designed for Swift

There's even more that we didn't cover, like `Host` objects, IP Addresses, _lazy_ percent encoding/decoding, `Origin`s, the `JSModel`,
or our super-powered `UTF8View`. If you'd like to continue reading about the APIs available in the `WebURL` package,
see the [official documentation](https://karwa.github.io/swift-url/), or just go try it out for yourself!