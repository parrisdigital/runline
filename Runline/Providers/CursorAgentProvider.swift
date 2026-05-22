import Foundation

@MainActor
final class CursorAgentProvider: AgentProvider, EnterpriseDataProvider {
    let capabilities = ProviderCapabilities(
        supportsRepositoriesList: true,
        supportsSSEStreaming: true,
        supportsWebhooks: true,
        supportsArtifacts: true,
        supportsImagesInPrompt: true,
        supportsAutoCreatePR: true,
        supportsArchive: true,
        supportsDelete: true,
        supportsNativePullRequestReview: false
    )

    private let client: CursorAPIClient
    private var repositoryCache: [Repository] = []
    private var lastStreamEventIDByRunID: [AgentRun.ID: String] = [:]
    private var endpointCacheByID: [CursorAPIEndpoint.ID: CursorAPIEndpointCacheEntry] = [:]

    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.cursor.com")!,
        session: URLSession = .shared
    ) throws {
        client = try CursorAPIClient(apiKey: apiKey, baseURL: baseURL, session: session)
    }

    func validateConnection() async throws -> ProviderAccount {
        let dto: CursorMeDTO = try await client.request("/v1/me")
        return dto.domainModel
    }

    func listRepositories() async throws -> [Repository] {
        let response: CursorListResponse<CursorRepositoryDTO> = try await client.request("/v1/repositories")
        let repositories = response.items.map(\.domainModel)
        repositoryCache = repositories
        return repositories
    }

    func listModels() async throws -> [AgentModel] {
        let response: CursorListResponse<CursorModelDTO> = try await client.request("/v1/models")
        return uniqueModelIDs(["default"] + response.items.map(\.id)).map { modelID in
            AgentModel(
                id: modelID,
                displayName: modelID,
                subtitle: subtitle(for: modelID),
                category: category(for: modelID),
                qualityScore: modelID.contains("thinking") || modelID.contains("gpt-5") ? 5 : 3,
                costTier: modelID.contains("mini") || modelID.contains("fast") ? 1 : 2
            )
        }
    }

    private func uniqueModelIDs(_ modelIDs: [String]) -> [String] {
        var seen = Set<String>()
        return modelIDs.compactMap { modelID in
            let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    func listAgents() async throws -> [Agent] {
        let response: CursorListResponse<CursorAgentDTO> = try await client.request(
            "/v1/agents",
            queryItems: [
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "includeArchived", value: "true"),
            ]
        )

        var agents: [Agent] = []
        for item in response.items {
            if item.source == nil || item.target == nil {
                let detail: CursorAgentDTO = (try? await client.request("/v1/agents/\(item.id)")) ?? item
                agents.append(detail.domainModel(repositoryFallbacks: repositoryCache))
            } else {
                agents.append(item.domainModel(repositoryFallbacks: repositoryCache))
            }
        }
        return agents
    }

    func getAgent(agentID: Agent.ID) async throws -> Agent {
        let detail: CursorAgentDTO = try await client.request("/v1/agents/\(agentID)")
        return detail.domainModel(repositoryFallbacks: repositoryCache)
    }

    func listRuns(agentID: Agent.ID) async throws -> [AgentRun] {
        let response: CursorListResponse<CursorRunDTO> = try await client.request(
            "/v1/agents/\(agentID)/runs",
            queryItems: [
                URLQueryItem(name: "limit", value: "20"),
            ]
        )
        return response.items.map(\.domainModel)
    }

    func getRun(agentID: Agent.ID, runID: AgentRun.ID) async throws -> AgentRun {
        let run: CursorRunDTO = try await client.request("/v1/agents/\(agentID)/runs/\(runID)")
        return run.domainModel
    }

    func streamEvents(agentID: Agent.ID, runID: AgentRun.ID) async throws -> [AgentStreamEvent] {
        let events = try await client.serverSentEvents(
            "/v1/agents/\(agentID)/runs/\(runID)/stream",
            lastEventID: lastStreamEventIDByRunID[runID]
        )
        var mappedEvents: [AgentStreamEvent] = []
        for (index, event) in events.enumerated() {
            let mappedEvent = makeStreamEvent(runID: runID, event: event, fallbackIndex: index)
            if let id = event.id, mappedEvent?.kind != .done {
                lastStreamEventIDByRunID[runID] = id
            }
            if let mappedEvent {
                mappedEvents.append(mappedEvent)
            }
        }
        return mappedEvents
    }

    func createAgent(_ draft: AgentLaunchDraft) async throws -> AgentLaunchResult {
        let request = try makeCreateAgentRequest(from: draft)
        let response: CursorCreateAgentResponse = try await client.request(
            "/v1/agents",
            method: .post,
            body: request
        )
        let agent = response.agent.domainModel(repositoryFallbacks: repositoryCache)
        return AgentLaunchResult(agent: agent, run: response.run.domainModel)
    }

    func createRun(_ draft: AgentFollowUpDraft) async throws -> AgentRun {
        let modelID = draft.modelID?.nilIfBlank
        let model = modelID?.isCursorDefaultModelIdentifier == true ? nil : modelID.map { CursorModelObjectDTO(id: $0) }
        let request = CursorCreateRunRequest(
            prompt: makePromptRequest(from: draft.prompt),
            model: model
        )
        let response: CursorCreateRunResponse = try await client.request(
            "/v1/agents/\(draft.agentID)/runs",
            method: .post,
            body: request
        )
        return response.run.domainModel
    }

    func cancelRun(agentID: Agent.ID, runID: AgentRun.ID) async throws {
        let _: CursorIDResponse = try await client.request(
            "/v1/agents/\(agentID)/runs/\(runID)/cancel",
            method: .post
        )
    }

    func archiveAgent(agentID: Agent.ID) async throws {
        let _: EmptyResponse = try await client.request(
            "/v1/agents/\(agentID)/archive",
            method: .post
        )
    }

    func unarchiveAgent(agentID: Agent.ID) async throws {
        let _: EmptyResponse = try await client.request(
            "/v1/agents/\(agentID)/unarchive",
            method: .post
        )
    }

    func deleteAgent(agentID: Agent.ID) async throws {
        let _: EmptyResponse = try await client.request("/v1/agents/\(agentID)", method: .delete)
    }

    func listArtifacts(agentID: Agent.ID) async throws -> [Artifact] {
        let response: CursorListResponse<CursorArtifactDTO> = try await client.request("/v1/agents/\(agentID)/artifacts")
        return response.items.map(\.domainModel)
    }

    func downloadArtifact(agentID: Agent.ID, path: String) async throws -> ArtifactDownload {
        let response: CursorArtifactDownloadDTO = try await client.request(
            "/v1/agents/\(agentID)/artifacts/download",
            queryItems: [URLQueryItem(name: "path", value: path)]
        )
        return response.domainModel
    }

    var enterpriseEndpoints: [CursorAPIEndpoint] {
        CursorAPIEndpointCatalog.endpoints
    }

    func fetchEndpoint(_ endpoint: CursorAPIEndpoint) async throws -> CursorAPIEndpointResult {
        let cached = endpointCacheByID[endpoint.id]
        let conditionalHeaders = cached.map { ["If-None-Match": $0.etag] } ?? [:]
        let envelope: CursorAPIClient.ResponseEnvelope<JSONValue> = try await client.response(
            endpoint.path,
            method: endpoint.method,
            queryItems: endpoint.queryItems,
            extraHeaders: conditionalHeaders,
            notModifiedFallback: cached?.json
        )

        if envelope.metadata.statusCode == 304, var result = cached?.result {
            result.statusCode = 304
            result.latencyMilliseconds = envelope.metadata.latencyMilliseconds
            result.capturedAt = .now
            return result
        }

        return CursorAPIEndpointResult(
            endpoint: endpoint,
            statusCode: envelope.metadata.statusCode,
            latencyMilliseconds: envelope.metadata.latencyMilliseconds,
            capturedAt: .now,
            etag: envelope.metadata.etag,
            preview: envelope.value.preview(),
            recordCount: envelope.value.recordCount,
            errorMessage: nil
        )
        .cachingIfPossible(
            endpointCache: &endpointCacheByID,
            endpointID: endpoint.id,
            json: envelope.value
        )
    }

    private func makeCreateAgentRequest(from draft: AgentLaunchDraft) throws -> CursorCreateAgentRequest {
        let repo: CursorLaunchRepositoryRequest
        switch draft.source {
        case .repository(let url, let startingRef):
            repo = CursorLaunchRepositoryRequest(url: url.absoluteString, startingRef: startingRef?.nilIfBlank, prUrl: nil)
        case .pullRequest(let url):
            repo = CursorLaunchRepositoryRequest(url: nil, startingRef: nil, prUrl: url.absoluteString)
        }
        let modelID = draft.modelID?.nilIfBlank
        let model = modelID?.isCursorDefaultModelIdentifier == true ? nil : modelID.map { CursorModelObjectDTO(id: $0) }
        return CursorCreateAgentRequest(
            prompt: makePromptRequest(from: draft.prompt),
            model: model,
            repos: [repo],
            branchName: draft.branchName?.nilIfBlank,
            autoGenerateBranch: autoGenerateBranchValue(for: draft),
            autoCreatePR: draft.autoCreatePullRequest,
            skipReviewerRequest: draft.skipReviewerRequest
        )
    }

    private func autoGenerateBranchValue(for draft: AgentLaunchDraft) -> Bool? {
        guard case .pullRequest = draft.source else { return nil }
        return draft.autoGenerateBranch ? nil : false
    }

    private func makePromptRequest(from prompt: AgentPrompt) -> CursorPromptRequest {
        let images = prompt.images.isEmpty ? nil : prompt.images.prefix(5).map { image in
            CursorPromptImageRequest(
                data: image.data.base64EncodedString(),
                dimension: CursorPromptImageDimensionRequest(width: image.width, height: image.height)
            )
        }
        return CursorPromptRequest(text: prompt.textWithFileContext, images: images)
    }

    private func runFromAgent(agentID: Agent.ID) async throws -> AgentRun {
        let agent = try await getAgent(agentID: agentID)
        return run(from: agent)
    }

    private func run(from agent: Agent) -> AgentRun {
        AgentRun(
            id: agent.latestRunID.isEmpty ? agent.id : agent.latestRunID,
            agentID: agent.id,
            status: RunStatus(agentStatus: agent.status, agentID: agent.id),
            createdAtDescription: agent.updatedAtDescription,
            updatedAtDescription: agent.updatedAtDescription
        )
    }

    private func makeStreamEvent(runID: AgentRun.ID, event: ServerSentEvent, fallbackIndex: Int) -> AgentStreamEvent? {
        if event.data == "[DONE]" {
            return AgentStreamEvent(
                id: event.id ?? "\(runID)-done",
                runID: runID,
                kind: .done,
                title: "Done",
                message: "Stream closed",
                timestamp: "now"
            )
        }

        let json = try? JSONDecoder().decode(JSONValue.self, from: Data(event.data.utf8))
        let object = json?.objectValue
        let eventName = event.event ?? object?.stringValue(for: "event") ?? object?.stringValue(for: "type")

        if eventName == "interaction_update", let object {
            return makeInteractionUpdateStreamEvent(runID: runID, event: event, object: object, fallbackIndex: fallbackIndex)
        }

        let kind = StreamEventKind(cursorValue: eventName)
        let content = streamContent(for: kind, eventName: eventName, object: object, json: json)

        return AgentStreamEvent(
            id: object?.stringValue(for: "id") ?? event.id ?? "\(runID)-\(fallbackIndex)",
            runID: runID,
            kind: kind,
            title: content.title,
            message: content.message,
            timestamp: object?.stringValue(for: "timestamp")
                ?? CursorDateParser.relativeDescription(from: object?.stringValue(for: "createdAt"))
        )
    }

    private func makeInteractionUpdateStreamEvent(
        runID: AgentRun.ID,
        event: ServerSentEvent,
        object: [String: JSONValue],
        fallbackIndex: Int
    ) -> AgentStreamEvent? {
        guard let updateType = object.stringValue(for: "type") else { return nil }
        if updateType == "token-delta" {
            return nil
        }

        let content: (kind: StreamEventKind, title: String, message: String)
        switch updateType {
        case "user-message-appended":
            content = (
                .user,
                "User",
                object.objectValue(for: "userMessage")?.stringValue(for: "text")
                    ?? object.objectValue(for: "user_message")?.stringValue(for: "text")
                    ?? "User message appended"
            )
        case "text-delta":
            content = (.assistant, "Assistant", object.stringValue(for: "text") ?? "Assistant output")
        case "thinking-delta":
            content = (.thinking, "Thinking", object.stringValue(for: "text") ?? "Thinking update")
        case "thinking-completed":
            let duration = object.numberValue(for: "thinkingDurationMs")
                ?? object.numberValue(for: "thinking_duration_ms")
            content = (
                .thinking,
                "Thinking Completed",
                duration.map { "Completed in \(Int($0)) ms" } ?? "Thinking completed"
            )
        case "tool-call-started", "partial-tool-call", "tool-call-completed":
            let toolCall = object.objectValue(for: "toolCall")
                ?? object.objectValue(for: "tool_call")
            let toolName = toolCall?.stringValue(for: "name")
                ?? toolCall?.stringValue(for: "type")
                ?? "tool"
            let status = object.stringValue(for: "status")
                ?? (updateType == "tool-call-completed" ? "completed" : "running")
            let details = toolDetailMessage(toolCall: toolCall, status: status)
            content = (.toolCall, displayTitle(from: updateType), "\(toolName): \(details)")
        case "step-started", "step-completed", "turn-ended":
            content = (.task, displayTitle(from: updateType), stepMessage(from: object, fallback: displayTitle(from: updateType)))
        case "summary", "summary-started", "summary-delta", "summary-completed":
            content = (
                .task,
                "Summary",
                object.stringValue(for: "summary")
                    ?? object.stringValue(for: "text")
                    ?? displayTitle(from: updateType)
            )
        case "shell-output-delta":
            content = (
                .task,
                "Shell Output",
                object.stringValue(for: "text")
                    ?? object.stringValue(for: "stdout")
                    ?? object.stringValue(for: "stderr")
                    ?? "Shell output updated"
            )
        default:
            content = (.unknown, displayTitle(from: updateType), JSONValue.object(object).previewLine())
        }

        return AgentStreamEvent(
            id: object.stringValue(for: "id") ?? event.id ?? "\(runID)-\(fallbackIndex)",
            runID: runID,
            kind: content.kind,
            title: content.title,
            message: content.message,
            timestamp: object.stringValue(for: "timestamp")
                ?? CursorDateParser.relativeDescription(from: object.stringValue(for: "createdAt"))
        )
    }

    private func streamContent(
        for kind: StreamEventKind,
        eventName: String?,
        object: [String: JSONValue]?,
        json: JSONValue?
    ) -> (title: String, message: String) {
        let title = object?.stringValue(for: "title") ?? displayTitle(from: eventName ?? "event")

        switch kind {
        case .system:
            return (title, object?.stringValue(for: "subtype") ?? "Run metadata received")
        case .user:
            return ("User", textContent(from: object) ?? "User message received")
        case .assistant:
            return ("Assistant", textContent(from: object) ?? "Assistant output")
        case .thinking:
            return ("Thinking", textContent(from: object) ?? "Thinking update")
        case .toolCall:
            let toolObject = object?.objectValue(for: "data") ?? object
            let name = toolObject?.stringValue(for: "name")
                ?? toolObject?.stringValue(for: "type")
                ?? "tool"
            let status = toolObject?.stringValue(for: "status") ?? "running"
            return ("Tool Call", "\(name): \(toolDetailMessage(toolCall: toolObject, status: status))")
        case .status:
            return ("Status", object?.stringValue(for: "message") ?? object?.stringValue(for: "status") ?? "Status update")
        case .task:
            return ("Task", textContent(from: object) ?? object?.stringValue(for: "status") ?? "Task update")
        case .request:
            return ("Request", object?.stringValue(for: "message") ?? "Cursor is waiting for input or approval.")
        case .result:
            return ("Result", object?.stringValue(for: "result") ?? object?.stringValue(for: "text") ?? object?.stringValue(for: "status") ?? "Run result received")
        case .heartbeat:
            return ("Heartbeat", "Cursor stream heartbeat")
        case .error:
            let code = object?.stringValue(for: "code") ?? "UNKNOWN"
            let message = object?.stringValue(for: "message") ?? "Unknown stream error"
            return ("Error", "[\(code)] \(message)")
        case .done:
            return ("Done", "Stream closed")
        case .unknown:
            return (title, textContent(from: object) ?? json?.previewLine() ?? "Stream event received")
        }
    }

    private func textContent(from object: [String: JSONValue]?) -> String? {
        guard let object else { return nil }
        if let text = object.stringValue(for: "text") {
            return text
        }
        if let message = object.stringValue(for: "message") {
            return message
        }
        if let message = object.objectValue(for: "message"),
           let content = message.arrayValue(for: "content") {
            let text = content.compactMap { block -> String? in
                if let value = block.stringValue {
                    return value
                }
                return block.objectValue?.stringValue(for: "text")
            }
            .joined()
            if !text.isEmpty {
                return text
            }
        }
        if let userMessage = object.objectValue(for: "userMessage")
            ?? object.objectValue(for: "user_message") {
            return userMessage.stringValue(for: "text")
        }
        return nil
    }

    private func toolDetailMessage(toolCall: [String: JSONValue]?, status: String) -> String {
        var parts = [status]
        if let args = toolCall?["args"] ?? toolCall?["input"] {
            parts.append("args \(args.previewLine(maxLength: 120))")
        }
        if let result = toolCall?["result"] {
            parts.append("result \(result.previewLine(maxLength: 120))")
        }
        return parts.joined(separator: " - ")
    }

    private func stepMessage(from object: [String: JSONValue], fallback: String) -> String {
        if let step = object.objectValue(for: "step") {
            return step.stringValue(for: "type")
                ?? step.stringValue(for: "status")
                ?? JSONValue.object(step).previewLine()
        }
        return object.stringValue(for: "status") ?? fallback
    }

    private func displayTitle(from value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + String(word.dropFirst())
            }
            .joined(separator: " ")
    }

    private func category(for modelID: String) -> AgentModel.Category {
        if modelID == "default" {
            return .default
        }
        if modelID.contains("mini") || modelID.contains("fast") {
            return .fast
        }
        return .coding
    }

    private func subtitle(for modelID: String) -> String {
        if modelID == "default" {
            return "Cursor configured default"
        }
        if modelID.contains("thinking") {
            return "Deep reasoning"
        }
        if modelID.contains("mini") || modelID.contains("fast") {
            return "Lower latency"
        }
        return "Cloud Agent model"
    }

    private func repositoryURL(fromPullRequestURL url: URL) -> URL? {
        let components = url.path.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return nil }
        let owner = components[0]
        let repository = components[1]
        var urlComponents = URLComponents()
        urlComponents.scheme = url.scheme
        urlComponents.host = url.host
        urlComponents.path = "/\(owner)/\(repository)"
        return urlComponents.url
    }
}

