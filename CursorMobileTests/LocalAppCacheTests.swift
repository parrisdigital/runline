import Foundation
import XCTest
@testable import CursorMobile

final class LocalAppCacheTests: XCTestCase {
    func testSaveLoadAndClearSnapshot() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("cache.json")
        let cache = LocalAppCache(fileURL: fileURL)
        let snapshot = makeSnapshot()

        try cache.save(snapshot)

        let loaded = try XCTUnwrap(cache.load())
        XCTAssertEqual(loaded.account, snapshot.account)
        XCTAssertEqual(loaded.repositories, snapshot.repositories)
        XCTAssertEqual(loaded.models, snapshot.models)
        XCTAssertEqual(loaded.agents, snapshot.agents)
        XCTAssertEqual(loaded.runsByAgentID, snapshot.runsByAgentID)
        XCTAssertEqual(loaded.eventsByRunID, snapshot.eventsByRunID)
        XCTAssertEqual(loaded.artifactsByAgentID, snapshot.artifactsByAgentID)
        XCTAssertEqual(loaded.sdkBridgeRunIDs, snapshot.sdkBridgeRunIDs)
        XCTAssertEqual(loaded.sdkBridgeMCPProfileIDsByAgentID, snapshot.sdkBridgeMCPProfileIDsByAgentID)
        XCTAssertEqual(loaded.launchDraft, snapshot.launchDraft)
        XCTAssertEqual(loaded.notificationPreferences, snapshot.notificationPreferences)

        try cache.clear()
        XCTAssertNil(try cache.load())
    }

    private func makeSnapshot() -> AppCacheSnapshot {
        let repository = Repository(
            owner: "acme",
            name: "ios-app",
            url: URL(string: "https://github.com/acme/ios-app")!,
            defaultBranch: "main",
            isFavorite: true,
            lastUsedDescription: "now"
        )
        let model = AgentModel(
            id: "default",
            displayName: "default",
            subtitle: "Cursor default",
            category: .default,
            qualityScore: 4,
            costTier: 1
        )
        let agent = Agent(
            id: "agent_1",
            name: "cache-test",
            status: .active,
            repository: repository,
            branchName: "main",
            modelID: model.id,
            latestRunID: "run_1",
            updatedAtDescription: "now",
            artifactCount: 1,
            pullRequestURL: URL(string: "https://github.com/acme/ios-app/pull/1")
        )
        let run = AgentRun(
            id: "run_1",
            agentID: agent.id,
            status: .finished,
            createdAtDescription: "1m ago",
            updatedAtDescription: "now"
        )
        return AppCacheSnapshot(
            account: ProviderAccount(apiKeyName: "Key", userEmail: "developer@example.com", createdAt: Date(timeIntervalSince1970: 100)),
            repositories: [repository],
            models: [model],
            agents: [agent],
            runsByAgentID: [agent.id: [run]],
            eventsByRunID: [
                run.id: [
                    AgentStreamEvent(id: "event_1", runID: run.id, kind: .done, title: "Done", message: "Finished", timestamp: "now")
                ]
            ],
            artifactsByAgentID: [
                agent.id: [
                    Artifact(path: "artifacts/run-log.txt", kind: .log, sizeDescription: "1 KB", updatedAtDescription: "now")
                ]
            ],
            sdkBridgeRunIDs: [run.id],
            sdkBridgeMCPProfileIDsByAgentID: [agent.id: "github-tools"],
            launchDraft: AgentLaunchDraft(
                prompt: AgentPrompt(text: "Cache this"),
                modelID: model.id,
                source: .repository(url: repository.url, startingRef: repository.defaultBranch),
                branchName: nil,
                autoGenerateBranch: true,
                autoCreatePullRequest: true,
                skipReviewerRequest: false
            ),
            notificationPreferences: NotificationPreferences(runStarted: true, runFinished: true, runFailed: true, artifactReady: false, pullRequestCreated: true),
            cachedAt: Date(timeIntervalSince1970: 200)
        )
    }
}
