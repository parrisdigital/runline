import Foundation

struct CursorListResponse<Item: Decodable>: Decodable {
    let items: [Item]
    let nextCursor: String?

    init(from decoder: Decoder) throws {
        if let directItems = try? [Item](from: decoder) {
            items = directItems
            nextCursor = nil
            return
        }
        if let directItems = try? LossyDecodableList<Item>(from: decoder) {
            items = directItems.items
            nextCursor = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = Self.decodeItemsIfPresent(in: container, forKey: .items)
            ?? Self.decodeItemsIfPresent(in: container, forKey: .repositories)
            ?? Self.decodeItemsIfPresent(in: container, forKey: .models)
            ?? Self.decodeItemsIfPresent(in: container, forKey: .agents)
            ?? Self.decodeItemsIfPresent(in: container, forKey: .runs)
            ?? Self.decodeItemsIfPresent(in: container, forKey: .artifacts)
            ?? []
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
    }

    private static func decodeItemsIfPresent(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [Item]? {
        guard container.contains(key) else { return nil }
        if let items = try? container.decode([Item].self, forKey: key) {
            return items
        }
        return (try? container.decode(LossyDecodableList<Item>.self, forKey: key))?.items
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case repositories
        case models
        case agents
        case runs
        case artifacts
        case nextCursor
    }
}

private struct LossyDecodableList<Item: Decodable>: Decodable {
    let items: [Item]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decodedItems: [Item] = []

        while !container.isAtEnd {
            if let item = try? container.decode(Item.self) {
                decodedItems.append(item)
            } else {
                _ = try container.decode(JSONValue.self)
            }
        }

        items = decodedItems
    }
}

private extension KeyedDecodingContainer {
    func decodeStringLeniently(forKey key: Key) -> String? {
        (try? decodeIfPresent(String.self, forKey: key)) ?? nil
    }

    func decodeIntLeniently(forKey key: Key) -> Int? {
        (try? decodeIfPresent(Int.self, forKey: key)) ?? nil
    }

    func decodeURLLeniently(forKey key: Key) -> URL? {
        (try? decodeIfPresent(URL.self, forKey: key)) ?? nil
    }
}

struct CursorMeDTO: Decodable {
    let apiKeyName: String
    let createdAt: String?
    let userEmail: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let apiKey = try? container.decode(NestedAPIKey.self, forKey: .apiKey)
        let user = try? container.decode(NestedUser.self, forKey: .user)

        apiKeyName = try container.decodeIfPresent(String.self, forKey: .apiKeyName)
            ?? container.decodeIfPresent(String.self, forKey: .keyName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? apiKey?.name
            ?? "Cursor API Key"
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
            ?? apiKey?.createdAt
        userEmail = try container.decodeIfPresent(String.self, forKey: .userEmail)
            ?? container.decodeIfPresent(String.self, forKey: .email)
            ?? user?.email
    }

    var domainModel: ProviderAccount {
        ProviderAccount(
            apiKeyName: apiKeyName,
            userEmail: userEmail ?? "Email unavailable",
            createdAt: CursorDateParser.date(from: createdAt) ?? .now
        )
    }

    private enum CodingKeys: String, CodingKey {
        case apiKeyName
        case keyName
        case name
        case createdAt
        case userEmail
        case email
        case apiKey
        case user
    }

    private struct NestedAPIKey: Decodable {
        let name: String?
        let createdAt: String?
    }

    private struct NestedUser: Decodable {
        let email: String?
    }
}

struct CursorRepositoryDTO: Decodable {
    let owner: String?
    let name: String?
    let repository: String?
    let url: String?
    let defaultBranch: String?

    var domainModel: Repository {
        let url = URL(string: url ?? repository ?? "") ?? URL(string: "https://github.com/\(owner ?? "unknown")/\(name ?? "repository")")!
        let parsed = Self.parse(url: url)
        return Repository(
            owner: owner ?? parsed.owner,
            name: name ?? parsed.name,
            url: url,
            defaultBranch: defaultBranch ?? "",
            isFavorite: false,
            lastUsedDescription: "Cursor"
        )
    }

