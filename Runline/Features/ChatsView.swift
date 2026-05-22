import SwiftUI

struct ChatsView: View {
    @Environment(AppState.self) private var appState
    @State private var path: [Agent.ID] = []
    @State private var isNewChatPresented = false
    @State private var query = ""

    var body: some View {
        NavigationStack(path: $path) {
            ChatListContent(query: $query, presentation: .navigation)
                .navigationTitle("Runline")
                .navigationBarTitleDisplayMode(.inline)
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
    @Binding var query: String
    var presentation: Presentation

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                CloudChatScreenHeader(
                    query: $query,
                    activeCount: cloudActiveAgents.count,
                    runningCount: runningAgents.count,
                    repositoryCount: appState.repositories.count
                )

                listContent
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 110)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await appState.reloadWorkspace()
        }
    }

    private var runningAgents: [Agent] {
        filteredActiveAgents.filter { agent in
            let status = appState.runs(for: agent).first?.status
            return status == .running || status == .creating
        }
    }

    private var recentAgents: [Agent] {
        filteredActiveAgents.filter { agent in
            let status = appState.runs(for: agent).first?.status
            return status != .running && status != .creating
        }
    }

    private var archivedAgents: [Agent] {
        filteredAgents.filter { agent in
            if case .archived = agent.status { return true }
            return false
        }
    }

    private var cloudAgents: [Agent] {
        appState.agents
    }

    private var filteredAgents: [Agent] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return cloudAgents }
        return cloudAgents.filter { agent in
            agent.name.localizedCaseInsensitiveContains(trimmedQuery)
                || agent.repository.displayName.localizedCaseInsensitiveContains(trimmedQuery)
                || agent.branchName.localizedCaseInsensitiveContains(trimmedQuery)
                || agent.modelID.localizedCaseInsensitiveContains(trimmedQuery)
                || agent.status.title.localizedCaseInsensitiveContains(trimmedQuery)
                || (appState.runs(for: agent).first?.status.title.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }

    private var cloudActiveAgents: [Agent] {
        cloudAgents.filter { agent in
            guard case .archived = agent.status else { return true }
            return false
        }
    }

    private var filteredActiveAgents: [Agent] {
        filteredAgents.filter { agent in
            guard case .archived = agent.status else { return true }
            return false
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if cloudAgents.isEmpty {
            ContentUnavailableView(
                "No Chats",
                systemImage: "message",
                description: Text("Start a Cloud Agent run to create your first chat.")
            )
        } else if filteredAgents.isEmpty {
            ContentUnavailableView(
                "No Matches",
                systemImage: "magnifyingglass",
                description: Text("Try a repository, branch, model, or status.")
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text("\(agents.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 2)

                VStack(spacing: 8) {
                    ForEach(agents) { agent in
                        agentRow(agent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func agentRow(_ agent: Agent) -> some View {
        let run = appState.runs(for: agent).first
        switch presentation {
        case .navigation:
            NavigationLink(value: agent.id) {
                AgentListRow(agent: agent, run: run)
            }
            .buttonStyle(.plain)
        case .selection(let selectedAgentID):
            Button {
                selectedAgentID.wrappedValue = agent.id
            } label: {
                AgentListRow(
                    agent: agent,
                    run: run,
                    isSelected: selectedAgentID.wrappedValue == agent.id
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CloudChatScreenHeader: View {
    @Binding var query: String
    var activeCount: Int
    var runningCount: Int
    var repositoryCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Chats")
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Cloud Agent conversations across your Cursor repositories.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            CloudChatSearchField(query: $query)

            CloudChatOverviewPanel(
                activeCount: activeCount,
                runningCount: runningCount,
                repositoryCount: repositoryCount
            )
        }
    }
}

private struct CloudChatSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            TextField("Search chats", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.body)
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 0.5)
        )
    }
}

private struct CloudChatOverviewPanel: View {
    var activeCount: Int
    var runningCount: Int
    var repositoryCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                    Image(systemName: "cloud.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cursor Cloud")
                        .font(.headline.weight(.semibold))
                    Text("Connected directly from this device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Label("Live", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.green.opacity(0.11)))
            }

            HStack(spacing: 8) {
                CloudChatMetric(title: "Active", value: activeCount)
                CloudChatMetric(title: "Running", value: runningCount)
                CloudChatMetric(title: "Repos", value: repositoryCount)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct CloudChatMetric: View {
    var title: String
    var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.headline.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }
}
