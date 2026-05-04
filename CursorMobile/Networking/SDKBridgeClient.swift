import Foundation

enum SDKBridgeError: LocalizedError, Equatable {
    case invalidURL
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The SDK bridge URL could not be created."
        case .requestFailed(let statusCode, let message):
            "SDK bridge returned \(statusCode): \(message)"
        }
    }
}

struct SDKBridgeHealthResponse: Decodable, Equatable {
    var ok: Bool
    var service: String
    var sdk: String
}

struct SDKBridgeCloudRunRequest: Encodable, Equatable {
    var prompt: String
    var repositoryUrl: String?
    var startingRef: String?
    var prUrl: String?
    var modelId: String?
    var autoCreatePR: Bool
    var skipReviewerRequest: Bool?
}

struct SDKBridgeRunStartResponse: Decodable, Equatable {
    var agentId: String
    var runId: String
    var status: String
    var eventsURL: String?
    var stateURL: String?
}

struct SDKBridgeRunStateResponse: Decodable, Equatable {
    var agentId: String?
    var runId: String
    var status: String
    var result: JSONValue?
    var durationMs: Double?
    var git: JSONValue?
}

final class SDKBridgeClient: @unchecked Sendable {
    private enum Method: String {
        case get = "GET"
        case post = "POST"
    }

    private let baseURL: URL
    private let apiKey: String?
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, apiKey: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.session = session
    }

    func health() async throws -> SDKBridgeHealthResponse {
        try await request("/health")
    }

    func createCloudRun(_ body: SDKBridgeCloudRunRequest) async throws -> SDKBridgeRunStartResponse {
        try await request("/runs/cloud", method: .post, body: body)
    }

    func runState(agentID: String, runID: String) async throws -> SDKBridgeRunStateResponse {
        try await request("/agents/\(agentID)/runs/\(runID)/state")
    }

    func streamEvents(agentID: String, runID: String, maxEvents: Int = 80, timeoutSeconds: UInt64 = 4) async throws -> [ServerSentEvent] {
        let request = try makeRequest(
            "/agents/\(agentID)/runs/\(runID)/events",
            method: .get,
            accept: "text/event-stream"
        )
        let accumulator = ServerSentEventAccumulator()

        return try await withThrowingTaskGroup(of: [ServerSentEvent].self) { group in
            group.addTask {
                let (bytes, response) = try await self.session.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw SDKBridgeError.requestFailed(statusCode: -1, message: "No HTTP response.")
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

    private func request<Response: Decodable>(
        _ path: String,
        method: Method = .get,
        body: (any Encodable)? = nil
    ) async throws -> Response {
        let request = try makeRequest(path, method: method, body: body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SDKBridgeError.requestFailed(statusCode: -1, message: "No HTTP response.")
        }
        try validate(response: httpResponse, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest(
        _ path: String,
        method: Method,
        body: (any Encodable)? = nil,
        accept: String = "application/json"
    ) throws -> URLRequest {
        guard let url = URL(
            string: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            relativeTo: baseURL
        )?.absoluteURL else {
            throw SDKBridgeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func validate(response: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            let message: String
            if let decoded = try? decoder.decode(SDKBridgeErrorResponse.self, from: data) {
                message = decoded.message ?? decoded.error ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            } else {
                message = HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            }
            throw SDKBridgeError.requestFailed(statusCode: response.statusCode, message: message)
        }
    }
}

private struct SDKBridgeErrorResponse: Decodable {
    var error: String?
    var message: String?
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
