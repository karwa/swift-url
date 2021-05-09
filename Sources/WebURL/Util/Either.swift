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

/// A container holding a value which may be of 2 possible types.
///
@usableFromInline
internal enum Either<Left, Right> {
  case left(Left)
  case right(Right)
}

extension Either {

  @inlinable
  internal func map<NewLeft, NewRight>(
    left transformLeft: (Left) -> NewLeft,
    right transformRight: (Right) -> NewRight
  ) -> Either<NewLeft, NewRight> {
    switch self {
    case .left(let value): return .left(transformLeft(value))
    case .right(let value): return .right(transformRight(value))
    }
  }
}

extension Either where Left == Right {

  /// Returns the value held by this container.
  ///
  @inlinable
  internal func get() -> Left {
    switch self {
    case .left(let value): return value
    case .right(let value): return value
    }
  }
}
