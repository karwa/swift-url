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

/// A description of a file path's structure.
///
public struct FilePathFormat: Equatable, Hashable, CustomStringConvertible {

  @usableFromInline
  internal enum _Format {
    case posix
    case windows
  }

  @usableFromInline
  internal var _fmt: _Format

  @inlinable
  internal init(_ _fmt: _Format) {
    self._fmt = _fmt
  }

  /// A path which is compatible with the POSIX standard.
  ///
  @inlinable
  public static var posix: FilePathFormat {
    FilePathFormat(.posix)
  }

  /// A path which is compatible with those used by Microsoft Windows.
  ///
  @inlinable
  public static var windows: FilePathFormat {
    FilePathFormat(.windows)
  }

  /// The native path style used by the current operating system.
  ///
  @inlinable
  public static var native: FilePathFormat {
    #if os(Windows)
      return .windows
    #else
      return .posix
    #endif
  }

  public var description: String {
    switch _fmt {
    case .posix: return "posix"
    case .windows: return "windows"
    }
  }
}

