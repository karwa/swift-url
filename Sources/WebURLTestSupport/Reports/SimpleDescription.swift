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

/// Returns a simple structural description of a value.
///
/// It's a bit rough, but the output is a bit easier to read in test reports than the result of `String(reflecting:)` or `String(describing:)`,
/// and is less boilerplate-y than writing custom formatters for everything you want to log.
///
internal func describe<T>(_ value: T, maxLevel: Int = 8) -> String {

  let mirror = Mirror(reflecting: value)

  // Scalars.
  if mirror.children.isEmpty {
    return String(describing: value)
    // Optionals.
  } else if let optional = value as? OptionalProtocol {
    if let unwrapped = optional.asOptional {
      return describe(unwrapped)
    } else {
      return "<nil>"
    }
  }
  // Complex structures.
  var string = "{\n"
  for (label, value) in mirror.children {
    string += "  - " + "\(label ?? "_"):  \(_describeChild(value, level: 2, maxLevel: maxLevel))\n"
  }
  string += "}"
  return string
}

private func _describeChild<T>(_ value: T, level: Int, maxLevel: Int) -> String {

  let mirror = Mirror(reflecting: value)

  // Scalars/depth limit.
  if mirror.children.isEmpty || level == maxLevel {
    return String(describing: value)
    // Optionals.
  } else if let optional = value as? OptionalProtocol {
    if let unwrapped = optional.asOptional {
      return _describeChild(unwrapped, level: level, maxLevel: maxLevel)
    } else {
      return "<nil>"
    }
  }
  // Complex structures. No braces around these because it's just too much noise.
  var string = "\n"
  for (label, value) in mirror.children {
    string += String(repeating: "  ", count: level)
    string += "- \(label ?? "_"):  \(_describeChild(value, level: level + 1, maxLevel: maxLevel))\n"
  }
  string.removeLast()
  return string
}

private protocol OptionalProtocol {
  var asOptional: Any? { get }
}

extension Optional: OptionalProtocol {
  fileprivate var asOptional: Any? {
    self
  }
}

extension CustomStringConvertible where Self: RawRepresentable, Self.RawValue == String {
  public var description: String {
    rawValue
  }
}
