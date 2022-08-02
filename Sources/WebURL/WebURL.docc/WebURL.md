# ``WebURL``

A new URL type for Swift.

## Overview

WebURL provides support for creating and interpreting URLs according to the latest [industry standard][whatwg-url].
The API is more expressive than Swift's current `URL` type and more comprehensive, yet also simpler, 
with more intuitive semantics. Integration libraries mean that it works seamlessly with Foundation,
swift-system, and other libraries which use the current URL type.

URLs are universal identifiers, and while most of us probably think of websites (HTTP URLs) or other network services,
they can be used for anything, including local applications and databases. With a better URL library,
you can _do more_ with URLs, in a way that is more obvious and robust, and compatible with existing tooling.

[whatwg-url]: https://url.spec.whatwg.org/

➡️ **Visit the ``WebURL/WebURL`` type to get started.**

## Topics

### Creating or Modifying URLs

- ``WebURL/WebURL``
- <doc:PercentEncoding>

### Foundation Interoperability

- <doc:FoundationInterop>

### Network Hosts

- ``WebURL/WebURL/Domain``
- ``IPv4Address``
- ``IPv6Address``

### Deprecated APIs

- <doc:Deprecated>
