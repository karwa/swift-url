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

#if WEBURL_UNICODE_PARSE_N_PRINT

  // --------------------------------------------
  // MARK: - Formatting Integers
  // --------------------------------------------


  @usableFromInline
  internal enum HexStringFormat {
    /// Format without any leading zeroes, e.g. `0x2`.
    case minimal
    /// Format which includes all leading zeroes in a fixed-width integer, e.g. `0x00CE`.
    case fullWidth
    /// Format which pads values with enough zeroes to reach a minimum length.
    case padded(toLength: Int)
  }

  extension FixedWidthInteger {

    @usableFromInline
    internal func hexString(format: HexStringFormat = .fullWidth) -> String {
      "0x" + unprefixedHexString(format: format)
    }

    @usableFromInline
    internal func unprefixedHexString(format: HexStringFormat) -> String {
      let minimal = String(self, radix: 16, uppercase: true)
      switch format {
      case .minimal:
        return minimal
      case .fullWidth:
        return minimal.leftPadding(toLength: Self.bitWidth / 4, withPad: "0")
      case .padded(toLength: let minLength):
        if minimal.count < minLength {
          return minimal.leftPadding(toLength: minLength, withPad: "0")
        } else {
          return minimal
        }
      }
    }
  }


  // --------------------------------------------
  // MARK: - Array Literals
  // --------------------------------------------


  internal func printArrayLiteral<Data, OutputStream>(
    name: String, elementType: String, data: Data,
    columns: Int = 8, formatter: (Data.Element) -> String = { String(describing: $0) },
    includeSizeComment: Bool = true,
    to output: inout OutputStream
  ) where Data: Sequence, OutputStream: TextOutputStream {

    output.write(
      #"""
      // swift-format-ignore
      @usableFromInline
      internal let \#(name): [\#(elementType)] = [
      """#
    )
    output.write("\n")

    var totalCount = 0

    var it = data.makeIterator()
    var row = [Data.Element]()
    row.reserveCapacity(columns)

    func populateNextRow() {
      row.removeAll(keepingCapacity: true)
      while row.count < columns, let nextColumn = it.next() { row.append(nextColumn) }
    }
    populateNextRow()

    let rowLeading = "  "
    let rowTrailing = ",\n"
    while !row.isEmpty {
      output.write(rowLeading)
      for i in 0..<row.count {
        output.write(formatter(row[i]))
        totalCount += 1
        if i + 1 < row.endIndex {
          output.write(", ")
        }
      }
      output.write(rowTrailing)
      populateNextRow()
    }
    output.write("]\n")

    if includeSizeComment {
      output.write("// \(name) size = \(totalCount) elements")
      output.write("\n")
    }
  }

#endif  // WEBURL_UNICODE_PARSE_N_PRINT
