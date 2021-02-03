# WebURL

This package contains a new URL type for Swift, written in Swift.

## What is a URL, and what does a URL type do?

A URL is fundamentally _a_ string which describes some location and the information to access it. URLs are sent by a _client_ as part of
a _request_, which is received by a _server_. The URL string can be broken down in to various sub-strings (such as the "path" and
"query" components), each of which might have its own structure. The URL standards define some protocol-agnostic operations which
can be performed on URL strings, but broadly speaking, they do not define what a particular server should _do_ with a URL it receives.

A URL type's job is to read the structure of a URL string, allowing you to extract data from it, and to provide you with high-level APIs
to manipulate those strings. It is designed to be a model-level view of the URL string, although some protocol-level information is 
required for compatibility. 
 
There have been several attempts to define the structure of URL strings over the years, including 
[RFC 1738](https://tools.ietf.org/html/rfc1738) from 1994 and [RFC 3986](https://tools.ietf.org/html/rfc3986) from 2005.  

This project is designed to interpret URLs according to the WHATWG URL specification