    private static func parse(url: URL) -> (owner: String, name: String) {
        let pathParts = url.path.split(separator: "/").map(String.init)
        let owner = pathParts.dropLast().last ?? url.host ?? "unknown"
        let name = pathParts.last?.replacingOccurrences(of: ".git", with: "") ?? "repository"
        return (owner, name)
    }
}

struct CursorAgentRepoDTO: Decodable, Encodable, Hashable {
    let url: String?
    let repository: String?
    let startingRef: String?
    let prUrl: String?

    init(url: String, startingRef: String?, prUrl: String? = nil) {
        self.url = url
        repository = nil
        self.startingRef = startingRef
        self.prUrl = prUrl
    }

    var resolvedURL: URL? {
        if let url = URL(string: url ?? repository ?? "") {
            return url
        }
        guard let prUrl, let pullRequestURL = URL(string: prUrl) else {
            return nil
        }
        return Self.repositoryURL(fromPullRequestURL: pullRequestURL)
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
}

struct CursorAgentDTO: Decodable {
    let id: String
    let name: String?
    let status: String?
    let source: CursorAgentSourceDTO?
    let target: CursorAgentTargetDTO?
    let repos: [CursorAgentRepoDTO]?
    let branchName: String?
    let model: CursorModelReference?
    let modelId: String?
    let latestRunId: String?
    let url: String?
    let prUrl: String?
    let pullRequestUrl: String?
    let summary: String?
    let createdAt: String?
    let updatedAt: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = container.decodeStringLeniently(forKey: .name)
        status = container.decodeStringLeniently(forKey: .status)
        source = (try? container.decodeIfPresent(CursorAgentSourceDTO.self, forKey: .source)) ?? nil
        target = (try? container.decodeIfPresent(CursorAgentTargetDTO.self, forKey: .target)) ?? nil
        repos = (try? container.decodeIfPresent([CursorAgentRepoDTO].self, forKey: .repos)) ?? nil
        branchName = container.decodeStringLeniently(forKey: .branchName)
        model = (try? container.decodeIfPresent(CursorModelReference.self, forKey: .model)) ?? nil
        modelId = container.decodeStringLeniently(forKey: .modelId)
        latestRunId = container.decodeStringLeniently(forKey: .latestRunId)
        url = container.decodeStringLeniently(forKey: .url)
        prUrl = container.decodeStringLeniently(forKey: .prUrl)
        pullRequestUrl = container.decodeStringLeniently(forKey: .pullRequestUrl)
        summary = container.decodeStringLeniently(forKey: .summary)
        createdAt = container.decodeStringLeniently(forKey: .createdAt)
        updatedAt = container.decodeStringLeniently(forKey: .updatedAt)
    }

    func domainModel(repositoryFallbacks: [Repository]) -> Agent {
        let repo = repository(from: repositoryFallbacks)
        return Agent(
            id: id,
            name: name ?? id,
            status: AgentStatus(cursorValue: status),
            repository: repo,
            branchName: target?.branchName ?? branchName ?? repo.defaultBranch,
            modelID: model?.id ?? modelId ?? "default",
            latestRunID: latestRunId ?? id,
            updatedAtDescription: CursorDateParser.relativeDescription(from: updatedAt ?? createdAt),
            artifactCount: 0,
            pullRequestURL: URL(string: target?.prUrl ?? pullRequestUrl ?? prUrl ?? "")
        )
    }

