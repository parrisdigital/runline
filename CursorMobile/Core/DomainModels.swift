import Foundation
import SwiftUI

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
    case repository(url: URL, startingRef: String?)
    case pullRequest(url: URL)
}

enum AgentRunMode: String, CaseIterable, Identifiable, Hashable, Codable {
    case cloudAgent
    case sdkBridge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cloudAgent:
            "Cloud Agent"
        case .sdkBridge:
            "SDK Agent"
        }
    }

    var detail: String {
        switch self {
        case .cloudAgent:
            "Direct Cursor Cloud Agents API from iOS."
        case .sdkBridge:
            "Multi-turn Cursor SDK session with Cloud Agent runtime."
        }
    }
}

enum SDKMessageIntent: String, CaseIterable, Identifiable, Hashable, Codable {
    case continueConversation
    case plan
    case execute

    var id: String { rawValue }

    var bridgeValue: String {
        switch self {
        case .continueConversation:
            "continue"
        case .plan:
            "plan"
        case .execute:
            "execute"
        }
    }

    var title: String {
        switch self {
        case .continueConversation:
            "Continue"
        case .plan:
            "Plan"
        case .execute:
            "Execute"
        }
    }
}

struct SDKBridgeMCPProfile: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var description: String?
    var mcpServerCount: Int
    var subagentCount: Int

    var summary: String {
        var parts: [String] = []
        if mcpServerCount > 0 {
            parts.append("\(mcpServerCount) MCP")
        }
        if subagentCount > 0 {
            parts.append("\(subagentCount) subagent")
        }
        return parts.isEmpty ? "SDK profile" : parts.joined(separator: " / ")
    }
}

struct AgentLaunchDraft: Hashable, Codable {
    var prompt: AgentPrompt
    var modelID: String?
    var source: AgentSource
    var runMode: AgentRunMode
    var sdkMCPProfileID: String?
    var branchName: String?
    var autoGenerateBranch: Bool
    var autoCreatePullRequest: Bool
    var skipReviewerRequest: Bool?

    init(
        prompt: AgentPrompt,
        modelID: String?,
        source: AgentSource,
        runMode: AgentRunMode = .cloudAgent,
        sdkMCPProfileID: String? = nil,
        branchName: String?,
        autoGenerateBranch: Bool,
        autoCreatePullRequest: Bool,
        skipReviewerRequest: Bool?
    ) {
        self.prompt = prompt
        self.modelID = modelID
        self.source = source
        self.runMode = runMode
        self.sdkMCPProfileID = sdkMCPProfileID
        self.branchName = branchName
        self.autoGenerateBranch = autoGenerateBranch
        self.autoCreatePullRequest = autoCreatePullRequest
        self.skipReviewerRequest = skipReviewerRequest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prompt = try container.decode(AgentPrompt.self, forKey: .prompt)
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        source = try container.decode(AgentSource.self, forKey: .source)
        runMode = try container.decodeIfPresent(AgentRunMode.self, forKey: .runMode) ?? .cloudAgent
        sdkMCPProfileID = try container.decodeIfPresent(String.self, forKey: .sdkMCPProfileID)
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

    static let disconnected = ProviderCapabilities(
        supportsRepositoriesList: false,
        supportsSSEStreaming: false,
        supportsWebhooks: false,
        supportsArtifacts: false,
        supportsImagesInPrompt: false,
        supportsAutoCreatePR: false,
        supportsArchive: false,
        supportsDelete: false,
        supportsNativePullRequestReview: false
    )
}
