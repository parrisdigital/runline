import Foundation
import SwiftUI

enum AgentRuntimeMode: String, CaseIterable, Identifiable, Hashable, Codable {
    case cloud = "cloud"
    case sdkBridge = "sdk_bridge"

    static let preferredComposerModelID = "composer-2.5"
    static let cursorChatPreferredModelID = preferredComposerModelID

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cloud:
            "Cursor Cloud"
        case .sdkBridge:
            "Cursor Chat"
        }
    }

    var shortTitle: String {
        switch self {
        case .cloud:
            "Cloud"
        case .sdkBridge:
            "Chat"
        }
    }

    var detailSymbolName: String {
        switch self {
        case .cloud:
            "cloud.fill"
        case .sdkBridge:
            "message.fill"
        }
    }

    var detailTint: Color {
        switch self {
        case .cloud:
            Color(uiColor: .systemBlue)
        case .sdkBridge:
            Color(uiColor: .systemGreen)
        }
    }

    var preferredLaunchModelID: String? {
        switch self {
        case .cloud:
            Self.preferredComposerModelID
        case .sdkBridge:
            Self.preferredComposerModelID
        }
    }

    var preferredLaunchModelTitle: String {
        preferredLaunchModelID ?? "Default"
    }

    func normalizedLaunchModelID(_ modelID: String?) -> String? {
        let trimmed = modelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty, !trimmed.isCursorDefaultModelIdentifier else {
            return preferredLaunchModelID
        }
        return trimmed
    }

    func launchModelIDAfterSwitch(from previousMode: AgentRuntimeMode, currentModelID: String?) -> String? {
        return normalizedLaunchModelID(currentModelID)
    }
}

enum CursorCloudModelPreference {
    static let selectedModelIDKey = "runline.cursorCloud.selectedModelID"

    static func normalizedModelID(_ modelID: String?) -> String {
        AgentRuntimeMode.cloud.normalizedLaunchModelID(modelID) ?? AgentRuntimeMode.preferredComposerModelID
    }

    static func selectedModelID(defaults: UserDefaults = .standard) -> String {
        normalizedModelID(defaults.string(forKey: selectedModelIDKey))
    }

    static func resolvedModelID(_ modelID: String?, defaults: UserDefaults = .standard) -> String {
        let trimmed = modelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty, !trimmed.isCursorDefaultModelIdentifier else {
            return selectedModelID(defaults: defaults)
        }
        return normalizedModelID(trimmed)
    }

    static func saveSelectedModelID(_ modelID: String?, defaults: UserDefaults = .standard) {
        defaults.set(normalizedModelID(modelID), forKey: selectedModelIDKey)
    }
}

enum CursorChatModelPreference {
    static let selectedModelIDKey = "runline.cursorChat.selectedModelID"

    static func normalizedModelID(_ modelID: String?) -> String {
        AgentRuntimeMode.sdkBridge.normalizedLaunchModelID(modelID) ?? AgentRuntimeMode.preferredComposerModelID
    }

    static func selectedModelID(defaults: UserDefaults = .standard) -> String {
        normalizedModelID(defaults.string(forKey: selectedModelIDKey))
    }

    static func resolvedModelID(_ modelID: String?, defaults: UserDefaults = .standard) -> String {
        let trimmed = modelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty, !trimmed.isCursorDefaultModelIdentifier else {
            return selectedModelID(defaults: defaults)
        }
        return normalizedModelID(trimmed)
    }

    static func saveSelectedModelID(_ modelID: String?, defaults: UserDefaults = .standard) {
        defaults.set(normalizedModelID(modelID), forKey: selectedModelIDKey)
    }
}

struct ProviderAccount: Identifiable, Hashable, Codable {
    var id: String { apiKeyName }
    var apiKeyName: String
    var userEmail: String
    var createdAt: Date
}