    private func repository(from fallbacks: [Repository]) -> Repository {
        guard let repoURL = URL(string: source?.repository ?? "") ?? sourcePullRequestRepositoryURL ?? repos?.first?.resolvedURL else {
            return fallbacks.first ?? Repository(
                owner: "cursor",
                name: "repository",
                url: URL(string: "https://github.com/unknown/repository")!,
                defaultBranch: "",
                isFavorite: false,
                lastUsedDescription: "Cursor"
            )
        }

        if let existing = fallbacks.first(where: { $0.url == repoURL }) {
            return existing
        }

        let pathParts = repoURL.path.split(separator: "/").map(String.init)
        let owner = pathParts.dropLast().last ?? repoURL.host ?? "unknown"
        let name = pathParts.last ?? repoURL.lastPathComponent

        return Repository(
            owner: owner,
            name: name.replacingOccurrences(of: ".git", with: ""),
            url: repoURL,
            defaultBranch: source?.ref ?? repos?.first?.startingRef ?? "",
            isFavorite: false,
            lastUsedDescription: "Cursor"
        )
    }

    private var sourcePullRequestRepositoryURL: URL? {
        guard let prUrl = source?.prUrl, let pullRequestURL = URL(string: prUrl) else { return nil }
        let components = pullRequestURL.path.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return nil }
        var urlComponents = URLComponents()
        urlComponents.scheme = pullRequestURL.scheme
        urlComponents.host = pullRequestURL.host
        urlComponents.path = "/\(components[0])/\(components[1])"
        return urlComponents.url
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case source
        case target
        case repos
        case branchName
        case model
        case modelId
        case latestRunId
        case url
        case prUrl
        case pullRequestUrl
        case summary
        case createdAt
        case updatedAt
    }
}

struct CursorAgentSourceDTO: Decodable {
    let repository: String?
    let ref: String?
    let prUrl: String?
}

struct CursorAgentTargetDTO: Decodable {
    let branchName: String?
    let url: String?
    let prUrl: String?
    let autoCreatePr: Bool?
    let openAsCursorGithubApp: Bool?
    let skipReviewerRequest: Bool?
}

struct CursorModelObjectDTO: Decodable, Encodable, Hashable {
    let id: String
}

struct CursorModelDTO: Decodable, Hashable {
    let id: String

