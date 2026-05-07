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
    @AppStorage(RunlineWorkflowPreferences.didChooseDefaultRunModeKey) private var didChooseDefaultRunMode = false
    @AppStorage(RunlineWorkflowPreferences.defaultRunModeKey) private var defaultRunModeRawValue = RunlineWorkflowPreferences.defaultRunMode.rawValue
    @AppStorage(SDKBridgePreferences.isEnabledKey) private var isSDKBridgeEnabled = SDKBridgePreferences.defaultIsEnabled
    @AppStorage(SDKBridgePreferences.baseURLKey) private var sdkBridgeBaseURL = SDKBridgePreferences.defaultBaseURLString
    @State private var enterpriseAPIKey = ""
    @State private var cursorSDKOnboardingSheet: CursorSDKOnboardingSheet?
    @State private var pairingCode = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case bridgeURL
        case pairingCode
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
                Picker("Default", selection: defaultRunModeBinding) {
                    ForEach(AgentRunMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Current default", value: RunlineWorkflowPreferences.runMode(from: defaultRunModeRawValue).detail)
            } header: {
                Text("Default Runtime")
            } footer: {
                Text("Cloud Agent is the default runtime. Cursor SDK can be selected per chat once Runline Bridge is connected.")
            }

            Section {
                Button {
                    cursorSDKOnboardingSheet = .setup
                } label: {
                    Label("Cursor SDK Setup", systemImage: "point.3.connected.trianglepath.dotted")
                }

                NavigationLink {
                    SDKToolsView()
                } label: {
                    Label("SDK Tools", systemImage: "wrench.and.screwdriver")
                }

                Toggle("Enable Runline Bridge", isOn: $isSDKBridgeEnabled)

                TextField("Bridge URL", text: $sdkBridgeBaseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .bridgeURL)
                    .disabled(!isSDKBridgeEnabled)

                if isSDKBridgeEnabled {
                    HStack(spacing: 12) {
                        Text("Status")
                        Spacer()
                        Label(sdkBridgeConnectionTitle, systemImage: appState.sdkBridgeConnectionState.systemImage)
                            .foregroundStyle(appState.sdkBridgeConnectionState.tint)
                            .labelStyle(.titleAndIcon)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Profiles", value: "\(appState.sdkBridgeProfiles.count)")
                    LabeledContent("Pairing", value: appState.isSDKBridgePaired ? "Paired" : "Not Paired")

                    if let detail = sdkBridgeConnectionDetail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let loopbackHelp = SDKBridgePreferences.deviceLoopbackHelp(for: SDKBridgePreferences.baseURL(from: sdkBridgeBaseURL)) {
                        Text(loopbackHelp)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task {
                            await checkSDKBridgeHealth()
                        }
                    } label: {
                        if appState.sdkBridgeConnectionState == .checking {
                            ProgressView()
                        } else {
                            Text(appState.sdkBridgeConnectionState.isConnected ? "Recheck Connection" : "Check Connection")
                        }
                    }
                    .disabled(appState.sdkBridgeConnectionState == .checking)

                    if appState.isSDKBridgePaired {
                        Button("Forget Pairing", role: .destructive) {
                            appState.forgetSDKBridgePairing()
                        }
                    } else {
                        Button {
                            Task {
                                await startBridgePairing()
                            }
                        } label: {
                            if appState.sdkBridgePairingState == .starting {
                                ProgressView()
                            } else {
                                Label("Start Pairing", systemImage: "link.badge.plus")
                            }
                        }
                        .disabled(appState.sdkBridgePairingState == .starting || appState.sdkBridgePairingState == .completing)

                        if case .waiting = appState.sdkBridgePairingState {
                            TextField("Pairing Code", text: $pairingCode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .focused($focusedField, equals: .pairingCode)

                            Button {
                                Task {
                                    await completeBridgePairing()
                                }
                            } label: {
                                if appState.sdkBridgePairingState == .completing {
                                    ProgressView()
                                } else {
                                    Text("Complete Pairing")
                                }
                            }
                            .disabled(pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.sdkBridgePairingState == .completing)
                        }

                        if let pairingDetail {
                            Text(pairingDetail)
                                .font(.footnote)
                                .foregroundStyle(pairingDetailIsError ? .red : .secondary)
                        }
                    }
                }
            } header: {
                Text("Cursor SDK")
            } footer: {
                Text("Cloud Agent stays direct from iOS. Cursor SDK is available only after Runline Bridge connects.")
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
            appState.syncSDKBridgeConfiguration()
            ensureDefaultWorkflowSelectionIsAvailable()
        }
        .onChange(of: sdkBridgeBaseURL) { _, _ in
            appState.syncSDKBridgeConfiguration(resetConnection: true)
            ensureDefaultWorkflowSelectionIsAvailable()
        }
        .onChange(of: isSDKBridgeEnabled) { _, _ in
            appState.syncSDKBridgeConfiguration(resetConnection: true)
            ensureDefaultWorkflowSelectionIsAvailable()
        }
        .onChange(of: appState.sdkBridgePairingState) { _, state in
            if case .paired = state {
                pairingCode = ""
                focusedField = nil
            }
        }
        .onChange(of: appState.sdkBridgeConnectionState) { _, _ in
            ensureDefaultWorkflowSelectionIsAvailable()
        }
        .sheet(item: $cursorSDKOnboardingSheet) { _ in
            CursorSDKOnboardingView(
                onUseCloud: {
                    defaultRunModeRawValue = AgentRunMode.cloudAgent.rawValue
                    didChooseDefaultRunMode = true
                    appState.applyDefaultRunMode(.cloudAgent)
                },
                onUseSDK: {
                    defaultRunModeRawValue = AgentRunMode.sdkBridge.rawValue
                    didChooseDefaultRunMode = true
                    appState.applyDefaultRunMode(.sdkBridge)
                },
                onOpenSettings: {
                    isSDKBridgeEnabled = true
                    appState.syncSDKBridgeConfiguration(resetConnection: true)
                }
            )
        }
    }

    private var defaultRunModeBinding: Binding<String> {
        Binding {
            defaultRunModeRawValue
        } set: { rawValue in
            let mode = RunlineWorkflowPreferences.runMode(from: rawValue)
            if mode == .sdkBridge, !appState.isSDKBridgeReadyForLaunch {
                cursorSDKOnboardingSheet = .setup
                defaultRunModeRawValue = AgentRunMode.cloudAgent.rawValue
                didChooseDefaultRunMode = true
                appState.applyDefaultRunMode(.cloudAgent)
                return
            }
            defaultRunModeRawValue = rawValue
            didChooseDefaultRunMode = true
            appState.applyDefaultRunMode(mode)
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

    private var sdkBridgeConnectionTitle: String {
        switch appState.sdkBridgeConnectionState {
        case .disabled:
            "Disabled"
        case .unchecked:
            "Not Checked"
        case .checking:
            "Checking"
        case .connected:
            "Connected"
        case .failed:
            "Unavailable"
        }
    }

    private var sdkBridgeConnectionDetail: String? {
        switch appState.sdkBridgeConnectionState {
        case .connected(let message), .failed(let message):
            message
        case .unchecked:
            "Check the bridge before selecting Cursor SDK. The bridge must be reachable from this device."
        case .disabled, .checking:
            nil
        }
    }

    private var pairingDetail: String? {
        switch appState.sdkBridgePairingState {
        case .idle:
            "Start pairing, then enter the six-digit code printed in the Runline Bridge terminal."
        case .starting:
            "Starting a pairing session..."
        case .waiting(_, let expiresAt, let message):
            [message, expiresAt.map { "Expires at \($0)." }]
                .compactMap { $0 }
                .joined(separator: " ")
        case .completing:
            "Completing pairing..."
        case .paired(let name):
            "Paired with \(name)."
        case .failed(let message):
            message
        }
    }

    private var pairingDetailIsError: Bool {
        if case .failed = appState.sdkBridgePairingState {
            return true
        }
        return false
    }

    private func ensureDefaultWorkflowSelectionIsAvailable() {
        guard RunlineWorkflowPreferences.runMode(from: defaultRunModeRawValue) == .sdkBridge,
              !appState.isSDKBridgeReadyForLaunch else {
            return
        }
        defaultRunModeRawValue = AgentRunMode.cloudAgent.rawValue
        appState.applyDefaultRunMode(.cloudAgent)
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
        await appState.checkSDKBridgeConnection()
    }

    private func startBridgePairing() async {
        focusedField = nil
        pairingCode = ""
        await appState.startSDKBridgePairing()
    }

    private func completeBridgePairing() async {
        focusedField = nil
        await appState.completeSDKBridgePairing(code: pairingCode)
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

private extension SDKBridgeConnectionState {
    var systemImage: String {
        switch self {
        case .disabled, .unchecked:
            "circle"
        case .checking:
            "clock"
        case .connected:
            "checkmark.circle"
        case .failed:
            "exclamationmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .connected:
            .green
        case .failed:
            .red
        case .checking, .disabled, .unchecked:
            .secondary
        }
    }
}
