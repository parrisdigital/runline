import SwiftUI
import UIKit

enum CursorSDKOnboardingSheet: String, Identifiable {
    case setup

    var id: String { rawValue }
}

struct RunlineBridgeBenefit: Identifiable, Equatable {
    var id: String { title }
    var symbolName: String
    var title: String
    var detail: String

    static let all: [RunlineBridgeBenefit] = [
        RunlineBridgeBenefit(
            symbolName: "macbook.and.iphone",
            title: "Mac runtime",
            detail: "Your Mac runs Cursor SDK while iPhone stays the native remote."
        ),
        RunlineBridgeBenefit(
            symbolName: "message.badge.waveform",
            title: "Session chat",
            detail: "Plan, continue, and execute against the same SDK session."
        ),
        RunlineBridgeBenefit(
            symbolName: "point.3.connected.trianglepath.dotted",
            title: "MCP profiles",
            detail: "Expose bridge-side tools without storing private config on device."
        ),
        RunlineBridgeBenefit(
            symbolName: "sparkles",
            title: "Skills and subagents",
            detail: "Publish bridge-side skills, hooks, and subagent profiles."
        ),
        RunlineBridgeBenefit(
            symbolName: "key",
            title: "Per-request keys",
            detail: "Runline sends your Cursor key as a bearer token for each request."
        ),
    ]
}

enum RunlineBridgeStartMode: String, CaseIterable, Identifiable, Equatable {
    case standard
    case keepAwake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            "Standard"
        case .keepAwake:
            "Keep Awake"
        }
    }

    var detail: String {
        switch self {
        case .standard:
            "Runs until you stop the terminal process. Your Mac follows normal sleep settings."
        case .keepAwake:
            "Uses macOS caffeinate while the bridge is running. Stops when the bridge exits."
        }
    }

    var command: String {
        switch self {
        case .standard:
            "runline-bridge up"
        case .keepAwake:
            "runline-bridge up --keep-awake"
        }
    }

    static func resolve(keepAwake: Bool) -> RunlineBridgeStartMode {
        keepAwake ? .keepAwake : .standard
    }
}

enum RunlineBridgeOnboardingStep: String, CaseIterable, Identifiable, Equatable {
    case overview
    case bridge
    case start
    case connect

    var id: String { rawValue }

    var eyebrow: String {
        switch self {
        case .overview:
            "Cursor SDK"
        case .bridge:
            "Step 1"
        case .start:
            "Step 2"
        case .connect:
            "Step 3"
        }
    }

    var title: String {
        switch self {
        case .overview:
            "Use Cursor SDK from your iPhone"
        case .bridge:
            "Install the bridge"
        case .start:
            "Start the bridge"
        case .connect:
            "Pair and verify"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            "Cloud Agent remains the default. Cursor SDK is optional for local SDK sessions, MCP profiles, files, images, planning, and execution."
        case .bridge:
            "Install Runline Bridge from npm only when you want Cursor SDK mode."
        case .start:
            "Run the bridge on your Mac, then connect from iPhone using the Mac LAN address."
        case .connect:
            "Enter the bridge URL, pair with the code printed in your Mac terminal, then verify the connection."
        }
    }

    var symbolName: String {
        switch self {
        case .overview:
            "terminal"
        case .bridge:
            "shippingbox"
        case .start:
            "play.circle"
        case .connect:
            "qrcode.viewfinder"
        }
    }

    var command: String? {
        command(keepAwake: false)
    }

    func command(keepAwake: Bool) -> String? {
        switch self {
        case .overview, .connect:
            nil
        case .bridge:
            "npm install -g runline-bridge"
        case .start:
            RunlineBridgeStartMode.resolve(keepAwake: keepAwake).command
        }
    }

    var footnote: String? {
        switch self {
        case .overview:
            nil
        case .bridge:
            "Cloud Agent mode works without the bridge."
        case .start:
            "Simulator can use localhost. A physical iPhone needs a reachable Mac LAN URL such as http://192.168.1.10:8787."
        case .connect:
            "Cloud Agent remains available even when Cursor SDK is unavailable."
        }
    }
}

