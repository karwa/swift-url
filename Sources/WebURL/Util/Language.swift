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
/// Consider the following example type:
/// ```
/// struct MyObject {
///   func withOptionalResource<Result>(_ perform: (Resource?) -> Result) -> Result
/// }
/// ```
/// Notice that the `perform` closure accepts an optional argument. It can be useful when presented with a `MyObject?` to handle
/// nil objects and nil resources in the same way. One way to do this would be through an optional chaining and an optional result type:
/// ```
/// let maybeObject: MyObject? = ...
/// let result: MyResult? = maybeObject?.withOptionalResource { maybeResource -> MyResult? in
///   guard let resource = maybeResource else { return nil }
///   return MyResult()
/// }
/// if let resourceResult = result {
///   // Either maybeObject or maybeResource were nil
/// } else {
///   // Neither were nil.
/// }
/// ```
/// But this is cumbersome when our nil case involves an early return, and when the `withOptionalResource` call contains a large amount
/// of code. Instead, we can write:
/// ```
/// let maybeObject: MyObject? = ...
/// accessOptionalResource(from: maybeObject, using: { $0.withOptionalResource($1) }) { maybeResource in
///   guard let resource = maybeResource else {
///     // Either maybeObject or maybeResource were nil
///   }
///   // Neither were nil.
/// }
/// ```
/// Essentially, it makes optional chaining flow in the opposite direction, making a `nil` root object result in a `nil` _parameter_ to
/// the `withOptionalResource` closure, rather a `nil` result.
///
func accessOptionalResource<Root, Argument, Result>(
  from root: Root?, using accessor: (Root, (Argument?) -> Result) -> Result, _ handler: (Argument?) -> Result
) -> Result {
  guard let root = root else {
    return handler(nil)
  }
  return withoutActuallyEscaping(handler) { handler in
    accessor(root, handler)
  }
}
