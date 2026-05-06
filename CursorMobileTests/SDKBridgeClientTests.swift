import Foundation
import XCTest
@testable import CursorMobile

final class SDKBridgeClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockBridgeURLProtocol.reset()
    }

    override func tearDown() {
        MockBridgeURLProtocol.reset()
        super.tearDown()
    }

    func testHealthUsesBridgeBaseURL() async throws {
        MockBridgeURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: [
                "ok": true,
                "service": "runline-bridge",
                "sdk": "@cursor/sdk",
                "pairingRequired": true,
                "paired": true
            ])
        }

        let client = makeClient()
        let health = try await client.health()

        XCTAssertTrue(health.ok)
        XCTAssertEqual(health.sdk, "@cursor/sdk")
        XCTAssertEqual(health.pairingRequired, true)
        XCTAssertEqual(health.paired, true)
        let request = try XCTUnwrap(MockBridgeURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url?.path, "/health")
        XCTAssertEqual(request.header("Accept"), "application/json")
    }

    func testLoopbackBridgeURLShowsDeviceGuidance() throws {
        let localhost = try XCTUnwrap(URL(string: "http://localhost:8787"))
        let lanURL = try XCTUnwrap(URL(string: "http://192.168.1.10:8787"))

        XCTAssertTrue(SDKBridgePreferences.isLoopback(localhost))
        XCTAssertNotNil(SDKBridgePreferences.deviceLoopbackHelp(for: localhost))
        XCTAssertFalse(SDKBridgePreferences.isLoopback(lanURL))
        XCTAssertNil(SDKBridgePreferences.deviceLoopbackHelp(for: lanURL))
    }

    func testCreateCloudRunSendsBearerKeyAndLaunchBody() async throws {
        MockBridgeURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: [
                "sessionId": "agent_123",
                "agentId": "agent_123",
                "runId": "run_123",
                "status": "running",
                "mode": "sdk-agent",
                "eventsURL": "/agents/agent_123/runs/run_123/events",
                "stateURL": "/agents/agent_123/runs/run_123/state"
            ])
        }

        let client = makeClient(apiKey: "cursor-test-key")
        let response = try await client.createCloudRun(
            SDKBridgeCloudRunRequest(
                prompt: "Fix failing tests.",
                repositoryUrl: "https://github.com/acme/app",
                startingRef: "main",
                prUrl: nil,
                modelId: "composer-2",
                autoCreatePR: true,
                skipReviewerRequest: false
            )
        )

        XCTAssertEqual(response.agentId, "agent_123")
        XCTAssertEqual(response.runId, "run_123")

        let request = try XCTUnwrap(MockBridgeURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.path, "/runs/cloud")
        XCTAssertEqual(request.header("Authorization"), "Bearer cursor-test-key")
        XCTAssertEqual(request.header("Content-Type"), "application/json")

        let body = try XCTUnwrap(request.jsonBody)
        XCTAssertEqual(body["prompt"] as? String, "Fix failing tests.")
        XCTAssertEqual(body["repositoryUrl"] as? String, "https://github.com/acme/app")
        XCTAssertEqual(body["startingRef"] as? String, "main")
        XCTAssertEqual(body["modelId"] as? String, "composer-2")
        XCTAssertEqual(body["autoCreatePR"] as? Bool, true)
        XCTAssertEqual(body["skipReviewerRequest"] as? Bool, false)
    }

    func testBridgeTokenHeaderIsSentOnProtectedRequests() async throws {
        MockBridgeURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: [
                "profiles": []
            ])
        }

        let client = makeClient(apiKey: "cursor-test-key", bridgeToken: "bridge-token")
        _ = try await client.listMCPProfiles()

        let request = try XCTUnwrap(MockBridgeURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.header("Authorization"), "Bearer cursor-test-key")
        XCTAssertEqual(request.header("X-Runline-Bridge-Token"), "bridge-token")
    }

    func testPairingStartAndCompleteUsePairingEndpoints() async throws {
        MockBridgeURLProtocol.handler = { request in
            switch request.url?.path {
            case "/pair/start":
                return try Self.jsonResponse(for: request, body: [
                    "pairingId": "pair-123",
                    "expiresAt": "2026-05-06T20:00:00Z",
                    "message": "Check the terminal running Runline Bridge for the pairing code."
                ])
            case "/pair/complete":
                return try Self.jsonResponse(for: request, body: [
                    "bridgeToken": "bridge-token",
                    "bridgeName": "Runline Bridge",
                    "service": "runline-bridge",
                    "sdk": "@cursor/sdk"
                ])
            default:
                throw URLError(.badURL)
            }
        }

        let client = makeClient()
        let start = try await client.startPairing(deviceName: "Matthew's iPhone")
        let complete = try await client.completePairing(
            pairingID: "pair-123",
            code: "123456",
            deviceName: "Matthew's iPhone"
        )

        XCTAssertEqual(start.pairingId, "pair-123")
        XCTAssertEqual(complete.bridgeToken, "bridge-token")
        XCTAssertEqual(MockBridgeURLProtocol.capturedRequests.map { $0.url?.path }, ["/pair/start", "/pair/complete"])

        let startBody = try XCTUnwrap(MockBridgeURLProtocol.capturedRequests.first?.jsonBody)
        XCTAssertEqual(startBody["deviceName"] as? String, "Matthew's iPhone")

        let completeBody = try XCTUnwrap(MockBridgeURLProtocol.capturedRequests.last?.jsonBody)
        XCTAssertEqual(completeBody["pairingId"] as? String, "pair-123")
        XCTAssertEqual(completeBody["code"] as? String, "123456")
    }

    func testCreateSessionUsesSDKSessionEndpointAndProfile() async throws {
        MockBridgeURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: [
                "sessionId": "bc-session",
                "agentId": "bc-session",
                "runId": "run-session",
                "status": "running",
                "mode": "sdk-agent",
                "mcpProfile": [
                    "id": "github-tools",
                    "name": "GitHub Tools",
                    "description": "GitHub MCP and reviewer subagent.",
                    "mcpServerCount": 1,
                    "subagentCount": 1
                ],
                "sessionEventsURL": "/sdk/sessions/bc-session/runs/run-session/events",
                "sessionStateURL": "/sdk/sessions/bc-session/state?runId=run-session"
            ])
        }

        let client = makeClient(apiKey: "cursor-test-key")
        let response = try await client.createSession(
            SDKBridgeCloudRunRequest(
                prompt: "Plan the migration.",
                intent: "plan",
                repositoryUrl: "https://github.com/acme/app",
                startingRef: "main",
                prUrl: nil,
                modelId: nil,
                mcpProfileId: "github-tools",
                autoCreatePR: false,
                skipReviewerRequest: true
            )
        )

        XCTAssertEqual(response.sessionId, "bc-session")
        XCTAssertEqual(response.mcpProfile?.id, "github-tools")

        let request = try XCTUnwrap(MockBridgeURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.path, "/sdk/sessions")
        let body = try XCTUnwrap(request.jsonBody)
        XCTAssertEqual(body["intent"] as? String, "plan")
        XCTAssertEqual(body["mcpProfileId"] as? String, "github-tools")
    }

    func testSendSessionMessageUsesSessionEndpoint() async throws {
        MockBridgeURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: [
                "sessionId": "bc-session",
                "agentId": "bc-session",
                "runId": "run-follow-up",
                "status": "running",
                "mode": "sdk-agent"
            ])
        }

        let client = makeClient(apiKey: "cursor-test-key")
        let response = try await client.sendSessionMessage(
            sessionID: "bc-session",
            body: SDKBridgeSessionMessageRequest(
                prompt: "Execute the approved plan.",
                intent: "execute",
                modelId: "composer-2",
                mcpProfileId: "github-tools"
            )
        )

        XCTAssertEqual(response.runId, "run-follow-up")
        let request = try XCTUnwrap(MockBridgeURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.path, "/sdk/sessions/bc-session/messages")
        let body = try XCTUnwrap(request.jsonBody)
        XCTAssertEqual(body["prompt"] as? String, "Execute the approved plan.")
        XCTAssertEqual(body["intent"] as? String, "execute")
        XCTAssertEqual(body["modelId"] as? String, "composer-2")
        XCTAssertEqual(body["mcpProfileId"] as? String, "github-tools")
    }

    func testListMCPProfilesMapsPublicProfileMetadata() async throws {
        MockBridgeURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: [
                "profiles": [
                    [
                        "id": "github-tools",
                        "name": "GitHub Tools",
                        "description": "GitHub MCP and reviewer subagent.",
                        "mcpServerCount": 1,
                        "subagentCount": 1
                    ]
                ]
            ])
        }

        let client = makeClient(apiKey: "cursor-test-key")
        let profiles = try await client.listMCPProfiles()

        XCTAssertEqual(profiles.first?.id, "github-tools")
        XCTAssertEqual(profiles.first?.summary, "1 MCP / 1 subagent")
        let request = try XCTUnwrap(MockBridgeURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url?.path, "/sdk/mcp-profiles")
    }

    func testSessionStateUsesSessionScopedRouteAndEscapesRunQuery() async throws {
        MockBridgeURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: [
                "sessionId": "bc-session",
                "latestRun": [
                    "agentId": "bc-session",
                    "runId": "run&value",
                    "status": "finished"
                ]
            ])
        }

        let client = makeClient(apiKey: "cursor-test-key")
        let state = try await client.sessionState(sessionID: "bc-session", runID: "run&value")

        XCTAssertEqual(state.latestRun?.status, "finished")
        let request = try XCTUnwrap(MockBridgeURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url?.path, "/sdk/sessions/bc-session/state")
        XCTAssertEqual(request.url?.query, "runId=run%26value")
    }

    func testStreamEventsUsesRunEventRouteAndParsesSSE() async throws {
        MockBridgeURLProtocol.handler = { request in
            let payload = """
            id: evt-1
            event: assistant
            data: {"type":"assistant","text":"Working"}

            id: evt-2
            event: done
            data: {}

            """
            return HTTPResponse(
                response: HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!,
                data: Data(payload.utf8)
            )
        }

        let client = makeClient(apiKey: "cursor-test-key")
        let events = try await client.streamEvents(agentID: "agent_123", runID: "run_123")

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.id, "evt-1")
        XCTAssertEqual(events.first?.event, "assistant")
        let request = try XCTUnwrap(MockBridgeURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url?.path, "/agents/agent_123/runs/run_123/events")
        XCTAssertEqual(request.header("Accept"), "text/event-stream")
        XCTAssertEqual(request.header("Authorization"), "Bearer cursor-test-key")
    }

    func testStreamSessionEventsUsesSDKSessionRoute() async throws {
        MockBridgeURLProtocol.handler = { request in
            let payload = """
            id: evt-1
            event: assistant
            data: {"type":"assistant","text":"Working"}

            """
            return HTTPResponse(
                response: HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!,
                data: Data(payload.utf8)
            )
        }

        let client = makeClient(apiKey: "cursor-test-key")
        let events = try await client.streamSessionEvents(sessionID: "bc-session", runID: "run-session")

        XCTAssertEqual(events.first?.event, "assistant")
        let request = try XCTUnwrap(MockBridgeURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url?.path, "/sdk/sessions/bc-session/runs/run-session/events")
        XCTAssertEqual(request.header("Accept"), "text/event-stream")
    }

    private func makeClient(apiKey: String? = nil, bridgeToken: String? = nil) -> SDKBridgeClient {
        SDKBridgeClient(
            baseURL: URL(string: "http://localhost:8787")!,
            apiKey: apiKey,
            bridgeToken: bridgeToken,
            session: makeSession()
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockBridgeURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func jsonResponse(
        for request: URLRequest,
        body: Any,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) throws -> HTTPResponse {
        HTTPResponse(
            response: HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: headers
            )!,
            data: try JSONSerialization.data(withJSONObject: body)
        )
    }
}

private struct HTTPResponse {
    let response: HTTPURLResponse
    let data: Data
}

private struct CapturedHTTPRequest {
    let url: URL?
    let method: String?
    let headers: [String: String]
    let body: Data

    var jsonBody: [String: Any]? {
        guard !body.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    func header(_ name: String) -> String? {
        headers.first { key, _ in
            key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }
}

private final class MockBridgeURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> HTTPResponse)?
    nonisolated(unsafe) static var capturedRequests: [CapturedHTTPRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let body = Self.bodyData(from: request)
            Self.capturedRequests.append(
                CapturedHTTPRequest(
                    url: request.url,
                    method: request.httpMethod,
                    headers: request.allHTTPHeaderFields ?? [:],
                    body: body
                )
            )

            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let output = try handler(request)
            client?.urlProtocol(self, didReceive: output.response, cacheStoragePolicy: .notAllowed)
            if !output.data.isEmpty {
                client?.urlProtocol(self, didLoad: output.data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        handler = nil
        capturedRequests = []
    }

    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }

        return data
    }
}
