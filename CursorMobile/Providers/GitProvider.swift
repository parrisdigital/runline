import Foundation

enum GitProviderKind: String, Codable, Equatable, Hashable {
    case github
    case gitlab
}

struct GitProviderCapabilities: Codable, Equatable, Hashable {
    var supportsDiffs: Bool
    var supportsChecks: Bool
    var supportsInlineComments: Bool
    var supportsApprove: Bool
    var supportsRequestChanges: Bool

    static let disconnected = GitProviderCapabilities(
        supportsDiffs: false,
        supportsChecks: false,
        supportsInlineComments: false,
        supportsApprove: false,
        supportsRequestChanges: false
    )
}

struct PullRequestRef: Identifiable, Codable, Equatable, Hashable {
    var id: String { url.absoluteString }
    var provider: GitProviderKind
    var repositoryURL: URL
    var number: Int
    var url: URL
}

struct PullRequestSummary: Identifiable, Codable, Equatable, Hashable {
    var id: String { ref.id }
    var ref: PullRequestRef
    var title: String
    var author: String
    var sourceBranch: String
    var targetBranch: String
    var state: String
    var updatedAt: Date?
}

struct PullRequestFileDiff: Identifiable, Codable, Equatable, Hashable {
    var id: String { path }
    var path: String
    var additions: Int
    var deletions: Int
    var patch: String?
}

struct PullRequestCheck: Identifiable, Codable, Equatable, Hashable {
    enum Status: String, Codable {
        case queued
        case running
        case passed
        case failed
        case cancelled
        case skipped
        case unknown
    }

    var id: String
    var name: String
    var status: Status
    var detailsURL: URL?
}

struct PullRequestReviewComment: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var author: String
    var body: String
    var path: String?
    var line: Int?
    var createdAt: Date?
}

enum PullRequestReviewDecision: String, Codable, Equatable, Hashable {
    case approve
    case requestChanges
    case comment
}

struct PullRequestReviewDraft: Codable, Equatable, Hashable {
    var decision: PullRequestReviewDecision
    var body: String
    var comments: [PullRequestReviewComment]
}

@MainActor
protocol GitProvider {
    var kind: GitProviderKind { get }
    var capabilities: GitProviderCapabilities { get }

    func fetchPullRequest(_ ref: PullRequestRef) async throws -> PullRequestSummary
    func fetchDiff(_ ref: PullRequestRef) async throws -> [PullRequestFileDiff]
    func fetchChecks(_ ref: PullRequestRef) async throws -> [PullRequestCheck]
    func fetchComments(_ ref: PullRequestRef) async throws -> [PullRequestReviewComment]
    func submitReview(_ draft: PullRequestReviewDraft, for ref: PullRequestRef) async throws
}
