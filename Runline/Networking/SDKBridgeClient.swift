import Foundation

enum SDKBridgeError: LocalizedError, Equatable {
    case invalidURL
    case missingBridge
    case requestFailed(statusCode: Int, message: String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The SDK Bridge URL could not be created."
        case .missingBridge:
            "Configure the SDK Bridge before starting Cursor Chat."
        case .requestFailed(let statusCode, let message):
            if statusCode == 429, message.localizedCaseInsensitiveContains("hard usage limit") {
                message
            } else {
                "SDK Bridge returned \(statusCode): \(message)"
            }
        case .decodingFailed(let message):
            "SDK Bridge response could not be decoded: \(message)"
        }
    }
}

enum SDKBridgePreferences {
    static let isEnabledKey = "sdkBridge.isEnabled"
    static let baseURLKey = "sdkBridge.baseURL"
    static let defaultBaseURLString = "https://runline-sdk-bridge.fly.dev"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isEnabledKey) != nil else { return true }
        return defaults.bool(forKey: isEnabledKey)
    }

    static func setEnabled(_ isEnabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: isEnabledKey)
    }

    static func baseURLString(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: baseURLKey) ?? defaultBaseURLString
    }

    static func setBaseURLString(_ value: String, defaults: UserDefaults = .standard) {
        defaults.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: baseURLKey)
    }

    static func configuredBaseURL(defaults: UserDefaults = .standard) -> URL? {
        baseURL(from: baseURLString(defaults: defaults))
    }

    static func baseURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

struct SDKBridgeListResponse<Item: Decodable>: Decodable {
    var items: [Item]
}

struct SDKBridgeCapabilitiesDTO: Decodable, Equatable {
    struct Supports: Decodable, Equatable {
        var createSession: Bool
        var followUps: Bool
        var runStreaming: Bool
        var cancel: Bool
        var artifacts: Bool
        var cursorKeyPersistence: Bool
    }

    var service: String
    var version: String
    var runtime: String
    var transport: [String]
    var supports: Supports
}

struct SDKBridgeSessionStartRequest: Encodable, Equatable {
    var prompt: String
    var images: [SDKBridgePromptImageRequest]?
    var repo: SDKBridgeRepoRequest?
    var modelId: String?
    var autoCreatePR: Bool
    var skipReviewerRequest: Bool?
    var workOnCurrentBranch: Bool?
}

struct SDKBridgeMessageRequest: Encodable, Equatable {
    var prompt: String
    var images: [SDKBridgePromptImageRequest]?
    var modelId: String?
}

struct SDKBridgeCancelRequest: Encodable, Equatable {
    var runId: String?
}

struct SDKBridgeRepoRequest: Encodable, Equatable {
    var url: String
    var startingRef: String?
    var prUrl: String?
}

struct SDKBridgePromptImageDimensionRequest: Encodable, Equatable {
    var width: Int
    var height: Int
}

struct SDKBridgePromptImageRequest: Encodable, Equatable {
    var data: String
    var mimeType: String
    var dimension: SDKBridgePromptImageDimensionRequest
}

struct SDKBridgeSessionStartResponse: Decodable, Equatable {
    var sessionId: String
    var agentId: String
    var runId: String
    var status: String
    var eventsURL: String?
    var runEventsURL: String?
    var stateURL: String?
}

struct SDKBridgeSessionStateResponse: Decodable, Equatable {
    var session: SDKBridgeSessionDTO
    var latestRun: SDKBridgeRunDTO?
}

struct SDKBridgeSessionDTO: Decodable, Equatable {
    var sessionId: String
    var agentId: String
    var name: String?
    var repositoryUrl: String?
    var startingRef: String?
    var prUrl: String?
    var modelId: String?
    var autoCreatePR: Bool
    var latestRunId: String?
    var runs: [SDKBridgeRunDTO]
    var createdAt: String
    var updatedAt: String
}

struct SDKBridgeRunDTO: Decodable, Equatable {
    var runId: String
    var agentId: String
    var status: String
    var createdAt: String
    var updatedAt: String
    var result: String?
    var durationMs: Double?
    var git: JSONValue?
}

struct SDKBridgeArtifactDTO: Decodable, Equatable {
    var path: String
    var sizeBytes: Int?
    var updatedAt: String?
}

final class SDKBridgeClient: @unchecked Sendable {
    private enum Method: String {
        case get = "GET"
        case post = "POST"
    }

