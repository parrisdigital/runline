import SwiftUI
import XCTest
@testable import Runline

final class RunlineTests: XCTestCase {
    @MainActor
    func testMockProviderLaunchCreatesAgentAndRun() async throws {
        let provider = MockAgentProvider()
        let repo = try await provider.listRepositories().first!
        let draft = AgentLaunchDraft(
            prompt: AgentPrompt(text: "Add regression tests for login"),
            modelID: "default",
            source: .repository(url: repo.url, startingRef: repo.defaultBranch),
            branchName: "tests/login-regression",
            autoGenerateBranch: true,
            autoCreatePullRequest: true,
            skipReviewerRequest: false
        )

        let result = try await provider.createAgent(draft)

        XCTAssertFalse(result.agent.id.isEmpty)
        XCTAssertFalse(result.run.id.isEmpty)
        XCTAssertEqual(result.agent.branchName, "tests/login-regression")
        XCTAssertEqual(result.run.status, .creating)
    }

    func testUnknownRunStatusIsNonTerminal() {
        XCTAssertFalse(RunStatus.unknown("PAUSED").isTerminal)
    }

    func testPrimaryTabBarSeparatesChatAndCloudNavigation() {
        XCTAssertEqual(AppTab.allCases, [.cursorChat, .cursorCloud, .repositories, .settings])
        XCTAssertEqual(AppTab.allCases.count, 4)
        XCTAssertEqual(AppTab(runtimeMode: .sdkBridge), .cursorChat)
        XCTAssertEqual(AppTab(runtimeMode: .cloud), .cursorCloud)
    }

    @MainActor
    func testSDKBridgeCanLaunchGeneralConversationWithoutRepository() {
        let appState = AppState(provider: MockAgentProvider(), apiKeyStore: InMemoryAPIKeyStore())
        appState.launchDraft.prompt.text = "Explain this architecture"
        appState.launchDraft.runtimeMode = .sdkBridge
        appState.launchDraft.source = .general

        XCTAssertTrue(appState.canLaunchAgent)

        appState.launchDraft.runtimeMode = .cloud

        XCTAssertFalse(appState.canLaunchAgent)
    }

    @MainActor
    func testLaunchSeedsLocalUserMessageForImmediateConversation() async throws {
        let appState = AppState(provider: MockAgentProvider(), apiKeyStore: InMemoryAPIKeyStore())
        appState.launchDraft.prompt.text = "Say hello in one short sentence."
        appState.launchDraft.source = .repository(
            url: URL(string: "https://github.com/acme/ios-app")!,
            startingRef: "main"
        )

        let launchResult = await appState.launchAgent()
        let result = try XCTUnwrap(launchResult)
        let events = appState.events(for: result.run.id)

        XCTAssertEqual(events.first?.kind, .user)
        XCTAssertEqual(events.first?.message, "Say hello in one short sentence.")
    }

    @MainActor
    func testFollowUpSeedsLocalUserMessageForImmediateConversation() async throws {
        let appState = AppState(provider: MockAgentProvider(), apiKeyStore: InMemoryAPIKeyStore())
        appState.launchDraft.prompt.text = "Start the thread."
        appState.launchDraft.source = .repository(
            url: URL(string: "https://github.com/acme/ios-app")!,
            startingRef: "main"
        )

        let launchResult = await appState.launchAgent()
        let result = try XCTUnwrap(launchResult)
        await appState.createFollowUp(agent: result.agent, prompt: AgentPrompt(text: "Continue with the next step."))
        let latestRun = try XCTUnwrap(appState.runs(for: result.agent).first)
        let events = appState.events(for: latestRun.id)

        XCTAssertEqual(events.first?.kind, .user)
        XCTAssertEqual(events.first?.message, "Continue with the next step.")
    }

