import Foundation

@MainActor
final class MockAgentProvider: AgentProvider, EnterpriseDataProvider {
    let capabilities = ProviderCapabilities()

    private let repositories: [Repository]
    private let models: [AgentModel]
    private var agents: [Agent]
    private var runsByAgentID: [String: [AgentRun]]
    private var streamEventsByRunID: [String: [AgentStreamEvent]]

    init() {
        let iosRepo = Repository(
            owner: "acme",
            name: "ios-app",
            url: URL(string: "https://github.com/acme/ios-app")!,
            defaultBranch: "main",
            isFavorite: true,
            lastUsedDescription: "2m ago"
        )
        let apiRepo = Repository(
            owner: "acme",
            name: "api-server",
            url: URL(string: "https://github.com/acme/api-server")!,
            defaultBranch: "main",
            isFavorite: true,
            lastUsedDescription: "1h ago"
        )
        let designRepo = Repository(
            owner: "acme",
            name: "design-system",
            url: URL(string: "https://github.com/acme/design-system")!,
            defaultBranch: "main",
            isFavorite: false,
            lastUsedDescription: "3h ago"
        )

        repositories = [iosRepo, apiRepo, designRepo]
        models = [
            AgentModel(id: "default", displayName: "default", subtitle: "Cursor recommended", category: .default, qualityScore: 4, costTier: 2),
            AgentModel(id: "gpt-5.2", displayName: "gpt-5.2", subtitle: "Strong reasoning for complex tasks", category: .coding, qualityScore: 5, costTier: 3),
            AgentModel(id: "claude-4.5-sonnet-thinking", displayName: "claude-4.5-sonnet-thinking", subtitle: "Coding focused with deep reasoning", category: .coding, qualityScore: 5, costTier: 2),
            AgentModel(id: "gpt-4.1-mini", displayName: "gpt-4.1-mini", subtitle: "Fast and cost-efficient", category: .fast, qualityScore: 3, costTier: 1)
        ]

        let runOne = AgentRun(
            id: "run-0001",
            agentID: "bc-0001",
            status: .running,
            createdAtDescription: "3m ago",
            updatedAtDescription: "now"
        )
        let runTwo = AgentRun(
            id: "run-0002",
            agentID: "bc-0002",
            status: .finished,
            createdAtDescription: "22m ago",
            updatedAtDescription: "18m ago"
        )

        agents = [
            Agent(
                id: "bc-0001",
                name: "fix-auth-state",
                status: .active,
                repository: iosRepo,
                branchName: "fix/auth-state",
                modelID: "gpt-5.2",
                latestRunID: runOne.id,
                updatedAtDescription: "3m 12s",
                artifactCount: 2,
                pullRequestURL: URL(string: "https://github.com/acme/ios-app/pull/123")
            ),
            Agent(
                id: "bc-0002",
                name: "update-tests",
                status: .active,
                repository: iosRepo,
                branchName: "main",
                modelID: "default",
                latestRunID: runTwo.id,
                updatedAtDescription: "18m",
                artifactCount: 1,
                pullRequestURL: URL(string: "https://github.com/acme/ios-app/pull/122")
            )
        ]

        runsByAgentID = [
            "bc-0001": [runOne],
            "bc-0002": [runTwo]
        ]

        streamEventsByRunID = [
            runOne.id: Self.sampleEvents(runID: runOne.id, terminal: false),
            runTwo.id: Self.sampleEvents(runID: runTwo.id, terminal: true)
        ]
    }

    func validateConnection() async throws -> ProviderAccount {
        ProviderAccount(apiKeyName: "Mock Cursor API Key", userEmail: "developer@example.com", createdAt: .now)
    }

    func listRepositories() async throws -> [Repository] {
        repositories
    }

    func listModels() async throws -> [AgentModel] {
        models
    }

    func listAgents() async throws -> [Agent] {
        agents
    }

