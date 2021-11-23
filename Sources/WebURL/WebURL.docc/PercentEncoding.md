# Percent-Encoding and Decoding

Encode Data for a URL, or Decode Data from a URL.

## What is Percent-Encoding?

Because URLs are a string format, certain characters may have special meaning depending on their position:
for example, a `"/"` in the path is used to separate the path's segments, and the first `"?"` in the URL
marks the start of the query section. This poses an interesting question: 
What if I have a path component that contains a _literal_ forward-slash?

```swift
"https://example.com/music/bands/AC/DC" 
//                                 ^
//            "AC/DC" should be a single component!
```

When these situations occur, we need to encode (or "escape") the slash in our path component,
so it won't be confused with the path delimiters. URLs use a form of encoding called **percent-encoding**,
because it encodes binary data using `"%XX"` strings, where `XX` is a hexadecimal byte value.

For the ASCII forward-slash character, the byte value is `2F`, so the URL shown above would become:

```swift
"https://example.com/music/bands/AC%2FDC"
//                                 ^^^ 😌
```

Percent-encoding is particularly important when building strings for URL components at runtime, because it means that
even `"/"` or `"?"` characters in user input won't be confused with path delimiters or other characters with special
meaning to the URL. Additionally, since percent-encoding always produces an ASCII string, we can use it
to encode Unicode text in URLs.

```swift
func urlForProfile(_ username: String) -> WebURL {
  var url  = WebURL("https://example.com/")!  
  url.path = "/accounts/" + username.percentEncoded(using: .urlComponentSet) + "/profile"
  return url
}

urlForProfile("BakerAli88") 
// ✅ "https://example.com/accounts/BakerAli88/profile"
urlForProfile("AC/DC??")
// ✅ "https://example.com/accounts/AC%2FDC%3F%3F/profile"                             
//                                  ^^^^^^^^^^^^^
urlForProfile("Günther")    
// ✅ "https://example.com/accounts/G%C3%BCnther/profile"                            
//                                  ^^^^^^^^^^^^
urlForProfile("🦆")
// ✅ "https://example.com/accounts/%F0%9F%A6%86/profile"
//                                  ^^^^^^^^^^^^
```

Since URL components are percent-encoded, their contents must be recovered by decoding.

```swift
let url = WebURL("https://%F0%9F%A6%86@example.com/")!
url.username                  // "%F0%9F%A6%86" - Who's that?
url.username.percentDecoded() // "🦆" - Oh...
```

Remember - percent encoding exists so that URL components have an unambiguous structure.
If you decode a component's value too early or too many times, you may introduce bugs. 
The following example demonstrates this with two approaches to split a path string in to its components. 

```swift
let url = urlForBand("AC/DC") 
// "https://example.com/bands/AC%2FDC"                              
//                     ^^^^^^^^^^^^^^

// The Right Way: Split, then decode each component.
let rawPath = url.path // "/bands/AC%2FDC"
let rawPathComponents = rawPath.split("/").map { $0.percentDecoded() }
// ✅ ["bands", "AC/DC"]

// The Wrong Way: Decode the entire path, then split.
let decodedPath = url.path.percentDecoded() // "/bands/AC/DC"
let decodedPathComponents = decodedPath.split("/")
// ❌ ["bands", "AC", "DC"]
```

> Tip:
> Working with percent-encoded path strings can be tricky. We recommend leaving it to the
> ``WebURL/WebURL/pathComponents-swift.property`` view wherever possible.

Data is encoded using a ``WebURL/PercentEncodeSet`` that informs the encoder which characters are allowed
in the resulting string. The URL Standard defines some encode-sets, and you can define your own.


## Extensions to Standard Library Types


WebURL provides a number of extensions to standard library types to aid
in encoding or decoding percent-encoded data.

### Encoding Text or Binary Data

- `String.percentEncoded(using: PercentEncodeSet) -> String`
- `Collection.percentEncodedString(using: PercentEncodeSet) -> String`

To percent-encode a String, call the `.percentEncoded(using:)` function and specify an encode-set to use.
``WebURL/PercentEncodeSet/urlComponentSet`` is usually a good choice for arbitrary strings: 
it includes all URL special characters, and encodes some additional characters to match the JavaScript function
`encodeURIComponent`.

If you have binary data, you can call the `.percentEncodedString(using:)` function, which is available
on all collections of bytes, to produce a percent-encoded ASCII string of its contents.

```swift
"AC/DC".percentEncoded(using: .urlComponentSet)
// "AC%2FDC"
Data(...).percentEncodedString(using: .urlComponentSet)
// "%BAt_%E0%11%22..."
```

### Decoding Strings to Text or Binary Data

- `String.percentDecoded() -> String`
- `String.percentDecodedBytesArray() -> [UInt8]`

To decode a String containing percent-encoding, call the `.percentDecoded()` function, which decodes the
string to bytes and interprets them as Unicode text. If the decoded bytes do not contain Unicode text,
call `.percentDecodedBytesArray()` to retrieve the bytes as binary data.

```swift
"AC%2FDC".percentDecoded()
// "AC/DC"
"%BAt_%E0%11%22".percentDecodedBytesArray()
// [186, 116, 95, 224, 17, 34, ...]
```

### Encoding and Decoding Lazily

For certain algorithms, it can be useful to percent-encode binary data, or to read decoded binary data, lazily.
WebURL adds `.percentEncoded(using:)` and `.percentDecoded()` functions to `LazyCollection`, each returning view objects
which encode and decode data on-demand.


## Topics

@Comment {
  DocC does not support these yet.
  ### Encoding Text or Binary Data

  - `StringProtocol/percentEncoded(using:)`
  - `Collection/percentEncodedString(using:)`

  ### Decoding Strings to Text or Binary Data

  - `StringProtocol/percentDecoded()`
  - `StringProtocol/percentDecodedBytesArray()`
}

### Percent-Encoding Sets

- ``WebURL/PercentEncodeSet``
- ``WebURL/PercentEncodeSet/urlComponentSet``
- ``WebURL/PercentEncodeSet/formEncoding``

### Encoding and Decoding Lazily

- ``LazilyPercentEncoded``
- ``LazilyPercentDecoded``
- ``LazilyPercentDecodedWithSubstitutions``