    func testLayoutModeUsesSplitViewForRegularWidth() {
        XCTAssertEqual(AppLayoutMode.resolve(horizontalSizeClass: .compact), .compactTabs)
        XCTAssertEqual(AppLayoutMode.resolve(horizontalSizeClass: .regular), .regularSplit)
        XCTAssertEqual(AppLayoutMode.resolve(horizontalSizeClass: nil), .compactTabs)
    }

    func testNewChatModelPickerCollapsesDefaultModelSentinel() {
        let models = [
            AgentModel(id: "default", displayName: "default", subtitle: "Cursor default", category: .default, qualityScore: 4, costTier: 2),
            AgentModel(id: "composer-2", displayName: "composer-2", subtitle: "Composer", category: .coding, qualityScore: 4, costTier: 2),
        ]

        XCTAssertEqual(NewChatModelPickerOptions.visibleModels(from: models).map(\.id), ["composer-2"])
        XCTAssertNil(NewChatModelPickerOptions.selection(from: "default"))
        XCTAssertNil(NewChatModelPickerOptions.modelID(from: "Default"))
        XCTAssertEqual(NewChatModelPickerOptions.selection(from: "composer-2"), "composer-2")
        XCTAssertEqual(NewChatModelPickerOptions.modelID(from: "composer-2"), "composer-2")
    }

    func testSDKRuntimeUsesComposer25InsteadOfCursorDefault() {
        let models = [
            AgentModel(id: "default", displayName: "default", subtitle: "Cursor default", category: .default, qualityScore: 4, costTier: 2),
            AgentModel(id: "composer-2.5", displayName: "composer-2.5", subtitle: "Composer", category: .coding, qualityScore: 5, costTier: 2),
            AgentModel(id: "gpt-5.2", displayName: "gpt-5.2", subtitle: "Reasoning", category: .coding, qualityScore: 5, costTier: 3),
        ]

        XCTAssertEqual(AgentRuntimeMode.sdkBridge.preferredLaunchModelID, "composer-2.5")
        XCTAssertEqual(NewChatModelPickerOptions.selection(from: nil, runtimeMode: .sdkBridge), "composer-2.5")
        XCTAssertEqual(NewChatModelPickerOptions.modelID(from: "default", runtimeMode: .sdkBridge), "composer-2.5")
        XCTAssertEqual(
            NewChatModelPickerOptions.visibleModels(from: models, excluding: AgentRuntimeMode.sdkBridge.preferredLaunchModelID).map(\.id),
            ["gpt-5.2"]
        )
    }

    func testCursorChatModelPreferenceDefaultsToComposerAndRetainsExplicitSelection() {
        let suiteName = "RunlineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertEqual(CursorChatModelPreference.selectedModelID(defaults: defaults), "composer-2.5")
        XCTAssertEqual(CursorChatModelPreference.resolvedModelID(nil, defaults: defaults), "composer-2.5")

        CursorChatModelPreference.saveSelectedModelID("gpt-5.2", defaults: defaults)

        XCTAssertEqual(CursorChatModelPreference.selectedModelID(defaults: defaults), "gpt-5.2")
        XCTAssertEqual(CursorChatModelPreference.resolvedModelID(nil, defaults: defaults), "gpt-5.2")
        XCTAssertEqual(CursorChatModelPreference.resolvedModelID("claude-4.5-sonnet-thinking", defaults: defaults), "claude-4.5-sonnet-thinking")

        CursorChatModelPreference.saveSelectedModelID("default", defaults: defaults)

        XCTAssertEqual(CursorChatModelPreference.selectedModelID(defaults: defaults), "composer-2.5")
    }

    func testConversationTitleGeneratorCreatesContextualTitles() {
        let repository = Repository(
            owner: "parrisdigital",
            name: "cursor_mobile",
            url: URL(string: "https://github.com/parrisdigital/cursor_mobile")!,
            defaultBranch: "main",
            isFavorite: false,
            lastUsedDescription: "now"
        )

        XCTAssertEqual(
            ConversationTitleGenerator.title(from: "Can you research native Cursor app architecture?", repository: repository),
            "Research Native Cursor App Architecture"
        )
        XCTAssertEqual(
            ConversationTitleGenerator.title(from: "alright what should we build?", repository: repository),
            "Next Project Ideas"
        )
    }

