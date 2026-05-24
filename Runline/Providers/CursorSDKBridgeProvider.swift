import Foundation

@MainActor
final class CursorSDKBridgeProvider: AgentProvider {
    let capabilities = ProviderCapabilities(
        supportsRepositoriesList: true,
        supportsSSEStreaming: true,
        supportsWebhooks: false,
        supportsArtifacts: true,
        supportsImagesInPrompt: true,
        supportsAutoCreatePR: true,
        supportsArchive: false,
        supportsDelete: false,
        supportsNativePullRequestReview: false,
        supportsSDKBridge: true,
        supportsLiveWorkspace: true,
        supportsPRMetadata: true
    )

    private let client: SDKBridgeClient
    private var repositoryCache: [Repository] = []
    private var lastStreamEventIDByRunID: [AgentRun.ID: String] = [:]

    init(apiKey: String, bridgeBaseURL: URL, bridgeSecret: String? = nil, session: URLSession = .shared) throws {
        client = try SDKBridgeClient(baseURL: bridgeBaseURL, apiKey: apiKey, bridgeSecret: bridgeSecret, session: session)
    }

    func validateConnection() async throws -> ProviderAccount {
        try await client.validateConnection().domainModel
    }

    func listRepositories() async throws -> [Repository] {
        let repositories = try await client.listRepositories().items.compactMap(\.domainModel)
        repositoryCache = repositories
        return repositories
    }

    func listModels() async throws -> [AgentModel] {
        let models = try await client.listModels().items.map(\.domainModel)
        return models.isEmpty ? [Self.defaultModel] : models
    }

    func listAgents() async throws -> [Agent] {
        try await client.listSessions().items.map { $0.domainAgent(repositoryFallbacks: repositoryCache) }
    }

    func getAgent(agentID: Agent.ID) async throws -> Agent {
        try await client.sessionState(sessionID: agentID).session.domainAgent(repositoryFallbacks: repositoryCache)
    }

    func listRuns(agentID: Agent.ID) async throws -> [AgentRun] {
        try await client.sessionState(sessionID: agentID).session.runs.map(\.domainRun)
    }

    func getRun(agentID: Agent.ID, runID: AgentRun.ID) async throws -> AgentRun {
        let runs = try await listRuns(agentID: agentID)
        guard let run = runs.first(where: { $0.id == runID }) else {
            throw SDKBridgeError.requestFailed(statusCode: 404, message: "Run not found.")
        }
        return run
    }

    func streamEvents(agentID: Agent.ID, runID: AgentRun.ID) async throws -> [AgentStreamEvent] {
        let events = try await client.streamEvents(
            sessionID: agentID,
            runID: runID,
            lastEventID: lastStreamEventIDByRunID[runID]
        )
        for event in events where event.id != nil && event.event != "done" {
            lastStreamEventIDByRunID[runID] = event.id
        }
        return SDKBridgeEventMapper.events(from: events, runID: runID)
    }

    func createAgent(_ draft: AgentLaunchDraft) async throws -> AgentLaunchResult {
        let response = try await client.createSession(makeSessionStartRequest(from: draft))
        let state = try? await client.sessionState(sessionID: response.sessionId)
        let agent = state?.session.domainAgent(repositoryFallbacks: repositoryCache)
            ?? fallbackAgent(from: draft, response: response)
        let run = state?.latestRun?.domainRun
            ?? AgentRun(id: response.runId, agentID: response.agentId, status: .running, createdAtDescription: "now", updatedAtDescription: "now")
        return AgentLaunchResult(agent: agent, run: run)
    }

    func createRun(_ draft: AgentFollowUpDraft) async throws -> AgentRun {
        let response = try await client.sendMessage(
            sessionID: draft.agentID,
            body: SDKBridgeMessageRequest(
                prompt: draft.prompt.textWithFileContext,
                images: makeImages(from: draft.prompt),
                modelId: modelIDForBridge(draft.modelID)
            )
        )
        return AgentRun(id: response.runId, agentID: response.agentId, status: .running, createdAtDescription: "now", updatedAtDescription: "now")
    }

