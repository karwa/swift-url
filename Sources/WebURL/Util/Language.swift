// Copyright The swift-url Contributors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// Accesses the scoped, optional UTF-8 code-units of an optional URL's components.
///
/// It can be useful, when presented with an optional `WebURL?` value, to treat `nil` objects and `nil` components as equivalent for the purposes of
/// `body`. One way to achieve this would be to use optional chaining, and for `body` to return an optional `Result` type which propagates whether or
/// not the resource was present:
///
/// ```
/// let optionalURL: WebURL? = ...
/// let result: MyResult? = optionalURL?.storage.withUTF8(of: .path) { optionalPath -> MyResult? in
///   // optionalURL is not nil.
///   guard let path = optionalPath else { return nil } // propagate optionalPath being nil.
///   return MyResult()
/// }
///
/// if let resourceResult = result {
///   // Either optionalURL or optionalPath were nil
/// } else {
///   // Neither were nil.
/// }
/// ```
///
/// This is rather a lot of code, and can be quite cumbersome when `body` is large. Instead, we can use `accessUTF8FromOptionalURL`:
///
/// ```
/// let optionalURL: MyObject? = ...
/// accessUTF8FromOptionalURL(maybeObject, of: .path) { optionalPath in
///   guard let path = optionalPath else {
///     // Either optionalURL or optionalPath were nil
///   }
///   // Neither were nil.
/// }
/// ```
///
/// Essentially, it is analogous to optional chaining, but flowing in the opposite direction; making a `nil` root object result in a `nil` _parameter_ to
/// `body`, collapsing the levels of `Optional`.
///
@inlinable
internal func accessUTF8FromOptionalURL<Result>(
  _ root: WebURL?, of component: WebURL.Component, _ handler: (UnsafeBufferPointer<UInt8>?) -> Result
) -> Result {
  guard let root = root else {
    return handler(nil)
  }
  return root.storage.withUTF8(of: component, handler)
}