    func testGeneralChatTitleUsesConversationTopic() {
        let repository = Repository(
            owner: "Cursor",
            name: "General Chat",
            url: URL(string: "https://cursor.com/general-chat")!,
            defaultBranch: "",
            isFavorite: false,
            lastUsedDescription: "now"
        )
        let events = [
            AgentStreamEvent(
                id: "run-general-local-user",
                runID: "run-general",
                kind: .user,
                title: "User",
                message: "Research native Cursor app architecture",
                timestamp: "now"
            )
        ]

        XCTAssertEqual(
            ConversationTitleGenerator.title(from: events, repository: repository),
            "Research Native Cursor App Architecture"
        )
        XCTAssertTrue(
            ConversationTitleGenerator.shouldReplace(
                currentTitle: "General Chat",
                with: "Research Native Cursor App Architecture",
                repository: repository,
                firstPrompt: events[0].message
            )
        )
    }

    func testConversationTitleGeneratorOnlyReplacesPlaceholderTitles() {
        let repository = Repository(
            owner: "parrisdigital",
            name: "cursor_mobile",
            url: URL(string: "https://github.com/parrisdigital/cursor_mobile")!,
            defaultBranch: "main",
            isFavorite: false,
            lastUsedDescription: "now"
        )

        XCTAssertTrue(
            ConversationTitleGenerator.shouldReplace(
                currentTitle: "parrisdigital/cursor_mobile",
                with: "Research Native Cursor App",
                repository: repository,
                firstPrompt: "Research native Cursor app"
            )
        )
        XCTAssertFalse(
            ConversationTitleGenerator.shouldReplace(
                currentTitle: "Manual project name",
                with: "Research Native Cursor App",
                repository: repository,
                firstPrompt: "Research native Cursor app"
            )
        )
    }

    func testWorkspaceHandoffPromptKeepsOriginalChatTopicAsTitle() {
        let events = [
            AgentStreamEvent(
                id: "run-1-local-user",
                runID: "run-1",
                kind: .user,
                title: "User",
                message: "Research native Cursor app architecture",
                timestamp: "now"
            ),
            AgentStreamEvent(
                id: "run-1-assistant",
                runID: "run-1",
                kind: .assistant,
                title: "Assistant",
                message: "We should use a Fly bridge for SDK-backed workspace sessions.",
                timestamp: "now"
            )
        ]

        let prompt = WorkspaceHandoffPromptBuilder.prompt(
            from: events,
            instruction: "Create the first workspace implementation pass.",
            sourceTitle: "Research Native Cursor App Architecture"
        )

        XCTAssertEqual(prompt.components(separatedBy: .newlines).first, "Research Native Cursor App Architecture")
        XCTAssertTrue(prompt.contains("Continue this Cursor Chat in a repository-backed workspace."))
        XCTAssertTrue(prompt.contains("User: Research native Cursor app architecture"))
        XCTAssertTrue(prompt.contains("Cursor: We should use a Fly bridge"))
        XCTAssertTrue(prompt.contains("Workspace instruction:\nCreate the first workspace implementation pass."))
    }

