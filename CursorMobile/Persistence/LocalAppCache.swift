import Foundation

struct AppCacheSnapshot: Codable, Equatable {
    var account: ProviderAccount?
    var enterpriseAccount: ProviderAccount?
    var repositories: [Repository]
    var models: [AgentModel]
    var agents: [Agent]
    var runsByAgentID: [String: [AgentRun]]
    var eventsByRunID: [String: [AgentStreamEvent]]
    var artifactsByAgentID: [String: [Artifact]]
    var launchDraft: AgentLaunchDraft
    var notificationPreferences: NotificationPreferences
    var deviceTokenRegistration: DeviceTokenRegistration?
    var cachedAt: Date

    init(
        account: ProviderAccount?,
        enterpriseAccount: ProviderAccount? = nil,
        repositories: [Repository],
        models: [AgentModel],
        agents: [Agent],
        runsByAgentID: [String: [AgentRun]],
        eventsByRunID: [String: [AgentStreamEvent]],
        artifactsByAgentID: [String: [Artifact]],
        launchDraft: AgentLaunchDraft,
        notificationPreferences: NotificationPreferences,
        deviceTokenRegistration: DeviceTokenRegistration? = nil,
        cachedAt: Date
    ) {
        self.account = account
        self.enterpriseAccount = enterpriseAccount
        self.repositories = repositories
        self.models = models
        self.agents = agents
        self.runsByAgentID = runsByAgentID
        self.eventsByRunID = eventsByRunID
        self.artifactsByAgentID = artifactsByAgentID
        self.launchDraft = launchDraft
        self.notificationPreferences = notificationPreferences
        self.deviceTokenRegistration = deviceTokenRegistration
        self.cachedAt = cachedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        account = try container.decodeIfPresent(ProviderAccount.self, forKey: .account)
        enterpriseAccount = try container.decodeIfPresent(ProviderAccount.self, forKey: .enterpriseAccount)
        repositories = try container.decodeIfPresent([Repository].self, forKey: .repositories) ?? []
        models = try container.decodeIfPresent([AgentModel].self, forKey: .models) ?? []
        agents = try container.decodeIfPresent([Agent].self, forKey: .agents) ?? []
        runsByAgentID = try container.decodeIfPresent([String: [AgentRun]].self, forKey: .runsByAgentID) ?? [:]
        eventsByRunID = try container.decodeIfPresent([String: [AgentStreamEvent]].self, forKey: .eventsByRunID) ?? [:]
        artifactsByAgentID = try container.decodeIfPresent([String: [Artifact]].self, forKey: .artifactsByAgentID) ?? [:]
        launchDraft = try container.decode(AgentLaunchDraft.self, forKey: .launchDraft)
        notificationPreferences = try container.decodeIfPresent(NotificationPreferences.self, forKey: .notificationPreferences) ?? NotificationPreferences()
        deviceTokenRegistration = try container.decodeIfPresent(DeviceTokenRegistration.self, forKey: .deviceTokenRegistration)
        cachedAt = try container.decodeIfPresent(Date.self, forKey: .cachedAt) ?? .distantPast
    }
}

final class LocalAppCache {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    func load() throws -> AppCacheSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(AppCacheSnapshot.self, from: data)
    }

    func save(_ snapshot: AppCacheSnapshot) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return baseURL
            .appendingPathComponent("Runline", isDirectory: true)
            .appendingPathComponent("cache-v1.json", isDirectory: false)
    }
}
