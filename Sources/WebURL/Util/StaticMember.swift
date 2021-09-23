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

/// A utility which allows emulating static members on protocol types.
///
/// In Swift 5.5+, this functionality has been superseded by [SE-0299 - Extending Static Member Lookup in Generic Contexts][SE-0299].
/// This struct survives as an implementation detail, allowing APIs to use the syntax enabled by SE-0299 while remaining compatible with older toolchains.
///
/// Please **never write this type name directly**. You may use it in APIs published by this library (e.g. `.percentEncoded(using: .pathSet)`),
/// but you should never write the name `_StaticMember`: never declare a variable using this type, never add extensions to it, never write new APIs using it, etc.
/// Forget you ever found it and move on.
///
/// One day, when this library is able to require a minimum 5.5 toolchain, this type will be removed.
/// As long as you never write this type's name directly, that removal will be a source-compatible change.
///
/// [SE-0299]: https://github.com/apple/swift-evolution/blob/main/proposals/0299-extend-generic-static-member-lookup.md
///
public struct _StaticMember<Base> {

  @usableFromInline
  internal var base: Base

  @inlinable
  internal init(_ base: Base) { self.base = base }
}