    func getAgent(agentID: Agent.ID) async throws -> Agent {
        guard let agent = agents.first(where: { $0.id == agentID }) else {
            throw CursorAPIError.requestFailed(statusCode: 404, message: "Agent not found.")
        }
        return agent
    }

    func listRuns(agentID: Agent.ID) async throws -> [AgentRun] {
        runsByAgentID[agentID, default: []]
    }

    func getRun(agentID: Agent.ID, runID: AgentRun.ID) async throws -> AgentRun {
        guard let run = runsByAgentID[agentID, default: []].first(where: { $0.id == runID }) else {
            throw CursorAPIError.requestFailed(statusCode: 404, message: "Run not found.")
        }
        return run
    }

    func streamEvents(agentID: Agent.ID, runID: AgentRun.ID) async throws -> [AgentStreamEvent] {
        streamEventsByRunID[runID, default: []]
    }

    func createAgent(_ draft: AgentLaunchDraft) async throws -> AgentLaunchResult {
        let repo: Repository
        let branch: String
        switch draft.source {
        case .repository(let url, let startingRef):
            repo = repositories.first(where: { $0.url == url }) ?? Repository(
                owner: url.deletingLastPathComponent().lastPathComponent,
                name: url.lastPathComponent,
                url: url,
                defaultBranch: startingRef ?? "main",
                isFavorite: false,
                lastUsedDescription: "now"
            )
            branch = draft.branchName?.isEmpty == false ? draft.branchName! : "cursor/mobile-launch"
        case .pullRequest(let url):
            repo = repositories.first ?? Repository(
                owner: "manual",
                name: "pull-request",
                url: url,
                defaultBranch: "main",
                isFavorite: false,
                lastUsedDescription: "now"
            )
            branch = "pull-request"
        }

        let agentID = "bc-\(UUID().uuidString.lowercased())"
        let runID = "run-\(UUID().uuidString.lowercased())"
        let run = AgentRun(id: runID, agentID: agentID, status: .creating, createdAtDescription: "now", updatedAtDescription: "now")
        let agent = Agent(
            id: agentID,
            name: draft.prompt.text.firstLineSlug,
            status: .active,
            repository: repo,
            branchName: branch,
            modelID: draft.modelID ?? "default",
            latestRunID: runID,
            updatedAtDescription: "now",
            artifactCount: 0,
            pullRequestURL: nil
        )

        agents.insert(agent, at: 0)
        runsByAgentID[agentID] = [run]
        streamEventsByRunID[runID] = Self.sampleEvents(runID: runID, terminal: false)
        return AgentLaunchResult(agent: agent, run: run)
    }

    func createRun(_ draft: AgentFollowUpDraft) async throws -> AgentRun {
        let runID = "run-\(UUID().uuidString.lowercased())"
        let run = AgentRun(id: runID, agentID: draft.agentID, status: .creating, createdAtDescription: "now", updatedAtDescription: "now")
        runsByAgentID[draft.agentID, default: []].insert(run, at: 0)
        streamEventsByRunID[runID] = [
            AgentStreamEvent(id: "\(runID)-1", runID: runID, kind: .assistant, title: "Follow-up", message: draft.prompt.text, timestamp: "now"),
            AgentStreamEvent(id: "\(runID)-2", runID: runID, kind: .status, title: "Status", message: "Queued new run", timestamp: "now")
        ]
        return run
    }

    func cancelRun(agentID: Agent.ID, runID: AgentRun.ID) async throws {
        runsByAgentID[agentID] = runsByAgentID[agentID, default: []].map { run in
            run.id == runID ? AgentRun(id: run.id, agentID: run.agentID, status: .cancelled, createdAtDescription: run.createdAtDescription, updatedAtDescription: "cancelled") : run
        }
    }

    func archiveAgent(agentID: Agent.ID) async throws {
        updateAgentStatus(agentID: agentID, status: .archived)
    }

    func unarchiveAgent(agentID: Agent.ID) async throws {
        updateAgentStatus(agentID: agentID, status: .active)
    }