    @MainActor
    func testWorkspaceHandoffDraftTargetsRepositoryBackedSDKChat() {
        let appState = AppState(provider: MockAgentProvider(), apiKeyStore: InMemoryAPIKeyStore())
        let repository = Repository(
            owner: "acme",
            name: "ios-app",
            url: URL(string: "https://github.com/acme/ios-app")!,
            defaultBranch: "main",
            isFavorite: true,
            lastUsedDescription: "now"
        )
        let sourceAgent = Agent(
            id: "bc-general",
            name: "Research Native Cursor App Architecture",
            status: .active,
            repository: Repository(
                owner: "Cursor",
                name: "General Chat",
                url: URL(string: "https://cursor.com/general-chat")!,
                defaultBranch: "",
                isFavorite: false,
                lastUsedDescription: "now"
            ),
            branchName: "",
            modelID: "composer-2.5",
            latestRunID: "run-general",
            updatedAtDescription: "now",
            artifactCount: 0,
            pullRequestURL: nil,
            runtimeMode: .sdkBridge
        )
        let events = [
            AgentStreamEvent(
                id: "run-general-local-user",
                runID: "run-general",
                kind: .user,
                title: "User",
                message: "Research native Cursor app architecture",
                timestamp: "now"
            )
        ]

        let draft = appState.workspaceHandoffDraft(
            from: sourceAgent,
            events: events,
            repository: repository,
            branch: "main",
            instruction: "Implement the repo-backed workspace shell."
        )

        XCTAssertEqual(draft.runtimeMode, .sdkBridge)
        XCTAssertEqual(draft.modelID, "composer-2.5")
        XCTAssertEqual(draft.autoCreatePullRequest, false)
        XCTAssertEqual(draft.prompt.text.components(separatedBy: .newlines).first, "Research Native Cursor App Architecture")
        guard case .repository(let url, let startingRef) = draft.source else {
            return XCTFail("Expected a repository-backed handoff draft.")
        }
        XCTAssertEqual(url, repository.url)
        XCTAssertEqual(startingRef, "main")
    }

    func testLaunchDraftClearsComposer25WhenSwitchingBackToCloud() {
        var draft = AgentLaunchDraft(
            prompt: AgentPrompt(text: "Build a chat flow"),
            modelID: nil,
            source: .general,
            runtimeMode: .cloud,
            branchName: nil,
            autoGenerateBranch: true,
            autoCreatePullRequest: false,
            skipReviewerRequest: false
        )

        draft.applyRuntimeMode(.sdkBridge)
        XCTAssertEqual(draft.modelID, "composer-2.5")

        draft.applyRuntimeMode(.cloud)
        XCTAssertNil(draft.modelID)
    }

    func testSDKBridgeUsageLimitErrorKeepsActionableMessage() {
        let error = SDKBridgeError.requestFailed(
            statusCode: 429,
            message: "Your Cursor account has reached its hard usage limit. Increase the hard limit in Cursor settings, then try again."
        )

        XCTAssertEqual(error.localizedDescription, "Your Cursor account has reached its hard usage limit. Increase the hard limit in Cursor settings, then try again.")
    }

    @MainActor
    func testDeepLinksFocusChatsTabForAdaptiveShells() {
        let appState = AppState(provider: MockAgentProvider(), apiKeyStore: InMemoryAPIKeyStore())
        appState.selectedTab = .settings

        appState.handleDeepLink(URL(string: "runline://agent/bc-0001")!)

        XCTAssertEqual(appState.selectedTab, .cursorCloud)
        XCTAssertEqual(appState.focusedAgentID, "bc-0001")

        appState.selectedTab = .repositories
        appState.handleDeepLink(URL(string: "runline://agents/bc-0002/runs/run-0002")!)

        XCTAssertEqual(appState.selectedTab, .cursorCloud)
        XCTAssertEqual(appState.focusedAgentID, "bc-0002")
    }

    func testAppearanceModesMapToPreferredColorSchemes() {
        XCTAssertNil(AppAppearanceMode.system.colorScheme)
        XCTAssertEqual(AppAppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppAppearanceMode.dark.colorScheme, .dark)
    }