struct CursorSDKOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @AppStorage(SDKBridgePreferences.isEnabledKey) private var isSDKBridgeEnabled = SDKBridgePreferences.defaultIsEnabled
    @AppStorage(SDKBridgePreferences.baseURLKey) private var sdkBridgeBaseURL = SDKBridgePreferences.defaultBaseURLString
    @AppStorage(SDKBridgePreferences.keepAwakeKey) private var keepMacAwake = SDKBridgePreferences.defaultKeepAwake
    var onUseCloud: (() -> Void)?
    var onUseSDK: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    @State private var selectedStep: RunlineBridgeOnboardingStep = .overview
    @State private var copiedStepID: RunlineBridgeOnboardingStep.ID?
    @State private var pairingCode = ""

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedStep) {
                ForEach(RunlineBridgeOnboardingStep.allCases) { step in
                    CursorSDKOnboardingPage(
                        step: step,
                        copiedStepID: $copiedStepID,
                        keepMacAwake: $keepMacAwake,
                        isSDKBridgeEnabled: $isSDKBridgeEnabled,
                        sdkBridgeBaseURL: $sdkBridgeBaseURL,
                        pairingCode: $pairingCode,
                        openSettings: openSettings
                    )
                    .tag(step)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
            .navigationTitle("Cursor SDK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: isSDKBridgeEnabled) { _, _ in
            appState.syncSDKBridgeConfiguration(resetConnection: true)
        }
        .onChange(of: sdkBridgeBaseURL) { _, _ in
            appState.syncSDKBridgeConfiguration(resetConnection: true)
        }
        .onChange(of: appState.sdkBridgePairingState) { _, state in
            if case .paired = state {
                pairingCode = ""
            }
        }
    }

    private var bottomActionBar: some View {
        VStack(spacing: 12) {
            RunlineBridgePageIndicator(selectedStep: selectedStep)

            Button {
                handlePrimaryAction()
            } label: {
                Text(primaryButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .frame(maxWidth: 540)
            .disabled(isPrimaryButtonDisabled)

            Button("Use Cloud Agent for Now") {
                onUseCloud?()
                dismiss()
            }
            .buttonStyle(.borderless)
            .font(.callout.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var primaryButtonTitle: String {
        selectedStep == .connect ? "Use Cursor SDK" : "Continue"
    }

    private var isPrimaryButtonDisabled: Bool {
        selectedStep == .connect && !appState.isSDKBridgeReadyForLaunch
    }

    private func handlePrimaryAction() {
        guard selectedStep == .connect else {
            advance()
            return
        }
        guard appState.isSDKBridgeReadyForLaunch else { return }
        onUseSDK?()
        dismiss()
    }

    private func advance() {
        guard let currentIndex = RunlineBridgeOnboardingStep.allCases.firstIndex(of: selectedStep) else {
            selectedStep = .connect
            return
        }
        let nextIndex = RunlineBridgeOnboardingStep.allCases.index(after: currentIndex)
        if RunlineBridgeOnboardingStep.allCases.indices.contains(nextIndex) {
            withAnimation(.snappy(duration: 0.2)) {
                selectedStep = RunlineBridgeOnboardingStep.allCases[nextIndex]
            }
        } else {
            selectedStep = .connect
        }
    }

    private func openSettings() {
        onOpenSettings?()
        dismiss()
    }
}

private struct CursorSDKOnboardingPage: View {
    var step: RunlineBridgeOnboardingStep
    @Binding var copiedStepID: RunlineBridgeOnboardingStep.ID?
    @Binding var keepMacAwake: Bool
    @Binding var isSDKBridgeEnabled: Bool
    @Binding var sdkBridgeBaseURL: String
    @Binding var pairingCode: String
    var openSettings: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            fixedContent
            scrollContent
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var fixedContent: some View {
        VStack {
            Spacer(minLength: 12)
            pageContent
            Spacer(minLength: 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var scrollContent: some View {
        ScrollView {
            pageContent
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 18)
        }
    }

    private var pageContent: some View {
        VStack(spacing: 14) {
            CursorSDKOnboardingHeader(step: step)

            switch step {
            case .overview:
                CursorSDKBenefitsList()
            case .bridge:
                EmptyView()
            case .start:
                RunlineBridgeStartModePanel(keepMacAwake: $keepMacAwake)
            case .connect:
                CursorSDKBridgeSetupPanel(
                    isSDKBridgeEnabled: $isSDKBridgeEnabled,
                    sdkBridgeBaseURL: $sdkBridgeBaseURL,
                    pairingCode: $pairingCode,
                    openSettings: openSettings
                )
            }

            if let command = step.command(keepAwake: keepMacAwake) {
                CommandCopyRow(
                    command: command,
                    isCopied: copiedStepID == step.id
                ) {
                    UIPasteboard.general.string = command
                    withAnimation(.snappy(duration: 0.2)) {
                        copiedStepID = step.id
                    }
                }
            }

            if let footnote = step.footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 540)
    }
}

private struct CursorSDKOnboardingHeader: View {
    var step: RunlineBridgeOnboardingStep

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: step.symbolName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 60, height: 60)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 6) {
                Text(step.eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)

                Text(step.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(step.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct RunlineBridgeStartModePanel: View {
    @Binding var keepMacAwake: Bool

    private var selectedMode: RunlineBridgeStartMode {
        RunlineBridgeStartMode.resolve(keepAwake: keepMacAwake)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Bridge Start Mode", selection: $keepMacAwake) {
                Text("Standard").tag(false)
                Text("Keep Awake").tag(true)
            }
            .pickerStyle(.segmented)

            Label(selectedMode.detail, systemImage: keepMacAwake ? "moon.zzz.slash" : "terminal")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Keep Awake is disabled by default and only affects Cursor SDK mode.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CursorSDKAPIKeyPanel: View {
    @Environment(AppState.self) private var appState
    @State private var apiKey = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Label("Cursor API Key", systemImage: "key")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if appState.isConnected {
                    Label("Keychain", systemImage: "checkmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Text("Required")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }

            if let account = appState.account {
                Text("Stored in Keychain as \(account.apiKeyName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SecureField("Cursor API key", text: $apiKey)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .accessibilityIdentifier("sdkOnboarding.cursorAPIKey")

                Button {
                    connectKey()
                } label: {
                    if appState.isLoading {
                        ProgressView()
                    } else {
                        Label("Connect Key", systemImage: "key.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedAPIKey.isEmpty || appState.isLoading)

                Text("Runline stores the key in Keychain and sends it to Runline Bridge only as a per-request bearer token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
    }

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connectKey() {
        let key = trimmedAPIKey
        guard !key.isEmpty else { return }
        isFocused = false
        apiKey = ""
        Task {
            await appState.connect(apiKey: key)
        }
    }
}

private struct CursorSDKBridgeSetupPanel: View {
    @Environment(AppState.self) private var appState
    @Binding var isSDKBridgeEnabled: Bool
    @Binding var sdkBridgeBaseURL: String
    @Binding var pairingCode: String
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CursorSDKAPIKeyPanel()

            Divider()

            Toggle("Enable Runline Bridge", isOn: $isSDKBridgeEnabled)
                .padding(.vertical, 10)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("Bridge URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("http://192.168.1.10:8787", text: $sdkBridgeBaseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(!isSDKBridgeEnabled)
                    .accessibilityIdentifier("sdkOnboarding.bridgeURL")

                if let loopbackHelp = SDKBridgePreferences.deviceLoopbackHelp(for: SDKBridgePreferences.baseURL(from: sdkBridgeBaseURL)) {
                    Text(loopbackHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 10)

            Divider()

            statusRows

            Divider()

            setupActions
                .padding(.vertical, 10)
        }
        .padding(.horizontal, 14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            if !isSDKBridgeEnabled {
                isSDKBridgeEnabled = true
            }
            appState.syncSDKBridgeConfiguration(resetConnection: false)
        }
    }

    private var statusRows: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("Status")
                Spacer()
                Label(bridgeConnectionTitle, systemImage: bridgeConnectionSystemImage)
                    .foregroundStyle(bridgeConnectionTint)
                    .labelStyle(.titleAndIcon)
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 12) {
                Text("Pairing")
                Spacer()
                Text(appState.isSDKBridgePaired ? "Paired" : "Not Paired")
                    .foregroundStyle(appState.isSDKBridgePaired ? .green : .secondary)
            }

            if let readiness = appState.sdkBridgeReadinessIssue {
                Text(readiness)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Cursor SDK is ready.", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var setupActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appState.isSDKBridgeReadyForLaunch {
                Button {
                    Task {
                        await appState.checkSDKBridgeConnection()
                    }
                } label: {
                    Label("Recheck Connection", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            } else if appState.isSDKBridgePaired {
                Button {
                    Task {
                        await appState.checkSDKBridgeConnection()
                    }
                } label: {
                    if appState.sdkBridgeConnectionState == .checking {
                        ProgressView()
                    } else {
                        Label("Check Connection", systemImage: "network")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.sdkBridgeConnectionState == .checking)
            } else {
                Button {
                    Task {
                        await startPairing()
                    }
                } label: {
                    if appState.sdkBridgePairingState == .starting {
                        ProgressView()
                    } else {
                        Label("Start Pairing", systemImage: "link.badge.plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isSDKBridgeEnabled || appState.sdkBridgePairingState == .starting || appState.sdkBridgePairingState == .completing)

                if case .waiting = appState.sdkBridgePairingState {
                    TextField("Pairing Code", text: $pairingCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("sdkOnboarding.pairingCode")

                    Button {
                        Task {
                            await completePairing()
                        }
                    } label: {
                        if appState.sdkBridgePairingState == .completing {
                            ProgressView()
                        } else {
                            Label("Complete Pairing", systemImage: "checkmark.circle")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.sdkBridgePairingState == .completing)
                }
            }

            if let pairingDetail {
                Text(pairingDetail)
                    .font(.caption)
                    .foregroundStyle(pairingDetailIsError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Open Full Settings") {
                openSettings()
            }
            .buttonStyle(.borderless)
        }
    }

    private var bridgeConnectionTitle: String {
        switch appState.sdkBridgeConnectionState {
        case .disabled:
            "Disabled"
        case .unchecked:
            "Needs Check"
        case .checking:
            "Checking"
        case .connected:
            "Connected"
        case .failed:
            "Unavailable"
        }
    }

    private var bridgeConnectionSystemImage: String {
        switch appState.sdkBridgeConnectionState {
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

    private var bridgeConnectionTint: Color {
        switch appState.sdkBridgeConnectionState {
        case .connected:
            .green
        case .failed:
            .red
        case .checking, .disabled, .unchecked:
            .secondary
        }
    }

    private var pairingDetail: String? {
        switch appState.sdkBridgePairingState {
        case .idle:
            "Start pairing, then enter the code printed in the Runline Bridge terminal."
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

    private func startPairing() async {
        if !isSDKBridgeEnabled {
            isSDKBridgeEnabled = true
        }
        pairingCode = ""
        await appState.startSDKBridgePairing()
    }

    private func completePairing() async {
        await appState.completeSDKBridgePairing(code: pairingCode)
    }
}

private struct CursorSDKBenefitsList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(RunlineBridgeBenefit.all) { benefit in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: benefit.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(benefit.title)
                            .font(.subheadline.weight(.semibold))

                        Text(benefit.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct RunlineBridgePageIndicator: View {
    var selectedStep: RunlineBridgeOnboardingStep

    var body: some View {
        HStack(spacing: 7) {
            ForEach(RunlineBridgeOnboardingStep.allCases) { step in
                Capsule(style: .continuous)
                    .fill(step == selectedStep ? Color.primary : Color.secondary.opacity(0.32))
                    .frame(width: step == selectedStep ? 26 : 7, height: 7)
            }
        }
        .animation(.snappy(duration: 0.2), value: selectedStep)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cursor SDK setup step")
        .accessibilityValue("\(currentIndex) of \(RunlineBridgeOnboardingStep.allCases.count)")
    }

    private var currentIndex: Int {
        (RunlineBridgeOnboardingStep.allCases.firstIndex(of: selectedStep) ?? 0) + 1
    }
}

private struct CommandCopyRow: View {
    var command: String
    var isCopied: Bool
    var copy: () -> Void

    var body: some View {
        Button(action: copy) {
            HStack(alignment: .center, spacing: 10) {
                Text(command)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.headline)
                    .foregroundStyle(.tint)
            }
            .padding(14)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCopied ? "Command copied" : "Copy command")
    }
}

#Preview {
    CursorSDKOnboardingView()
}