    private let baseURL: URL
    private let apiKey: String
    private let bridgeSecret: String?
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, apiKey: String, bridgeSecret: String? = nil, session: URLSession = .shared) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw CursorAPIError.emptyAPIKey }
        self.baseURL = baseURL
        self.apiKey = trimmedKey
        self.bridgeSecret = bridgeSecret?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.session = session
    }

    func capabilities() async throws -> SDKBridgeCapabilitiesDTO {
        try await request("/v1/capabilities")
    }

    func validateConnection() async throws -> CursorMeDTO {
        try await request("/v1/me")
    }

    func listRepositories() async throws -> SDKBridgeListResponse<SDKBridgeRepositoryDTO> {
        try await request("/v1/repositories")
    }

    func listModels() async throws -> SDKBridgeListResponse<SDKBridgeModelDTO> {
        try await request("/v1/models")
    }

    func listSessions() async throws -> SDKBridgeListResponse<SDKBridgeSessionDTO> {
        try await request("/v1/sessions")
    }

    func sessionState(sessionID: String) async throws -> SDKBridgeSessionStateResponse {
        try await request("/v1/sessions/\(sessionID.urlPathComponentEncoded)")
    }

    func createSession(_ body: SDKBridgeSessionStartRequest) async throws -> SDKBridgeSessionStartResponse {
        try await request("/v1/sessions", method: .post, body: body)
    }

    func sendMessage(sessionID: String, body: SDKBridgeMessageRequest) async throws -> SDKBridgeSessionStartResponse {
        try await request("/v1/sessions/\(sessionID.urlPathComponentEncoded)/messages", method: .post, body: body)
    }

    func cancel(sessionID: String, body: SDKBridgeCancelRequest) async throws -> SDKBridgeRunDTO {
        try await request("/v1/sessions/\(sessionID.urlPathComponentEncoded)/cancel", method: .post, body: body)
    }

    func listArtifacts(sessionID: String) async throws -> SDKBridgeListResponse<SDKBridgeArtifactDTO> {
        try await request("/v1/sessions/\(sessionID.urlPathComponentEncoded)/artifacts")
    }

    func streamEvents(sessionID: String, runID: String, lastEventID: String?) async throws -> [ServerSentEvent] {
        try await serverSentEvents(
            "/v1/sessions/\(sessionID.urlPathComponentEncoded)/runs/\(runID.urlPathComponentEncoded)/events",
            lastEventID: lastEventID
        )
    }

    private func request<Response: Decodable>(
        _ path: String,
        method: Method = .get,
        body: (any Encodable)? = nil
    ) async throws -> Response {
        let request = try makeRequest(path, method: method, body: body, accept: "application/json")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw SDKBridgeError.decodingFailed(error.localizedDescription)
        }
    }

    private func serverSentEvents(
        _ path: String,
        maxEvents: Int = 80,
        timeoutSeconds: UInt64 = 4,
        lastEventID: String?
    ) async throws -> [ServerSentEvent] {
        let request = try makeRequest(
            path,
            method: .get,
            body: nil,
            accept: "text/event-stream",
            extraHeaders: lastEventID.map { ["Last-Event-ID": $0] } ?? [:]
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
                    if Task.isCancelled { break }
                    lineBuffer.append(byte)
                    if byte == 10 {
                        let lineData = lineBuffer.dropLast()
                        lineBuffer.removeAll(keepingCapacity: true)
                        var line = String(decoding: lineData, as: UTF8.self)
                        if line.last == "\r" { line.removeLast() }
                        if let event = parser.ingest(line) {
                            await accumulator.append(event)
                            if Self.isTerminalServerSentEvent(event) {
                                break
                            }
                            if await accumulator.snapshot().count >= maxEvents {
                                break
                            }
                        }
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

    private static func isTerminalServerSentEvent(_ event: ServerSentEvent) -> Bool {
        if isTerminalEventName(event.event) {
            return true
        }

        guard let data = event.data.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return false
        }

        let eventName = json.objectValue?.stringValue(for: "event")
            ?? json.objectValue?.objectValue(for: "data")?.stringValue(for: "type")
            ?? json.objectValue?.stringValue(for: "type")
        return isTerminalEventName(eventName)
    }

    private static func isTerminalEventName(_ eventName: String?) -> Bool {
        switch eventName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "done", "complete", "completed":
            return true
        default:
            return false
        }
    }

    private func makeRequest(
        _ path: String,
        method: Method,
        body: (any Encodable)?,
        accept: String,
        extraHeaders: [String: String] = [:]
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw SDKBridgeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Cursor-API-Key")
        if let bridgeSecret {
            request.setValue(bridgeSecret, forHTTPHeaderField: "X-Runline-Bridge-Secret")
        }
        for (name, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw SDKBridgeError.requestFailed(statusCode: -1, message: "No HTTP response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? decoder.decode(SDKBridgeErrorResponse.self, from: data).message)
                ?? String(data: data, encoding: .utf8)
                ?? "Request failed."
            throw SDKBridgeError.requestFailed(statusCode: response.statusCode, message: message)
        }
    }
}

private struct SDKBridgeErrorResponse: Decodable {
    var message: String
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

    var urlPathComponentEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let object) = self {
            return object
        }
        return nil
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func stringValue(for key: String) -> String? {
        guard case .string(let value)? = self[key] else { return nil }
        return value
    }

    func objectValue(for key: String) -> [String: JSONValue]? {
        guard case .object(let object)? = self[key] else { return nil }
        return object
    }
}

struct SDKBridgeRepositoryDTO: Decodable, Equatable {
    var url: String
}

struct SDKBridgeModelDTO: Decodable, Equatable {
    var id: String
    var displayName: String?
    var description: String?
    var aliases: [String]?
}
