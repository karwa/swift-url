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
enum Either<Left, Right> {
  case left(Left)
  case right(Right)
}

extension Either {

  func map<NewLeft, NewRight>(
    left transformLeft: (Left) -> NewLeft,
    right transformRight: (Right) -> NewRight
  ) -> Either<NewLeft, NewRight> {
    switch self {
    case .left(let value):
      return .left(transformLeft(value))
    case .right(let value):
      return .right(transformRight(value))
    }
  }
}

extension Either {

  /// Extracts the value held by this container as a tuple.
  /// Either the `.left` or `.right` element will have a value; the other component will be `Optional.none`.
  ///
  var extracted: (left: Left?, right: Right?) {
    switch self {
    case .left(let value):
      return (value, nil)
    case .right(let value):
      return (nil, value)
    }
  }
}

extension Either where Left == Right {

  /// Returns the value held by this container.
  ///
  func get() -> Left {
    switch self {
    case .left(let value):
      return value
    case .right(let value):
      return value
    }
  }
}

// Standard protocols.

extension Either: Equatable where Left: Equatable, Right: Equatable {
}

extension Either: Hashable where Left: Hashable, Right: Hashable {
}