    @MainActor
    func testManualBranchNamingRequiresBranchNameBeforeLaunch() {
        let appState = AppState(provider: MockAgentProvider(), apiKeyStore: InMemoryAPIKeyStore())
        appState.launchDraft.prompt.text = "Build the landing page"
        appState.launchDraft.autoGenerateBranch = false
        appState.launchDraft.branchName = nil

        XCTAssertFalse(appState.canLaunchAgent)

        appState.launchDraft.branchName = "runline/landing-page"

        XCTAssertTrue(appState.canLaunchAgent)
    }

    @MainActor
    func testWorkspaceRefreshCancellationDoesNotShowGlobalAlert() async {
        let appState = AppState(provider: CancellingAgentProvider(), apiKeyStore: InMemoryAPIKeyStore())

        await appState.reloadWorkspace()

        XCTAssertNil(appState.errorMessage)
    }

    @MainActor
    func testConnectKeepsAccountWhenInitialWorkspaceRefreshFails() async {
        let provider = RefreshFailingAgentProvider()
        let appState = AppState(
            apiKeyStore: InMemoryAPIKeyStore(),
            providerFactory: { _ in provider }
        )

        await appState.connect(apiKey: "cursor-test-key")

        XCTAssertTrue(appState.isConnected)
        XCTAssertEqual(appState.account?.apiKeyName, "Runline Test Key")
        XCTAssertNil(appState.errorMessage)
        XCTAssertEqual(appState.statusMessage, "Cursor returned data Runline could not parse. Your key is still connected; refresh again shortly.")
    }

    @MainActor
    func testWorkspaceRefreshIgnoresPerAgentRunPreloadFailures() async {
        let appState = AppState(provider: RunPreloadFailingAgentProvider(), apiKeyStore: InMemoryAPIKeyStore())

        await appState.reloadWorkspace()

        XCTAssertNil(appState.errorMessage)
        XCTAssertEqual(appState.agents.count, 1)
    }

    @MainActor
    func testWorkspaceRefreshPreservesCachedEventsWhenTerminalReplayIsEmpty() async throws {
        let provider = TerminalEmptyEventAgentProvider()
        let agent = try await provider.listAgents()[0]
        let run = try await provider.listRuns(agentID: agent.id)[0]
        let cachedEvent = AgentStreamEvent(
            id: "run-terminal-local-user",
            runID: run.id,
            kind: .user,
            title: "User",
            message: "Research native Cursor app architecture",
            timestamp: "now"
        )
        let appState = AppState(provider: provider, apiKeyStore: InMemoryAPIKeyStore())
        appState.agents = [agent]
        appState.runsByAgentID[agent.id] = [run]
        appState.eventsByRunID[run.id] = [cachedEvent]

        await appState.reloadWorkspace()

        XCTAssertEqual(appState.events(for: run.id), [cachedEvent])
    }

    @MainActor
    func testStreamExpiredDoesNotShowGlobalAlert() async throws {
        let provider = StreamExpiredAgentProvider()
        let agent = try await provider.listAgents().first!
        let run = try await provider.listRuns(agentID: agent.id).first!
        let appState = AppState(provider: provider, apiKeyStore: InMemoryAPIKeyStore())

        await appState.loadEvents(for: agent, run: run)

        XCTAssertNil(appState.errorMessage)
        XCTAssertTrue(appState.isStreamExpired(runID: run.id))
    }

    @MainActor
    func testMockProviderArchiveAndDeleteUpdateAgentList() async throws {
        let provider = MockAgentProvider()
        let agent = try await provider.listAgents().first!

        try await provider.archiveAgent(agentID: agent.id)
        let archived = try await provider.listAgents().first { $0.id == agent.id }
        XCTAssertEqual(archived?.status, .archived)

        try await provider.deleteAgent(agentID: agent.id)
        let remaining = try await provider.listAgents()
        XCTAssertFalse(remaining.contains { $0.id == agent.id })
    }
}

@MainActor
private final class CancellingAgentProvider: AgentProvider {
    let capabilities = ProviderCapabilities()

    func validateConnection() async throws -> ProviderAccount {
        throw CancellationError()
    }

