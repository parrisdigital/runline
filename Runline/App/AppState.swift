import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class AppState {
    private var provider: AgentProvider?
    private var enterpriseProvider: EnterpriseDataProvider?
    private let apiKeyStore: APIKeyStore
    private let enterpriseAPIKeyStore: APIKeyStore
    private let sdkBridgeAuthStore: APIKeyStore
    private let appCache: LocalAppCache
    private let providerFactory: @MainActor (String) throws -> AgentProvider
    private let sdkBridgeProviderFactory: @MainActor (String, URL, String?) throws -> AgentProvider
    private var connectedAPIKey: String?
    private var hasRestoredConnection = false
    private var observingRunIDs: Set<AgentRun.ID> = []
    private var streamExpiredRunIDs: Set<AgentRun.ID> = []
    private var artifactDownloadsByKey: [String: ArtifactDownload] = [:]

    var selectedTab: AppTab = .cursorChat
    var account: ProviderAccount?
    var enterpriseAccount: ProviderAccount?
    var repositories: [Repository] = []
    var models: [AgentModel] = []
    var agents: [Agent] = []
    var runsByAgentID: [String: [AgentRun]] = [:]
    var eventsByRunID: [String: [AgentStreamEvent]] = [:]
    var artifactsByAgentID: [String: [Artifact]] = [:]
    var endpointResults: [CursorAPIEndpoint.ID: CursorAPIEndpointResult] = [:]
    var loadingEndpointIDs: Set<CursorAPIEndpoint.ID> = []
    var endpointPageOverrides: [CursorAPIEndpoint.ID: Int] = [:]
    var focusedAgentID: Agent.ID?
    var notificationPreferences = NotificationPreferences()
    var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    var deviceTokenRegistration: DeviceTokenRegistration?
    var notificationRegistrationError: String?
    var isLoading = false
    var isLaunching = false
    var isRefreshing = false
    var isCheckingSDKBridge = false
    var errorMessage: String?
    var statusMessage: String?
    var launchDraft: AgentLaunchDraft

    init(
        provider: AgentProvider? = nil,
        apiKeyStore: APIKeyStore = KeychainAPIKeyStore(),
        enterpriseAPIKeyStore: APIKeyStore = KeychainAPIKeyStore(account: .cursorEnterpriseAdmin),
        sdkBridgeAuthStore: APIKeyStore = KeychainAPIKeyStore(account: .sdkBridgeAuth),
        appCache: LocalAppCache = LocalAppCache(),
        providerFactory: @escaping @MainActor (String) throws -> AgentProvider = { try CursorAgentProvider(apiKey: $0) },
        sdkBridgeProviderFactory: @escaping @MainActor (String, URL, String?) throws -> AgentProvider = { apiKey, baseURL, bridgeSecret in
            try CursorSDKBridgeProvider(apiKey: apiKey, bridgeBaseURL: baseURL, bridgeSecret: bridgeSecret)
        }
    ) {
        self.provider = provider
        enterpriseProvider = provider as? EnterpriseDataProvider
        self.apiKeyStore = apiKeyStore
        self.enterpriseAPIKeyStore = enterpriseAPIKeyStore
        self.sdkBridgeAuthStore = sdkBridgeAuthStore
        self.appCache = appCache
        self.providerFactory = providerFactory
        self.sdkBridgeProviderFactory = sdkBridgeProviderFactory
        launchDraft = AgentLaunchDraft(
            prompt: AgentPrompt(text: ""),
            modelID: nil,
            source: .repository(url: URL(string: "https://github.com/owner/repository")!, startingRef: nil),
            runtimeMode: .cloud,
            branchName: nil,
            autoGenerateBranch: true,
            autoCreatePullRequest: true,
            skipReviewerRequest: false
        )
    }

    var capabilities: ProviderCapabilities {
        provider?.capabilities ?? .disconnected
    }

    var enterpriseEndpoints: [CursorAPIEndpoint] {
        enterpriseProvider?.enterpriseEndpoints ?? CursorAPIEndpointCatalog.endpoints
    }

    var isConnected: Bool {
        account != nil
    }

    var isSDKBridgeEnabled: Bool {
        SDKBridgePreferences.isEnabled()
    }

    var sdkBridgeURLString: String {
        SDKBridgePreferences.baseURLString()
    }

    var isSDKBridgeConfigured: Bool {
        SDKBridgePreferences.configuredBaseURL() != nil
    }

    var activeAgents: [Agent] {
        agents.filter { agent in
            guard case .archived = agent.status else { return true }
            return false
        }
    }

    var selectedRepository: Repository? {
        if case .repository(let url, _) = launchDraft.source {
            return repositories.first(where: { $0.url == url })
        }
        return nil
    }

    var canLaunchAgent: Bool {
        guard launchDraft.prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }
        if launchDraft.runtimeMode == .sdkBridge {
            guard SDKBridgePreferences.configuredBaseURL() != nil else { return false }
        }
        if !launchDraft.autoGenerateBranch,
           launchDraft.branchName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return false
        }
        switch launchDraft.source {
        case .general:
            guard launchDraft.runtimeMode == .sdkBridge else { return false }
        case .repository(let url, _):
            guard Self.isUsableRepositoryURL(url) else { return false }
        case .pullRequest(let url):
            guard Self.isUsablePullRequestURL(url) else { return false }
        }
        return true
    }

    func restoreConnectionIfAvailable() async {
        guard !hasRestoredConnection else { return }
        hasRestoredConnection = true

        do {
            guard let apiKey = try apiKeyStore.loadAPIKey() else { return }
            if let snapshot = try appCache.load() {
                apply(snapshot)
            }
            await connect(apiKey: apiKey, shouldPersist: false)
            if let enterpriseAPIKey = try enterpriseAPIKeyStore.loadAPIKey() {
                await connectEnterpriseAPIKey(apiKey: enterpriseAPIKey, shouldPersist: false)
            }
        } catch {
            errorMessage = "Could not read the saved Cursor API key."
        }
    }

    func connect(apiKey: String, shouldPersist: Bool = true) async {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            errorMessage = CursorAPIError.emptyAPIKey.userMessage
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let cursorProvider = try providerFactory(trimmedKey)
            let validatedAccount = try await cursorProvider.validateConnection()
            if shouldPersist {
                try apiKeyStore.saveAPIKey(trimmedKey)
            }
            provider = cursorProvider
            enterpriseProvider = cursorProvider as? EnterpriseDataProvider
            connectedAPIKey = trimmedKey
            account = validatedAccount
        } catch {
            provider = nil
            enterpriseProvider = nil
            connectedAPIKey = nil
            account = nil
            handleError(error)
            isLoading = false
            return
        }

        do {
            try await refreshWorkspace()
        } catch {
            handleNonBlockingError(error)
        }
        isLoading = false
    }

    func disconnect() {
        do {
            try apiKeyStore.deleteAPIKey()
            try enterpriseAPIKeyStore.deleteAPIKey()
        } catch {
            errorMessage = "Could not remove the local Cursor API key."
        }
        try? appCache.clear()
        provider = nil
        enterpriseProvider = nil
        connectedAPIKey = nil
        account = nil
        enterpriseAccount = nil
        repositories = []
        models = []
        agents = []
        runsByAgentID = [:]
        eventsByRunID = [:]
        artifactsByAgentID = [:]
        endpointResults = [:]
        loadingEndpointIDs = []
        endpointPageOverrides = [:]
        notificationPreferences = NotificationPreferences()
        deviceTokenRegistration = nil
        selectedTab = .cursorChat
    }

    func setSDKBridgeEnabled(_ isEnabled: Bool) {
        SDKBridgePreferences.setEnabled(isEnabled)
        if !isEnabled, launchDraft.runtimeMode == .sdkBridge {
            launchDraft.applyRuntimeMode(.cloud)
        }
        saveCachedState()
    }

    func setSDKBridgeURLString(_ value: String) {
        SDKBridgePreferences.setBaseURLString(value)
        saveCachedState()
    }

    func saveSDKBridgeSecret(_ value: String) {
        do {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try sdkBridgeAuthStore.deleteAPIKey()
            } else {
                try sdkBridgeAuthStore.saveAPIKey(trimmed)
            }
            statusMessage = "SDK Bridge settings saved."
        } catch {
            errorMessage = "Could not save SDK Bridge settings."
        }
    }

    func testSDKBridgeConnection() async {
        isCheckingSDKBridge = true
        errorMessage = nil
        defer { isCheckingSDKBridge = false }

        do {
            let bridgeProvider = try agentProvider(for: .sdkBridge)
            _ = try await bridgeProvider.validateConnection()
            statusMessage = "SDK Bridge connection verified."
        } catch {
            handleError(error)
        }
    }

    func connectEnterpriseAPIKey(apiKey: String, shouldPersist: Bool = true) async {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            errorMessage = CursorAPIError.emptyAPIKey.userMessage
            return
        }

        do {
            let cursorProvider = try providerFactory(trimmedKey)
            enterpriseAccount = try await cursorProvider.validateConnection()
            enterpriseProvider = cursorProvider as? EnterpriseDataProvider
            if shouldPersist {
                try enterpriseAPIKeyStore.saveAPIKey(trimmedKey)
            }
        } catch {
            enterpriseAccount = nil
            handleError(error)
        }
    }

    func disconnectEnterpriseAPIKey() {
        do {
            try enterpriseAPIKeyStore.deleteAPIKey()
            enterpriseAccount = nil
            enterpriseProvider = provider as? EnterpriseDataProvider
            endpointResults = [:]
            loadingEndpointIDs = []
        } catch {
            errorMessage = "Could not remove the enterprise Cursor API key."
        }
    }

    func refreshWorkspace() async throws {
        guard let provider else { throw CursorAPIError.missingProvider }

        isRefreshing = true
        defer { isRefreshing = false }

        var refreshError: Error?

        do {
            repositories = try await provider.listRepositories()
        } catch {
            refreshError = error
        }

        do {
            models = try await provider.listModels()
        } catch {
            refreshError = refreshError ?? error
        }

        let existingAgentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        let existingSDKAgents = agents.filter { $0.runtimeMode == .sdkBridge }
        let existingCloudAgents = agents.filter { $0.runtimeMode == .cloud }
        var mergedAgents: [Agent]

        do {
            let cloudAgents = try await provider.listAgents()
            mergedAgents = cloudAgents.map { reconciledIncomingAgent($0, existing: existingAgentsByID[$0.id]) }
        } catch {
            refreshError = refreshError ?? error
            mergedAgents = existingCloudAgents
        }

        do {
            if let bridgeProvider = try? agentProvider(for: .sdkBridge) {
                let bridgeAgents = try await bridgeProvider.listAgents()
                for bridgeAgent in bridgeAgents {
                    let resolvedBridgeAgent = reconciledIncomingAgent(bridgeAgent, existing: existingAgentsByID[bridgeAgent.id])
                    if let existingIndex = mergedAgents.firstIndex(where: { $0.id == bridgeAgent.id }) {
                        mergedAgents[existingIndex] = resolvedBridgeAgent
                    } else {
                        mergedAgents.append(resolvedBridgeAgent)
                    }
                }
            }
        } catch {
            refreshError = refreshError ?? error
        }

        agents = mergedAgents + existingSDKAgents.filter { sdkAgent in
            !mergedAgents.contains { $0.id == sdkAgent.id }
        }

        if let firstRepo = repositories.first, selectedRepository == nil {
            launchDraft.source = .repository(url: firstRepo.url, startingRef: firstRepo.defaultBranch.nilIfBlank)
        } else if case .repository(let url, let startingRef) = launchDraft.source,
                  let repository = repositories.first(where: { $0.url == url }),
                  repository.defaultBranch.isEmpty,
                  startingRef?.lowercased() == "main" {
            launchDraft.source = .repository(url: url, startingRef: nil)
        }
        if launchDraft.modelID == nil {
            launchDraft.modelID = launchDraft.runtimeMode == .cloud
                ? CursorCloudModelPreference.selectedModelID()
                : CursorChatModelPreference.selectedModelID()
        }

        for agent in agents {
            do {
                let runs = try await agentProvider(for: agent).listRuns(agentID: agent.id)
                runsByAgentID[agent.id] = runs
                if let latestRun = runs.first, latestRun.status.isTerminal {
                    if let preloadedEvents = try? await agentProvider(for: agent).streamEvents(agentID: agent.id, runID: latestRun.id),
                       !preloadedEvents.isEmpty {
                        mergeEvents(preloadedEvents, runID: latestRun.id)
                    }
                }
            } catch {
                if isNotFound(error) {
                    runsByAgentID[agent.id] = []
                }
            }
        }
        refreshAutomaticConversationMetadata()
        saveCachedState()

        if let refreshError {
            throw refreshError
        }
        statusMessage = nil
    }

    func reloadWorkspace() async {
        do {
            try await refreshWorkspace()
        } catch {
            handleNonBlockingError(error)
        }
    }

    func dismissStatusMessage() {
        statusMessage = nil
    }

    func runs(for agent: Agent) -> [AgentRun] {
        runsByAgentID[agent.id, default: []]
    }

    func events(for runID: String) -> [AgentStreamEvent] {
        eventsByRunID[runID, default: []]
    }

    func isObserving(runID: AgentRun.ID) -> Bool {
        observingRunIDs.contains(runID)
    }

    func isStreamExpired(runID: AgentRun.ID) -> Bool {
        streamExpiredRunIDs.contains(runID)
    }

    func refreshAgentDetail(agentID: Agent.ID) async {
        let provider: AgentProvider
        do {
            guard let agent = agent(id: agentID) else { throw CursorAPIError.missingProvider }
            provider = try agentProvider(for: agent)
        } catch {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return
        }

        do {
            let agent = try await provider.getAgent(agentID: agentID)
            upsertAgent(agent)

            let runs = try await provider.listRuns(agentID: agentID)
            runsByAgentID[agentID] = runs

            if let selectedRunID = runs.first?.id {
                let selectedRun = (try? await provider.getRun(agentID: agentID, runID: selectedRunID)) ?? runs[0]
                updateRun(selectedRun, agentID: agentID)
            }

            saveCachedState()
        } catch {
            if shouldReport(error) {
                handleNonBlockingError(error)
            }
        }
    }

    func loadEvents(for agent: Agent, run: AgentRun) async {
        let provider: AgentProvider
        do {
            provider = try agentProvider(for: agent)
        } catch {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return
        }
        do {
            mergeEvents(try await provider.streamEvents(agentID: agent.id, runID: run.id), runID: run.id)
            saveCachedState()
        } catch {
            if isStreamExpired(error) {
                streamExpiredRunIDs.insert(run.id)
                saveCachedState()
                return
            }
            if shouldReport(error) {
                handleNonBlockingError(error)
            }
        }
    }

    func observeRun(agent: Agent, run: AgentRun) async {
        guard observingRunIDs.contains(run.id) == false else { return }

        observingRunIDs.insert(run.id)
        streamExpiredRunIDs.remove(run.id)
        defer { observingRunIDs.remove(run.id) }

        let provider: AgentProvider
        do {
            provider = try agentProvider(for: agent)
        } catch {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return
        }

        var emptyRefreshCount = 0
        var currentRun = run

        while !Task.isCancelled {
            do {
                let events = try await provider.streamEvents(agentID: agent.id, runID: currentRun.id)
                var shouldSaveSnapshot = false
                if events.isEmpty {
                    emptyRefreshCount += 1
                } else {
                    emptyRefreshCount = 0
                    mergeEvents(events, runID: currentRun.id)
                    shouldSaveSnapshot = true
                }

                let runs = try await provider.listRuns(agentID: agent.id)
                if runsByAgentID[agent.id, default: []] != runs {
                    runsByAgentID[agent.id] = runs
                    shouldSaveSnapshot = true
                }
                if let refreshedRun = runs.first(where: { $0.id == currentRun.id }) {
                    currentRun = refreshedRun
                }

                if currentRun.status.isTerminal {
                    streamExpiredRunIDs.remove(currentRun.id)
                    _ = await artifacts(for: agent, forceRefresh: true)
                    saveCachedState()
                    return
                }

                if emptyRefreshCount >= 3 {
                    streamExpiredRunIDs.insert(currentRun.id)
                    saveCachedState()
                    return
                }

                if shouldSaveSnapshot {
                    saveCachedState()
                }
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                if isCancellation(error) {
                    return
                }
                if isNotFound(error) {
                    emptyRefreshCount += 1
                    if emptyRefreshCount >= 3 {
                        streamExpiredRunIDs.insert(currentRun.id)
                        saveCachedState()
                        return
                    }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                }
                if isStreamExpired(error) {
                    let refreshedRun = (try? await provider.getRun(agentID: agent.id, runID: currentRun.id)) ?? currentRun
                    updateRun(refreshedRun, agentID: agent.id)
                    streamExpiredRunIDs.insert(currentRun.id)
                    saveCachedState()
                    return
                }
                streamExpiredRunIDs.insert(currentRun.id)
                handleNonBlockingError(error)
                saveCachedState()
                return
            }
        }
    }

    func artifacts(for agent: Agent, forceRefresh: Bool = false) async -> [Artifact] {
        if !forceRefresh, let cached = artifactsByAgentID[agent.id] {
            return cached
        }
        let provider: AgentProvider
        do {
            provider = try agentProvider(for: agent)
        } catch {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return []
        }
        do {
            let artifacts = try await provider.listArtifacts(agentID: agent.id)
            artifactsByAgentID[agent.id] = artifacts
            saveCachedState()
            return artifacts
        } catch {
            if isNotFound(error) {
                artifactsByAgentID[agent.id] = []
                saveCachedState()
            } else if shouldReport(error) {
                handleNonBlockingError(error)
            }
            return []
        }
    }

    func downloadArtifact(agentID: Agent.ID, path: String) async -> URL? {
        let provider: AgentProvider
        do {
            guard let agent = agent(id: agentID) else { throw CursorAPIError.missingProvider }
            provider = try agentProvider(for: agent)
        } catch {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return nil
        }
        let cacheKey = "\(agentID):\(path)"
        if let cached = artifactDownloadsByKey[cacheKey], cached.expiresAt > Date(timeIntervalSinceNow: 60) {
            return cached.url
        }
        do {
            let download = try await provider.downloadArtifact(agentID: agentID, path: path)
            artifactDownloadsByKey[cacheKey] = download
            return download.url
        } catch {
            handleError(error)
            return nil
        }
    }

    @discardableResult
    func launchAgent() async -> AgentLaunchResult? {
        guard canLaunchAgent else {
            errorMessage = "Select a repository and add instructions before launching an agent."
            return nil
        }

        isLaunching = true
        errorMessage = nil
        var draft = launchDraft
        draft.modelID = switch draft.runtimeMode {
        case .cloud:
            CursorCloudModelPreference.resolvedModelID(draft.modelID)
        case .sdkBridge:
            CursorChatModelPreference.resolvedModelID(draft.modelID)
        }
        defer { isLaunching = false }

        do {
            let provider = try agentProvider(for: draft.runtimeMode)
            let result = try await provider.createAgent(draft)
            let initialEvents = initialLocalEvents(runID: result.run.id, prompt: draft.prompt)
            let launchedAgent = agentWithAutomaticConversationMetadata(result.agent, events: initialEvents)
            agents.insert(launchedAgent, at: 0)
            runsByAgentID[launchedAgent.id] = [result.run]
            eventsByRunID[result.run.id] = initialEvents
            focusedAgentID = launchedAgent.id
            selectedTab = AppTab(runtimeMode: launchedAgent.runtimeMode)
            saveCachedState()
            return AgentLaunchResult(agent: launchedAgent, run: result.run)
        } catch {
            handleError(error)
            return nil
        }
    }

    func createFollowUp(agent: Agent, text: String) async {
        await createFollowUp(agent: agent, prompt: AgentPrompt(text: text))
    }

    func workspaceHandoffDraft(
        from agent: Agent,
        events: [AgentStreamEvent],
        repository: Repository,
        branch: String?,
        instruction: String
    ) -> AgentLaunchDraft {
        let startingRef = branch?.nilIfBlank ?? repository.defaultBranch.nilIfBlank
        return AgentLaunchDraft(
            prompt: AgentPrompt(
                text: WorkspaceHandoffPromptBuilder.prompt(
                    from: events,
                    instruction: instruction,
                    sourceTitle: agent.name
                )
            ),
            modelID: agent.modelID,
            source: .repository(url: repository.url, startingRef: startingRef),
            runtimeMode: .sdkBridge,
            branchName: nil,
            autoGenerateBranch: true,
            autoCreatePullRequest: false,
            skipReviewerRequest: false
        )
    }

    @discardableResult
    func createWorkspaceFromGeneralChat(
        agent: Agent,
        events: [AgentStreamEvent],
        repository: Repository,
        branch: String?,
        instruction: String
    ) async -> AgentLaunchResult? {
        launchDraft = workspaceHandoffDraft(
            from: agent,
            events: events,
            repository: repository,
            branch: branch,
            instruction: instruction
        )
        return await launchAgent()
    }

    func createFollowUp(
        agent: Agent,
        prompt: AgentPrompt,
        modelID: String? = nil
    ) async {
        let provider: AgentProvider
        do {
            provider = try agentProvider(for: agent)
        } catch {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return
        }
        let promptText = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptText.isEmpty else {
            errorMessage = "Add a follow-up instruction first."
            return
        }

        let followUpPrompt = AgentPrompt(text: promptText, images: prompt.images, files: prompt.files)
        do {
            let run = try await provider.createRun(
                AgentFollowUpDraft(
                    agentID: agent.id,
                    prompt: followUpPrompt,
                    modelID: modelID
                )
            )
            let refreshedRuns = (try? await provider.listRuns(agentID: agent.id)) ?? [run] + runsByAgentID[agent.id, default: []]
            runsByAgentID[agent.id] = refreshedRuns
            eventsByRunID[run.id] = initialLocalEvents(runID: run.id, prompt: followUpPrompt)
            refreshAutomaticConversationMetadata(runID: run.id)
            saveCachedState()
        } catch {
            handleError(error)
        }
    }

    func cancel(agent: Agent, run: AgentRun) async {
        let provider: AgentProvider
        do {
            provider = try agentProvider(for: agent)
        } catch {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return
        }
        do {
            try await provider.cancelRun(agentID: agent.id, runID: run.id)
            runsByAgentID[agent.id] = try await provider.listRuns(agentID: agent.id)
            saveCachedState()
        } catch {
            handleError(error)
        }
    }

    func archive(agent: Agent) async {
        let provider: AgentProvider
        do {
            provider = try agentProvider(for: agent)
        } catch {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return
        }
        do {
            try await provider.archiveAgent(agentID: agent.id)
            updateAgent(agent.id) { $0.status = .archived }
            selectedTab = AppTab(runtimeMode: agent.runtimeMode)
            saveCachedState()
        } catch {
            handleError(error)
        }
    }

    func unarchive(agent: Agent) async {
        let provider: AgentProvider
        do {
            provider = try agentProvider(for: agent)
        } catch {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return
        }
        do {
            try await provider.unarchiveAgent(agentID: agent.id)
            updateAgent(agent.id) { $0.status = .active }
            saveCachedState()
        } catch {
            handleError(error)
        }
    }

    func delete(agent: Agent) async {
        let provider: AgentProvider
        do {
            provider = try agentProvider(for: agent)
        } catch {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return
        }
        do {
            try await provider.deleteAgent(agentID: agent.id)
            agents.removeAll { $0.id == agent.id }
            runsByAgentID.removeValue(forKey: agent.id)
            artifactsByAgentID.removeValue(forKey: agent.id)
            selectedTab = AppTab(runtimeMode: agent.runtimeMode)
            saveCachedState()
        } catch {
            handleError(error)
        }
    }

    func result(for endpoint: CursorAPIEndpoint) -> CursorAPIEndpointResult? {
        endpointResults[effectiveEndpoint(endpoint).id]
    }

    func agent(id: Agent.ID) -> Agent? {
        agents.first { $0.id == id }
    }

    func isLoading(_ endpoint: CursorAPIEndpoint) -> Bool {
        loadingEndpointIDs.contains(effectiveEndpoint(endpoint).id)
    }

    func page(for endpoint: CursorAPIEndpoint) -> Int {
        endpointPageOverrides[endpoint.id] ?? endpoint.page ?? 1
    }

    func setPage(_ page: Int, for endpoint: CursorAPIEndpoint) {
        endpointPageOverrides[endpoint.id] = max(1, page)
    }

    func fetchEndpoint(_ endpoint: CursorAPIEndpoint) async {
        guard let enterpriseProvider else {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return
        }

        let endpoint = effectiveEndpoint(endpoint)
        loadingEndpointIDs.insert(endpoint.id)
        defer { loadingEndpointIDs.remove(endpoint.id) }

        do {
            endpointResults[endpoint.id] = try await enterpriseProvider.fetchEndpoint(endpoint)
        } catch {
            guard !isCancellation(error) else { return }
            endpointResults[endpoint.id] = CursorAPIEndpointResult(
                endpoint: endpoint,
                statusCode: statusCode(from: error),
                latencyMilliseconds: 0,
                capturedAt: .now,
                etag: nil,
                preview: "",
                recordCount: nil,
                errorMessage: userMessage(from: error)
            )
        }
    }

    func fetchEndpoints(in area: CursorAPIEndpointArea) async {
        for endpoint in enterpriseEndpoints.filter({ $0.area == area }) {
            await fetchEndpoint(endpoint)
        }
    }

    func requestNotificationPermission() async {
        do {
            let center = UNUserNotificationCenter.current()
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            notificationAuthorizationStatus = await center.notificationSettings().authorizationStatus
            if notificationAuthorizationStatus == .authorized || notificationAuthorizationStatus == .provisional {
                UIApplication.shared.registerForRemoteNotifications()
            }
            saveCachedState()
        } catch {
            errorMessage = "Runline could not update notification permission."
        }
    }

    func refreshNotificationStatus() async {
        notificationAuthorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func updateNotificationPreferences(_ mutate: (inout NotificationPreferences) -> Void) {
        mutate(&notificationPreferences)
        if var registration = deviceTokenRegistration {
            registration.preferences = notificationPreferences
            registration.updatedAt = .now
            deviceTokenRegistration = registration
        }
        saveCachedState()
    }

    func handleDeepLink(_ url: URL) {
        guard let deepLink = RunlineDeepLink(url: url) else { return }
        switch deepLink {
        case .agent(let agentID):
            focusedAgentID = agentID
            selectedTab = tab(forAgentID: agentID)
        case .run(let agentID, _):
            focusedAgentID = agentID
            selectedTab = tab(forAgentID: agentID)
        }
    }

    func updateDeviceToken(_ deviceToken: Data) {
        let registration = DeviceTokenRegistration(
            deviceID: storedDeviceID,
            tokenHex: deviceToken.hexadecimalString,
            environment: .production,
            preferences: notificationPreferences,
            appVersion: appVersion,
            updatedAt: .now
        )
        deviceTokenRegistration = registration
        notificationRegistrationError = nil
        saveCachedState()
    }

    func updateDeviceTokenRegistrationFailure(_ error: Error) {
        notificationRegistrationError = userMessage(from: error)
        saveCachedState()
    }

    private func updateAgent(_ agentID: Agent.ID, mutate: (inout Agent) -> Void) {
        guard let index = agents.firstIndex(where: { $0.id == agentID }) else { return }
        mutate(&agents[index])
    }

    private func tab(forAgentID agentID: Agent.ID) -> AppTab {
        guard let agent = agent(id: agentID) else { return .cursorCloud }
        return AppTab(runtimeMode: agent.runtimeMode)
    }

    private func effectiveEndpoint(_ endpoint: CursorAPIEndpoint) -> CursorAPIEndpoint {
        guard endpoint.supportsPagination else { return endpoint }
        return endpoint.withPage(page(for: endpoint))
    }

    private func agentProvider(for agent: Agent) throws -> AgentProvider {
        try agentProvider(for: agent.runtimeMode)
    }

    private func agentProvider(for runtimeMode: AgentRuntimeMode) throws -> AgentProvider {
        switch runtimeMode {
        case .cloud:
            guard let provider else { throw CursorAPIError.missingProvider }
            return provider
        case .sdkBridge:
            guard let baseURL = SDKBridgePreferences.configuredBaseURL() else {
                throw SDKBridgeError.invalidURL
            }
            let storedAPIKey = try apiKeyStore.loadAPIKey()
            guard let apiKey = connectedAPIKey ?? storedAPIKey else {
                throw CursorAPIError.missingProvider
            }
            return try sdkBridgeProviderFactory(apiKey, baseURL, try sdkBridgeAuthStore.loadAPIKey())
        }
    }

    private func upsertAgent(_ agent: Agent) {
        let resolvedAgent = reconciledIncomingAgent(agent, existing: self.agent(id: agent.id))
        if let index = agents.firstIndex(where: { $0.id == resolvedAgent.id }) {
            agents[index] = resolvedAgent
        } else {
            agents.insert(resolvedAgent, at: 0)
        }
    }

    private func reconciledIncomingAgent(_ incomingAgent: Agent, existing: Agent?) -> Agent {
        guard incomingAgent.runtimeMode == .sdkBridge,
              let existing,
              existing.runtimeMode == .sdkBridge else {
            return incomingAgent
        }

        var resolvedAgent = incomingAgent
        if ConversationTitleGenerator.isPlaceholderTitle(incomingAgent.name, repository: incomingAgent.repository),
           !ConversationTitleGenerator.isPlaceholderTitle(existing.name, repository: existing.repository) {
            resolvedAgent.name = existing.name
        }
        if resolvedAgent.conversationPreview?.nilIfBlank == nil {
            resolvedAgent.conversationPreview = existing.conversationPreview
        }
        return resolvedAgent
    }

    private func refreshAutomaticConversationMetadata() {
        for runID in eventsByRunID.keys {
            refreshAutomaticConversationMetadata(runID: runID)
        }
    }

    private func refreshAutomaticConversationMetadata(runID: AgentRun.ID) {
        guard let agentIndex = agents.firstIndex(where: { agent in
            runsByAgentID[agent.id, default: []].contains { $0.id == runID }
        }),
              agents[agentIndex].runtimeMode == .sdkBridge else {
            return
        }

        let events = eventsByRunID[runID, default: []]
        if let preview = ConversationPreviewGenerator.preview(from: events) {
            agents[agentIndex].conversationPreview = preview
        }

        if let title = ConversationTitleGenerator.title(from: events, repository: agents[agentIndex].repository) {
            let firstPrompt = events.first { $0.kind == .user }?.message
            guard ConversationTitleGenerator.shouldReplace(
                currentTitle: agents[agentIndex].name,
                with: title,
                repository: agents[agentIndex].repository,
                firstPrompt: firstPrompt
            ) else {
                return
            }

            agents[agentIndex].name = title
        }
    }

    private func agentWithAutomaticConversationMetadata(_ agent: Agent, events: [AgentStreamEvent]) -> Agent {
        guard agent.runtimeMode == .sdkBridge else { return agent }

        var updatedAgent = agent
        updatedAgent.conversationPreview = ConversationPreviewGenerator.preview(from: events)
        if let title = ConversationTitleGenerator.title(from: events, repository: agent.repository),
           ConversationTitleGenerator.shouldReplace(
                currentTitle: agent.name,
                with: title,
                repository: agent.repository,
                firstPrompt: events.first { $0.kind == .user }?.message
           ) {
            updatedAgent.name = title
        }
        return updatedAgent
    }

    private func updateRun(_ run: AgentRun, agentID: Agent.ID) {
        var runs = runsByAgentID[agentID, default: []]
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = run
        } else {
            runs.insert(run, at: 0)
        }
        runsByAgentID[agentID] = runs
    }

    private func mergeEvents(_ events: [AgentStreamEvent], runID: AgentRun.ID) {
        guard events.isEmpty == false else { return }
        var existing = eventsByRunID[runID, default: []]
        if events.contains(where: { $0.kind == .user }) {
            existing.removeAll { isLocalUserEvent($0, runID: runID) }
        }
        let knownIDs = Set(existing.map(\.id))
        existing.append(contentsOf: events.filter { knownIDs.contains($0.id) == false })
        eventsByRunID[runID] = existing
        refreshAutomaticConversationMetadata(runID: runID)
    }

    private func initialLocalEvents(runID: AgentRun.ID, prompt: AgentPrompt) -> [AgentStreamEvent] {
        let text = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return [
            AgentStreamEvent(
                id: localUserEventID(runID: runID),
                runID: runID,
                kind: .user,
                title: "User",
                message: text,
                timestamp: "now"
            )
        ]
    }

    private func isLocalUserEvent(_ event: AgentStreamEvent, runID: AgentRun.ID) -> Bool {
        event.kind == .user && event.id == localUserEventID(runID: runID)
    }

    private func localUserEventID(runID: AgentRun.ID) -> String {
        "\(runID)-local-user"
    }

    private func repository(from source: AgentSource) -> Repository {
        switch source {
        case .general:
            return Self.repository(
                from: URL(string: "https://cursor.com/general-chat")!,
                defaultBranch: nil
            )
        case .repository(let url, let startingRef):
            return repositories.first(where: { $0.url == url })
                ?? Self.repository(from: url, defaultBranch: startingRef)
        case .pullRequest(let url):
            let repoURL = Self.repositoryURL(fromPullRequestURL: url) ?? url
            return repositories.first(where: { $0.url == repoURL })
                ?? Self.repository(from: repoURL, defaultBranch: nil)
        }
    }

    private static func repository(from url: URL, defaultBranch: String?) -> Repository {
        let components = url.path.split(separator: "/").map(String.init)
        let owner = components.first ?? url.host ?? "Repository"
        let rawName = components.dropFirst().first ?? url.lastPathComponent
        let name = rawName.replacingOccurrences(of: ".git", with: "")
        return Repository(
            owner: owner,
            name: name.isEmpty ? "Repository" : name,
            url: url,
            defaultBranch: defaultBranch?.nilIfBlank ?? "main",
            isFavorite: false,
            lastUsedDescription: "now"
        )
    }

    private static func repositoryURL(fromPullRequestURL url: URL) -> URL? {
        let components = url.path.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return nil }
        var urlComponents = URLComponents()
        urlComponents.scheme = url.scheme
        urlComponents.host = url.host
        urlComponents.path = "/\(components[0])/\(components[1])"
        return urlComponents.url
    }

    private func userMessage(from error: Error) -> String {
        if let bridgeError = error as? SDKBridgeError {
            return bridgeError.localizedDescription
        }
        if let apiError = error as? CursorAPIError {
            return apiError.userMessage
        }
        return error.localizedDescription
    }

    private func handleError(_ error: Error) {
        guard !isCancellation(error) else { return }
        errorMessage = userMessage(from: error)
    }

    private func handleNonBlockingError(_ error: Error) {
        guard shouldReport(error) else { return }
        statusMessage = nonBlockingMessage(from: error)
    }

    private func nonBlockingMessage(from error: Error) -> String {
        if let apiError = error as? CursorAPIError {
            switch apiError {
            case .decodingFailed(let message), .unsupportedResponse(let message):
                if let endpoint = cursorEndpoint(from: message) {
                    return "Cursor returned data Runline could not parse from \(endpoint). Your key is still connected; refresh again shortly."
                }
                return "Cursor returned data Runline could not parse. Your key is still connected; refresh again shortly."
            case .requestFailed(429, _):
                return "Cursor rate-limited this refresh. Your key is still connected; try again shortly."
            default:
                return apiError.userMessage
            }
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "Cursor refresh timed out. Your key is still connected; try again shortly."
        }
        return error.localizedDescription
    }

    private func cursorEndpoint(from message: String) -> String? {
        guard let endpointRange = message.range(of: "endpoint=") else { return nil }
        let suffix = message[endpointRange.upperBound...]
        guard let rawEndpoint = suffix.split(separator: "|", maxSplits: 1).first else { return nil }
        let endpoint = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return endpoint.hasPrefix("/") ? endpoint : nil
    }

    private func shouldReport(_ error: Error) -> Bool {
        !isCancellation(error) && !isNotFound(error)
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func isNotFound(_ error: Error) -> Bool {
        if case SDKBridgeError.requestFailed(statusCode: 404, _) = error {
            return true
        }
        return (error as? CursorAPIError)?.isNotFound == true
    }

    private func isStreamExpired(_ error: Error) -> Bool {
        (error as? CursorAPIError)?.isStreamExpired == true
    }

    private func statusCode(from error: Error) -> Int {
        if case let SDKBridgeError.requestFailed(statusCode, _) = error {
            return statusCode
        }
        if case let CursorAPIError.requestFailed(statusCode, _) = error {
            return statusCode
        }
        return -1
    }

    private static func isUsableRepositoryURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["https", "http", "ssh"].contains(scheme),
              url.host?.isEmpty == false else {
            return false
        }
        return url.path.split(separator: "/").count >= 2
    }

    private static func isUsablePullRequestURL(_ url: URL) -> Bool {
        guard isUsableRepositoryURL(url) else { return false }
        let components = url.path.split(separator: "/").map(String.init)
        return components.contains("pull") || components.contains("merge_requests")
    }

    private func apply(_ snapshot: AppCacheSnapshot) {
        account = snapshot.account
        enterpriseAccount = snapshot.enterpriseAccount
        repositories = snapshot.repositories
        models = snapshot.models
        agents = snapshot.agents
        runsByAgentID = snapshot.runsByAgentID
        eventsByRunID = snapshot.eventsByRunID
        artifactsByAgentID = snapshot.artifactsByAgentID
        launchDraft = snapshot.launchDraft
        notificationPreferences = snapshot.notificationPreferences
        deviceTokenRegistration = snapshot.deviceTokenRegistration
        notificationRegistrationError = nil
    }

    private var storedDeviceID: UUID {
        let key = "runline.deviceID"
        if let value = UserDefaults.standard.string(forKey: key), let uuid = UUID(uuidString: value) {
            return uuid
        }
        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: key)
        return uuid
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    private func saveCachedState() {
        let snapshot = AppCacheSnapshot(
            account: account,
            enterpriseAccount: enterpriseAccount,
            repositories: repositories,
            models: models,
            agents: agents,
            runsByAgentID: runsByAgentID,
            eventsByRunID: eventsByRunID,
            artifactsByAgentID: artifactsByAgentID,
            launchDraft: launchDraft,
            notificationPreferences: notificationPreferences,
            deviceTokenRegistration: deviceTokenRegistration,
            cachedAt: .now
        )
        try? appCache.save(snapshot)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
