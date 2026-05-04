import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isConnected {
                AppShellView()
            } else {
                WelcomeView()
            }
        }
        .task {
            await appState.restoreConnectionIfAvailable()
        }
        .onOpenURL { url in
            appState.handleDeepLink(url)
        }
        .alert("Runline", isPresented: isShowingError) {
            Button("OK") {
                appState.errorMessage = nil
            }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if appState.isConnected, let message = appState.statusMessage {
                StatusBanner(message: message) {
                    appState.dismissStatusMessage()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: appState.statusMessage)
    }

    private var isShowingError: Binding<Bool> {
        Binding {
            appState.errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                appState.errorMessage = nil
            }
        }
    }
}

private struct StatusBanner: View {
    var message: String
    var dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)

            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss status")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 8, y: 4)
    }
}

struct AppShellView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        switch AppLayoutMode.resolve(horizontalSizeClass: horizontalSizeClass) {
        case .compactTabs:
            CompactAppShellView()
        case .regularSplit:
            RegularAppShellView()
        }
    }
}

private struct CompactAppShellView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: $appState.selectedTab) {
            ChatsView()
                .tabItem { Label(AppTab.chats.title, systemImage: AppTab.chats.symbolName) }
                .tag(AppTab.chats)
                .accessibilityIdentifier("tab.chats")

            RepositoriesView()
                .tabItem { Label(AppTab.repositories.title, systemImage: AppTab.repositories.symbolName) }
                .tag(AppTab.repositories)
                .accessibilityIdentifier("tab.repositories")

            SettingsView()
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.symbolName) }
                .tag(AppTab.settings)
                .accessibilityIdentifier("tab.settings")
        }
    }
}

private struct RegularAppShellView: View {
    @Environment(AppState.self) private var appState
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var selectedAgentID: Agent.ID?
    @State private var selectedRepositoryURL: URL?
    @State private var repositoryQuery = ""
    @State private var isComposing = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: selectedTabBinding) {
                ForEach(AppTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbolName)
                        .tag(tab)
                }
            }
            .navigationTitle("Runline")
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: appState.selectedTab) { _, tab in
            if tab == .settings {
                isComposing = false
            }
        }
        .onChange(of: appState.focusedAgentID) { _, agentID in
            focusAgent(agentID)
        }
        .onChange(of: appState.agents.map(\.id)) { _, agentIDs in
            guard let selectedAgentID, !agentIDs.contains(selectedAgentID) else { return }
            self.selectedAgentID = nil
        }
        .task {
            selectedRepositoryURL = appState.selectedRepository?.url
            focusAgent(appState.focusedAgentID)
        }
    }

    private var selectedTabBinding: Binding<AppTab?> {
        Binding {
            appState.selectedTab
        } set: { tab in
            if let tab {
                appState.selectedTab = tab
            }
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch appState.selectedTab {
        case .chats:
            ChatListContent(presentation: .selection($selectedAgentID))
                .navigationTitle("Chats")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: startNewChat) {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("New Chat")
                    }
                }
        case .repositories:
            RepositoryListContent(
                query: $repositoryQuery,
                presentation: .selection($selectedRepositoryURL),
                select: selectRepository
            )
            .navigationTitle("Repositories")
            .searchable(text: $repositoryQuery, prompt: "Search repositories")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await appState.reloadWorkspace()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
        case .settings:
            SettingsColumnSummary()
                .navigationTitle("Settings")
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch appState.selectedTab {
        case .chats:
            if isComposing {
                NewChatForm(presentation: .detail)
            } else if let selectedAgentID,
                      let agent = appState.agent(id: selectedAgentID) {
                ChatDetailView(agent: agent)
            } else {
                ContentUnavailableView(
                    "Select a Chat",
                    systemImage: "message",
                    description: Text("Choose a cloud-agent run from the Chats column.")
                )
                .navigationTitle("Chat")
            }
        case .repositories:
            if isComposing {
                NewChatForm(presentation: .detail)
            } else {
                ContentUnavailableView(
                    "Select a Repository",
                    systemImage: "folder",
                    description: Text("Choose a repository to configure a new cloud-agent run.")
                )
                .navigationTitle("New Chat")
            }
        case .settings:
            SettingsFormContent()
                .navigationTitle("Settings")
        }
    }

    private func startNewChat() {
        selectedAgentID = nil
        isComposing = true
    }

    private func selectRepository(_ repository: Repository) {
        selectedRepositoryURL = repository.url
        appState.launchDraft.source = .repository(
            url: repository.url,
            startingRef: repository.defaultBranch.nilIfBlank
        )
        isComposing = true
    }

    private func focusAgent(_ agentID: Agent.ID?) {
        guard let agentID else { return }
        selectedAgentID = agentID
        isComposing = false
        appState.selectedTab = .chats
        appState.focusedAgentID = nil
    }
}

private struct SettingsColumnSummary: View {
    var body: some View {
        List {
            Section {
                Label("Account", systemImage: "person.crop.circle")
                Label("Appearance", systemImage: "circle.lefthalf.filled")
                Label("Notifications", systemImage: "bell")
                Label("SDK Bridge", systemImage: "point.3.connected.trianglepath.dotted")
            }

            Section {
                Text("Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
