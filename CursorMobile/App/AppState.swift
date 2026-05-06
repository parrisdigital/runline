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
    private let sdkBridgeTokenStore: APIKeyStore
    private let appCache: LocalAppCache
    private let providerFactory: @MainActor (String) throws -> AgentProvider
    private var hasRestoredConnection = false
    private var observingRunIDs: Set<AgentRun.ID> = []
    private var streamExpiredRunIDs: Set<AgentRun.ID> = []
    private var sdkBridgeRunIDs: Set<AgentRun.ID> = []
    private var sdkBridgeMCPProfileIDsByAgentID: [Agent.ID: SDKBridgeMCPProfile.ID] = [:]
    private var sdkBridgeToken: String?
    private var artifactDownloadsByKey: [String: ArtifactDownload] = [:]

    var selectedTab: AppTab = .chats
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
    var sdkBridgeProfiles: [SDKBridgeMCPProfile] = []
    var sdkBridgeConnectionState: SDKBridgeConnectionState = SDKBridgePreferences.isEnabled() ? .unchecked : .disabled
    var sdkBridgePairingState: SDKBridgePairingState = .idle
    var focusedAgentID: Agent.ID?
    var notificationPreferences = NotificationPreferences()
    var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    var deviceTokenRegistration: DeviceTokenRegistration?
    var notificationRegistrationError: String?
    var isLoading = false
    var isLaunching = false
    var isRefreshing = false
    var errorMessage: String?
    var statusMessage: String?
    var launchDraft: AgentLaunchDraft

    private let sdkBridgeClientFactory: @MainActor (URL, String?, String?) -> SDKBridgeClient

    init(
        provider: AgentProvider? = nil,
        apiKeyStore: APIKeyStore = KeychainAPIKeyStore(),
        enterpriseAPIKeyStore: APIKeyStore = KeychainAPIKeyStore(account: .cursorEnterpriseAdmin),
        sdkBridgeTokenStore: APIKeyStore = KeychainAPIKeyStore(account: .runlineBridgeToken),
        appCache: LocalAppCache = LocalAppCache(),
        providerFactory: @escaping @MainActor (String) throws -> AgentProvider = { try CursorAgentProvider(apiKey: $0) },
        sdkBridgeClientFactory: @escaping @MainActor (URL, String?, String?) -> SDKBridgeClient = { baseURL, apiKey, bridgeToken in
            SDKBridgeClient(baseURL: baseURL, apiKey: apiKey, bridgeToken: bridgeToken)
        }
    ) {
        self.provider = provider
        enterpriseProvider = provider as? EnterpriseDataProvider
        self.apiKeyStore = apiKeyStore
        self.enterpriseAPIKeyStore = enterpriseAPIKeyStore
        self.sdkBridgeTokenStore = sdkBridgeTokenStore
        self.appCache = appCache
        self.providerFactory = providerFactory
        self.sdkBridgeClientFactory = sdkBridgeClientFactory
        let storedBridgeToken = try? sdkBridgeTokenStore.loadAPIKey()?.nilIfBlank
        sdkBridgeToken = storedBridgeToken
        launchDraft = AgentLaunchDraft(
            prompt: AgentPrompt(text: ""),
            modelID: nil,
            source: .repository(url: URL(string: "https://github.com/owner/repository")!, startingRef: nil),
            branchName: nil,
            autoGenerateBranch: true,
            autoCreatePullRequest: true,
            skipReviewerRequest: false
        )
        if storedBridgeToken != nil {
            sdkBridgePairingState = .paired("Runline Bridge")
        }
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
        if !launchDraft.autoGenerateBranch,
           launchDraft.branchName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return false
        }
        switch launchDraft.source {
        case .repository(let url, _):
            guard Self.isUsableRepositoryURL(url) else { return false }
        case .pullRequest(let url):
            guard Self.isUsablePullRequestURL(url) else { return false }
        }

        if launchDraft.runMode == .sdkBridge {
            return sdkBridgeLaunchIssue == nil
        }
        return true
    }

    var isSDKBridgeReadyForLaunch: Bool {
        sdkBridgeReadinessIssue == nil
    }

    var isSDKBridgePaired: Bool {
        sdkBridgeToken?.nilIfBlank != nil
    }

    var sdkBridgeReadinessIssue: String? {
        guard account != nil else {
            return "Connect a Cursor API key before using Cursor SDK."
        }
        guard SDKBridgePreferences.isEnabled() else {
            return "Enable Runline Bridge in Settings before using Cursor SDK."
        }
        guard SDKBridgePreferences.configuredBaseURL() != nil else {
            return "Enter a valid Runline Bridge URL in Settings."
        }
        guard isSDKBridgePaired else {
            return "Pair Runline Bridge in Settings before using Cursor SDK."
        }
        switch sdkBridgeConnectionState {
        case .connected:
            return nil
        case .disabled:
            return "Enable Runline Bridge in Settings before using Cursor SDK."
        case .unchecked:
            return "Check the Runline Bridge connection in Settings before using Cursor SDK."
        case .checking:
            return "Runline is checking the bridge connection."
        case .failed(let message):
            return "Runline Bridge is unavailable. \(message)"
        }
    }

    var sdkBridgeLaunchIssue: String? {
        guard launchDraft.runMode == .sdkBridge else { return nil }
        return sdkBridgeReadinessIssue
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
            account = validatedAccount
            syncSDKBridgeConfiguration()
        } catch {
            provider = nil
            enterpriseProvider = nil
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
            try sdkBridgeTokenStore.deleteAPIKey()
        } catch {
            errorMessage = "Could not remove the local Cursor API key."
        }
        try? appCache.clear()
        provider = nil
        enterpriseProvider = nil
        account = nil
        enterpriseAccount = nil
        repositories = []
        models = []
        agents = []
        runsByAgentID = [:]
        eventsByRunID = [:]
        artifactsByAgentID = [:]
        sdkBridgeRunIDs = []
        sdkBridgeMCPProfileIDsByAgentID = [:]
        sdkBridgeToken = nil
        sdkBridgeProfiles = []
        sdkBridgePairingState = .idle
        sdkBridgeConnectionState = SDKBridgePreferences.isEnabled() ? .unchecked : .disabled
        endpointResults = [:]
        loadingEndpointIDs = []
        endpointPageOverrides = [:]
        notificationPreferences = NotificationPreferences()
        deviceTokenRegistration = nil
        selectedTab = .chats
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

        do {
            agents = try await provider.listAgents()
        } catch {
            refreshError = refreshError ?? error
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
            launchDraft.modelID = models.first?.id
        }

        for agent in agents {
            do {
                let runs = try await provider.listRuns(agentID: agent.id)
                runsByAgentID[agent.id] = runs
                if let latestRun = runs.first, latestRun.status.isTerminal {
                    eventsByRunID[latestRun.id] = (try? await provider.streamEvents(agentID: agent.id, runID: latestRun.id)) ?? []
                }
            } catch {
                if isNotFound(error) {
                    runsByAgentID[agent.id] = []
                }
            }
        }
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

    func applyDefaultRunMode(_ mode: AgentRunMode) {
        if mode == .sdkBridge, !isSDKBridgeReadyForLaunch {
            launchDraft.runMode = .cloudAgent
            saveCachedState()
            return
        }
        launchDraft.runMode = mode
        saveCachedState()
    }

    func ensureLaunchRunModeIsAvailable() {
        if launchDraft.runMode == .sdkBridge, !isSDKBridgeReadyForLaunch {
            launchDraft.runMode = .cloudAgent
            saveCachedState()
        }
    }

    func isSDKBridgeRun(runID: AgentRun.ID) -> Bool {
        sdkBridgeRunIDs.contains(runID)
    }

    func isSDKBridgeAgent(_ agent: Agent) -> Bool {
        runsByAgentID[agent.id, default: []].contains { sdkBridgeRunIDs.contains($0.id) }
    }

    func sdkBridgeProfile(for agent: Agent) -> SDKBridgeMCPProfile? {
        guard let profileID = sdkBridgeMCPProfileIDsByAgentID[agent.id] else { return nil }
        return sdkBridgeProfiles.first { $0.id == profileID }
    }

    func sdkBridgeProfileID(for agent: Agent) -> SDKBridgeMCPProfile.ID? {
        sdkBridgeMCPProfileIDsByAgentID[agent.id]
    }

    func syncSDKBridgeConfiguration(resetConnection: Bool = false) {
        guard SDKBridgePreferences.isEnabled() else {
            sdkBridgeConnectionState = .disabled
            sdkBridgeProfiles = []
            ensureLaunchRunModeIsAvailable()
            return
        }
        guard SDKBridgePreferences.configuredBaseURL() != nil else {
            sdkBridgeConnectionState = .failed("The bridge URL is invalid.")
            sdkBridgeProfiles = []
            ensureLaunchRunModeIsAvailable()
            return
        }
        if resetConnection || !sdkBridgeConnectionState.isConnected {
            sdkBridgeConnectionState = .unchecked
            sdkBridgeProfiles = []
            ensureLaunchRunModeIsAvailable()
        }
    }

    func startSDKBridgePairing() async {
        guard SDKBridgePreferences.isEnabled() else {
            sdkBridgePairingState = .failed("Enable Runline Bridge before pairing.")
            return
        }
        guard let baseURL = SDKBridgePreferences.configuredBaseURL() else {
            sdkBridgePairingState = .failed("Enter a valid Runline Bridge URL before pairing.")
            return
        }

        sdkBridgePairingState = .starting
        do {
            let response = try await sdkBridgeClientFactory(baseURL, nil, nil).startPairing(deviceName: UIDevice.current.name)
            if response.pairingRequired == false {
                sdkBridgePairingState = .paired("Runline Bridge")
                sdkBridgeConnectionState = .unchecked
                return
            }
            guard let pairingID = response.pairingId?.nilIfBlank else {
                sdkBridgePairingState = .failed("Runline Bridge did not return a pairing session.")
                return
            }
            sdkBridgePairingState = .waiting(
                pairingID: pairingID,
                expiresAt: response.expiresAt,
                message: response.message
            )
        } catch {
            sdkBridgePairingState = .failed(sdkBridgeConnectionFailureMessage(for: error, baseURL: baseURL))
        }
    }

    func completeSDKBridgePairing(code: String) async {
        guard case .waiting(let pairingID, _, _) = sdkBridgePairingState else {
            sdkBridgePairingState = .failed("Start pairing before entering a code.")
            return
        }
        guard let baseURL = SDKBridgePreferences.configuredBaseURL() else {
            sdkBridgePairingState = .failed("Enter a valid Runline Bridge URL before pairing.")
            return
        }
        let pairingCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pairingCode.isEmpty else {
            sdkBridgePairingState = .failed("Enter the pairing code shown in the bridge terminal.")
            return
        }

        sdkBridgePairingState = .completing
        do {
            let response = try await sdkBridgeClientFactory(baseURL, nil, nil).completePairing(
                pairingID: pairingID,
                code: pairingCode,
                deviceName: UIDevice.current.name
            )
            guard let token = response.bridgeToken?.nilIfBlank else {
                sdkBridgePairingState = .failed("Runline Bridge did not return a bridge token.")
                return
            }
            try sdkBridgeTokenStore.saveAPIKey(token)
            sdkBridgeToken = token
            sdkBridgePairingState = .paired(response.bridgeName?.nilIfBlank ?? response.service?.nilIfBlank ?? "Runline Bridge")
            sdkBridgeConnectionState = .unchecked
            await checkSDKBridgeConnection()
        } catch {
            sdkBridgePairingState = .failed(sdkBridgeConnectionFailureMessage(for: error, baseURL: baseURL))
        }
    }

    func forgetSDKBridgePairing() {
        do {
            try sdkBridgeTokenStore.deleteAPIKey()
        } catch {
            errorMessage = "Could not remove the Runline Bridge pairing token."
        }
        sdkBridgeToken = nil
        sdkBridgeProfiles = []
        sdkBridgePairingState = .idle
        sdkBridgeConnectionState = SDKBridgePreferences.isEnabled() ? .unchecked : .disabled
        ensureLaunchRunModeIsAvailable()
    }

    func checkSDKBridgeConnection() async {
        guard SDKBridgePreferences.isEnabled() else {
            sdkBridgeConnectionState = .disabled
            sdkBridgeProfiles = []
            ensureLaunchRunModeIsAvailable()
            return
        }
        guard let baseURL = SDKBridgePreferences.configuredBaseURL() else {
            sdkBridgeConnectionState = .failed("The bridge URL is invalid.")
            sdkBridgeProfiles = []
            ensureLaunchRunModeIsAvailable()
            return
        }
        guard isSDKBridgePaired else {
            sdkBridgeConnectionState = .failed("Pair Runline Bridge before checking Cursor SDK.")
            sdkBridgeProfiles = []
            ensureLaunchRunModeIsAvailable()
            return
        }

        sdkBridgeConnectionState = .checking
        do {
            let health = try await sdkBridgeClientFactory(baseURL, nil, sdkBridgeToken).health()
            if health.ok, health.paired != false {
                sdkBridgeConnectionState = .connected("\(health.service) - \(health.sdk)")
                await reloadSDKBridgeProfiles()
            } else {
                sdkBridgeConnectionState = .failed("The bridge responded but did not accept this pairing token.")
                sdkBridgeProfiles = []
                ensureLaunchRunModeIsAvailable()
            }
        } catch {
            sdkBridgeConnectionState = .failed(sdkBridgeConnectionFailureMessage(for: error, baseURL: baseURL))
            sdkBridgeProfiles = []
            ensureLaunchRunModeIsAvailable()
        }
    }

    func reloadSDKBridgeProfiles() async {
        guard SDKBridgePreferences.isEnabled(),
              let baseURL = SDKBridgePreferences.configuredBaseURL() else {
            sdkBridgeProfiles = []
            return
        }
        guard isSDKBridgePaired else {
            sdkBridgeProfiles = []
            return
        }
        do {
            let apiKey = try apiKeyStore.loadAPIKey()?.nilIfBlank
            sdkBridgeProfiles = try await sdkBridgeClientFactory(baseURL, apiKey, sdkBridgeToken).listMCPProfiles()
            if let profileID = launchDraft.sdkMCPProfileID,
               !sdkBridgeProfiles.contains(where: { $0.id == profileID }) {
                launchDraft.sdkMCPProfileID = nil
            }
        } catch {
            sdkBridgeProfiles = []
            if shouldReport(error) {
                handleNonBlockingError(error)
            }
        }
    }

    func refreshAgentDetail(agentID: Agent.ID) async {
        if runsByAgentID[agentID, default: []].contains(where: { sdkBridgeRunIDs.contains($0.id) }) {
            return
        }
        guard let provider else {
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
        if sdkBridgeRunIDs.contains(run.id) {
            await loadSDKBridgeEvents(for: agent, run: run)
            return
        }

        guard let provider else {
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

        if sdkBridgeRunIDs.contains(run.id) {
            await observeSDKBridgeRun(agent: agent, run: run)
            return
        }

        guard let provider else {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return
        }

        var emptyRefreshCount = 0
        var currentRun = run

        while !Task.isCancelled {
            do {
                let events = try await provider.streamEvents(agentID: agent.id, runID: currentRun.id)
                if events.isEmpty {
                    emptyRefreshCount += 1
                } else {
                    emptyRefreshCount = 0
                    mergeEvents(events, runID: currentRun.id)
                }

                let runs = try await provider.listRuns(agentID: agent.id)
                runsByAgentID[agent.id] = runs
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

                saveCachedState()
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

    private func loadSDKBridgeEvents(for agent: Agent, run: AgentRun) async {
        do {
            let client = try makeSDKBridgeClient()
            let rawEvents = try await client.streamSessionEvents(sessionID: agent.id, runID: run.id)
            mergeEvents(SDKBridgeEventMapper.events(from: rawEvents, runID: run.id), runID: run.id)
            saveCachedState()
        } catch {
            if shouldReport(error) {
                handleNonBlockingError(error)
            }
        }
    }

    private func observeSDKBridgeRun(agent: Agent, run: AgentRun) async {
        var emptyRefreshCount = 0
        var currentRun = run

        while !Task.isCancelled {
            do {
                let client = try makeSDKBridgeClient()
                let rawEvents = try await client.streamSessionEvents(sessionID: agent.id, runID: currentRun.id)
                let mappedEvents = SDKBridgeEventMapper.events(from: rawEvents, runID: currentRun.id)
                if mappedEvents.isEmpty {
                    emptyRefreshCount += 1
                } else {
                    emptyRefreshCount = 0
                    mergeEvents(mappedEvents, runID: currentRun.id)
                }

                let state = try await client.sessionState(sessionID: agent.id, runID: currentRun.id)
                let latestRun = state.latestRun
                currentRun = AgentRun(
                    id: latestRun?.runId ?? currentRun.id,
                    agentID: latestRun?.agentId ?? agent.id,
                    status: latestRun.map { RunStatus(cursorValue: $0.status) } ?? currentRun.status,
                    createdAtDescription: currentRun.createdAtDescription,
                    updatedAtDescription: "now"
                )
                updateRun(currentRun, agentID: agent.id)

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

                saveCachedState()
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                if isCancellation(error) {
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
        guard let provider else {
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
        guard let provider else {
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

    func launchAgent() async {
        guard canLaunchAgent else {
            errorMessage = sdkBridgeLaunchIssue ?? "Select a repository and add instructions before launching an agent."
            return
        }

        isLaunching = true
        errorMessage = nil
        do {
            let result: AgentLaunchResult
            switch launchDraft.runMode {
            case .cloudAgent:
                guard let provider else {
                    throw CursorAPIError.missingProvider
                }
                result = try await provider.createAgent(launchDraft)
            case .sdkBridge:
                result = try await launchSDKBridgeAgent()
                sdkBridgeRunIDs.insert(result.run.id)
            }
            agents.insert(result.agent, at: 0)
            runsByAgentID[result.agent.id] = [result.run]
            eventsByRunID[result.run.id] = launchDraft.runMode == .sdkBridge ? [
                AgentStreamEvent(
                    id: "\(result.run.id)-sdk-started",
                    runID: result.run.id,
                    kind: .status,
                    title: "Cursor SDK",
                    message: "Session started through Runline Bridge.",
                    timestamp: "now"
                )
            ] : []
            focusedAgentID = result.agent.id
            selectedTab = .chats
            saveCachedState()
        } catch {
            handleError(error)
        }
        isLaunching = false
    }

    func createFollowUp(agent: Agent, text: String) async {
        await createFollowUp(agent: agent, prompt: AgentPrompt(text: text))
    }

    func createFollowUp(
        agent: Agent,
        prompt: AgentPrompt,
        intent: SDKMessageIntent = .continueConversation,
        sdkModelID: String? = nil,
        sdkMCPProfileID: String? = nil
    ) async {
        if isSDKBridgeAgent(agent) {
            await createSDKBridgeFollowUp(
                agent: agent,
                prompt: prompt,
                intent: intent,
                modelID: sdkModelID,
                mcpProfileID: sdkMCPProfileID
            )
            return
        }

        guard let provider else {
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
            let run = try await provider.createRun(AgentFollowUpDraft(agentID: agent.id, prompt: followUpPrompt))
            let refreshedRuns = (try? await provider.listRuns(agentID: agent.id)) ?? [run] + runsByAgentID[agent.id, default: []]
            runsByAgentID[agent.id] = refreshedRuns
            eventsByRunID[run.id] = []
            saveCachedState()
        } catch {
            handleError(error)
        }
    }

    private func createSDKBridgeFollowUp(
        agent: Agent,
        prompt: AgentPrompt,
        intent: SDKMessageIntent,
        modelID: String?,
        mcpProfileID: String?
    ) async {
        let promptText = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptText.isEmpty else {
            errorMessage = "Add a follow-up instruction first."
            return
        }

        do {
            let client = try makeSDKBridgeClient()
            let selectedModelID = modelID?.nilIfBlank
            let selectedProfileID = mcpProfileID?.nilIfBlank
            let response = try await client.sendSessionMessage(
                sessionID: agent.id,
                body: SDKBridgeSessionMessageRequest(
                    prompt: AgentPrompt(text: promptText, images: prompt.images, files: prompt.files).textWithFileContext,
                    images: sdkPromptImages(from: prompt),
                    intent: intent.bridgeValue,
                    modelId: selectedModelID?.isCursorDefaultModelIdentifier == true ? nil : selectedModelID,
                    mcpProfileId: selectedProfileID
                )
            )
            let run = AgentRun(
                id: response.runId,
                agentID: response.sessionId ?? response.agentId,
                status: RunStatus(cursorValue: response.status),
                createdAtDescription: "now",
                updatedAtDescription: "now"
            )
            sdkBridgeRunIDs.insert(run.id)
            updateRun(run, agentID: agent.id)
            updateAgent(agent.id) { agent in
                agent.latestRunID = run.id
                agent.updatedAtDescription = "now"
                agent.modelID = selectedModelID ?? "default"
            }
            if let selectedProfileID {
                sdkBridgeMCPProfileIDsByAgentID[agent.id] = selectedProfileID
            } else {
                sdkBridgeMCPProfileIDsByAgentID.removeValue(forKey: agent.id)
            }
            eventsByRunID[run.id] = [
                AgentStreamEvent(
                    id: "\(run.id)-user-message",
                    runID: run.id,
                    kind: .user,
                    title: "User",
                    message: promptText,
                    timestamp: "now"
                ),
                AgentStreamEvent(
                    id: "\(run.id)-sdk-\(intent.rawValue)",
                    runID: run.id,
                    kind: .status,
                    title: "Cursor SDK",
                    message: "\(intent.title) message sent through Runline Bridge.",
                    timestamp: "now"
                ),
            ]
            saveCachedState()
        } catch {
            handleError(error)
        }
    }

    func cancel(agent: Agent, run: AgentRun) async {
        guard let provider else {
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
        guard let provider else {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return
        }
        do {
            try await provider.archiveAgent(agentID: agent.id)
            updateAgent(agent.id) { $0.status = .archived }
            selectedTab = .chats
            saveCachedState()
        } catch {
            handleError(error)
        }
    }

    func unarchive(agent: Agent) async {
        guard let provider else {
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
        guard let provider else {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return
        }
        do {
            try await provider.deleteAgent(agentID: agent.id)
            agents.removeAll { $0.id == agent.id }
            runsByAgentID.removeValue(forKey: agent.id)
            artifactsByAgentID.removeValue(forKey: agent.id)
            selectedTab = .chats
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
        guard let deepLink = CursorMobileDeepLink(url: url) else { return }
        switch deepLink {
        case .agent(let agentID):
            focusedAgentID = agentID
            selectedTab = .chats
        case .run(let agentID, _):
            focusedAgentID = agentID
            selectedTab = .chats
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

    private func launchSDKBridgeAgent() async throws -> AgentLaunchResult {
        let client = try makeSDKBridgeClient()
        let request = SDKBridgeCloudRunRequest(
            prompt: launchDraft.prompt.textWithFileContext,
            images: sdkPromptImages(from: launchDraft.prompt),
            intent: nil,
            repositoryUrl: sdkBridgeRepositoryURL(from: launchDraft.source)?.absoluteString,
            startingRef: sdkBridgeStartingRef(from: launchDraft.source),
            prUrl: sdkBridgePullRequestURL(from: launchDraft.source)?.absoluteString,
            modelId: sdkBridgeModelID,
            mcpProfileId: launchDraft.sdkMCPProfileID,
            autoCreatePR: launchDraft.autoCreatePullRequest,
            skipReviewerRequest: launchDraft.skipReviewerRequest
        )
        let response = try await client.createSession(request)
        let repository = repository(from: launchDraft.source)
        let agentID = response.sessionId ?? response.agentId
        let run = AgentRun(
            id: response.runId,
            agentID: agentID,
            status: RunStatus(cursorValue: response.status),
            createdAtDescription: "now",
            updatedAtDescription: "now"
        )
        let agent = Agent(
            id: agentID,
            name: agentName(from: launchDraft.prompt.text),
            status: .active,
            repository: repository,
            branchName: displayBranchName(from: launchDraft),
            modelID: sdkBridgeModelID ?? "default",
            latestRunID: response.runId,
            updatedAtDescription: "now",
            artifactCount: 0,
            pullRequestURL: sdkBridgePullRequestURL(from: launchDraft.source)
        )
        if let profileID = launchDraft.sdkMCPProfileID?.nilIfBlank {
            sdkBridgeMCPProfileIDsByAgentID[agent.id] = profileID
        }
        return AgentLaunchResult(agent: agent, run: run)
    }

    private func makeSDKBridgeClient() throws -> SDKBridgeClient {
        guard SDKBridgePreferences.isEnabled() else {
            throw SDKBridgeUnavailableError.bridgeDisabled
        }
        guard let baseURL = SDKBridgePreferences.configuredBaseURL() else {
            throw SDKBridgeUnavailableError.invalidBridgeURL
        }
        guard let bridgeToken = sdkBridgeToken?.nilIfBlank else {
            throw SDKBridgeUnavailableError.bridgeNotPaired
        }
        guard let apiKey = try apiKeyStore.loadAPIKey()?.nilIfBlank else {
            throw SDKBridgeUnavailableError.missingAPIKey
        }
        return sdkBridgeClientFactory(baseURL, apiKey, bridgeToken)
    }

    private func updateAgent(_ agentID: Agent.ID, mutate: (inout Agent) -> Void) {
        guard let index = agents.firstIndex(where: { $0.id == agentID }) else { return }
        mutate(&agents[index])
    }

    private func effectiveEndpoint(_ endpoint: CursorAPIEndpoint) -> CursorAPIEndpoint {
        guard endpoint.supportsPagination else { return endpoint }
        return endpoint.withPage(page(for: endpoint))
    }

    private func upsertAgent(_ agent: Agent) {
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        } else {
            agents.insert(agent, at: 0)
        }
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
        let knownIDs = Set(existing.map(\.id))
        existing.append(contentsOf: events.filter { knownIDs.contains($0.id) == false })
        eventsByRunID[runID] = existing
    }

    private var sdkBridgeModelID: String? {
        let modelID = launchDraft.modelID?.nilIfBlank
        return modelID?.isCursorDefaultModelIdentifier == true ? nil : modelID
    }

    private func sdkPromptImages(from prompt: AgentPrompt) -> [SDKBridgePromptImageRequest]? {
        let images = prompt.images.prefix(5).map { image in
            SDKBridgePromptImageRequest(
                data: image.data.base64EncodedString(),
                mimeType: "image/jpeg",
                dimension: SDKBridgePromptImageDimensionRequest(width: image.width, height: image.height)
            )
        }
        return images.isEmpty ? nil : images
    }

    private func sdkBridgeRepositoryURL(from source: AgentSource) -> URL? {
        switch source {
        case .repository(let url, _):
            url
        case .pullRequest:
            nil
        }
    }

    private func sdkBridgeStartingRef(from source: AgentSource) -> String? {
        switch source {
        case .repository(_, let startingRef):
            startingRef?.nilIfBlank
        case .pullRequest:
            nil
        }
    }

    private func sdkBridgePullRequestURL(from source: AgentSource) -> URL? {
        switch source {
        case .repository:
            nil
        case .pullRequest(let url):
            url
        }
    }

    private func repository(from source: AgentSource) -> Repository {
        switch source {
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

    private func displayBranchName(from draft: AgentLaunchDraft) -> String {
        if !draft.autoGenerateBranch, let branchName = draft.branchName?.nilIfBlank {
            return branchName
        }
        switch draft.source {
        case .repository(_, let startingRef):
            return startingRef?.nilIfBlank ?? "SDK Mode"
        case .pullRequest:
            return "Pull request"
        }
    }

    private func agentName(from prompt: String) -> String {
        let firstLine = prompt
            .split(whereSeparator: \.isNewline)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "SDK Run"
        guard firstLine.count > 48 else { return firstLine }
        return String(firstLine.prefix(45)) + "..."
    }

    private func sdkBridgeConnectionFailureMessage(for error: Error, baseURL: URL) -> String {
        if SDKBridgePreferences.isLoopback(baseURL) {
            return "Runline cannot reach \(baseURL.absoluteString). On a physical iPhone, localhost points to the phone. Use your Mac LAN URL or a hosted HTTPS bridge."
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
                return "Runline cannot reach \(baseURL.absoluteString). Start Runline Bridge or update the URL."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private func userMessage(from error: Error) -> String {
        if let apiError = error as? CursorAPIError {
            return apiError.userMessage
        }
        if let bridgeError = error as? SDKBridgeUnavailableError {
            return bridgeError.errorDescription ?? error.localizedDescription
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
        (error as? CursorAPIError)?.isNotFound == true
    }

    private func isStreamExpired(_ error: Error) -> Bool {
        (error as? CursorAPIError)?.isStreamExpired == true
    }

    private func statusCode(from error: Error) -> Int {
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
        sdkBridgeRunIDs = snapshot.sdkBridgeRunIDs
        sdkBridgeMCPProfileIDsByAgentID = snapshot.sdkBridgeMCPProfileIDsByAgentID
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
            sdkBridgeRunIDs: sdkBridgeRunIDs,
            sdkBridgeMCPProfileIDsByAgentID: sdkBridgeMCPProfileIDsByAgentID,
            launchDraft: launchDraft,
            notificationPreferences: notificationPreferences,
            deviceTokenRegistration: deviceTokenRegistration,
            cachedAt: .now
        )
        try? appCache.save(snapshot)
    }
}

private enum SDKBridgeUnavailableError: LocalizedError {
    case bridgeDisabled
    case invalidBridgeURL
    case bridgeNotPaired
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .bridgeDisabled:
            "Enable Runline Bridge in Settings before using Cursor SDK."
        case .invalidBridgeURL:
            "Enter a valid Runline Bridge URL in Settings."
        case .bridgeNotPaired:
            "Pair Runline Bridge in Settings before using Cursor SDK."
        case .missingAPIKey:
            "Reconnect your Cursor API key before using Cursor SDK."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
