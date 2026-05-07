import Foundation

@MainActor
protocol AgentProvider {
    var capabilities: ProviderCapabilities { get }

    func validateConnection() async throws -> ProviderAccount
    func listRepositories() async throws -> [Repository]
    func listModels() async throws -> [AgentModel]
    func listAgents() async throws -> [Agent]
    func getAgent(agentID: Agent.ID) async throws -> Agent
    func listRuns(agentID: Agent.ID) async throws -> [AgentRun]
    func getRun(agentID: Agent.ID, runID: AgentRun.ID) async throws -> AgentRun
    func streamEvents(agentID: Agent.ID, runID: AgentRun.ID) async throws -> [AgentStreamEvent]
    func createAgent(_ draft: AgentLaunchDraft) async throws -> AgentLaunchResult
    func createRun(_ draft: AgentFollowUpDraft) async throws -> AgentRun
    func cancelRun(agentID: Agent.ID, runID: AgentRun.ID) async throws
    func archiveAgent(agentID: Agent.ID) async throws
    func unarchiveAgent(agentID: Agent.ID) async throws
    func deleteAgent(agentID: Agent.ID) async throws
    func listArtifacts(agentID: Agent.ID) async throws -> [Artifact]
    func downloadArtifact(agentID: Agent.ID, path: String) async throws -> ArtifactDownload
}
