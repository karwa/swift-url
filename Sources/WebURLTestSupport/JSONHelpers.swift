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

// --------------------------------------------
// MARK: - Section Markers
// --------------------------------------------


/// An array containing instances of `Element`, broken up in to sections by marker objects.
///
/// When decoding, data which fails to decode as an `Element` and contains a `__section__` key is considered a section marker.
///
public typealias FlatSectionedArray<Element> = [SectionHeaderOr<Element>]

/// An object which is either an `Element` or a section header.
///
/// When decoding, data which fails to be decode as an `Element` and contains a `__section__` key will be considered a section marker.
/// This is useful for organizing large JSON arrays, such as a list of test-cases.
///
public enum SectionHeaderOr<Element> {
  case sectionHeader(String)
  case element(Element)
}

extension SectionHeaderOr: Codable where Element: Codable {

  enum SectionCodingKeys: String, CodingKey {
    case section = "__section__"
  }

  public init(from decoder: Decoder) throws {
    do {
      let element = try Element(from: decoder)
      self = .element(element)
    } catch {
      let elementDecodingError = error
      do {
        let sectionObject = try decoder.container(keyedBy: SectionCodingKeys.self)
        let sectionName = try sectionObject.decode(String.self, forKey: .section)
        self = .sectionHeader(sectionName)
      } catch {
        throw elementDecodingError
      }
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .sectionHeader(let name):
      var container = encoder.container(keyedBy: SectionCodingKeys.self)
      try container.encode(name, forKey: .section)
    case .element(let element):
      try element.encode(to: encoder)
    }
  }
}

extension SectionHeaderOr: Equatable where Element: Equatable {}
extension SectionHeaderOr: Hashable where Element: Hashable {}


// --------------------------------------------
// MARK: - Encoded 'Result'
// --------------------------------------------


/// An object which, like the standard library's `Result`, represents the result of an operation which may fail.
///
/// It is different from the standard library's `Result` in that the failure condition may not be an `Error` (it can, for instance, be a `String`),
/// and by having a custom `Codable` representation. When decoding, if data fails to be decoded as a `Value` and includes a `failure-reason` key,
/// the data for that key will be decoded as the `Failure` type.
///
public enum EncodedResult<Value, Failure> {
  case success(Value)
  case failure(Failure)
}

extension EncodedResult: Codable where Value: Codable, Failure: Codable {

  enum FailureCaseCodingKeys: String, CodingKey {
    case reason = "failure-reason"
  }

  public init(from decoder: Decoder) throws {
    do {
      self = .success(try decoder.singleValueContainer().decode(Value.self))
    } catch {
      let valueDecodingError = error
      do {
        let failureObject = try decoder.container(keyedBy: FailureCaseCodingKeys.self)
        self = .failure(try failureObject.decode(Failure.self, forKey: .reason))
      } catch {
        throw valueDecodingError
      }
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .success(let successResult):
      var container = encoder.singleValueContainer()
      try container.encode(successResult)
    case .failure(let reason):
      var container = encoder.container(keyedBy: FailureCaseCodingKeys.self)
      try container.encode(reason, forKey: .reason)
    }
  }
}

extension EncodedResult: Equatable where Value: Equatable, Failure: Equatable {}
extension EncodedResult: Hashable where Value: Hashable, Failure: Hashable {}

extension EncodedResult where Failure: Error {

  public init(_ other: Result<Value, Failure>) {
    switch other {
    case .success(let value):
      self = .success(value)
    case .failure(let error):
      self = .failure(error)
    }
  }
}

extension Result {

  public init(_ other: EncodedResult<Success, Failure>) {
    switch other {
    case .success(let value):
      self = .success(value)
    case .failure(let error):
      self = .failure(error)
    }
  }
}