    func cancelRun(agentID: Agent.ID, runID: AgentRun.ID) async throws {
        _ = try await client.cancel(sessionID: agentID, body: SDKBridgeCancelRequest(runId: runID))
    }

    func archiveAgent(agentID: Agent.ID) async throws {
        throw SDKBridgeError.requestFailed(statusCode: 501, message: "SDK Bridge archive is not implemented.")
    }

    func unarchiveAgent(agentID: Agent.ID) async throws {
        throw SDKBridgeError.requestFailed(statusCode: 501, message: "SDK Bridge unarchive is not implemented.")
    }

    func deleteAgent(agentID: Agent.ID) async throws {
        throw SDKBridgeError.requestFailed(statusCode: 501, message: "SDK Bridge delete is not implemented.")
    }

    func listArtifacts(agentID: Agent.ID) async throws -> [Artifact] {
        try await client.listArtifacts(sessionID: agentID).items.map(\.domainModel)
    }

    func downloadArtifact(agentID: Agent.ID, path: String) async throws -> ArtifactDownload {
        throw SDKBridgeError.requestFailed(statusCode: 501, message: "SDK Bridge artifact downloads are not implemented yet.")
    }

    private func makeSessionStartRequest(from draft: AgentLaunchDraft) -> SDKBridgeSessionStartRequest {
        SDKBridgeSessionStartRequest(
            prompt: draft.prompt.textWithFileContext,
            images: makeImages(from: draft.prompt),
            repo: makeRepo(from: draft.source),
            modelId: modelIDForBridge(draft.modelID),
            autoCreatePR: draft.autoCreatePullRequest,
            skipReviewerRequest: draft.skipReviewerRequest,
            workOnCurrentBranch: !draft.autoGenerateBranch
        )
    }

    private func makeRepo(from source: AgentSource) -> SDKBridgeRepoRequest? {
        switch source {
        case .general:
            nil
        case .repository(let url, let startingRef):
            SDKBridgeRepoRequest(url: url.absoluteString, startingRef: startingRef?.nilIfBlank, prUrl: nil)
        case .pullRequest(let url):
            SDKBridgeRepoRequest(url: url.absoluteString, startingRef: nil, prUrl: url.absoluteString)
        }
    }

    private func makeImages(from prompt: AgentPrompt) -> [SDKBridgePromptImageRequest]? {
        let images = prompt.images.prefix(5).map { image in
            SDKBridgePromptImageRequest(
                data: image.data.base64EncodedString(),
                mimeType: "image/png",
                dimension: SDKBridgePromptImageDimensionRequest(width: image.width, height: image.height)
            )
        }
        return images.isEmpty ? nil : images
    }

    private func modelIDForBridge(_ modelID: String?) -> String? {
        AgentRuntimeMode.sdkBridge.normalizedLaunchModelID(modelID)
    }

    private func fallbackAgent(from draft: AgentLaunchDraft, response: SDKBridgeSessionStartResponse) -> Agent {
        let repository = repository(from: draft.source)
        return Agent(
            id: response.agentId,
            name: ConversationTitleGenerator.title(from: draft.prompt.text, repository: repository)
                ?? draft.prompt.text.firstLineSlug,
            status: .active,
            repository: repository,
            branchName: repository.isGeneralChat ? "" : draft.branchName?.nilIfBlank ?? "Cursor Chat",
            modelID: modelIDForBridge(draft.modelID) ?? AgentRuntimeMode.cursorChatPreferredModelID,
            latestRunID: response.runId,
            updatedAtDescription: "now",
            artifactCount: 0,
            pullRequestURL: nil,
            runtimeMode: .sdkBridge
        )
    }

    private func repository(from source: AgentSource) -> Repository {
        switch source {
        case .general:
            Repository.bridgeFallback(url: URL(string: "https://cursor.com/general-chat")!, startingRef: nil)
        case .repository(let url, let startingRef):
            repositoryCache.first { $0.url == url } ?? Repository.bridgeFallback(url: url, startingRef: startingRef)
        case .pullRequest(let url):
            repositoryCache.first ?? Repository.bridgeFallback(url: url, startingRef: nil)
        }
    }

