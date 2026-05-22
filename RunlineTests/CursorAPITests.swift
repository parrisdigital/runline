import Foundation
import XCTest
@testable import Runline

final class CursorAPITests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    @MainActor
    func testValidateConnectionUsesBasicAuthAndMeEndpoint() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(
                for: request,
                body: [
                    "apiKeyName": "Runline Test Key",
                    "createdAt": "2026-04-27T12:00:00Z",
                    "userEmail": "developer@example.com"
                ]
            )
        }

        let provider = try makeProvider(apiKey: "cursor-test-key")
        let account = try await provider.validateConnection()

        XCTAssertEqual(account.apiKeyName, "Runline Test Key")
        XCTAssertEqual(account.userEmail, "developer@example.com")

        let captured = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(captured.method, "GET")
        XCTAssertEqual(captured.url?.path, "/v1/me")
        XCTAssertEqual(captured.header("Accept"), "application/json")
        XCTAssertEqual(captured.header("Authorization"), "Basic \(Data("cursor-test-key:".utf8).base64EncodedString())")
    }

    @MainActor
    func testValidateConnectionAllowsMissingUserEmail() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(
                for: request,
                body: [
                    "apiKeyName": "Runline Test Key",
                    "createdAt": "2026-04-27T12:00:00Z"
                ]
            )
        }

        let provider = try makeProvider(apiKey: "cursor-test-key")
        let account = try await provider.validateConnection()

        XCTAssertEqual(account.apiKeyName, "Runline Test Key")
        XCTAssertEqual(account.userEmail, "Email unavailable")
    }

    @MainActor
    func testValidateConnectionAllowsNestedAPIKeyMetadata() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(
                for: request,
                body: [
                    "apiKey": [
                        "name": "Runline Service Account",
                        "createdAt": "2026-04-27T12:00:00Z"
                    ],
                    "user": [
                        "email": "service@example.com"
                    ]
                ]
            )
        }

        let provider = try makeProvider(apiKey: "cursor-test-key")
        let account = try await provider.validateConnection()

        XCTAssertEqual(account.apiKeyName, "Runline Service Account")
        XCTAssertEqual(account.userEmail, "service@example.com")
    }

    @MainActor
    func testDecodeFailuresIncludeEndpointDiagnostics() async throws {
        MockURLProtocol.handler = { request in
            HTTPResponse(
                response: HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "application/json",
                        "X-Request-ID": "req-decode"
                    ]
                )!,
                data: Data("[1,2,3]".utf8)
            )
        }
        let client = try makeClient()

        do {
            let _: CursorMeDTO = try await client.request("/v1/me")
            XCTFail("Expected a decode failure.")
        } catch CursorAPIError.decodingFailed(let message) {
            XCTAssertTrue(message.contains("endpoint=/v1/me"))
            XCTAssertTrue(message.contains("type=CursorMeDTO"))
            XCTAssertTrue(message.contains("requestID=req-decode"))
            XCTAssertTrue(message.contains("preview=[1,2,3]"))
        }
    }

    @MainActor
    func testListModelsAcceptsObjectResponsesAndSkipsMalformedItems() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(
                for: request,
                body: [
                    "models": [
                        "default",
                        [
                            "id": "gpt-5.4-high"
                        ],
                        [
                            "model": "claude-4.6-opus-high-thinking"
                        ],
                        [
                            "unexpected": "missing-id"
                        ]
                    ]
                ]
            )
        }

        let provider = try makeProvider()
        let models = try await provider.listModels()

        XCTAssertEqual(models.map(\.id), [
            "default",
            "gpt-5.4-high",
            "claude-4.6-opus-high-thinking"
        ])
    }

    @MainActor
    func testListAgentsToleratesAlternateModelShape() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: [
                "agents": [
                    [
                        "id": "bc-model-object",
                        "name": "Model object",
                        "status": "FINISHED",
                        "source": [
                            "repository": "https://github.com/acme/app",
                            "ref": "main"
                        ],
                        "target": [
                            "branchName": "cursor/model-object",
                            "prUrl": "https://github.com/acme/app/pull/42"
                        ],
                        "model": [
                            "name": "gpt-5.4-high"
                        ],
                        "createdAt": "2026-04-27T12:00:00Z"
                    ]
                ],
                "nextCursor": NSNull()
            ])
        }

        let provider = try makeProvider()
        let agents = try await provider.listAgents()

        XCTAssertEqual(agents.first?.id, "bc-model-object")
        XCTAssertEqual(agents.first?.modelID, "gpt-5.4-high")
    }

    @MainActor
    func testRunHistoryAcceptsAlternateRunKeys() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: [
                "runs": [
                    [
                        "runId": "run-alt",
                        "agent_id": "bc-alt",
                        "status": "FINISHED",
                        "created_at": "2026-04-27T12:00:00Z",
                        "updated_at": "2026-04-27T12:10:00Z"
                    ]
                ],
                "nextCursor": NSNull()
            ])
        }

        let provider = try makeProvider()
        let runs = try await provider.listRuns(agentID: "bc-alt")

        XCTAssertEqual(runs.first?.id, "run-alt")
        XCTAssertEqual(runs.first?.agentID, "bc-alt")
        XCTAssertEqual(runs.first?.status, .finished)
    }

    @MainActor
    func testCreateAgentUsesCursorV1LaunchSchema() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: Self.createAgentResponse(id: "bc-123", runID: "run-123", status: "CREATING"))
        }
        let provider = try makeProvider()
        let draft = AgentLaunchDraft(
            prompt: AgentPrompt(text: "Add regression tests for login."),
            modelID: "gpt-5.2",
            source: .repository(url: URL(string: "https://github.com/acme/app")!, startingRef: "main"),
            branchName: "runline/login-regression",
            autoGenerateBranch: true,
            autoCreatePullRequest: true,
            skipReviewerRequest: false
        )

        let result = try await provider.createAgent(draft)

        XCTAssertEqual(result.agent.id, "bc-123")
        XCTAssertEqual(result.run.id, "run-123")

        let captured = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(captured.method, "POST")
        XCTAssertEqual(captured.url?.path, "/v1/agents")

        let body = try XCTUnwrap(captured.jsonBody)
        let prompt = try XCTUnwrap(body["prompt"] as? [String: Any])
        XCTAssertEqual(prompt["text"] as? String, "Add regression tests for login.")
        let model = try XCTUnwrap(body["model"] as? [String: Any])
        XCTAssertEqual(model["id"] as? String, "gpt-5.2")

        let repos = try XCTUnwrap(body["repos"] as? [[String: Any]])
        XCTAssertEqual(repos.first?["url"] as? String, "https://github.com/acme/app")
        XCTAssertEqual(repos.first?["startingRef"] as? String, "main")
        XCTAssertNil(repos.first?["prUrl"])
        XCTAssertEqual(body["branchName"] as? String, "runline/login-regression")
        XCTAssertNil(body["autoGenerateBranch"])
        XCTAssertEqual(body["autoCreatePR"] as? Bool, true)
        XCTAssertEqual(body["skipReviewerRequest"] as? Bool, false)
    }

    @MainActor
    func testCreateAgentOmitsRefWhenBranchIsUnknown() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: Self.createAgentResponse(id: "bc-no-ref", runID: "run-no-ref", status: "CREATING"))
        }
        let provider = try makeProvider()
        let draft = AgentLaunchDraft(
            prompt: AgentPrompt(text: "Build a simple HTML website."),
            modelID: "default",
            source: .repository(url: URL(string: "https://github.com/parrisdigital/cursor-cloud-test")!, startingRef: nil),
            branchName: nil,
            autoGenerateBranch: true,
            autoCreatePullRequest: true,
            skipReviewerRequest: false
        )

        _ = try await provider.createAgent(draft)

        let body = try XCTUnwrap(MockURLProtocol.capturedRequests.first?.jsonBody)
        XCTAssertNil(body["model"])
        let repos = try XCTUnwrap(body["repos"] as? [[String: Any]])
        XCTAssertEqual(repos.first?["url"] as? String, "https://github.com/parrisdigital/cursor-cloud-test")
        XCTAssertNil(repos.first?["startingRef"])
    }

    @MainActor
    func testCreateAgentUsesManualWorkingBranchWhenAutoNamingIsDisabled() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: Self.createAgentResponse(id: "bc-manual-branch", runID: "run-manual-branch", status: "CREATING"))
        }
        let provider = try makeProvider()
        let draft = AgentLaunchDraft(
            prompt: AgentPrompt(text: "Build a settings polish pass."),
            modelID: "default",
            source: .repository(url: URL(string: "https://github.com/acme/app")!, startingRef: "main"),
            branchName: "runline/settings-polish",
            autoGenerateBranch: false,
            autoCreatePullRequest: false,
            skipReviewerRequest: nil
        )

        _ = try await provider.createAgent(draft)

        let body = try XCTUnwrap(MockURLProtocol.capturedRequests.first?.jsonBody)
        XCTAssertEqual(body["branchName"] as? String, "runline/settings-polish")
        XCTAssertNil(body["autoGenerateBranch"])
        XCTAssertEqual(body["autoCreatePR"] as? Bool, false)
        XCTAssertNil(body["skipReviewerRequest"])
    }

    @MainActor
    func testCreateRunUsesFollowUpEndpointAndPromptSchema() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: [
                "run": [
                    "id": "run-456",
                    "agentId": "bc-123",
                    "status": "CREATING",
                    "createdAt": "2026-04-27T12:00:00Z",
                    "updatedAt": "2026-04-27T12:00:01Z"
                ]
            ])
        }
        let provider = try makeProvider()

        let run = try await provider.createRun(
            AgentFollowUpDraft(
                agentID: "agent_123",
                prompt: AgentPrompt(text: "Continue with the failing test output.")
            )
        )

        XCTAssertEqual(run.id, "run-456")
        let captured = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(captured.method, "POST")
        XCTAssertEqual(captured.url?.path, "/v1/agents/agent_123/runs")

        let body = try XCTUnwrap(captured.jsonBody)
        let prompt = try XCTUnwrap(body["prompt"] as? [String: Any])
        XCTAssertEqual(prompt["text"] as? String, "Continue with the failing test output.")
        XCTAssertNil(body["repos"])
        XCTAssertNil(body["source"])
        XCTAssertNil(body["target"])
    }

    @MainActor
    func testCreateRunCanSelectCloudModel() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: [
                "run": [
                    "id": "run-model",
                    "agentId": "bc-123",
                    "status": "CREATING",
                    "createdAt": "2026-04-27T12:00:00Z",
                    "updatedAt": "2026-04-27T12:00:01Z"
                ]
            ])
        }
        let provider = try makeProvider()

        _ = try await provider.createRun(
            AgentFollowUpDraft(
                agentID: "agent_123",
                prompt: AgentPrompt(text: "Continue with Composer."),
                modelID: "composer-2"
            )
        )

        let body = try XCTUnwrap(MockURLProtocol.capturedRequests.first?.jsonBody)
        let model = try XCTUnwrap(body["model"] as? [String: Any])
        XCTAssertEqual(model["id"] as? String, "composer-2")
    }

    @MainActor
    func testCreateRunIncludesTextFileContextInPromptText() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: [
                "run": [
                    "id": "run-files",
                    "agentId": "bc-123",
                    "status": "CREATING",
                    "createdAt": "2026-04-27T12:00:00Z",
                    "updatedAt": "2026-04-27T12:00:01Z"
                ]
            ])
        }
        let provider = try makeProvider()

        _ = try await provider.createRun(
            AgentFollowUpDraft(
                agentID: "agent_123",
                prompt: AgentPrompt(
                    text: "Review this attached file.",
                    files: [
                        PromptFile(
                            filename: "AppState.swift",
                            contentType: "public.swift-source",
                            text: "final class AppState {}",
                            byteCount: 23
                        )
                    ]
                )
            )
        )

        let body = try XCTUnwrap(MockURLProtocol.capturedRequests.first?.jsonBody)
        let prompt = try XCTUnwrap(body["prompt"] as? [String: Any])
        let text = try XCTUnwrap(prompt["text"] as? String)
        XCTAssertTrue(text.contains("Review this attached file."))
        XCTAssertTrue(text.contains("Attached file context:"))
        XCTAssertTrue(text.contains(#"<attached_file name="AppState.swift""#))
        XCTAssertTrue(text.contains("final class AppState {}"))
    }

    @MainActor
    func testCreateAgentFromPullRequestUsesPrURLSource() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(
                for: request,
                body: Self.createAgentResponse(
                    id: "bc-pr",
                    runID: "run-pr",
                    status: "CREATING",
                    repos: [
                        [
                            "prUrl": "https://github.com/acme/app/pull/42"
                        ]
                    ]
                )
            )
        }
        let provider = try makeProvider()
        let draft = AgentLaunchDraft(
            prompt: AgentPrompt(text: "Continue this PR."),
            modelID: "default",
            source: .pullRequest(url: URL(string: "https://github.com/acme/app/pull/42")!),
            branchName: nil,
            autoGenerateBranch: true,
            autoCreatePullRequest: true,
            skipReviewerRequest: true
        )

        let result = try await provider.createAgent(draft)

        XCTAssertEqual(result.agent.repository.displayName, "acme/app")

        let body = try XCTUnwrap(MockURLProtocol.capturedRequests.first?.jsonBody)
        let repos = try XCTUnwrap(body["repos"] as? [[String: Any]])
        XCTAssertNil(repos.first?["url"])
        XCTAssertEqual(repos.first?["prUrl"] as? String, "https://github.com/acme/app/pull/42")
        XCTAssertNil(body["autoGenerateBranch"])
        XCTAssertEqual(body["skipReviewerRequest"] as? Bool, true)
    }

    @MainActor
    func testRunHistoryUsesV1RunEndpoints() async throws {
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            if request.url?.path == "/v1/agents/bc-123/runs/run-123" {
                return try Self.jsonResponse(for: request, body: [
                    "id": "run-123",
                    "agentId": "bc-123",
                    "status": "FINISHED",
                    "createdAt": "2026-04-27T12:00:00Z",
                    "updatedAt": "2026-04-27T12:10:00Z"
                ])
            }

            return try Self.jsonResponse(for: request, body: [
                "items": [
                    [
                        "id": "run-123",
                        "agentId": "bc-123",
                        "status": "RUNNING",
                        "createdAt": "2026-04-27T12:00:00Z",
                        "updatedAt": "2026-04-27T12:01:00Z"
                    ]
                ],
                "nextCursor": NSNull()
            ])
        }
        let provider = try makeProvider()

        let runs = try await provider.listRuns(agentID: "bc-123")
        let run = try await provider.getRun(agentID: "bc-123", runID: "run-123")

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(runs.first?.id, "run-123")
        XCTAssertEqual(runs.first?.status, .running)
        XCTAssertEqual(run.status, .finished)
        XCTAssertEqual(MockURLProtocol.capturedRequests[0].url?.path, "/v1/agents/bc-123/runs")
        XCTAssertEqual(MockURLProtocol.capturedRequests[1].url?.path, "/v1/agents/bc-123/runs/run-123")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(MockURLProtocol.capturedRequests[0].url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "limit" })?.value, "20")
    }

    @MainActor
    func testStreamEventsUsesRunScopedSSEAndResumeHeader() async throws {
        MockURLProtocol.handler = { request in
            let payload: String
            if request.value(forHTTPHeaderField: "Last-Event-ID") == "evt-1" {
                payload = """
                id: evt-2
                event: result
                data: {"runId":"run-123","status":"FINISHED"}

                """
            } else {
                payload = """
                id: evt-1
                event: assistant
                data: {"text":"I will update the tests."}

                """
            }

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
        let provider = try makeProvider()

        let firstEvents = try await provider.streamEvents(agentID: "bc-123", runID: "run-123")
        let secondEvents = try await provider.streamEvents(agentID: "bc-123", runID: "run-123")

        XCTAssertEqual(firstEvents.first?.kind, .assistant)
        XCTAssertEqual(firstEvents.first?.message, "I will update the tests.")
        XCTAssertEqual(secondEvents.first?.kind, .result)
        XCTAssertEqual(MockURLProtocol.capturedRequests.map { $0.url?.path }, [
            "/v1/agents/bc-123/runs/run-123/stream",
            "/v1/agents/bc-123/runs/run-123/stream"
        ])
        XCTAssertNil(MockURLProtocol.capturedRequests[0].header("Last-Event-ID"))
        XCTAssertEqual(MockURLProtocol.capturedRequests[1].header("Last-Event-ID"), "evt-1")
        XCTAssertEqual(MockURLProtocol.capturedRequests[0].header("Accept"), "text/event-stream")
    }

    @MainActor
    func testStreamEventsNormalizeInteractionUpdates() async throws {
        MockURLProtocol.handler = { request in
            let payload = [
                "id: evt-user",
                "event: interaction_update",
                #"data: {"type":"user-message-appended","userMessage":{"text":"Refine the timeout handling."}}"#,
                "",
                "id: evt-text",
                "event: interaction_update",
                #"data: {"type":"text-delta","text":"Searching"}"#,
                "",
                "id: evt-token",
                "event: interaction_update",
                #"data: {"type":"token-delta","tokens":2}"#,
                "",
                "id: evt-tool",
                "event: interaction_update",
                #"data: {"type":"tool-call-started","callId":"call-1","toolCall":{"name":"read_file","args":{"path":"Runline/App/AppState.swift"}}}"#,
                "",
            ].joined(separator: "\n")
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
        let provider = try makeProvider()

        let events = try await provider.streamEvents(agentID: "bc-123", runID: "run-123")

        XCTAssertEqual(events.map(\.kind), [.user, .assistant, .toolCall])
        XCTAssertEqual(events[0].message, "Refine the timeout handling.")
        XCTAssertEqual(events[1].message, "Searching")
        XCTAssertTrue(events[2].message.contains("read_file"))
        XCTAssertTrue(events[2].message.contains("AppState.swift"))
    }

    @MainActor
    func testStreamEventsNormalizeStructuredMessages() async throws {
        MockURLProtocol.handler = { request in
            let payload = [
                "id: evt-assistant",
                "event: assistant",
                #"data: {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I will update the tests."}]}}"#,
                "",
                "id: evt-task",
                "event: task",
                #"data: {"type":"task","text":"Summarizing changes"}"#,
                "",
                "id: evt-request",
                "event: request",
                #"data: {"type":"request","request_id":"req-1"}"#,
                "",
            ].joined(separator: "\n")
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
        let provider = try makeProvider()

        let events = try await provider.streamEvents(agentID: "bc-123", runID: "run-123")

        XCTAssertEqual(events.map(\.kind), [.assistant, .task, .request])
        XCTAssertEqual(events[0].message, "I will update the tests.")
        XCTAssertEqual(events[1].message, "Summarizing changes")
        XCTAssertEqual(events[2].message, "Cursor is waiting for input or approval.")
    }

    @MainActor
    func testLifecycleEndpointsUseDocumentedRoutes() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(for: request, body: ["id": "agent_123"])
        }
        let provider = try makeProvider()

        try await provider.cancelRun(agentID: "agent_123", runID: "agent_123")
        try await provider.archiveAgent(agentID: "agent_123")
        try await provider.unarchiveAgent(agentID: "agent_123")
        try await provider.deleteAgent(agentID: "agent_123")

        XCTAssertEqual(MockURLProtocol.capturedRequests.map(\.method), ["POST", "POST", "POST", "DELETE"])
        XCTAssertEqual(
            MockURLProtocol.capturedRequests.map { $0.url?.path },
            [
                "/v1/agents/agent_123/runs/agent_123/cancel",
                "/v1/agents/agent_123/archive",
                "/v1/agents/agent_123/unarchive",
                "/v1/agents/agent_123"
            ]
        )
    }

    func testNotFoundErrorPreservesCursorMessage() {
        let error = CursorAPIError.requestFailed(statusCode: 404, message: "Agent not found or access denied")

        XCTAssertEqual(error.userMessage, "Agent not found or access denied")
        XCTAssertTrue(error.isNotFound)
    }

    func testStreamExpiredErrorIsRecognized() {
        let error = CursorAPIError.requestFailed(statusCode: 410, message: "stream_expired")

        XCTAssertTrue(error.isStreamExpired)
        XCTAssertFalse(error.isNotFound)
    }

    func testEmptyRepositoryErrorShowsActionableMessage() {
        let error = CursorAPIError.requestFailed(
            statusCode: 404,
            message: "Resource not found.: Failed to fetch branch/tag ref main from GitHub: HttpError: Git Repository is empty."
        )

        XCTAssertEqual(
            error.userMessage,
            "This repository is empty or the selected branch does not exist. Add an initial commit on GitHub, then refresh repositories and launch again."
        )
    }

    @MainActor
    func testArtifactDownloadUsesPathQueryAndMapsPresignedURL() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(
                for: request,
                body: [
                    "url": "https://download.cursor.test/artifacts/build.log",
                    "expiresAt": "2026-04-27T12:05:00Z"
                ]
            )
        }
        let provider = try makeProvider()

        let download = try await provider.downloadArtifact(agentID: "agent_123", path: "logs/build.log")

        XCTAssertEqual(download.url.absoluteString, "https://download.cursor.test/artifacts/build.log")
        let captured = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(captured.method, "GET")
        XCTAssertEqual(captured.url?.path, "/v1/agents/agent_123/artifacts/download")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(captured.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "path" })?.value, "logs/build.log")
    }

    @MainActor
    func testEnterpriseEndpointFetchUsesDocumentedAnalyticsRoute() async throws {
        MockURLProtocol.handler = { request in
            try Self.jsonResponse(
                for: request,
                body: [
                    "data": [
                        "activeUsers": 12,
                        "period": "14d"
                    ]
                ],
                headers: [
                    "Content-Type": "application/json",
                    "ETag": "analytics-etag"
                ]
            )
        }
        let provider = try makeProvider()
        let endpoint = try XCTUnwrap(CursorAPIEndpointCatalog.endpoints.first { $0.title == "Daily Active Users" })

        let result = try await provider.fetchEndpoint(endpoint)

        let captured = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(captured.method, "GET")
        XCTAssertEqual(captured.url?.path, "/analytics/team/dau")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(captured.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "startDate" })?.value, "14d")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "endDate" })?.value, "today")
        XCTAssertEqual(captured.header("Authorization"), "Basic \(Data("cursor-test-key:".utf8).base64EncodedString())")
        XCTAssertEqual(result.statusCode, 200)
        XCTAssertEqual(result.etag, "analytics-etag")
        XCTAssertTrue(result.preview.contains("activeUsers"))
    }

    @MainActor
    func testEnterpriseEndpointFetchUsesETagCacheForNotModifiedResponse() async throws {
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            if requestCount == 1 {
                return try Self.jsonResponse(
                    for: request,
                    body: [
                        "data": [
                            "activeUsers": 12,
                            "period": "14d"
                        ]
                    ],
                    headers: [
                        "Content-Type": "application/json",
                        "ETag": "analytics-etag"
                    ]
                )
            }

            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "analytics-etag")
            return HTTPResponse(
                response: HTTPURLResponse(
                    url: request.url!,
                    statusCode: 304,
                    httpVersion: nil,
                    headerFields: [
                        "ETag": "analytics-etag"
                    ]
                )!,
                data: Data()
            )
        }
        let provider = try makeProvider()
        let endpoint = try XCTUnwrap(CursorAPIEndpointCatalog.endpoints.first { $0.title == "Daily Active Users" })

        let firstResult = try await provider.fetchEndpoint(endpoint)
        let secondResult = try await provider.fetchEndpoint(endpoint)

        XCTAssertEqual(firstResult.statusCode, 200)
        XCTAssertEqual(secondResult.statusCode, 304)
        XCTAssertTrue(secondResult.preview.contains("activeUsers"))
        XCTAssertEqual(requestCount, 2)
    }

    func testPushPayloadUsesDeepLinksWithoutPromptText() throws {
        let payload = RunlinePushPayload(
            event: .runFinished,
            agentID: "agent_123",
            runID: "run_123",
            artifactPath: "artifacts/build.log",
            pullRequestURL: URL(string: "https://github.com/acme/app/pull/42")
        )

        let data = try JSONEncoder().encode(payload)
        let encoded = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(payload.deepLinkURL.absoluteString, "runline://agents/agent_123/runs/run_123")
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("prompt"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("transcript"))
    }

    func testDeviceTokenHexEncoding() {
        XCTAssertEqual(Data([0, 15, 16, 255]).hexadecimalString, "000f10ff")
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

    private static func createAgentResponse(
        id: String,
        runID: String,
        status: String,
        repos: [[String: Any]] = [
            [
                "url": "https://github.com/acme/app",
                "startingRef": "main"
            ]
        ]
    ) -> [String: Any] {
        [
            "agent": [
                "id": id,
                "name": "Login regression",
                "status": "ACTIVE",
                "repos": repos,
                "branchName": "runline/login-regression",
                "model": "gpt-5.2",
                "url": "https://cursor.com/agents?id=\(id)",
                "pullRequestUrl": "https://github.com/acme/app/pull/42",
                "createdAt": "2026-04-27T12:00:00Z",
                "updatedAt": "2026-04-27T12:00:01Z",
                "latestRunId": runID
            ],
            "run": [
                "id": runID,
                "agentId": id,
                "status": status,
                "createdAt": "2026-04-27T12:00:00Z",
                "updatedAt": "2026-04-27T12:00:01Z"
            ]
        ]
    }

    @MainActor
    private func makeProvider(
        apiKey: String = "cursor-test-key",
        baseURL: URL = URL(string: "https://api.cursor.test")!
    ) throws -> CursorAgentProvider {
        try CursorAgentProvider(apiKey: apiKey, baseURL: baseURL, session: makeSession())
    }

    private func makeClient(
        apiKey: String = "cursor-test-key",
        baseURL: URL = URL(string: "https://api.cursor.test")!
    ) throws -> CursorAPIClient {
        try CursorAPIClient(apiKey: apiKey, baseURL: baseURL, session: makeSession())
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
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

private final class MockURLProtocol: URLProtocol {
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
