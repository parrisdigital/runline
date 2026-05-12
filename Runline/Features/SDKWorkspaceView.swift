import SwiftUI

struct SDKWorkspaceView: View {
    @Environment(AppState.self) private var appState
    @State private var path: [Agent.ID] = []
    @State private var isNewSDKSessionPresented = false
    @State private var cursorSDKOnboardingSheet: CursorSDKOnboardingSheet?

    var body: some View {
        NavigationStack(path: $path) {
            SDKWorkspaceContent(
                selectAgent: { path = [$0.id] },
                newSDKChat: startNewSDKSession,
                openSetup: { cursorSDKOnboardingSheet = .setup }
            )
            .navigationTitle("Cursor SDK")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: startNewSDKSession) {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New SDK Session")
                }
            }
            .navigationDestination(for: Agent.ID.self) { agentID in
                if let agent = appState.agent(id: agentID) {
                    SDKSessionDetailView(agent: agent)
                } else {
                    ContentUnavailableView(
                        "Session Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("This SDK session is no longer in the local cache.")
                    )
                    .navigationTitle("Cursor SDK")
                }
            }
            .sheet(isPresented: $isNewSDKSessionPresented) {
                SDKNewSessionSheet()
            }
            .sheet(item: $cursorSDKOnboardingSheet) { _ in
                CursorSDKOnboardingView(
                    onUseCloud: {
                        appState.applyDefaultRunMode(.cloudAgent)
                    },
                    onUseSDK: {
                        appState.applyDefaultRunMode(.sdkBridge)
                    },
                    onOpenSettings: {
                        appState.selectedTab = .settings
                    }
                )
            }
        }
    }

    private func startNewSDKSession() {
        appState.launchDraft.runMode = .sdkBridge
        isNewSDKSessionPresented = true
    }
}

struct SDKWorkspaceContent: View {
    @Environment(AppState.self) private var appState
    var selectAgent: (Agent) -> Void
    var newSDKChat: () -> Void
    var openSetup: () -> Void

    private var sdkAgents: [Agent] {
        appState.agents.filter(appState.isSDKBridgeAgent)
    }

    private var activeSDKAgents: [Agent] {
        sdkAgents.filter { agent in
            guard case .archived = agent.status else { return true }
            return false
        }
    }

    private var runningSDKAgents: [Agent] {
        activeSDKAgents.filter { appState.runs(for: $0).first?.status == .running || appState.runs(for: $0).first?.status == .creating }
    }

    private var recentSDKAgents: [Agent] {
        activeSDKAgents.filter { agent in
            guard let status = appState.runs(for: agent).first?.status else { return true }
            return status != .running && status != .creating
        }
    }

    private var archivedSDKAgents: [Agent] {
        sdkAgents.filter { agent in
            if case .archived = agent.status { return true }
            return false
        }
    }

    var body: some View {
        List {
            Section {
                SDKWorkspaceStatusCard(
                    newSDKChat: newSDKChat,
                    openSetup: openSetup
                )
            }

            Section("Sessions") {
                if sdkAgents.isEmpty {
                    ContentUnavailableView(
                        "No SDK Sessions",
                        systemImage: "terminal",
                        description: Text("Start a Cursor SDK chat to plan, execute, and continue against the same SDK session.")
                    )
                } else {
                    sdkAgentRows("Running", agents: runningSDKAgents)
                    sdkAgentRows("Recent", agents: recentSDKAgents)
                    sdkAgentRows("Archived", agents: archivedSDKAgents)
                }
            }

            Section("Controls") {
                SDKWorkspaceCapabilityRow(
                    title: "Models",
                    detail: modelSummary,
                    symbolName: "cpu"
                )
                SDKWorkspaceCapabilityRow(
                    title: "Files and images",
                    detail: "Attach context to the first prompt or follow-up composer.",
                    symbolName: "paperclip"
                )
                SDKWorkspaceCapabilityRow(
                    title: "Plan and execute",
                    detail: "Use Continue, Plan, or Execute from the SDK chat composer.",
                    symbolName: "checklist"
                )
            }

            Section("Bridge Tools") {
                NavigationLink {
                    SDKToolsView()
                } label: {
                    SDKWorkspaceCapabilityRow(
                        title: "MCP, skills, hooks, subagents",
                        detail: sdkProfileSummary,
                        symbolName: "point.3.connected.trianglepath.dotted"
                    )
                }

                SDKWorkspaceCapabilityRow(
                    title: "Remote access",
                    detail: "Use a relay, Tailscale, tunnel, or hosted HTTPS bridge when your iPhone is away from your Mac network.",
                    symbolName: "network"
                )
            }

            Section {
                Text("Cloud Agent mode stays direct from iOS. Cursor SDK mode requires Runline Bridge to be reachable while you control or stream SDK sessions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaPadding(.bottom, 24)
        .refreshable {
            await appState.checkSDKBridgeConnection()
            await appState.reloadSDKBridgeProfiles()
        }
        .task {
            appState.syncSDKBridgeConfiguration()
            if appState.isSDKBridgePaired {
                await appState.reloadSDKBridgeProfiles()
            }
        }
    }

    @ViewBuilder
    private func sdkAgentRows(_ title: String, agents: [Agent]) -> some View {
        if !agents.isEmpty {
            ForEach(agents) { agent in
                Button {
                    selectAgent(agent)
                } label: {
                    AgentListRow(agent: agent, run: appState.runs(for: agent).first)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var modelSummary: String {
        let visibleCount = NewChatModelPickerOptions.visibleModels(from: appState.models).count
        return visibleCount == 0 ? "Default Cursor model until models load." : "\(visibleCount) selectable Cursor models."
    }

    private var sdkProfileSummary: String {
        if appState.sdkBridgeProfiles.isEmpty {
            return "Publish profiles from Runline Bridge to expose bridge-side tools."
        }
        return "\(appState.sdkBridgeProfiles.count) bridge profile\(appState.sdkBridgeProfiles.count == 1 ? "" : "s") available."
    }
}

private struct SDKWorkspaceStatusCard: View {
    @Environment(AppState.self) private var appState
    var newSDKChat: () -> Void
    var openSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: appState.isSDKBridgeReadyForLaunch ? "checkmark.circle.fill" : "point.3.connected.trianglepath.dotted")
                    .font(.title2)
                    .foregroundStyle(appState.isSDKBridgeReadyForLaunch ? Color.green : Color.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button(action: newSDKChat) {
                    Label("New Session", systemImage: "square.and.pencil")
                        .lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.white)
                .disabled(!appState.isSDKBridgeReadyForLaunch)
                .accessibilityLabel("New SDK Session")

                Button(action: openSetup) {
                    Label(appState.isSDKBridgeReadyForLaunch ? "Manage" : "Set Up", systemImage: "slider.horizontal.3")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
            }

            if let issue = appState.sdkBridgeReadinessIssue {
                Text(issue)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusTitle: String {
        appState.isSDKBridgeReadyForLaunch ? "Cursor SDK Ready" : "Cursor SDK Needs Setup"
    }

    private var statusDetail: String {
        appState.isSDKBridgeReadyForLaunch
            ? "Use model selection, files, images, MCP profiles, and follow-up chat through Runline Bridge."
            : "Pair Runline Bridge to unlock the SDK workspace. Cloud Agent mode still works without it."
    }
}

private struct SDKWorkspaceCapabilityRow: View {
    var title: String
    var detail: String
    var symbolName: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbolName)
        }
    }
}