    func listRepositories() async throws -> [Repository] {
        throw CancellationError()
    }

    func listModels() async throws -> [AgentModel] {
        throw CancellationError()
    }

    func listAgents() async throws -> [Agent] {
        throw CancellationError()
    }

    func getAgent(agentID: Agent.ID) async throws -> Agent {
        throw CancellationError()
    }

    func listRuns(agentID: Agent.ID) async throws -> [AgentRun] {
        throw CancellationError()
    }

    func getRun(agentID: Agent.ID, runID: AgentRun.ID) async throws -> AgentRun {
        throw CancellationError()
    }

    func streamEvents(agentID: Agent.ID, runID: AgentRun.ID) async throws -> [AgentStreamEvent] {
        throw CancellationError()
    }

    func createAgent(_ draft: AgentLaunchDraft) async throws -> AgentLaunchResult {
        throw CancellationError()
    }

    func createRun(_ draft: AgentFollowUpDraft) async throws -> AgentRun {
        throw CancellationError()
    }

    func cancelRun(agentID: Agent.ID, runID: AgentRun.ID) async throws {
        throw CancellationError()
    }

    func archiveAgent(agentID: Agent.ID) async throws {
        throw CancellationError()
    }

    func unarchiveAgent(agentID: Agent.ID) async throws {
        throw CancellationError()
    }

    func deleteAgent(agentID: Agent.ID) async throws {
        throw CancellationError()
    }

    func listArtifacts(agentID: Agent.ID) async throws -> [Artifact] {
        throw CancellationError()
    }

    func downloadArtifact(agentID: Agent.ID, path: String) async throws -> ArtifactDownload {
        throw CancellationError()
    }
}

@MainActor
private final class RefreshFailingAgentProvider: AgentProvider {
    let capabilities = ProviderCapabilities()

    func validateConnection() async throws -> ProviderAccount {
        ProviderAccount(apiKeyName: "Runline Test Key", userEmail: "developer@example.com", createdAt: .now)
    }

    func listRepositories() async throws -> [Repository] {
        throw CursorAPIError.decodingFailed("Missing repository items")
    }

    func listModels() async throws -> [AgentModel] {
        []
    }

    func listAgents() async throws -> [Agent] {
        []
    }

    func getAgent(agentID: Agent.ID) async throws -> Agent {
        throw CursorAPIError.requestFailed(statusCode: 404, message: "Agent not found")
    }

    func listRuns(agentID: Agent.ID) async throws -> [AgentRun] {
        []
    }

    func getRun(agentID: Agent.ID, runID: AgentRun.ID) async throws -> AgentRun {
        throw CursorAPIError.requestFailed(statusCode: 404, message: "Run not found")
    }

    func streamEvents(agentID: Agent.ID, runID: AgentRun.ID) async throws -> [AgentStreamEvent] {
        []
    }

    func createAgent(_ draft: AgentLaunchDraft) async throws -> AgentLaunchResult {
        throw CursorAPIError.unsupportedResponse("Not supported in this test.")
    }

    func createRun(_ draft: AgentFollowUpDraft) async throws -> AgentRun {
        throw CursorAPIError.unsupportedResponse("Not supported in this test.")
    }

    func cancelRun(agentID: Agent.ID, runID: AgentRun.ID) async throws {}

    func archiveAgent(agentID: Agent.ID) async throws {}

    func unarchiveAgent(agentID: Agent.ID) async throws {}

    func deleteAgent(agentID: Agent.ID) async throws {}

    func listArtifacts(agentID: Agent.ID) async throws -> [Artifact] {
        []
    }

    func downloadArtifact(agentID: Agent.ID, path: String) async throws -> ArtifactDownload {
        throw CursorAPIError.unsupportedResponse("Not supported in this test.")
    }
}

@MainActor
private final class RunPreloadFailingAgentProvider: AgentProvider {
    let capabilities = ProviderCapabilities()