struct Repository: Identifiable, Hashable, Codable {
    var id: String { url.absoluteString }
    var owner: String
    var name: String
    var url: URL
    var defaultBranch: String
    var isFavorite: Bool
    var lastUsedDescription: String

    var displayName: String {
        "\(owner)/\(name)"
    }

    var isGeneralChat: Bool {
        url.absoluteString.contains("general-chat")
    }
}

struct AgentModel: Identifiable, Hashable, Codable {
    enum Category: String, CaseIterable, Hashable, Codable {
        case `default` = "Default"
        case coding = "Coding"
        case fast = "Fast"
    }

    var id: String
    var displayName: String
    var subtitle: String
    var category: Category
    var qualityScore: Int
    var costTier: Int

    var isCursorDefaultModel: Bool {
        id.isCursorDefaultModelIdentifier
    }
}

extension String {
    var isCursorDefaultModelIdentifier: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("default") == .orderedSame
    }
}

enum AgentStatus: Hashable, Codable {
    case active
    case archived
    case unknown(String)

    var title: String {
        switch self {
        case .active:
            "Active"
        case .archived:
            "Archived"
        case .unknown(let value):
            value
        }
    }
}

enum RunStatus: Hashable, Codable {
    case creating
    case running
    case finished
    case error
    case cancelled
    case expired
    case unknown(String)

    var title: String {
        switch self {
        case .creating:
            "Creating"
        case .running:
            "Running"
        case .finished:
            "Finished"
        case .error:
            "Failed"
        case .cancelled:
            "Cancelled"
        case .expired:
            "Expired"
        case .unknown(let value):
            value
        }
    }

    var isTerminal: Bool {
        switch self {
        case .finished, .error, .cancelled, .expired:
            true
        case .creating, .running, .unknown:
            false
        }
    }
}

struct Agent: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var status: AgentStatus
    var repository: Repository
    var branchName: String
    var modelID: String
    var latestRunID: String
    var updatedAtDescription: String
    var artifactCount: Int
    var pullRequestURL: URL?
    var runtimeMode: AgentRuntimeMode
    var conversationPreview: String?

    init(
        id: String,
        name: String,
        status: AgentStatus,
        repository: Repository,
        branchName: String,
        modelID: String,
        latestRunID: String,
        updatedAtDescription: String,
        artifactCount: Int,
        pullRequestURL: URL?,
        runtimeMode: AgentRuntimeMode = .cloud,
        conversationPreview: String? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.repository = repository
        self.branchName = branchName
        self.modelID = modelID
        self.latestRunID = latestRunID
        self.updatedAtDescription = updatedAtDescription
        self.artifactCount = artifactCount
        self.pullRequestURL = pullRequestURL
        self.runtimeMode = runtimeMode
        self.conversationPreview = conversationPreview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decode(AgentStatus.self, forKey: .status)
        repository = try container.decode(Repository.self, forKey: .repository)
        branchName = try container.decode(String.self, forKey: .branchName)
        modelID = try container.decode(String.self, forKey: .modelID)
        latestRunID = try container.decode(String.self, forKey: .latestRunID)
        updatedAtDescription = try container.decode(String.self, forKey: .updatedAtDescription)
        artifactCount = try container.decode(Int.self, forKey: .artifactCount)
        pullRequestURL = try container.decodeIfPresent(URL.self, forKey: .pullRequestURL)
        runtimeMode = try container.decodeIfPresent(AgentRuntimeMode.self, forKey: .runtimeMode) ?? .cloud
        conversationPreview = try container.decodeIfPresent(String.self, forKey: .conversationPreview)
    }
}

struct AgentRun: Identifiable, Hashable, Codable {
    var id: String
    var agentID: String
    var status: RunStatus
    var createdAtDescription: String
    var updatedAtDescription: String
}

struct PromptImage: Identifiable, Hashable, Codable {
    var id = UUID()
    var data: Data
    var width: Int
    var height: Int
}

