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
