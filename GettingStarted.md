# WebURL Quickstart Guide

WebURL is a new URL type for Swift which is compatible with the latest standard.
Creating a WebURL from a URL string is straightforward:

```swift
import WebURL

var url = WebURL("http://github.com/karwa/swift-url")!
```

Once you have constructed a URL object, you can inspect its properties:

```swift
url.scheme // "http"
url.hostname // "github.com"
url.path // "/karwa/swift-url"
url.query // nil
url.fragment // nil
```

The entire URL string is available via the `.serialized` property:

```swift
url.serialized // "http://github.com/karwa/swift-url"
```

WebURL allows its properties to be changed in-place. Let's upgrade our URL to use the https protocol:

```swift
url.scheme = "https"
url.serialized // "https://github.com/karwa/swift-url"
```

_be warned_: not all changes are possible for all URLs. Property setters may fail if the operation is not supported:

```swift
url.scheme = "foo"
url.serialized // "https://github.com/karwa/swift-url"
```

WebURL also provides setter methods which provide rich error information about why an operation failed.
In this instance, we tried to change our URL with the _special_ scheme "https" to the _non-special_ scheme "foo", which is not allowed by the standard.

```swift
do {
  try url.setScheme(to: "foo")
} catch {
  String(describing: error)
  // The new scheme is special/not-special, but the URL's existing scheme is not-special/special.
  // URLs with special schemes are encoded in a significantly different way from those with non-special schemes,
  // and switching from one style to the other via the 'scheme' property is not supported.
  //
  // The special schemes are: 'http', 'https', 'file', 'ftp', 'ws', 'wss'.
  // Gopher was considered a special scheme by previous standards, but no longer is.
}
```

We can also parse a relative URL string with another URL as its base, using the `join` function:

```swift
let url_tools = url.join("swift-url-tools")!
url_tools.serialized // "https://github.com/karwa/swift-url-tools"
```

Most URL properties will automatically percent-encode disallowed characters in the values you set them to. Already-encoded characters will not be double-encoded.

```swift
url.username = "my username"
url.password = "🤫"
url.serialized // "https://my%20username:%F0%9F%A4%AB@github.com/karwa/swift-url"
```

Additionally, paths will be lexically simplified, and IP addresses will be converted to their canonical representation:

```swift
var filepath = WebURL("file:///usr/bin/./swift")! // "file:///usr/bin/swift"
filepath.join("../tmp/../lib/") // "file:///usr/lib/"

var url_with_ip = WebURL("http://10.00.00.01/")! // "http://10.0.0.1/"
url_with_ip.hostname = "[::127.0.0.1]" // "http://[::7f00:1]/"
```
