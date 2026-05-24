import SwiftUI
import UserNotifications

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            SettingsFormContent()
                .navigationTitle("Settings")
        }
    }
}

struct SettingsFormContent: View {
    @Environment(AppState.self) private var appState
    @AppStorage("appearance.mode") private var appearanceMode = AppAppearanceMode.system.rawValue
    @State private var enterpriseAPIKey = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case enterpriseKey
    }

    var body: some View {
        Form {
            Section("Account") {
                if let account = appState.account {
                    LabeledContent("API key", value: account.apiKeyName)
                    LabeledContent("User", value: account.userEmail)
                    LabeledContent("Created", value: account.createdAt.formatted(date: .abbreviated, time: .omitted))

                    Button("Disconnect", role: .destructive) {
                        appState.disconnect()
                    }
                } else {
                    Text("No Cursor API key is connected.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Appearance") {
                Picker("Color Scheme", selection: $appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                LabeledContent("Repositories", value: "\(appState.repositories.count)")
                LabeledContent("Models", value: "\(appState.models.count)")
                LabeledContent("Cursor Cloud", value: "\(appState.agents.filter { $0.runtimeMode == .cloud }.count)")
                LabeledContent("Cursor Chat", value: "\(appState.agents.filter { $0.runtimeMode == .sdkBridge }.count)")

                Button {
                    Task {
                        await appState.reloadWorkspace()
                    }
                } label: {
                    if appState.isRefreshing {
                        ProgressView()
                    } else {
                        Label("Refresh Cursor Data", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(appState.isRefreshing)
            } header: {
                Text("Cursor Cloud")
            } footer: {
                Text("Runline talks directly to Cursor's Cloud Agents API from this device. No separate server is required.")
            }

            Section {
                LabeledContent("Status", value: "Ready")
                LabeledContent("Provider", value: "Runline Bridge")

                Button {
                    Task {
                        await appState.testSDKBridgeConnection()
                    }
                } label: {
                    if appState.isCheckingSDKBridge {
                        ProgressView()
                    } else {
                        Label("Test Bridge", systemImage: "network")
                    }
                }
                .disabled(appState.isCheckingSDKBridge)
            } header: {
                Text("Cursor Chat")
            } footer: {
                Text("Cursor Chat starts SDK-backed workspace sessions through the Runline bridge. Your Cursor key stays in Keychain and is sent over HTTPS only when you start or continue a chat.")
            }

            Section("Enterprise API") {
                if let enterpriseAccount = appState.enterpriseAccount {
                    LabeledContent("Key", value: enterpriseAccount.apiKeyName)
                    LabeledContent("User", value: enterpriseAccount.userEmail)
                    Button("Remove Enterprise Key", role: .destructive) {
                        appState.disconnectEnterpriseAPIKey()
                    }
                } else {
                    SecureField("Admin API key", text: $enterpriseAPIKey)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .enterpriseKey)

                    Button("Save Enterprise Key") {
                        saveEnterpriseKey()
                    }
                    .disabled(enterpriseAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Notifications") {
                LabeledContent("Permission", value: permissionTitle)

                Button("Request Permission") {
                    Task {
                        await appState.requestNotificationPermission()
                    }
                }

                Toggle("Run started", isOn: notificationBinding(\.runStarted))
                Toggle("Run finished", isOn: notificationBinding(\.runFinished))
                Toggle("Run failed", isOn: notificationBinding(\.runFailed))
                Toggle("Artifact ready", isOn: notificationBinding(\.artifactReady))
                Toggle("Pull request created", isOn: notificationBinding(\.pullRequestCreated))

                if let registration = appState.deviceTokenRegistration {
                    LabeledContent("Device", value: registration.deviceID.uuidString)
                }

                if let error = appState.notificationRegistrationError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section("About") {
                Text("Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Cursor bills Cloud Agent runs through your Cursor account. This app does not include Cursor credits.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .task {
            await appState.refreshNotificationStatus()
        }
    }

    private var permissionTitle: String {
        switch appState.notificationAuthorizationStatus {
        case .notDetermined:
            "Not Determined"
        case .denied:
            "Denied"
        case .authorized:
            "Authorized"
        case .provisional:
            "Provisional"
        case .ephemeral:
            "Ephemeral"
        @unknown default:
            "Unknown"
        }
    }

    private func saveEnterpriseKey() {
        let key = enterpriseAPIKey
        enterpriseAPIKey = ""
        focusedField = nil
        Task {
            await appState.connectEnterpriseAPIKey(apiKey: key)
        }
    }

    private func notificationBinding(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>) -> Binding<Bool> {
        Binding {
            appState.notificationPreferences[keyPath: keyPath]
        } set: { value in
            appState.updateNotificationPreferences { preferences in
                preferences[keyPath: keyPath] = value
            }
        }
    }
}