struct PromptFile: Identifiable, Hashable, Codable {
    var id = UUID()
    var filename: String
    var contentType: String?
    var text: String
    var byteCount: Int

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

struct AgentPrompt: Hashable, Codable {
    var text: String
    var images: [PromptImage] = []
    var files: [PromptFile] = []

    init(text: String, images: [PromptImage] = [], files: [PromptFile] = []) {
        self.text = text
        self.images = images
        self.files = files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        images = try container.decodeIfPresent([PromptImage].self, forKey: .images) ?? []
        files = try container.decodeIfPresent([PromptFile].self, forKey: .files) ?? []
    }

    var textWithFileContext: String {
        guard !files.isEmpty else { return text }

        let fileContext = files.map { file in
            """
            <attached_file name="\(file.filename)" size="\(file.sizeDescription)">
            \(file.text)
            </attached_file>
            """
        }
        .joined(separator: "\n\n")

        return """
        \(text)

        Attached file context:
        \(fileContext)
        """
    }
}

enum AgentSource: Hashable, Codable {
    case general
    case repository(url: URL, startingRef: String?)
    case pullRequest(url: URL)
}

struct AgentLaunchDraft: Hashable, Codable {
    var prompt: AgentPrompt
    var modelID: String?
    var source: AgentSource
    var runtimeMode: AgentRuntimeMode
    var branchName: String?
    var autoGenerateBranch: Bool
    var autoCreatePullRequest: Bool
    var skipReviewerRequest: Bool?

    init(
        prompt: AgentPrompt,
        modelID: String?,
        source: AgentSource,
        runtimeMode: AgentRuntimeMode = .cloud,
        branchName: String?,
        autoGenerateBranch: Bool,
        autoCreatePullRequest: Bool,
        skipReviewerRequest: Bool?
    ) {
        self.prompt = prompt
        self.modelID = modelID
        self.source = source
        self.runtimeMode = runtimeMode
        self.branchName = branchName
        self.autoGenerateBranch = autoGenerateBranch
        self.autoCreatePullRequest = autoCreatePullRequest
        self.skipReviewerRequest = skipReviewerRequest
    }

    mutating func applyRuntimeMode(_ mode: AgentRuntimeMode) {
        let previousMode = runtimeMode
        runtimeMode = mode
        modelID = mode.launchModelIDAfterSwitch(from: previousMode, currentModelID: modelID)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prompt = try container.decode(AgentPrompt.self, forKey: .prompt)
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        source = try container.decode(AgentSource.self, forKey: .source)
        runtimeMode = try container.decodeIfPresent(AgentRuntimeMode.self, forKey: .runtimeMode) ?? .cloud
        branchName = try container.decodeIfPresent(String.self, forKey: .branchName)
        autoGenerateBranch = try container.decode(Bool.self, forKey: .autoGenerateBranch)
        autoCreatePullRequest = try container.decode(Bool.self, forKey: .autoCreatePullRequest)
        skipReviewerRequest = try container.decodeIfPresent(Bool.self, forKey: .skipReviewerRequest)
    }
}

struct AgentLaunchResult: Hashable, Codable {
    var agent: Agent
    var run: AgentRun
}

struct AgentFollowUpDraft: Hashable, Codable {
    var agentID: Agent.ID
    var prompt: AgentPrompt
    var modelID: String? = nil
}

enum StreamEventKind: String, Hashable, Codable {
    case system
    case user
    case status
    case assistant
    case thinking
    case toolCall = "tool_call"
    case task
    case request
    case result
    case heartbeat
    case error
    case done
    case unknown
}

struct AgentStreamEvent: Identifiable, Hashable, Codable {
    var id: String
    var runID: String
    var kind: StreamEventKind
    var title: String
    var message: String
    var timestamp: String
    var rawPayload: JSONValue? = nil
}

enum ConversationTitleGenerator {
    static func title(from prompt: String, repository: Repository) -> String? {
        title(from: prompt, assistantMessage: nil, repository: repository)
    }