    init(from decoder: Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        if let id = try? singleValueContainer.decode(String.self) {
            self.id = id
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = container.decodeStringLeniently(forKey: .id)
            ?? container.decodeStringLeniently(forKey: .model)
            ?? container.decodeStringLeniently(forKey: .modelId)
            ?? container.decodeStringLeniently(forKey: .name)
            ?? container.decodeStringLeniently(forKey: .value) {
            self.id = id
            return
        }

        throw DecodingError.keyNotFound(
            CodingKeys.id,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Model identifier is missing.")
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case modelId
        case name
        case value
    }
}

enum CursorModelReference: Decodable, Hashable {
    case id(String)

    var id: String {
        switch self {
        case .id(let id):
            id
        }
    }

    init(from decoder: Decoder) throws {
        let model = try CursorModelDTO(from: decoder)
        self = .id(model.id)
    }
}

struct CursorRunDTO: Decodable {
    let id: String
    let agentId: String?
    let status: String?
    let createdAt: String?
    let updatedAt: String?

    init(id: String, agentId: String?, status: String?, createdAt: String?, updatedAt: String?) {
        self.id = id
        self.agentId = agentId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = container.decodeStringLeniently(forKey: .id)
            ?? container.decodeStringLeniently(forKey: .runId) {
            self.id = id
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Run identifier is missing.")
            )
        }
        agentId = container.decodeStringLeniently(forKey: .agentId)
            ?? container.decodeStringLeniently(forKey: .agentID)
            ?? container.decodeStringLeniently(forKey: .agentIDSnake)
        status = container.decodeStringLeniently(forKey: .status)
        createdAt = container.decodeStringLeniently(forKey: .createdAt)
            ?? container.decodeStringLeniently(forKey: .createdAtSnake)
        updatedAt = container.decodeStringLeniently(forKey: .updatedAt)
            ?? container.decodeStringLeniently(forKey: .updatedAtSnake)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case runId
        case agentId
        case agentID
        case agentIDSnake = "agent_id"
        case status
        case createdAt
        case createdAtSnake = "created_at"
        case updatedAt
        case updatedAtSnake = "updated_at"
    }

    var domainModel: AgentRun {
        AgentRun(
            id: id,
            agentID: agentId ?? "",
            status: RunStatus(cursorValue: status),
            createdAtDescription: CursorDateParser.relativeDescription(from: createdAt),
            updatedAtDescription: CursorDateParser.relativeDescription(from: updatedAt ?? createdAt)
        )
    }
}

struct CursorCreateAgentResponse: Decodable {
    let agent: CursorAgentDTO
    let run: CursorRunDTO

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let wrappedAgent = try? container.decode(CursorAgentDTO.self, forKey: .agent) {
            agent = wrappedAgent
        } else {
            agent = try CursorAgentDTO(from: decoder)
        }
        if let wrappedRun = try? container.decode(CursorRunDTO.self, forKey: .run) {
            run = wrappedRun
        } else {
            run = CursorRunDTO(
                id: agent.latestRunId ?? agent.id,
                agentId: agent.id,
                status: agent.status,
                createdAt: agent.createdAt,
                updatedAt: agent.updatedAt ?? agent.createdAt
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case agent
        case run
    }
}

struct CursorCreateRunResponse: Decodable {
    let run: CursorRunDTO

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let wrappedRun = try? container.decode(CursorRunDTO.self, forKey: .run) {
            run = wrappedRun
        } else {
            run = try CursorRunDTO(from: decoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case run
    }
}

struct CursorArtifactDTO: Decodable {
    let path: String
    let sizeBytes: Int?
    let updatedAt: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let path = container.decodeStringLeniently(forKey: .path)
            ?? container.decodeStringLeniently(forKey: .absolutePath)
            ?? container.decodeStringLeniently(forKey: .relativePath)
            ?? container.decodeStringLeniently(forKey: .filePath)
            ?? container.decodeStringLeniently(forKey: .name) else {
            throw DecodingError.keyNotFound(
                CodingKeys.path,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Artifact path is missing.")
            )
        }
        self.path = path
        sizeBytes = container.decodeIntLeniently(forKey: .sizeBytes)
            ?? container.decodeIntLeniently(forKey: .size)
        updatedAt = container.decodeStringLeniently(forKey: .updatedAt)
            ?? container.decodeStringLeniently(forKey: .updatedAtSnake)
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case absolutePath
        case relativePath
        case filePath
        case name
        case sizeBytes
        case size
        case updatedAt
        case updatedAtSnake = "updated_at"
    }

    var domainModel: Artifact {
        Artifact(
            path: path,
            kind: Artifact.Kind(path: path),
            sizeDescription: CursorByteFormatter.string(from: sizeBytes),
            updatedAtDescription: CursorDateParser.relativeDescription(from: updatedAt)
        )
    }
}

struct CursorArtifactDownloadDTO: Decodable {
    let url: URL
    let expiresAt: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let url = container.decodeURLLeniently(forKey: .url)
            ?? container.decodeURLLeniently(forKey: .downloadUrl)
            ?? container.decodeURLLeniently(forKey: .signedUrl)
            ?? container.decodeURLLeniently(forKey: .artifactUrl) {
            self.url = url
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.url,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Artifact download URL is missing.")
            )
        }
        expiresAt = container.decodeStringLeniently(forKey: .expiresAt)
            ?? container.decodeStringLeniently(forKey: .expiresAtSnake)
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case downloadUrl
        case signedUrl
        case artifactUrl
        case expiresAt
        case expiresAtSnake = "expires_at"
    }

    var domainModel: ArtifactDownload {
        ArtifactDownload(
            url: url,
            expiresAt: CursorDateParser.date(from: expiresAt) ?? Date(timeIntervalSinceNow: 300)
        )
    }
}

struct CursorPromptRequest: Encodable, Hashable {
    let text: String
    let images: [CursorPromptImageRequest]?
}