private extension CursorAPIEndpointResult {
    func cachingIfPossible(
        endpointCache: inout [CursorAPIEndpoint.ID: CursorAPIEndpointCacheEntry],
        endpointID: CursorAPIEndpoint.ID,
        json: JSONValue
    ) -> CursorAPIEndpointResult {
        guard let etag else { return self }
        endpointCache[endpointID] = CursorAPIEndpointCacheEntry(etag: etag, json: json, result: self)
        return self
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let object) = self {
            return object
        }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    func stringValue(for key: String) -> String? {
        objectValue?[key]?.stringValue
    }

    func objectValue(for key: String) -> [String: JSONValue]? {
        objectValue?[key]?.objectValue
    }

    func arrayValue(for key: String) -> [JSONValue]? {
        if case .array(let values)? = objectValue?[key] {
            return values
        }
        return nil
    }

    func numberValue(for key: String) -> Double? {
        if case .number(let value)? = objectValue?[key] {
            return value
        }
        return nil
    }

    func previewLine(maxLength: Int = 180) -> String {
        let flattened = preview(maxLines: 4)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        if flattened.count <= maxLength {
            return flattened
        }
        return String(flattened.prefix(maxLength)) + "..."
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func stringValue(for key: String) -> String? {
        self[key]?.stringValue
    }

    func objectValue(for key: String) -> [String: JSONValue]? {
        self[key]?.objectValue
    }

    func arrayValue(for key: String) -> [JSONValue]? {
        if case .array(let values)? = self[key] {
            return values
        }
        return nil
    }

    func numberValue(for key: String) -> Double? {
        if case .number(let value)? = self[key] {
            return value
        }
        return nil
    }
}