    private let repository = Repository(
        owner: "acme",
        name: "ios-app",
        url: URL(string: "https://github.com/acme/ios-app")!,
        defaultBranch: "main",
        isFavorite: false,
        lastUsedDescription: "Cursor"
    )

    func validateConnection() async throws -> ProviderAccount {
        ProviderAccount(apiKeyName: "Runline Test Key", userEmail: "developer@example.com", createdAt: .now)
    }

    func listRepositories() async throws -> [Repository] {
        [repository]
    }

    func listModels() async throws -> [AgentModel] {
        [AgentModel(id: "default", displayName: "default", subtitle: "Cursor configured default", category: .default, qualityScore: 4, costTier: 2)]
    }

    func listAgents() async throws -> [Agent] {
        [
            Agent(
                id: "bc-123",
                name: "Test agent",
                status: .active,
                repository: repository,
                branchName: "main",
                modelID: "default",
                latestRunID: "run-123",
                updatedAtDescription: "now",
                artifactCount: 0,
                pullRequestURL: nil
            )
        ]
    }

    func getAgent(agentID: Agent.ID) async throws -> Agent {
        (try await listAgents())[0]
    }

    func listRuns(agentID: Agent.ID) async throws -> [AgentRun] {
        throw CursorAPIError.decodingFailed("Run preload failed")
    }

    func getRun(agentID: Agent.ID, runID: AgentRun.ID) async throws -> AgentRun {
        throw CursorAPIError.requestFailed(statusCode: 404, message: "Run not found")
    }

    func streamEvents(agentID: Agent.ID, runID: AgentRun.ID) async throws -> [AgentStreamEvent] {
        []
    }

    func createAgent(_ draft: AgentLaunchDraft) async throws -> AgentLaunchResult {
        throw CursorAPIError.unsupportedResponse("Not supported in this test.")
    }

    func createRun(_ draft: AgentFollowUpDraft) async throws -> AgentRun {
        throw CursorAPIError.unsupportedResponse("Not supported in this test.")
    }

    func cancelRun(agentID: Agent.ID, runID: AgentRun.ID) async throws {}

    func archiveAgent(agentID: Agent.ID) async throws {}

    func unarchiveAgent(agentID: Agent.ID) async throws {}

    func deleteAgent(agentID: Agent.ID) async throws {}

    func listArtifacts(agentID: Agent.ID) async throws -> [Artifact] {
        []
    }

    func downloadArtifact(agentID: Agent.ID, path: String) async throws -> ArtifactDownload {
        throw CursorAPIError.unsupportedResponse("Not supported in this test.")
    }
}

@MainActor
private final class TerminalEmptyEventAgentProvider: AgentProvider {
    let capabilities = ProviderCapabilities()

    private let repository = Repository(
        owner: "Cursor",
        name: "General Chat",
        url: URL(string: "https://cursor.com/general-chat")!,
        defaultBranch: "",
        isFavorite: false,
        lastUsedDescription: "Cursor"
    )

    func validateConnection() async throws -> ProviderAccount {
        ProviderAccount(apiKeyName: "Runline Test Key", userEmail: "developer@example.com", createdAt: .now)
    }

    func listRepositories() async throws -> [Repository] {
        []
    }

    func listModels() async throws -> [AgentModel] {
        [AgentModel(id: "composer-2.5", displayName: "composer-2.5", subtitle: "Composer", category: .coding, qualityScore: 5, costTier: 2)]
    }

    func listAgents() async throws -> [Agent] {
        [
            Agent(
                id: "bc-terminal",
                name: "General Chat",
                status: .active,
                repository: repository,
                branchName: "",
                modelID: "composer-2.5",
                latestRunID: "run-terminal",
                updatedAtDescription: "now",
                artifactCount: 0,
                pullRequestURL: nil
            )
        ]
    }

