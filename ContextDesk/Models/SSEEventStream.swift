import Foundation

struct SSEEvent: Equatable {
    let event: String?
    let data: String
}

enum SSEEventStream {
    /// Stream SSE events directly from raw bytes. We do NOT use
    /// `bytes.lines` here because its line-splitting and empty-line handling
    /// have proven unreliable for real CRLF-terminated SSE payloads from
    /// OpenAI / Anthropic. We split on `\n` ourselves and strip a trailing
    /// `\r`, so an empty separator line always flushes an event.
    static func events(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream<SSEEvent, Error> { continuation in
            let task = Task {
                var eventName: String? = nil
                var dataLines: [String] = []
                var lineBytes: [UInt8] = []

                func flush() {
                    guard !dataLines.isEmpty else { return }
                    let event = SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"))
                    continuation.yield(event)
                    eventName = nil
                    dataLines.removeAll(keepingCapacity: true)
                }

                func processLine(_ raw: [UInt8]) {
                    var bytes = raw
                    if bytes.last == 0x0D { bytes.removeLast() } // strip trailing \r
                    let line = String(decoding: bytes, as: UTF8.self)
                    if line.isEmpty {
                        flush()
                        return
                    }
                    if line.hasPrefix(":") {
                        return
                    }
                    guard let colonIdx = line.firstIndex(of: ":") else {
                        return
                    }
                    let field = line[line.startIndex..<colonIdx]
                    var value = line[line.index(after: colonIdx)...]
                    if value.first == " " {
                        value = value.dropFirst()
                    }
                    switch field {
                    case "event":
                        eventName = String(value)
                    case "data":
                        dataLines.append(String(value))
                    default:
                        return
                    }
                }

                do {
                    for try await byte in bytes {
                        if byte == 0x0A { // \n terminates a line
                            processLine(lineBytes)
                            lineBytes.removeAll(keepingCapacity: true)
                        } else {
                            lineBytes.append(byte)
                        }
                    }
                    if !lineBytes.isEmpty {
                        processLine(lineBytes)
                        lineBytes.removeAll(keepingCapacity: true)
                    }
                    flush()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func events<S: AsyncSequence>(fromLines lines: S) -> AsyncThrowingStream<SSEEvent, Error> where S.Element == String {
        AsyncThrowingStream<SSEEvent, Error> { continuation in
            let task = Task {
                var eventName: String? = nil
                var dataLines: [String] = []

                func flush() {
                    guard !dataLines.isEmpty else { return }
                    let event = SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"))
                    continuation.yield(event)
                    eventName = nil
                    dataLines.removeAll(keepingCapacity: true)
                }

                do {
                    for try await rawLine in lines {
                        // Defensive: some line-iterators (notably URLSession.AsyncBytes.lines on
                        // CRLF-terminated payloads) leave a trailing \r attached to each line.
                        // The SSE spec treats CR, LF, and CRLF identically as line terminators,
                        // so strip any trailing \r before classifying the line.
                        let line: String = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
                        if line.isEmpty {
                            flush()
                            continue
                        }
                        if line.hasPrefix(":") {
                            continue
                        }
                        guard let colonIdx = line.firstIndex(of: ":") else {
                            continue
                        }
                        let field = line[line.startIndex..<colonIdx]
                        var value = line[line.index(after: colonIdx)...]
                        if value.first == " " {
                            value = value.dropFirst()
                        }
                        switch field {
                        case "event":
                            eventName = String(value)
                        case "data":
                            dataLines.append(String(value))
                        default:
                            continue
                        }
                    }
                    flush()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
