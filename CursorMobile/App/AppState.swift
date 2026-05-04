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
    private let appCache: LocalAppCache
    private let providerFactory: @MainActor (String) throws -> AgentProvider
    private var hasRestoredConnection = false
    private var observingRunIDs: Set<AgentRun.ID> = []
    private var streamExpiredRunIDs: Set<AgentRun.ID> = []
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

    init(
        provider: AgentProvider? = nil,
        apiKeyStore: APIKeyStore = KeychainAPIKeyStore(),
        enterpriseAPIKeyStore: APIKeyStore = KeychainAPIKeyStore(account: .cursorEnterpriseAdmin),
        appCache: LocalAppCache = LocalAppCache(),
        providerFactory: @escaping @MainActor (String) throws -> AgentProvider = { try CursorAgentProvider(apiKey: $0) }
    ) {
        self.provider = provider
        enterpriseProvider = provider as? EnterpriseDataProvider
        self.apiKeyStore = apiKeyStore
        self.enterpriseAPIKeyStore = enterpriseAPIKeyStore
        self.appCache = appCache
        self.providerFactory = providerFactory
        launchDraft = AgentLaunchDraft(
            prompt: AgentPrompt(text: ""),
            modelID: nil,
            source: .repository(url: URL(string: "https://github.com/owner/repository")!, startingRef: nil),
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
            return Self.isUsableRepositoryURL(url)
        case .pullRequest(let url):
            return Self.isUsablePullRequestURL(url)
        }
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

    func refreshAgentDetail(agentID: Agent.ID) async {
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
        guard let provider else {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return
        }
        guard observingRunIDs.contains(run.id) == false else { return }

        observingRunIDs.insert(run.id)
        streamExpiredRunIDs.remove(run.id)
        defer { observingRunIDs.remove(run.id) }

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
        guard let provider else {
            errorMessage = CursorAPIError.missingProvider.userMessage
            return
        }
        guard canLaunchAgent else {
            errorMessage = "Select a repository and add instructions before launching an agent."
            return
        }

        isLaunching = true
        errorMessage = nil
        do {
            let result = try await provider.createAgent(launchDraft)
            agents.insert(result.agent, at: 0)
            runsByAgentID[result.agent.id] = [result.run]
            eventsByRunID[result.run.id] = []
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

    func createFollowUp(agent: Agent, prompt: AgentPrompt) async {
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

    private func userMessage(from error: Error) -> String {
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
