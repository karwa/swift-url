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

/// Accesses a scoped optional resource from an optional root object.
///
/// Consider the common pattern of accessing a resource whose lifetime is bound to a scope.
/// Note that the resource presented to the `body` closure is an optional type:
///
/// ```
/// struct MyObject {
///   func withOptionalResource<Result>(_ body: (Resource?) -> Result) -> Result
/// }
/// ```
///
/// It can be useful, when presented with an optional `MyObject?` value, to treat `nil` objects and `nil` resources as equivalent for the purposes of
/// `body`. One way to achieve this would be to use optional chaining, and for `body` to return an optional `Result` type which propagates whether or
/// not the resource was present:
///
/// ```
/// let maybeObject: MyObject? = ...
/// let result: MyResult? = maybeObject?.withOptionalResource { maybeResource -> MyResult? in
///   // maybeObject is not nil.
///   guard let resource = maybeResource else { return nil } // propagate resource being nil.
///   return MyResult()
/// }
///
/// if let resourceResult = result {
///   // Either maybeObject or maybeResource were nil
/// } else {
///   // Neither were nil.
/// }
/// ```
///
/// This is rather a lot of code, and can be quite cumbersome when `body` is large. Instead, we can use `accessOptionalResource`:
///
/// ```
/// let maybeObject: MyObject? = ...
/// accessOptionalResource(from: maybeObject, using: { body in $0.withOptionalResource(body) }) { maybeResource in
///   guard let resource = maybeResource else {
///     // Either maybeObject or maybeResource were nil
///   }
///   // Neither were nil.
/// }
/// ```
///
/// Essentially, it is analogous to optional chaining, but flowing in the opposite direction; making a `nil` root object result in a `nil` _parameter_ to
/// `body`, collapsing the levels of `Optional`.
///
@inlinable
internal func accessOptionalResource<Root, Argument, Result>(
  from root: Root?, using accessor: (Root, (Argument?) -> Result) -> Result, _ handler: (Argument?) -> Result
) -> Result {
  guard let root = root else {
    return handler(nil)
  }
  return withoutActuallyEscaping(handler) { handler in
    accessor(root, handler)
  }
}
