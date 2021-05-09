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

extension WebURL {

  // swift-format-ignore
  /// A value representing a component in a URL.
  ///
  /// Each component has a unique bit set on its `rawValue`, making it suitable for use in bit-sets.
  ///
  /// - seealso: `WebURL.ComponentSet`.
  ///
  @usableFromInline
  internal struct Component: Equatable {

    @usableFromInline
    internal let rawValue: UInt8

    @inlinable
    internal init(_unchecked rawValue: UInt8) {
      self.rawValue = rawValue
    }

    @inlinable internal static var scheme:   Self { Self(_unchecked: 1 << 0) }
    @inlinable internal static var username: Self { Self(_unchecked: 1 << 1) }
    @inlinable internal static var password: Self { Self(_unchecked: 1 << 2) }
    @inlinable internal static var hostname: Self { Self(_unchecked: 1 << 3) }
    @inlinable internal static var port:     Self { Self(_unchecked: 1 << 4) }
    @inlinable internal static var path:     Self { Self(_unchecked: 1 << 5) }
    @inlinable internal static var query:    Self { Self(_unchecked: 1 << 6) }
    @inlinable internal static var fragment: Self { Self(_unchecked: 1 << 7) }
  }
}

extension WebURL {

  /// An efficient set of `WebURL.Component` values.
  ///
  @usableFromInline
  internal struct ComponentSet: Equatable, ExpressibleByArrayLiteral {

    @usableFromInline
    internal var _rawValue: UInt8

    @inlinable
    internal init(arrayLiteral elements: Component...) {
      self._rawValue = elements.reduce(into: 0) { $0 |= $1.rawValue }
    }

    @inlinable
    internal subscript(component: Component) -> Bool {
      get { contains(component) }
      set { newValue ? insert(component) : remove(component) }
    }

    /// Inserts a component in to the set.
    ///
    @inlinable
    internal mutating func insert(_ newMember: Component) {
      _rawValue |= newMember.rawValue
    }

    /// Removes a component from the set.
    ///
    @inlinable
    internal mutating func remove(_ newMember: Component) {
      _rawValue &= ~newMember.rawValue
    }

    /// Whether or not the given component is a member of this set.
    ///
    @inlinable
    internal func contains(_ member: Component) -> Bool {
      return (_rawValue & member.rawValue) != 0
    }
  }
}
