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

func printArrayLiteral<Data, OutputStream>(
  name: String, elementType: String, data: Data,
  columns: Int = 8, formatter: (Data.Element) -> String = { String(describing: $0) },
  includeSizeComment: Bool = true,
  to output: inout OutputStream
) where Data: Sequence, OutputStream: TextOutputStream {

  output.write(
    #"""
    // swift-format-ignore
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
