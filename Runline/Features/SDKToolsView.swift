import SwiftUI

struct SDKToolsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section("Bridge") {
                SDKBridgeReadinessRow()

                LabeledContent("Profiles", value: "\(appState.sdkBridgeProfiles.count)")
                LabeledContent("Pairing", value: appState.isSDKBridgePaired ? "Paired" : "Not Paired")
            }

            Section("SDK Experience") {
                SDKCapabilityRow(title: "Models", detail: "Choose a Cursor model per SDK chat or follow-up.", symbolName: "cpu")
                SDKCapabilityRow(title: "Context", detail: "Attach images and text files to prompts.", symbolName: "paperclip")
                SDKCapabilityRow(title: "Intent", detail: "Send Continue, Plan, or Execute messages.", symbolName: "checklist")
                SDKCapabilityRow(title: "Profiles", detail: "Select bridge-side MCP, skill, hook, and subagent bundles.", symbolName: "point.3.connected.trianglepath.dotted")
            }

            Section("Profiles") {
                if appState.sdkBridgeProfiles.isEmpty {
                    ContentUnavailableView(
                        "No SDK Profiles",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Publish profiles from Runline Bridge with RUNLINE_SDK_MCP_PROFILES.")
                    )
                } else {
                    ForEach(appState.sdkBridgeProfiles) { profile in
                        NavigationLink {
                            SDKBridgeProfileDetailView(profile: profile)
                        } label: {
                            SDKBridgeProfileRow(profile: profile)
                        }
                    }
                }
            }

            Section("Configuration") {
                SDKCapabilityRow(
                    title: "Bridge-side only",
                    detail: "MCP credentials, commands, hooks, and subagent prompts stay on the bridge. Runline receives safe metadata for display and selection.",
                    symbolName: "lock"
                )

                SDKCapabilityRow(
                    title: "Cloud execution",
                    detail: "SDK sessions still run through Cursor cloud mode when launched from this app.",
                    symbolName: "cloud"
                )
            }
        }
        .navigationTitle("SDK Tools")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await appState.reloadSDKBridgeProfiles()
        }
        .task {
            appState.syncSDKBridgeConfiguration()
            if appState.isSDKBridgePaired {
                await appState.reloadSDKBridgeProfiles()
            }
        }
    }
}

struct SDKBridgeProfileDetailView: View {
    var profile: SDKBridgeMCPProfile