    private static let defaultModel = AgentModel(
        id: "default",
        displayName: "default",
        subtitle: "Cursor default",
        category: .default,
        qualityScore: 4,
        costTier: 2
    )
}

private extension SDKBridgeRepositoryDTO {
    var domainModel: Repository? {
        guard let url = URL(string: url) else { return nil }
        return .bridgeFallback(url: url, startingRef: nil)
    }
}

private extension SDKBridgeModelDTO {
    var domainModel: AgentModel {
        AgentModel(
            id: id,
            displayName: displayName ?? id,
            subtitle: description ?? aliases?.first.map { "Alias \($0)" } ?? "Cursor SDK model",
            category: id.isCursorDefaultModelIdentifier ? .default : .coding,
            qualityScore: id.contains("gpt-5") || id.contains("composer") || id.contains("claude") ? 5 : 3,
            costTier: id.contains("mini") || id.contains("fast") ? 1 : 2
        )
    }
}

private extension SDKBridgeSessionDTO {
    func domainAgent(repositoryFallbacks: [Repository]) -> Agent {
        let repositoryURL = repositoryUrl.flatMap(URL.init(string:))
        let repository = repositoryURL.flatMap { url in
            repositoryFallbacks.first { $0.url == url } ?? .bridgeFallback(url: url, startingRef: startingRef)
        } ?? Repository.bridgeFallback(url: URL(string: "https://cursor.com/general-chat")!, startingRef: nil)

        let latestRun = latestRunId.flatMap { id in runs.first { $0.runId == id } } ?? runs.first
        let prURL = latestRun?.git?.objectValue?["branches"]?.arrayValue?.compactMap { branch -> URL? in
            guard let pr = branch.objectValue?["prUrl"]?.stringValue else { return nil }
            return URL(string: pr)
        }.first

        return Agent(
            id: agentId,
            name: name?.nilIfBlank ?? (repository.isGeneralChat ? "General Chat" : repository.displayName),
            status: .active,
            repository: repository,
            branchName: repository.isGeneralChat ? "" : startingRef ?? repository.defaultBranch,
            modelID: AgentRuntimeMode.sdkBridge.normalizedLaunchModelID(modelId) ?? AgentRuntimeMode.cursorChatPreferredModelID,
            latestRunID: latestRun?.runId ?? "",
            updatedAtDescription: CursorDateParser.relativeDescription(from: updatedAt),
            artifactCount: 0,
            pullRequestURL: prURL,
            runtimeMode: .sdkBridge
        )
    }
}

private extension SDKBridgeRunDTO {
    var domainRun: AgentRun {
        AgentRun(
            id: runId,
            agentID: agentId,
            status: RunStatus(cursorValue: status),
            createdAtDescription: CursorDateParser.relativeDescription(from: createdAt),
            updatedAtDescription: CursorDateParser.relativeDescription(from: updatedAt)
        )
    }
}

private extension SDKBridgeArtifactDTO {
    var domainModel: Artifact {
        Artifact(
            path: path,
            kind: Artifact.Kind(path: path),
            sizeDescription: CursorByteFormatter.string(from: sizeBytes),
            updatedAtDescription: CursorDateParser.relativeDescription(from: updatedAt)
        )
    }
}

private extension Repository {
    static func bridgeFallback(url: URL, startingRef: String?) -> Repository {
        let owner = url.deletingLastPathComponent().lastPathComponent.nilIfBlank ?? url.host ?? "Repository"
        let isGeneralChat = url.absoluteString.contains("general-chat")
        return Repository(
            owner: isGeneralChat ? "Cursor" : owner,
            name: isGeneralChat ? "General Chat" : url.lastPathComponent.nilIfBlank ?? "workspace",
            url: url,
            defaultBranch: isGeneralChat ? "" : startingRef ?? "main",
            isFavorite: false,
            lastUsedDescription: "now"
        )
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let object) = self {
            return object
        }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let values) = self {
            return values
        }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var firstLineSlug: String {
        let line = split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "live-workspace"
        let words = line
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(3)
        return words.isEmpty ? "live-workspace" : words.joined(separator: "-")
    }
}
