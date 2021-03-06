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

  /// A value representing a component in a URL.
  ///
  /// Each component has a unique `rawValue` suitable for bitmasks.
  ///
  /// - seealso: `WebURL.ComponentSet`.
  ///
  struct Component: Equatable {
    let rawValue: UInt8

    private init(_unchecked rawValue: UInt8) {
      self.rawValue = rawValue
    }

    static var scheme: Self { Self(_unchecked: 1 << 0) }
    static var username: Self { Self(_unchecked: 1 << 1) }
    static var password: Self { Self(_unchecked: 1 << 2) }
    static var hostname: Self { Self(_unchecked: 1 << 3) }
    static var port: Self { Self(_unchecked: 1 << 4) }
    static var path: Self { Self(_unchecked: 1 << 5) }
    static var query: Self { Self(_unchecked: 1 << 6) }
    static var fragment: Self { Self(_unchecked: 1 << 7) }
  }
}

extension WebURL {

  /// An efficient set of `WebURL.Component` values.
  ///
  struct ComponentSet: Equatable, ExpressibleByArrayLiteral {
    private var rawValue: UInt8

    init(arrayLiteral elements: Component...) {
      self.rawValue = elements.reduce(into: 0) { $0 |= $1.rawValue }
    }

    /// Inserts a component in to the set.
    ///
    mutating func insert(_ newMember: Component) {
      self.rawValue |= newMember.rawValue
    }

    /// Whether or not the given component is a member of this set.
    ///
    func contains(_ member: Component) -> Bool {
      return (self.rawValue & member.rawValue) != 0
    }
  }
}
