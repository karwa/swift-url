# Deprecated APIs

These APIs will be removed in a future version of WebURL.

<!--
> Note:
>
> Currently, there are no deprecated APIs.
>
> Should there be a need to deprecate any APIs in the future, a notice here will describe
> how to update your applications. Deprecated APIs will be removed at the next SemVer-major release
> (e.g. `1.x.y` -> `2.x.y`).
-->

## Topics

### Form Params (WebURL 0.5.0)

The `formParams` view has been replaced by the `WebURL.KeyValuePairs` view 
(available via the ``WebURL/WebURL/queryParams`` property or ``WebURL/WebURL/keyValuePairs(in:schema:)`` function).
The new API requires Swift 5.7+.

- ``WebURL/WebURL/formParams``