    static func title(from events: [AgentStreamEvent], repository: Repository) -> String? {
        let firstPrompt = events.first { $0.kind == .user }?.message
        let firstResponse = events.first { event in
            switch event.kind {
            case .assistant, .result:
                !event.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            default:
                false
            }
        }?.message

        guard let firstPrompt else { return nil }
        return title(from: firstPrompt, assistantMessage: firstResponse, repository: repository)
    }

    static func shouldReplace(currentTitle: String, with generatedTitle: String, repository: Repository, firstPrompt: String?) -> Bool {
        let current = normalizedComparisonValue(currentTitle)
        let generated = normalizedComparisonValue(generatedTitle)
        guard !current.isEmpty, current != generated else { return current != generated }

        if placeholderTitles(for: repository).contains(current) {
            return true
        }

        if let firstPrompt,
           let promptTitle = title(from: firstPrompt, repository: repository),
           normalizedComparisonValue(promptTitle) == current {
            return true
        }

        if isMachineGeneratedSlugTitle(currentTitle),
           generated.hasPrefix(current + " ") {
            return true
        }

        return false
    }

    static func isPlaceholderTitle(_ title: String, repository: Repository) -> Bool {
        placeholderTitles(for: repository).contains(normalizedComparisonValue(title))
    }

    private static func title(from prompt: String, assistantMessage: String?, repository: Repository) -> String? {
        if isGenericBuildPrompt(prompt) {
            return "Next Project Ideas"
        }

        let source = preferredTitleSource(prompt: prompt, assistantMessage: assistantMessage)
        let cleaned = cleanedTitleSource(source)
        guard !cleaned.isEmpty else { return fallbackTitle(for: repository) }
        return titleCased(cleaned)
    }

    private static func preferredTitleSource(prompt: String, assistantMessage: String?) -> String {
        let promptText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if isGenericPrompt(promptText),
           let assistantMessage,
           !assistantMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return assistantMessage
        }
        return promptText
    }

