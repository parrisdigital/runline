import SwiftUI

struct ChatsView: View {
    @Environment(AppState.self) private var appState
    @State private var path: [Agent.ID] = []
    @State private var isNewChatPresented = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if appState.agents.isEmpty {
                    ContentUnavailableView(
                        "No Chats",
                        systemImage: "message",
                        description: Text("Start a cloud-agent run to create your first chat.")
                    )
                } else {
                    agentSection("Running", agents: runningAgents)
                    agentSection("Recent", agents: recentAgents)
                    agentSection("Archived", agents: archivedAgents)
                }
            }
            .navigationTitle("Chats")
            .refreshable {
                await appState.reloadWorkspace()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isNewChatPresented = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New Chat")
                }
            }
            .navigationDestination(for: Agent.ID.self) { agentID in
                if let agent = appState.agent(id: agentID) {
                    ChatDetailView(agent: agent)
                } else {
                    ContentUnavailableView(
                        "Chat Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("This agent is no longer in the local cache.")
                    )
                    .navigationTitle("Chat")
                }
            }
            .onChange(of: appState.focusedAgentID) { _, agentID in
                guard let agentID else { return }
                path = [agentID]
                appState.focusedAgentID = nil
            }
            .sheet(isPresented: $isNewChatPresented) {
                NewChatSheet()
            }
        }
    }

    private var runningAgents: [Agent] {
        appState.activeAgents.filter { appState.runs(for: $0).first?.status == .running }
    }

    private var recentAgents: [Agent] {
        appState.activeAgents.filter { appState.runs(for: $0).first?.status != .running }
    }

    private var archivedAgents: [Agent] {
        appState.agents.filter { agent in
            if case .archived = agent.status { return true }
            return false
        }
    }

    @ViewBuilder
    private func agentSection(_ title: String, agents: [Agent]) -> some View {
        if !agents.isEmpty {
            Section(title) {
                ForEach(agents) { agent in
                    NavigationLink(value: agent.id) {
                        AgentListRow(agent: agent, run: appState.runs(for: agent).first)
                    }
                }
            }
        }
    }
}
