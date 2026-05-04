import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("appearance.mode") private var appearanceMode = AppAppearanceMode.system.rawValue
    @AppStorage("sdkBridge.isEnabled") private var isSDKBridgeEnabled = false
    @AppStorage("sdkBridge.baseURL") private var sdkBridgeBaseURL = "http://localhost:8787"
    @State private var enterpriseAPIKey = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case bridgeURL
        case enterpriseKey
    }

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
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
                    Toggle("Enable SDK bridge", isOn: $isSDKBridgeEnabled)

                    TextField("Bridge URL", text: $sdkBridgeBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .bridgeURL)
                        .disabled(!isSDKBridgeEnabled)
                } header: {
                    Text("Cursor SDK Bridge")
                } footer: {
                    Text("Core Cloud Agent actions still use Cursor's v1 API directly from iOS. Enable the bridge only for SDK-only workflows such as MCP profiles or subagents.")
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
                            let key = enterpriseAPIKey
                            enterpriseAPIKey = ""
                            focusedField = nil
                            Task {
                                await appState.connectEnterpriseAPIKey(apiKey: key)
                            }
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
            .navigationTitle("Settings")
            .task {
                await appState.refreshNotificationStatus()
            }
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
