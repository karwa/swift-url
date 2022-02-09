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

import Benchmark

// https://github.com/google/swift-benchmark/issues/69
@inline(__always)
internal func blackHole<T>(_ x: T) {
  @_optimize(none)
  func assumePointeeIsRead(_ x: UnsafeRawPointer) {}
  withUnsafePointer(to: x) { assumePointeeIsRead($0) }
}

// Benchmark plan:
// - Non-special versions of SpecialNonFile tests.
// - Cannot-be-a-base URLs
// - file: URLs

Benchmark.main([
  Constructor.HTTP,
  ComponentSetters,
  PathComponents,
  PercentEncoding,
  FoundationCompat.NSURLToWeb,
  FoundationCompat.WebToNSURL,
])
