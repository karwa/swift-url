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

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif
// TODO: Windows.

#if canImport(Darwin) || canImport(Glibc)

  import Dispatch

  /// A basic server, listening on the loopback address.
  ///
  /// It isn't very configurable, scalable, or even easy to use 😅.
  ///
  /// For receiving, it is basically a raw socket interface - just giving you the bytes that were sent
  /// by the client. You respond by returning a `Response` enum, which gets formatted as an HTTP response.
  ///
  /// It's a bit weird, perhaps - it's for these tests where we're really only interested in looking at
  /// the raw request that gets sent to the server by URLSession, and sometimes causing a redirect or whatever.
  /// For that purpose, it's fine.
  ///
  internal class LocalServer {

    /// A closure which receives a request from the wire, processes it, and returns a `Response`.
    /// The response will be formatted as an HTTP response - super basic, a status code,
    /// maybe a Content-Length, but no other headers or whatnot.
    ///
    /// The closure will be invoked on arbitrary threads, often in parallel.
    ///
    public typealias RequestHandler = ([UInt8], ServerInfo) -> Response

    public enum Response {
      case text(String)
      case data([UInt8])
      case redirect(String)
      case notFound
    }

    public struct ServerInfo {
      public private(set) var port: UInt16
    }

    private var state: Optional<(socketDescriptor: Int32, info: ServerInfo)>
    private let stateQueue: DispatchQueue
    private let handler: RequestHandler

    /// Creates a server.
    ///
    /// - parameters:
    ///   - requestHandler: A closure which receives a request from the wire, processes it, and returns a `Response`.
    ///                     See `RequestHandler` for more information. The closure will be invoked on arbitrary threads,
    ///                     often in parallel.
    ///
    public init(requestHandler: @escaping RequestHandler) {
      state = .none
      stateQueue = DispatchQueue(label: "[loopback-server]-state")
      handler = requestHandler
    }

    /// Starts the server on a port chosen by the system, if it is not already running.
    ///
    /// This function may be called on any thread.
    ///
    /// - returns: The port number the server is listening on.
    ///
    public func start() throws -> UInt16 {
      try stateQueue.sync {
        if state == nil {
          try makeSocketAndStart(port: 0)
        }
        return state!.info.port
      }
    }

    /// Stops the server.
    ///
    /// This function may be called on any thread.
    ///
    public func stop() {
      stateQueue.sync {
        if let socket = state?.socketDescriptor {
          close(socket)
        }
        state = nil
      }
    }
  }


  // --------------------------------
  // MARK: - Connection Handling
  // --------------------------------


  extension LocalServer {

    private enum MakeSocketError: Error {
      case failedToCreate
      case failedToBind
      case failedToListen
    }

    fileprivate func makeSocketAndStart(port: UInt16) throws {

      // This function reads and writes the server state.
      dispatchPrecondition(condition: .onQueue(stateQueue))

      // 1. Create the socket.
      #if canImport(Darwin)
        let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
      #elseif canImport(Glibc)
        let socketFD = socket(AF_INET, .init(SOCK_STREAM.rawValue), .init(IPPROTO_TCP))
      #endif
      guard socketFD != -1 else { throw MakeSocketError.failedToCreate }

      // 2. Set options.
      do {
        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, 4)
      }

      // 3. Bind the address.
      do {
        var address = sockaddr_in()
        let socklen = socklen_t(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
        address.sin_zero = (0, 0, 0, 0, 0, 0, 0, 0)

        let err = withUnsafePointer(to: &address) { sockaddrInPtr in
          sockaddrInPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            bind(socketFD, sockaddrPtr, socklen)
          }
        }
        guard err == 0 else {
          close(socketFD)
          throw MakeSocketError.failedToBind
        }
      }

      // 4. Start listening for connections.
      do {
        let err = listen(socketFD, 5)
        guard err == 0 else {
          close(socketFD)
          throw MakeSocketError.failedToListen
        }
      }

      // 5. Set the server's state info.
      do {
        let info = ServerInfo(port: LocalServer.getPort(socketDescriptor: socketFD))
        self.state = (socketFD, info)
      }

      // 6. Accept connections on a separate queue.
      DispatchQueue(label: "[loopback-server]-accept-loop").async {
        self.acceptLoop()
      }
    }

    private func acceptLoop() {

      // This function should be spinning in its own queue.
      dispatchPrecondition(condition: .notOnQueue(stateQueue))

      while true {

        // 1. Refresh the server state; check that we haven't been stopped.
        guard let serverState = stateQueue.sync(execute: { self.state }) else {
          break
        }

        // 2. Wait until somebody connects.
        #if canImport(WinSDK)
          // var _pollfd = WSAPOLLFD(fd: serverState.socketDescriptor, events: .init(POLL_IN), revents: 0)
          // let pollResult = WSAPoll(&_pollfd, 1, 100)
          // if pollResult == 0 {
          //   continue
          // } else if pollResult < 0 {
          //   break
          // }
        #else
          var _pollfd = pollfd(fd: serverState.socketDescriptor, events: .init(POLL_IN), revents: 0)
          let pollResult = poll(&_pollfd, 1, 100)
          if pollResult == 0 {
            continue
          } else if pollResult < 0 {
            break
          }
        #endif

        let clientDescriptor = accept(serverState.socketDescriptor, nil, nil)
        guard clientDescriptor != -1 else {
          continue
        }

        // 3. Handle the connection on a separate queue.
        DispatchQueue(label: "[loopback-server]-connection-\(clientDescriptor)").async {
          LocalServer.handleConnection(
            clientDescriptor: clientDescriptor,
            serverInfo: serverState.info,
            handler: self.handler  // Immutable, safe to read across queues.
          )
          close(clientDescriptor)
        }
      }
    }

    private static func handleConnection(clientDescriptor: Int32, serverInfo: ServerInfo, handler: RequestHandler) {

      // 1. Accumulate the bytes of the request.
      var accumulatedRequest = [UInt8]()
      do {
        let readBuffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
        accumulatedRequest.reserveCapacity(readBuffer.count)
        defer { readBuffer.deallocate() }

        while true {
          let bytesRead = read(clientDescriptor, readBuffer.baseAddress, readBuffer.count)
          guard bytesRead > 0 else { break }
          accumulatedRequest.append(contentsOf: readBuffer.prefix(bytesRead))
          if bytesRead == readBuffer.count {
            continue
          } else {
            break
          }
        }
        guard !accumulatedRequest.isEmpty else {
          return
        }
      }

      // 2. Process the request and write the response.
      do {
        let formattedResponse = handler(accumulatedRequest, serverInfo).formattedHTTPResponse()
        write(clientDescriptor, formattedResponse, formattedResponse.count)
      }

      // 3. The connection will be closed by the caller.
    }
  }


  // --------------------------------
  // MARK: - Server Info
  // --------------------------------


  extension LocalServer {

    private static func getPort(socketDescriptor: Int32) -> UInt16 {

      var socketAddress = sockaddr_in()
      var socklen = socklen_t(MemoryLayout<sockaddr_in>.size)
      let err = withUnsafeMutablePointer(to: &socketAddress) { sockaddrInPtr in
        sockaddrInPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
          getsockname(socketDescriptor, sockaddrPtr, &socklen)
        }
      }
      guard err == 0 else { return 0 }
      return UInt16(bigEndian: socketAddress.sin_port)
    }
  }


  // --------------------------------
  // MARK: - Response Formatting
  // --------------------------------


  extension LocalServer.Response {

    fileprivate func formattedHTTPResponse() -> [UInt8] {
      switch self {
      case .text(let text):
        return Self.formatOKResponse(body: text.utf8)
      case .data(let data):
        return Self.formatOKResponse(body: data)
      case .redirect(let location):
        return Array("HTTP/1.1 301\r\nLocation: \(location)\r\n\r\n".utf8)
      case .notFound:
        return Array("HTTP/1.1 404\r\n\r\n".utf8)
      }
    }

    private static func formatOKResponse<Body>(
      body: Body
    ) -> [UInt8] where Body: Collection, Body.Element == UInt8 {
      var result = Array("HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
      result.append(contentsOf: body)
      result.append(contentsOf: "\r\n\r\n".utf8)
      return result
    }
  }

#endif  // canImport(Darwin) || canImport(Glibc)
