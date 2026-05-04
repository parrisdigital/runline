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
    @AppStorage(SDKBridgePreferences.isEnabledKey) private var isSDKBridgeEnabled = SDKBridgePreferences.defaultIsEnabled
    @AppStorage(SDKBridgePreferences.baseURLKey) private var sdkBridgeBaseURL = SDKBridgePreferences.defaultBaseURLString
    @State private var enterpriseAPIKey = ""
    @State private var sdkBridgeHealth: SDKBridgeHealthCheckState = .idle
    @FocusState private var focusedField: Field?

    private enum Field {
        case bridgeURL
        case enterpriseKey
    }

    var body: some View {
        @Bindable var appState = appState

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

                if isSDKBridgeEnabled {
                    LabeledContent("Status") {
                        Label(sdkBridgeHealth.title, systemImage: sdkBridgeHealth.systemImage)
                            .foregroundStyle(sdkBridgeHealth.tint)
                    }

                    LabeledContent("Profiles", value: "\(appState.sdkBridgeProfiles.count)")

                    Button {
                        Task {
                            await checkSDKBridgeHealth()
                        }
                    } label: {
                        if sdkBridgeHealth == .checking {
                            ProgressView()
                        } else {
                            Text("Check Connection")
                        }
                    }
                    .disabled(sdkBridgeHealth == .checking)
                }
            } header: {
                Text("Cursor SDK Agent Bridge")
            } footer: {
                Text("Cloud Agent stays direct from iOS. SDK Agent uses this bridge for resumable SDK sessions, MCP profiles, and subagents.")
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
        .onChange(of: sdkBridgeBaseURL) { _, _ in
            sdkBridgeHealth = .idle
        }
        .onChange(of: isSDKBridgeEnabled) { _, _ in
            sdkBridgeHealth = .idle
            if isSDKBridgeEnabled {
                Task {
                    await appState.reloadSDKBridgeProfiles()
                }
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

    private func saveEnterpriseKey() {
        let key = enterpriseAPIKey
        enterpriseAPIKey = ""
        focusedField = nil
        Task {
            await appState.connectEnterpriseAPIKey(apiKey: key)
        }
    }

    private func checkSDKBridgeHealth() async {
        focusedField = nil
        guard let baseURL = SDKBridgePreferences.baseURL(from: sdkBridgeBaseURL) else {
            sdkBridgeHealth = .failed("Invalid URL")
            return
        }

        sdkBridgeHealth = .checking
        do {
            let health = try await SDKBridgeClient(baseURL: baseURL).health()
            sdkBridgeHealth = health.ok
                ? .healthy("\(health.service) - \(health.sdk)")
                : .failed("Bridge responded unhealthy")
            if health.ok {
                await appState.reloadSDKBridgeProfiles()
            }
        } catch {
            sdkBridgeHealth = .failed(error.localizedDescription)
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

private enum SDKBridgeHealthCheckState: Equatable {
    case idle
    case checking
    case healthy(String)
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            "Not Checked"
        case .checking:
            "Checking"
        case .healthy(let message), .failed(let message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "circle"
        case .checking:
            "clock"
        case .healthy:
            "checkmark.circle"
        case .failed:
            "exclamationmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .healthy:
            .green
        case .failed:
            .red
        case .checking, .idle:
            .secondary
        }
    }
}
