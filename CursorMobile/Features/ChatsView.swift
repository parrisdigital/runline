import SwiftUI

struct ChatsView: View {
    @Environment(AppState.self) private var appState
    @State private var path: [Agent.ID] = []
    @State private var isNewChatPresented = false

    var body: some View {
        NavigationStack(path: $path) {
            ChatListContent(presentation: .navigation)
                .navigationTitle("Chats")
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
}

struct ChatListContent: View {
    enum Presentation {
        case navigation
        case selection(Binding<Agent.ID?>)
    }

    @Environment(AppState.self) private var appState
    var presentation: Presentation

    var body: some View {
        switch presentation {
        case .navigation:
            List {
                listContent
            }
            .refreshable {
                await appState.reloadWorkspace()
            }
        case .selection(let selectedAgentID):
            List(selection: selectedAgentID) {
                listContent
            }
            .refreshable {
                await appState.reloadWorkspace()
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
    private var listContent: some View {
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

    @ViewBuilder
    private func agentSection(_ title: String, agents: [Agent]) -> some View {
        if !agents.isEmpty {
            Section(title) {
                ForEach(agents) { agent in
                    agentRow(agent)
                }
            }
        }
    }

    @ViewBuilder
    private func agentRow(_ agent: Agent) -> some View {
        switch presentation {
        case .navigation:
            NavigationLink(value: agent.id) {
                AgentListRow(agent: agent, run: appState.runs(for: agent).first)
            }
        case .selection(let selectedAgentID):
            Button {
                selectedAgentID.wrappedValue = agent.id
            } label: {
                AgentListRow(agent: agent, run: appState.runs(for: agent).first)
            }
            .buttonStyle(.plain)
            .tag(agent.id)
        }
    }
}
