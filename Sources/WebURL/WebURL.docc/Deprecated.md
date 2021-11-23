# Deprecated APIs

These APIs have been replaced and will be removed in a future version of WebURL.

## Topics

### KeyPath-based Percent Encoding
####

Since Swift 5.5, Swift now supports static-member syntax for protocol conformances
([SE-0299]).

This can replace the static-KeyPath solution we had previously used. A source-compatible fallback is in place
for pre-5.5 compilers. In most cases, the previous APIs still exist with deprecation notices, so the compiler will
help you upgrade to the new interface.

[SE-0299]: https://github.com/apple/swift-evolution/blob/main/proposals/0299-extend-generic-static-member-lookup.md

- ``PercentDecodeSet_Namespace``
- ``PercentEncodeSet_Namespace``
- ``LazilyPercentEncodedUTF8``
- ``LazilyPercentDecodedUTF8``
- ``LazilyPercentDecodedUTF8WithoutSubstitutions``
- ``PercentEncodeSetProtocol``

### IPv4 Parser with Hostname detection
####

A previous interface to the IPv4 parser returned a tri-state `{ ipv4, invalidIPv4, notAnIPAddress }` result, as a way
for clients to distinguish hostnames from IPv4 addresses as the URL parser does.

Changes to the URL Standard make this impractical to continue offering. A more comprehensive host-parsing API
would be a nice addition in the future, though. The previous API still exists with a deprecation notice, so the compiler
will help you migrate to the supported IPv4 parsing interface.

- ``IPv4Address/parse(utf8:)``
- ``IPv4Address/ParserResult``

### Renamed
####

Some minor functions and properties were renamed. The previous APIs still exist with renaming notices, so the compiler
will help you upgrade to the new names.

- ``WebURL/WebURL/cannotBeABase``
- ``WebURL/WebURL/fromFilePathBytes(_:format:)``
- ``WebURL/WebURL/filePathBytes(from:format:nullTerminated:)``
