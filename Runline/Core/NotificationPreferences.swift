import Foundation

struct NotificationPreferences: Codable, Equatable, Hashable {
    var runStarted = true
    var runFinished = true
    var runFailed = true
    var artifactReady = true
    var pullRequestCreated = true
}

enum RunlineDeepLink: Equatable, Hashable {
    case agent(Agent.ID)
    case run(agentID: Agent.ID, runID: AgentRun.ID)
    case bridge(URL)

    init?(url: URL) {
        guard url.scheme == "runline" else { return nil }
        let parts = [url.host].compactMap { $0 } + url.path.split(separator: "/").map(String.init)

        if parts.first == "bridge",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let rawBridgeURL = components.queryItems?.first(where: { $0.name == "url" })?.value,
           let bridgeURL = SDKBridgePreferences.baseURL(from: rawBridgeURL) {
            self = .bridge(bridgeURL)
            return
        }

        if parts.count >= 2, parts[0] == "agent" {
            self = .agent(parts[1])
            return
        }

        if parts.count >= 4, parts[0] == "agents", parts[2] == "runs" {
            self = .run(agentID: parts[1], runID: parts[3])
            return
        }

        return nil
    }
}