    func getAgent(agentID: Agent.ID) async throws -> Agent {
        try await listAgents()[0]
    }

    func listRuns(agentID: Agent.ID) async throws -> [AgentRun] {
        [
            AgentRun(
                id: "run-terminal",
                agentID: agentID,
                status: .finished,
                createdAtDescription: "now",
                updatedAtDescription: "now"
            )
        ]
    }

    func getRun(agentID: Agent.ID, runID: AgentRun.ID) async throws -> AgentRun {
        try await listRuns(agentID: agentID)[0]
    }

    func streamEvents(agentID: Agent.ID, runID: AgentRun.ID) async throws -> [AgentStreamEvent] {
        []
    }

    func createAgent(_ draft: AgentLaunchDraft) async throws -> AgentLaunchResult {
        throw CursorAPIError.unsupportedResponse("Not supported in this test.")
    }

    func createRun(_ draft: AgentFollowUpDraft) async throws -> AgentRun {
        throw CursorAPIError.unsupportedResponse("Not supported in this test.")
    }

    func cancelRun(agentID: Agent.ID, runID: AgentRun.ID) async throws {}

    func archiveAgent(agentID: Agent.ID) async throws {}

    func unarchiveAgent(agentID: Agent.ID) async throws {}

    func deleteAgent(agentID: Agent.ID) async throws {}

    func listArtifacts(agentID: Agent.ID) async throws -> [Artifact] {
        []
    }

    func downloadArtifact(agentID: Agent.ID, path: String) async throws -> ArtifactDownload {
        throw CursorAPIError.unsupportedResponse("Not supported in this test.")
    }
}

@MainActor
private final class StreamExpiredAgentProvider: AgentProvider {
    let capabilities = ProviderCapabilities()
    private let base = MockAgentProvider()

    func validateConnection() async throws -> ProviderAccount {
        try await base.validateConnection()
    }

    func listRepositories() async throws -> [Repository] {
        try await base.listRepositories()
    }

    func listModels() async throws -> [AgentModel] {
        try await base.listModels()
    }

    func listAgents() async throws -> [Agent] {
        try await base.listAgents()
    }

    func getAgent(agentID: Agent.ID) async throws -> Agent {
        try await base.getAgent(agentID: agentID)
    }

    func listRuns(agentID: Agent.ID) async throws -> [AgentRun] {
        try await base.listRuns(agentID: agentID)
    }

    func getRun(agentID: Agent.ID, runID: AgentRun.ID) async throws -> AgentRun {
        try await base.getRun(agentID: agentID, runID: runID)
    }

    func streamEvents(agentID: Agent.ID, runID: AgentRun.ID) async throws -> [AgentStreamEvent] {
        throw CursorAPIError.requestFailed(statusCode: 410, message: "stream_expired")
    }

    func createAgent(_ draft: AgentLaunchDraft) async throws -> AgentLaunchResult {
        try await base.createAgent(draft)
    }

    func createRun(_ draft: AgentFollowUpDraft) async throws -> AgentRun {
        try await base.createRun(draft)
    }

    func cancelRun(agentID: Agent.ID, runID: AgentRun.ID) async throws {
        try await base.cancelRun(agentID: agentID, runID: runID)
    }

    func archiveAgent(agentID: Agent.ID) async throws {
        try await base.archiveAgent(agentID: agentID)
    }

    func unarchiveAgent(agentID: Agent.ID) async throws {
        try await base.unarchiveAgent(agentID: agentID)
    }

    func deleteAgent(agentID: Agent.ID) async throws {
        try await base.deleteAgent(agentID: agentID)
    }

    func listArtifacts(agentID: Agent.ID) async throws -> [Artifact] {
        try await base.listArtifacts(agentID: agentID)
    }

    func downloadArtifact(agentID: Agent.ID, path: String) async throws -> ArtifactDownload {
        try await base.downloadArtifact(agentID: agentID, path: path)
    }
}
