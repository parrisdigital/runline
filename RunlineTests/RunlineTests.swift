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

    func testPrimaryTabBarUsesThreeExplicitTabs() {
        XCTAssertEqual(AppTab.allCases, [.chats, .repositories, .settings])
        XCTAssertEqual(AppTab.allCases.count, 3)
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

    func testWorkflowPreferencesResolveDefaultRunMode() {
        XCTAssertEqual(RunlineWorkflowPreferences.runMode(from: nil), .cloudAgent)
        XCTAssertEqual(RunlineWorkflowPreferences.runMode(from: AgentRunMode.sdkBridge.rawValue), .sdkBridge)
        XCTAssertEqual(RunlineWorkflowPreferences.runMode(from: "unknown"), .cloudAgent)
    }

    func testRunModesExposeCloudDefaultAndCursorSDKCopy() {
        XCTAssertEqual(AgentRunMode.cloudAgent.title, "Cloud Agent")
        XCTAssertEqual(AgentRunMode.sdkBridge.title, "Cursor SDK")
        XCTAssertTrue(AgentRunMode.sdkBridge.detail.contains("Runline Bridge"))
    }

    func testCursorSDKOnboardingStepsExposeCurrentBridgeCommands() {
        XCTAssertEqual(RunlineBridgeOnboardingStep.allCases.first, .overview)
        XCTAssertEqual(RunlineBridgeOnboardingStep.allCases.last, .connect)
        XCTAssertEqual(RunlineBridgeOnboardingStep.bridge.command, "npm install -g runline-bridge")
        XCTAssertEqual(RunlineBridgeOnboardingStep.start.command, "runline-bridge up")
        XCTAssertEqual(RunlineBridgeOnboardingStep.start.command(keepAwake: true), "runline-bridge up --keep-awake")
        XCTAssertEqual(RunlineBridgeOnboardingStep.connect.title, "Pair and verify")
        XCTAssertTrue(RunlineBridgeOnboardingStep.connect.subtitle.contains("verify"))
        XCTAssertNil(RunlineBridgeOnboardingStep.connect.command)
    }

    func testRunlineBridgeStartModesExposeKeepAwakeCommand() {
        XCTAssertEqual(RunlineBridgeStartMode.standard.command, "runline-bridge up")
        XCTAssertEqual(RunlineBridgeStartMode.keepAwake.command, "runline-bridge up --keep-awake")
        XCTAssertEqual(RunlineBridgeStartMode.resolve(keepAwake: false), .standard)
        XCTAssertEqual(RunlineBridgeStartMode.resolve(keepAwake: true), .keepAwake)
    }

    func testSDKBridgePreferencesCanEnableBridgeForSetupFlow() {
        let suiteName = "RunlineTests.SDKBridgePreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(SDKBridgePreferences.isEnabled(defaults: defaults))

        SDKBridgePreferences.setEnabled(true, defaults: defaults)

        XCTAssertTrue(SDKBridgePreferences.isEnabled(defaults: defaults))
    }

    func testSDKMessageIntentsExposeBridgeValuesAndSymbols() {
        XCTAssertEqual(SDKMessageIntent.continueConversation.bridgeValue, "continue")
        XCTAssertEqual(SDKMessageIntent.plan.bridgeValue, "plan")
        XCTAssertEqual(SDKMessageIntent.execute.bridgeValue, "execute")
        XCTAssertFalse(SDKMessageIntent.plan.symbolName.isEmpty)
    }

    func testSDKBridgeProfileDecodesDetailedToolMetadata() throws {
        let data = Data("""
        {
          "id": "github-tools",
          "name": "GitHub Tools",
          "description": "GitHub MCP plus review helpers.",
          "mcpServerCount": 1,
          "subagentCount": 1,
          "mcpServers": [
            {
              "id": "github",
              "name": "github",
              "transport": "stdio",
              "command": "npx -y @modelcontextprotocol/server-github",
              "hasAuth": true,
              "environmentKeys": ["GITHUB_PERSONAL_ACCESS_TOKEN"],
              "toolHints": [
                {
                  "id": "github-prs",
                  "name": "Pull requests",
                  "description": "Review pull request context.",
                  "server": "github"
                }
              ]
            }
          ],
          "subagents": [
            {
              "id": "reviewer",
              "name": "reviewer",
              "description": "Reviews implementation risk.",
              "promptPreview": "Review implementation risk and missing tests.",
              "modelID": "inherit",
              "mcpServerNames": ["github"]
            }
          ],
          "skills": [
            {
              "id": "review-checklist",
              "name": "Review checklist",
              "description": "Apply project review criteria.",
              "source": ".cursor/skills/review-checklist",
              "enabled": true
            }
          ],
          "hooks": [
            {
              "id": "preflight",
              "name": "Preflight checks",
              "event": "before_execute",
              "command": "npm test",
              "enabled": true
            }
          ],
          "toolHints": [
            {
              "id": "github-prs",
              "name": "Pull requests",
              "description": "Review pull request context.",
              "server": "github"
            }
          ]
        }
        """.utf8)

        let profile = try JSONDecoder().decode(SDKBridgeMCPProfile.self, from: data)

        XCTAssertEqual(profile.summary, "1 MCP / 1 subagent / 1 skill / 1 hook / 1 tool")
        XCTAssertTrue(profile.hasDetailedMetadata)
        XCTAssertEqual(profile.mcpServers.first?.name, "github")
        XCTAssertEqual(profile.mcpServers.first?.environmentKeys, ["GITHUB_PERSONAL_ACCESS_TOKEN"])
        XCTAssertEqual(profile.subagents.first?.mcpServerNames, ["github"])
        XCTAssertEqual(profile.skills.first?.source, ".cursor/skills/review-checklist")
        XCTAssertEqual(profile.hooks.first?.event, "before_execute")
        XCTAssertEqual(profile.toolHints.first?.server, "github")
    }

    func testSDKBridgeProfileDecodesLegacyMetadataWithoutDetails() throws {
        let data = Data("""
        {
          "id": "basic",
          "name": "Basic",
          "mcpServerCount": 1,
          "subagentCount": 0
        }
        """.utf8)

        let profile = try JSONDecoder().decode(SDKBridgeMCPProfile.self, from: data)

        XCTAssertEqual(profile.summary, "1 MCP")
        XCTAssertFalse(profile.hasDetailedMetadata)
        XCTAssertTrue(profile.mcpServers.isEmpty)
        XCTAssertTrue(profile.skills.isEmpty)
        XCTAssertTrue(profile.hooks.isEmpty)
    }

    func testLaunchDraftDecodesLegacyCacheAsCloudAgentRunMode() throws {
        let draft = AgentLaunchDraft(
            prompt: AgentPrompt(text: "Build settings"),
            modelID: "composer-2",
            source: .repository(url: URL(string: "https://github.com/acme/app")!, startingRef: "main"),
            runMode: .sdkBridge,
            branchName: nil,
            autoGenerateBranch: true,
            autoCreatePullRequest: true,
            skipReviewerRequest: false
        )
        let data = try JSONEncoder().encode(draft)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "runMode")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AgentLaunchDraft.self, from: legacyData)

        XCTAssertEqual(decoded.runMode, .cloudAgent)
    }

    @MainActor
    func testDeepLinksFocusChatsTabForAdaptiveShells() {
        let appState = AppState(provider: MockAgentProvider(), apiKeyStore: InMemoryAPIKeyStore())
        appState.selectedTab = .settings

        appState.handleDeepLink(URL(string: "runline://agent/bc-0001")!)

        XCTAssertEqual(appState.selectedTab, .chats)
        XCTAssertEqual(appState.focusedAgentID, "bc-0001")

        appState.selectedTab = .repositories
        appState.handleDeepLink(URL(string: "runline://agents/bc-0002/runs/run-0002")!)

        XCTAssertEqual(appState.selectedTab, .chats)
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
    func testSDKLaunchRequiresPairingAndConnectedBridge() {
        withSDKBridgeDefaults(enabled: true, baseURL: "http://localhost:8787") {
            let unpairedAppState = AppState(provider: MockAgentProvider(), apiKeyStore: InMemoryAPIKeyStore(apiKey: "cursor-test-key"))
            unpairedAppState.account = ProviderAccount(
                apiKeyName: "Runline Test Key",
                userEmail: "test@example.com",
                createdAt: .now
            )
            unpairedAppState.launchDraft.prompt.text = "Plan the settings cleanup"
            unpairedAppState.launchDraft.runMode = .sdkBridge
            unpairedAppState.sdkBridgeConnectionState = .connected("runline-bridge - @cursor/sdk")

            XCTAssertFalse(unpairedAppState.canLaunchAgent)
            XCTAssertEqual(unpairedAppState.sdkBridgeLaunchIssue, "Pair Runline Bridge in Settings before using Cursor SDK.")

            let appState = AppState(
                provider: MockAgentProvider(),
                apiKeyStore: InMemoryAPIKeyStore(apiKey: "cursor-test-key"),
                sdkBridgeTokenStore: InMemoryAPIKeyStore(apiKey: "bridge-token")
            )
            appState.account = ProviderAccount(
                apiKeyName: "Runline Test Key",
                userEmail: "test@example.com",
                createdAt: .now
            )
            appState.launchDraft.prompt.text = "Plan the settings cleanup"
            appState.launchDraft.runMode = .sdkBridge
            appState.sdkBridgeConnectionState = .unchecked

            XCTAssertFalse(appState.canLaunchAgent)
            XCTAssertEqual(appState.sdkBridgeLaunchIssue, "Check the Runline Bridge connection in Settings before using Cursor SDK.")

            appState.sdkBridgeConnectionState = .connected("runline-orchestrator - @cursor/sdk")

            XCTAssertTrue(appState.canLaunchAgent)
            XCTAssertNil(appState.sdkBridgeLaunchIssue)
        }
    }

    @MainActor
    func testUnavailableSDKModeFallsBackToCloudAgent() {
        withSDKBridgeDefaults(enabled: true, baseURL: "http://localhost:8787") {
            let appState = AppState(provider: MockAgentProvider(), apiKeyStore: InMemoryAPIKeyStore(apiKey: "cursor-test-key"))
            appState.account = ProviderAccount(
                apiKeyName: "Runline Test Key",
                userEmail: "test@example.com",
                createdAt: .now
            )
            appState.launchDraft.runMode = .sdkBridge
            appState.sdkBridgeConnectionState = .failed("Runline cannot reach the bridge.")

            appState.ensureLaunchRunModeIsAvailable()

            XCTAssertEqual(appState.launchDraft.runMode, .cloudAgent)
        }
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

    @MainActor
    private func withSDKBridgeDefaults(enabled: Bool, baseURL: String, run test: () -> Void) {
        let defaults = UserDefaults.standard
        let previousEnabled = defaults.object(forKey: SDKBridgePreferences.isEnabledKey)
        let previousBaseURL = defaults.object(forKey: SDKBridgePreferences.baseURLKey)

        defaults.set(enabled, forKey: SDKBridgePreferences.isEnabledKey)
        defaults.set(baseURL, forKey: SDKBridgePreferences.baseURLKey)
        defer {
            if let previousEnabled {
                defaults.set(previousEnabled, forKey: SDKBridgePreferences.isEnabledKey)
            } else {
                defaults.removeObject(forKey: SDKBridgePreferences.isEnabledKey)
            }

            if let previousBaseURL {
                defaults.set(previousBaseURL, forKey: SDKBridgePreferences.baseURLKey)
            } else {
                defaults.removeObject(forKey: SDKBridgePreferences.baseURLKey)
            }
        }

        test()
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