    private static func cleanedTitleSource(_ value: String) -> String {
        var text = value
            .components(separatedBy: .newlines)
            .first ?? value
        text = text.replacingOccurrences(of: #"(?i)^["'`]*\s*(please\s+)?(can|could|would)\s+you\s+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)^["'`]*\s*(please\s+)?(help\s+me|i\s+need\s+you\s+to|i\s+want\s+to|let'?s|we\s+need\s+to)\s+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)\busing\s+(cursor|runline|the\s+app)\b"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"["'`*_#>\[\]\(\)]"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[.!?;:]+$"#, with: "", options: .regularExpression)
        text = text
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(7)
            .joined(separator: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func titleCased(_ value: String) -> String {
        value
            .split(separator: " ")
            .map { formattedWord(String($0)) }
            .joined(separator: " ")
    }

    private static func formattedWord(_ word: String) -> String {
        let trimmed = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let lowercase = trimmed.lowercased()
        let knownForms: [String: String] = [
            "api": "API",
            "sdk": "SDK",
            "ui": "UI",
            "ux": "UX",
            "ios": "iOS",
            "ipados": "iPadOS",
            "macos": "macOS",
            "github": "GitHub",
            "gitlab": "GitLab",
            "json": "JSON",
            "sse": "SSE",
            "pr": "PR",
            "repo": "Repo"
        ]
        if let known = knownForms[lowercase] {
            return known
        }
        if trimmed.contains(where: { $0.isUppercase }) && trimmed.dropFirst().contains(where: { $0.isLowercase }) {
            return trimmed
        }
        guard let first = lowercase.first else { return trimmed }
        return String(first).uppercased() + lowercase.dropFirst()
    }

    private static func isGenericBuildPrompt(_ value: String) -> Bool {
        let normalized = normalizedComparisonValue(value)
        return normalized.contains("what should") && normalized.contains("build")
            || normalized.contains("what are we building")
            || normalized.contains("project ideas")
            || normalized.contains("next project")
    }

    private static func isGenericPrompt(_ value: String) -> Bool {
        let normalized = normalizedComparisonValue(value)
        return normalized.count < 18
            || normalized == "hello"
            || normalized == "hi"
            || normalized == "hey"
            || normalized.contains("what should")
            || normalized.contains("what can")
    }

    private static func fallbackTitle(for repository: Repository) -> String? {
        repository.isGeneralChat ? "General Chat" : repository.displayName
    }

    private static func placeholderTitles(for repository: Repository) -> Set<String> {
        [
            "",
            "general chat",
            "live workspace",
            "live-workspace",
            "new agent",
            "new-agent",
            "untitled chat",
            normalizedComparisonValue(repository.displayName),
            normalizedComparisonValue(repository.name),
            normalizedComparisonValue(repository.url.lastPathComponent.replacingOccurrences(of: ".git", with: ""))
        ]
    }

    private static func normalizedComparisonValue(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMachineGeneratedSlugTitle(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("-") || trimmed.contains("_") else { return false }
        return trimmed == trimmed.lowercased()
            && trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

enum ConversationPreviewGenerator {
    static func preview(from events: [AgentStreamEvent]) -> String? {
        guard let event = events.last(where: isPreviewEvent) else { return nil }
        return collapsedPreview(from: event.message)
    }

    static func preview(from prompt: AgentPrompt) -> String? {
        collapsedPreview(from: prompt.text)
    }

    static func collapsedPreview(from message: String, maxLength: Int = 140) -> String? {
        let collapsed = message
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func isPreviewEvent(_ event: AgentStreamEvent) -> Bool {
        switch event.kind {
        case .user, .assistant, .result, .task, .request, .status, .error:
            !event.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            false
        }
    }
}

enum WorkspaceFileChangeAction: String, Hashable, Codable {
    case added = "Added"
    case modified = "Modified"
    case deleted = "Deleted"
    case renamed = "Renamed"
    case unknown = "Changed"
}

struct WorkspaceFileChange: Identifiable, Hashable, Codable {
    var id: String { path }
    var path: String
    var action: WorkspaceFileChangeAction
    var additions: Int
    var deletions: Int
    var diff: String?
}

struct WorkspaceChangeSet: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var changes: [WorkspaceFileChange]
    var bodyText: String

    var totalAdditions: Int {
        changes.reduce(0) { $0 + $1.additions }
    }

    var totalDeletions: Int {
        changes.reduce(0) { $0 + $1.deletions }
    }
}

struct Artifact: Identifiable, Hashable, Codable {
    enum Kind: Hashable, Codable {
        case screenshot
        case video
        case log
        case file
    }

    var id: String { path }
    var path: String
    var kind: Kind
    var sizeDescription: String
    var updatedAtDescription: String
}

struct ArtifactDownload: Hashable, Codable {
    var url: URL
    var expiresAt: Date
}

struct ProviderCapabilities: Hashable, Codable {
    var supportsRepositoriesList = true
    var supportsSSEStreaming = true
    var supportsWebhooks = false
    var supportsArtifacts = true
    var supportsImagesInPrompt = true
    var supportsAutoCreatePR = true
    var supportsArchive = true
    var supportsDelete = true
    var supportsNativePullRequestReview = false
    var supportsSDKBridge = false
    var supportsLiveWorkspace = false
    var supportsPRMetadata = true

    static let disconnected = ProviderCapabilities(
        supportsRepositoriesList: false,
        supportsSSEStreaming: false,
        supportsWebhooks: false,
        supportsArtifacts: false,
        supportsImagesInPrompt: false,
        supportsAutoCreatePR: false,
        supportsArchive: false,
        supportsDelete: false,
        supportsNativePullRequestReview: false,
        supportsSDKBridge: false,
        supportsLiveWorkspace: false,
        supportsPRMetadata: false
    )
}
