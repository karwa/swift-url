# ``WebURL``

A new URL type for Swift.

## Overview

WebURL is a new URL library, built to conform to the latest [industry standard](https://url.spec.whatwg.org/)
for parsing and manipulating URLs. It has a very lenient parser which matches modern browsers,
JavaScript's native URL class, and other modern libraries. WebURL values are automatically normalized according
to the standard, meaning they remain highly interoperable with legacy systems and other libraries,
and are much easier to work with.

The API incorporates modern best practices, so it helps you write robust, correct code. It also takes full advantage
of Swift language features such as generics and zero-cost wrapper views to deliver an expressive, easy-to-use API
which scales to give you the best possible performance.

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