    func deleteAgent(agentID: Agent.ID) async throws {
        let runIDs = Set(runsByAgentID[agentID, default: []].map(\.id))
        agents.removeAll { $0.id == agentID }
        runsByAgentID.removeValue(forKey: agentID)
        streamEventsByRunID = streamEventsByRunID.filter { runIDs.contains($0.key) == false }
    }

    func listArtifacts(agentID: Agent.ID) async throws -> [Artifact] {
        [
            Artifact(path: "artifacts/screenshot.png", kind: .screenshot, sizeDescription: "1.2 MB", updatedAtDescription: "2m ago"),
            Artifact(path: "artifacts/run-log.txt", kind: .log, sizeDescription: "12 KB", updatedAtDescription: "2m ago")
        ]
    }

    func downloadArtifact(agentID: Agent.ID, path: String) async throws -> ArtifactDownload {
        ArtifactDownload(url: URL(string: "https://example.com/\(path)")!, expiresAt: Date(timeIntervalSinceNow: 300))
    }

    var enterpriseEndpoints: [CursorAPIEndpoint] {
        CursorAPIEndpointCatalog.endpoints
    }

    func fetchEndpoint(_ endpoint: CursorAPIEndpoint) async throws -> CursorAPIEndpointResult {
        let preview: String
        let count: Int?
        switch endpoint.area {
        case .cloudAgents:
            preview = """
            {
              "items": [
                "connected",
                "\(endpoint.title)"
              ]
            }
            """
            count = 2
        case .admin:
            preview = """
            {
              "members": [
                "developer@example.com"
              ],
              "access": "mock-admin"
            }
            """
            count = 1
        case .analytics:
            preview = """
            {
              "data": {
                "period": "30d",
                "metric": "\(endpoint.title)"
              }
            }
            """
            count = 1
        case .aiCode:
            preview = """
            {
              "data": [
                {
                  "source": "AGENT",
                  "lines": 128
                }
              ]
            }
            """
            count = 1
        }

        return CursorAPIEndpointResult(
            endpoint: endpoint,
            statusCode: 200,
            latencyMilliseconds: 18,
            capturedAt: .now,
            etag: "mock-etag",
            preview: preview,
            recordCount: count,
            errorMessage: nil
        )
    }

    private static func sampleEvents(runID: String, terminal: Bool) -> [AgentStreamEvent] {
        [
            AgentStreamEvent(id: "\(runID)-1", runID: runID, kind: .status, title: "Status", message: "Agent started", timestamp: "9:41:03 AM"),
            AgentStreamEvent(id: "\(runID)-2", runID: runID, kind: .assistant, title: "Assistant", message: "I'll inspect the current implementation and identify the persistence gap.", timestamp: "9:41:05 AM"),
            AgentStreamEvent(id: "\(runID)-3", runID: runID, kind: .thinking, title: "Thinking", message: "Reviewing auth state, storage, and session lifecycle.", timestamp: "9:41:07 AM"),
            AgentStreamEvent(id: "\(runID)-4", runID: runID, kind: .toolCall, title: "Tool Call", message: "Read File Sources/AuthManager.swift", timestamp: "9:41:08 AM"),
            AgentStreamEvent(id: "\(runID)-5", runID: runID, kind: .result, title: "Result", message: terminal ? "All tasks completed successfully" : "Found 8 matching call sites", timestamp: "9:41:12 AM"),
            AgentStreamEvent(id: "\(runID)-6", runID: runID, kind: terminal ? .done : .heartbeat, title: terminal ? "Done" : "Heartbeat", message: terminal ? "Run complete" : "Still working...", timestamp: "9:41:22 AM")
        ]
    }

    private func updateAgentStatus(agentID: Agent.ID, status: AgentStatus) {
        guard let index = agents.firstIndex(where: { $0.id == agentID }) else { return }
        agents[index].status = status
    }
}

private extension String {
    var firstLineSlug: String {
        let line = split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "new-agent"
        let words = line
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(3)
        return words.isEmpty ? "new-agent" : words.joined(separator: "-")
    }
}
