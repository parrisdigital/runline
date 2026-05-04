import Foundation
import os

struct EmptyResponse: Decodable, Equatable {}

struct ServerSentEvent: Equatable, Sendable {
    var id: String?
    var event: String?
    var data: String
}

actor ServerSentEventAccumulator {
    private var events: [ServerSentEvent] = []

    func append(_ event: ServerSentEvent) {
        events.append(event)
    }

    func snapshot() -> [ServerSentEvent] {
        events
    }
}

final class CursorAPIClient: @unchecked Sendable {
    enum Method: String, Hashable, Sendable {
        case get = "GET"
        case post = "POST"
        case delete = "DELETE"
    }

    struct ResponseMetadata: Equatable, Hashable, Sendable {
        var endpoint: String
        var statusCode: Int
        var latencyMilliseconds: Int
        var retryCount: Int
        var etag: String?
        var rateLimitLimit: String?
        var rateLimitRemaining: String?
        var rateLimitReset: String?
        var requestID: String?
    }

    struct ResponseEnvelope<Response: Decodable> {
        var value: Response
        var metadata: ResponseMetadata
    }

    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger = Logger(subsystem: "Runline", category: "CursorAPI")

    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.cursor.com")!,
        session: URLSession = .shared
    ) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw CursorAPIError.emptyAPIKey
        }
        self.apiKey = trimmedKey
        self.baseURL = baseURL
        self.session = session
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    func request<Response: Decodable>(
        _ path: String,
        method: Method = .get,
        queryItems: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        accept: String = "application/json"
    ) async throws -> Response {
        try await response(
            path,
            method: method,
            queryItems: queryItems,
            body: body,
            accept: accept
        ).value
    }

    func response<Response: Decodable>(
        _ path: String,
        method: Method = .get,
        queryItems: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        accept: String = "application/json",
        extraHeaders: [String: String] = [:],
        notModifiedFallback: Response? = nil
    ) async throws -> ResponseEnvelope<Response> {
        let request = try makeRequest(
            path,
            method: method,
            queryItems: queryItems,
            body: body,
            accept: accept,
            extraHeaders: extraHeaders
        )
        let output = try await data(for: request)

        let metadata = ResponseMetadata(
            endpoint: request.url?.path ?? path,
            statusCode: output.response.statusCode,
            latencyMilliseconds: output.latencyMilliseconds,
            retryCount: output.retryCount,
            etag: output.response.value(forHTTPHeaderField: "ETag"),
            rateLimitLimit: output.response.value(forHTTPHeaderField: "X-RateLimit-Limit"),
            rateLimitRemaining: output.response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
            rateLimitReset: output.response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
            requestID: output.response.value(forHTTPHeaderField: "X-Request-ID")
        )

        if output.response.statusCode == 304, let notModifiedFallback {
            return ResponseEnvelope(value: notModifiedFallback, metadata: metadata)
        }

        try validate(response: output.response, data: output.data)

        if Response.self == EmptyResponse.self, output.data.isEmpty {
            return ResponseEnvelope(value: EmptyResponse() as! Response, metadata: metadata)
        }

        do {
            return try ResponseEnvelope(value: decoder.decode(Response.self, from: output.data), metadata: metadata)
        } catch {
            let diagnostic = decodeFailureMessage(
                error: error,
                responseType: Response.self,
                metadata: metadata,
                data: output.data
            )
            logger.error("Cursor decode failed: \(diagnostic, privacy: .public)")
            throw CursorAPIError.decodingFailed(diagnostic)
        }
    }

    func serverSentEvents(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        maxEvents: Int = 80,
        timeoutSeconds: UInt64 = 4,
        lastEventID: String? = nil
    ) async throws -> [ServerSentEvent] {
        let request = try makeRequest(
            path,
            method: .get,
            queryItems: queryItems,
            body: nil,
            accept: "text/event-stream",
            extraHeaders: lastEventID.map { ["Last-Event-ID": $0] } ?? [:]
        )
        let accumulator = ServerSentEventAccumulator()

        return try await withThrowingTaskGroup(of: [ServerSentEvent].self) { group in
            group.addTask {
                let (bytes, response) = try await self.session.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CursorAPIError.requestFailed(statusCode: -1, message: "No HTTP response.")
                }
                if httpResponse.statusCode == 410 {
                    throw CursorAPIError.requestFailed(statusCode: 410, message: "stream_expired")
                }
                try self.validate(response: httpResponse, data: Data())

                var parser = CursorSSEParser()

                var lineBuffer = Data()
                for try await byte in bytes {
                    if Task.isCancelled {
                        break
                    }

                    lineBuffer.append(byte)
                    if byte == 10 {
                        let lineData = lineBuffer.dropLast()
                        lineBuffer.removeAll(keepingCapacity: true)
                        var line = String(decoding: lineData, as: UTF8.self)
                        if line.last == "\r" {
                            line.removeLast()
                        }
                        if let event = parser.ingest(line) {
                            await accumulator.append(event)
                            if await accumulator.snapshot().count >= maxEvents {
                                break
                            }
                        }
                    }
                }

                if !lineBuffer.isEmpty {
                    var line = String(decoding: lineBuffer, as: UTF8.self)
                    if line.last == "\r" {
                        line.removeLast()
                    }
                    if let event = parser.ingest(line) {
                        await accumulator.append(event)
                    }
                }
                if let event = parser.finish() {
                    await accumulator.append(event)
                }
                return await accumulator.snapshot()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                return await accumulator.snapshot()
            }

            let events = try await group.next() ?? []
            group.cancelAll()
            return events
        }
    }

    private func makeRequest(
        _ path: String,
        method: Method,
        queryItems: [URLQueryItem],
        body: (any Encodable)?,
        accept: String,
        extraHeaders: [String: String] = [:]
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false) else {
            throw CursorAPIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw CursorAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Basic \(authorizationToken)", forHTTPHeaderField: "Authorization")
        for (name, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }

        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private var authorizationToken: String {
        Data("\(apiKey):".utf8).base64EncodedString()
    }

    private func data(for request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse, retryCount: Int, latencyMilliseconds: Int) {
        var retryCount = 0
        let maxRetries = 2

        while true {
            let startedAt = Date()
            let (data, response) = try await session.data(for: request)
            let latencyMilliseconds = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CursorAPIError.requestFailed(statusCode: -1, message: "No HTTP response.")
            }

            if httpResponse.statusCode == 429, retryCount < maxRetries {
                let retryDelay = retryDelay(for: httpResponse, attempt: retryCount)
                retryCount += 1
                try await Task.sleep(nanoseconds: retryDelay)
                continue
            }

            return (data, httpResponse, retryCount, latencyMilliseconds)
        }
    }

    private func retryDelay(for response: HTTPURLResponse, attempt: Int) -> UInt64 {
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(retryAfter) {
            return UInt64(seconds * 1_000_000_000)
        }
        let seconds = pow(2.0, Double(attempt)) * 0.5
        return UInt64(seconds * 1_000_000_000)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorAPIError.requestFailed(statusCode: -1, message: "No HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let decodedError = try? decoder.decode(CursorAPIErrorResponse.self, from: data)
            let message = decodedError?.message ?? decodedError?.error ?? decodedError?.code ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw CursorAPIError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func decodeFailureMessage<Response>(
        error: Error,
        responseType: Response.Type,
        metadata: ResponseMetadata,
        data: Data
    ) -> String {
        var parts = [
            "endpoint=\(metadata.endpoint)",
            "status=\(metadata.statusCode)",
            "type=\(responseType)",
            "error=\(error.localizedDescription)"
        ]
        if let requestID = metadata.requestID, !requestID.isEmpty {
            parts.append("requestID=\(requestID)")
        }
        if let preview = responsePreview(from: data) {
            parts.append("preview=\(preview)")
        }
        return parts.joined(separator: " | ")
    }

    private func responsePreview(from data: Data, limit: Int = 512) -> String? {
        guard !data.isEmpty else { return nil }
        let prefix = data.prefix(limit)
        guard let value = String(data: prefix, encoding: .utf8) else { return nil }
        let flattened = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return data.count > limit ? flattened + "..." : flattened
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        encodeValue = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}