    var body: some View {
        List {
            Section("Profile") {
                LabeledContent("Name", value: profile.name)
                LabeledContent("Summary", value: profile.summary)

                if let description = profile.description {
                    Text(description)
                        .foregroundStyle(.secondary)
                }
            }

            Section("MCP Servers") {
                if profile.mcpServers.isEmpty {
                    EmptySDKMetadataRow(title: "No MCP Servers", symbolName: "server.rack")
                } else {
                    ForEach(profile.mcpServers) { server in
                        NavigationLink {
                            SDKBridgeMCPServerDetailView(server: server)
                        } label: {
                            SDKBridgeMCPServerRow(server: server)
                        }
                    }
                }
            }

            Section("Subagents") {
                if profile.subagents.isEmpty {
                    EmptySDKMetadataRow(title: "No Subagents", symbolName: "person.2")
                } else {
                    ForEach(profile.subagents) { subagent in
                        SDKBridgeSubagentRow(subagent: subagent)
                    }
                }
            }

            Section("Skills") {
                if profile.skills.isEmpty {
                    EmptySDKMetadataRow(title: "No Skills", symbolName: "sparkles")
                } else {
                    ForEach(profile.skills) { skill in
                        SDKBridgeSkillRow(skill: skill)
                    }
                }
            }

            Section("Hooks") {
                if profile.hooks.isEmpty {
                    EmptySDKMetadataRow(title: "No Hooks", symbolName: "link")
                } else {
                    ForEach(profile.hooks) { hook in
                        SDKBridgeHookRow(hook: hook)
                    }
                }
            }

            Section("Tools") {
                if profile.toolHints.isEmpty {
                    EmptySDKMetadataRow(title: "No Tool Hints", symbolName: "wrench.and.screwdriver")
                } else {
                    ForEach(profile.toolHints) { tool in
                        SDKBridgeToolHintRow(tool: tool)
                    }
                }
            }

            Section("Privacy") {
                Text("Runline shows bridge-published metadata only. Secrets, MCP auth headers, command environments, hook scripts, and full subagent prompts stay on the bridge.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SDKBridgeMCPServerDetailView: View {
    var server: SDKBridgeMCPServer

    var body: some View {
        List {
            Section("Server") {
                LabeledContent("Name", value: server.name)
                LabeledContent("Transport", value: server.transport)
                LabeledContent("Auth", value: server.hasAuth ? "Configured" : "None")

                if let url = server.url {
                    LabeledContent("URL", value: url)
                }

                if let command = server.command {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Command")
                        Text(command)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Environment") {
                if server.environmentKeys.isEmpty {
                    EmptySDKMetadataRow(title: "No Environment Keys", symbolName: "key")
                } else {
                    ForEach(server.environmentKeys, id: \.self) { key in
                        Label(key, systemImage: "key")
                    }
                }
            }

            Section("Tools") {
                if server.toolHints.isEmpty {
                    EmptySDKMetadataRow(title: "No Tool Hints", symbolName: "wrench.and.screwdriver")
                } else {
                    ForEach(server.toolHints) { tool in
                        SDKBridgeToolHintRow(tool: tool)
                    }
                }
            }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SDKBridgeReadinessRow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: appState.isSDKBridgeReadyForLaunch ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(appState.isSDKBridgeReadyForLaunch ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.isSDKBridgeReadyForLaunch ? "Ready" : "Needs Setup")
                if let issue = appState.sdkBridgeReadinessIssue {
                    Text(issue)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Cursor SDK sessions can launch from iPhone and iPad.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SDKCapabilityRow: View {
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
            }
        } icon: {
            Image(systemName: symbolName)
        }
    }
}

private struct SDKBridgeProfileRow: View {
    var profile: SDKBridgeMCPProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.name)
            Text(profile.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let description = profile.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct SDKBridgeMCPServerRow: View {
    var server: SDKBridgeMCPServer

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                Text(serverDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: server.transport == "stdio" ? "terminal" : "network")
        }
    }

    private var serverDetail: String {
        var parts = [server.transport]
        if server.hasAuth {
            parts.append("auth")
        }
        if !server.toolHints.isEmpty {
            parts.append("\(server.toolHints.count) tools")
        }
        return parts.joined(separator: " / ")
    }
}

private struct SDKBridgeSubagentRow: View {
    var subagent: SDKBridgeSubagent

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(subagent.name)

                if let description = subagent.description {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let promptPreview = subagent.promptPreview {
                    Text(promptPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if let modelID = subagent.modelID {
                    Text("Model: \(modelID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: "person.2")
        }
    }
}

private struct SDKBridgeSkillRow: View {
    var skill: SDKBridgeSkill

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(skill.name)
                    if !skill.enabled {
                        Text("Disabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let description = skill.description {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let source = skill.source {
                    Text(source)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: "sparkles")
        }
    }
}

private struct SDKBridgeHookRow: View {
    var hook: SDKBridgeHook

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(hook.name)
                    if !hook.enabled {
                        Text("Disabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(hook.event)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let description = hook.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let command = hook.command {
                    Text(command)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } icon: {
            Image(systemName: "link")
        }
    }
}

private struct SDKBridgeToolHintRow: View {
    var tool: SDKBridgeToolHint

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)

                if let description = tool.description {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let server = tool.server {
                    Text(server)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: "wrench.and.screwdriver")
        }
    }
}

private struct EmptySDKMetadataRow: View {
    var title: String
    var symbolName: String

    var body: some View {
        Label(title, systemImage: symbolName)
            .foregroundStyle(.secondary)
    }
}