struct CursorPromptImageRequest: Encodable, Hashable {
    let data: String
    let dimension: CursorPromptImageDimensionRequest
}

struct CursorPromptImageDimensionRequest: Encodable, Hashable {
    let width: Int
    let height: Int
}

struct CursorCreateAgentRequest: Encodable {
    let prompt: CursorPromptRequest
    let model: CursorModelObjectDTO?
    let repos: [CursorLaunchRepositoryRequest]
    let branchName: String?
    let autoGenerateBranch: Bool?
    let autoCreatePR: Bool
    let skipReviewerRequest: Bool?
}

struct CursorCreateRunRequest: Encodable {
    let prompt: CursorPromptRequest
}

struct CursorLaunchRepositoryRequest: Encodable, Hashable {
    let url: String?
    let startingRef: String?
    let prUrl: String?
}

struct CursorIDResponse: Decodable {
    let id: String
}

struct CursorConversationResponse: Decodable {
    let id: String
    let messages: [CursorConversationMessageDTO]
}

struct CursorConversationMessageDTO: Decodable {
    let id: String
    let type: String
    let text: String
}

struct CursorStreamPayloadDTO: Decodable {
    let id: String?
    let type: String?
    let event: String?
    let title: String?
    let message: String?
    let text: String?
    let status: String?
    let timestamp: String?
    let createdAt: String?
}

enum CursorDateParser {
    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func relativeDescription(from value: String?) -> String {
        guard let date = date(from: value) else { return "now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

enum CursorByteFormatter {
    static func string(from bytes: Int?) -> String {
        guard let bytes else { return "Unknown size" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

extension AgentStatus {
    init(cursorValue: String?) {
        switch cursorValue?.uppercased() {
        case "ACTIVE":
            self = .active
        case "ARCHIVED":
            self = .archived
        case .some(let value):
            self = .unknown(value)
        case .none:
            self = .unknown("UNKNOWN")
        }
    }
}

extension RunStatus {
    init(cursorValue: String?) {
        switch cursorValue?.uppercased() {
        case "CREATING":
            self = .creating
        case "RUNNING":
            self = .running
        case "FINISHED", "COMPLETED", "DONE":
            self = .finished
        case "ERROR", "FAILED":
            self = .error
        case "CANCELLED", "CANCELED":
            self = .cancelled
        case "EXPIRED":
            self = .expired
        case .some(let value):
            self = .unknown(value)
        case .none:
            self = .unknown("UNKNOWN")
        }
    }

    init(agentStatus: AgentStatus, agentID: Agent.ID = "") {
        switch agentStatus {
        case .active:
            self = .running
        case .archived:
            self = .finished
        case .unknown(let value):
            if value == agentID {
                self = .creating
            } else {
                self.init(cursorValue: value)
            }
        }
    }
}

extension StreamEventKind {
    init(cursorValue: String?) {
        switch cursorValue?.lowercased() {
        case "system":
            self = .system
        case "user", "user_message":
            self = .user
        case "status":
            self = .status
        case "assistant", "assistant_message":
            self = .assistant
        case "thinking", "reasoning":
            self = .thinking
        case "tool_call", "toolcall":
            self = .toolCall
        case "task", "summary":
            self = .task
        case "request":
            self = .request
        case "result", "tool_result":
            self = .result
        case "heartbeat":
            self = .heartbeat
        case "error":
            self = .error
        case "done", "complete", "completed":
            self = .done
        default:
            self = .unknown
        }
    }
}

extension Artifact.Kind {
    init(path: String) {
        let lowercased = path.lowercased()
        if lowercased.hasSuffix(".png") || lowercased.hasSuffix(".jpg") || lowercased.hasSuffix(".jpeg") {
            self = .screenshot
        } else if lowercased.hasSuffix(".mov") || lowercased.hasSuffix(".mp4") {
            self = .video
        } else if lowercased.hasSuffix(".log") || lowercased.hasSuffix(".txt") {
            self = .log
        } else {
            self = .file
        }
    }
}
