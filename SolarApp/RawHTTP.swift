import Foundation
import Network

/// 用 Network.framework 直接发 HTTP/1.1 请求。
/// ATS 只作用于 URL Loading System，这条路径不受限制，可访问明文 HTTP 的 HA。
enum RawHTTP {

    static func post(
        url: URL,
        headers: [String: String],
        body: Data,
        timeout: TimeInterval = 15
    ) async throws -> (status: Int, data: Data) {

        guard let host = url.host, !host.isEmpty else { throw HAError.badURL }
        let isTLS = url.scheme?.lowercased() == "https"
        let port = url.port ?? (isTLS ? 443 : 80)
        guard port > 0, port <= 65535,
              let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw HAError.badURL
        }

        let params: NWParameters = isTLS ? .tls : .tcp
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: params
        )

        return try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            group.addTask {
                try await perform(
                    connection: connection,
                    host: host,
                    port: port,
                    isTLS: isTLS,
                    path: url.path.isEmpty ? "/" : url.path,
                    headers: headers,
                    body: body
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                connection.cancel()
                throw URLError(.timedOut)
            }

            guard let result = try await group.next() else {
                throw URLError(.unknown)
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: 单次请求

    private static func perform(
        connection: NWConnection,
        host: String,
        port: Int,
        isTLS: Bool,
        path: String,
        headers: [String: String],
        body: Data
    ) async throws -> (Int, Data) {

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Int, Data), Error>) in
            let lock = NSLock()
            var finished = false
            var buffer = Data()

            func finish(_ result: Result<(Int, Data), Error>) {
                lock.lock()
                if finished {
                    lock.unlock()
                    return
                }
                finished = true
                lock.unlock()
                connection.cancel()
                continuation.resume(with: result)
            }

            func receiveLoop() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        buffer.append(data)
                    }
                    if let error {
                        finish(.failure(error))
                        return
                    }
                    if isComplete {
                        finish(parse(buffer))
                    } else {
                        receiveLoop()
                    }
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let headerLines = headers
                        .map { "\($0.key): \($0.value)" }
                        .sorted()
                        .joined(separator: "\r\n")

                    var head = "POST \(path) HTTP/1.1\r\n"
                    head += "Host: \(host)"
                    head += (port == (isTLS ? 443 : 80)) ? "\r\n" : ":\(port)\r\n"
                    head += headerLines + "\r\n"
                    head += "Content-Length: \(body.count)\r\n"
                    head += "Connection: close\r\n"
                    head += "\r\n"

                    var payload = Data(head.utf8)
                    payload.append(body)

                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            finish(.failure(error))
                        }
                    })
                    receiveLoop()

                case .failed(let error):
                    finish(.failure(error))
                case .cancelled:
                    finish(.failure(URLError(.cancelled)))
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    // MARK: 响应解析

    private static func parse(_ data: Data) -> Result<(Int, Data), Error> {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            return .failure(HAError.badBody)
        }

        let headData = data[data.startIndex..<separator.lowerBound]
        guard let headText = String(data: headData, encoding: .utf8) else {
            return .failure(HAError.badBody)
        }

        let lines = headText.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { return .failure(HAError.badBody) }

        let statusParts = statusLine.split(separator: " ")
        guard statusParts.count >= 2, let status = Int(statusParts[1]) else {
            return .failure(HAError.badBody)
        }

        var bodyData = Data(data[separator.upperBound...])

        let isChunked = lines.contains { line in
            let lower = line.lowercased()
            return lower.hasPrefix("transfer-encoding:") && lower.contains("chunked")
        }
        if isChunked {
            bodyData = decodeChunked(bodyData)
        }

        return .success((status, bodyData))
    }

    private static func decodeChunked(_ data: Data) -> Data {
        var output = Data()
        var index = data.startIndex
        let delimiter = Data("\r\n".utf8)

        while index < data.endIndex {
            guard let lineRange = data[index...].range(of: delimiter) else { break }
            let lineData = data[index..<lineRange.lowerBound]
            guard let lineText = String(data: lineData, encoding: .utf8) else { break }

            let sizeText = lineText
                .split(separator: ";").first
                .map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard let size = Int(sizeText, radix: 16), size > 0 else { break }

            let chunkStart = lineRange.upperBound
            guard let chunkEnd = data.index(chunkStart, offsetBy: size, limitedBy: data.endIndex) else {
                output.append(data[chunkStart...])
                break
            }
            output.append(data[chunkStart..<chunkEnd])

            index = data.index(chunkEnd, offsetBy: 2, limitedBy: data.endIndex) ?? data.endIndex
        }

        return output
    }
}
