import Foundation

struct DeviceTokenRegistration: Codable, Equatable, Hashable {
    enum Environment: String, Codable {
        case sandbox
        case production
    }

    var deviceID: UUID
    var tokenHex: String
    var environment: Environment
    var preferences: NotificationPreferences
    var appVersion: String
    var updatedAt: Date
}

enum CursorMobilePushEventKind: String, Codable, Equatable, Hashable {
    case runStarted
    case runFinished
    case runFailed
    case artifactReady
    case pullRequestCreated
}

struct CursorMobilePushPayload: Codable, Equatable, Hashable {
    var event: CursorMobilePushEventKind
    var agentID: Agent.ID
    var runID: AgentRun.ID?
    var artifactPath: String?
    var pullRequestURL: URL?
    var deepLinkURL: URL

    init(
        event: CursorMobilePushEventKind,
        agentID: Agent.ID,
        runID: AgentRun.ID? = nil,
        artifactPath: String? = nil,
        pullRequestURL: URL? = nil
    ) {
        self.event = event
        self.agentID = agentID
        self.runID = runID
        self.artifactPath = artifactPath
        self.pullRequestURL = pullRequestURL

        if let runID {
            deepLinkURL = URL(string: "runline://agents/\(agentID)/runs/\(runID)")!
        } else {
            deepLinkURL = URL(string: "runline://agent/\(agentID)")!
        }
    }
}

extension Data {
    var hexadecimalString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
