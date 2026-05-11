import AVFoundation
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
            "Start Pairing"
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
            "Run this on your computer. A QR code will appear in your terminal - scan it next."
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
        case .overview:
            nil
        case .bridge:
            "npm install -g runline-bridge"
        case .start, .connect:
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
            "The bridge and Mac must stay reachable for Cursor SDK sessions. Keep Awake is optional and only prevents Mac sleep while the bridge runs."
        }
    }
}

enum RunlineBridgeScannedPayload {
    static func bridgeURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let scannedURL = URL(string: trimmed) else { return nil }

        if case .bridge(let bridgeURL) = RunlineDeepLink(url: scannedURL) {
            return bridgeURL
        }

        return SDKBridgePreferences.baseURL(from: trimmed)
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
    @State private var isShowingQRScanner = false
    @State private var isShowingPairingCodeEntry = false
    @State private var scanErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selectedStep) {
                    ForEach(RunlineBridgeOnboardingStep.allCases) { step in
                        CursorSDKOnboardingPage(
                            step: step,
                            copiedStepID: $copiedStepID,
                            keepMacAwake: $keepMacAwake,
                            isSDKBridgeEnabled: $isSDKBridgeEnabled,
                            sdkBridgeBaseURL: $sdkBridgeBaseURL,
                            openSettings: openSettings
                        )
                        .tag(step)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                bottomActionBar
            }
            .background(Color(uiColor: .systemGroupedBackground))
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
        .sheet(isPresented: $isShowingQRScanner) {
            RunlineBridgeQRScannerSheet(
                errorMessage: scanErrorMessage,
                onCancel: {
                    isShowingQRScanner = false
                },
                onScan: handleScannedBridgeCode
            )
        }
        .sheet(isPresented: $isShowingPairingCodeEntry) {
            PairingCodeEntrySheet(
                pairingCode: $pairingCode,
                pairingState: appState.sdkBridgePairingState,
                completePairing: {
                    await completePairing()
                    if appState.isSDKBridgePaired {
                        isShowingPairingCodeEntry = false
                    }
                }
            )
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
        VStack(spacing: 10) {
            RunlineBridgePageIndicator(selectedStep: selectedStep)

            if selectedStep == .connect {
                connectActionButtons
            } else {
                Button {
                    advance()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .frame(maxWidth: 540)
            }

            Button("Use Cloud Agent for Now") {
                onUseCloud?()
                dismiss()
            }
            .buttonStyle(.borderless)
            .font(.callout.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var connectActionButtons: some View {
        VStack(spacing: 10) {
            if appState.isSDKBridgeReadyForLaunch {
                Button {
                    onUseSDK?()
                    dismiss()
                } label: {
                    Text("Use Cursor SDK")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            } else {
                Button {
                    scanErrorMessage = nil
                    isShowingQRScanner = true
                } label: {
                    Label("Scan with QR Code", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)

                Button {
                    startPairingAndShowCodeEntry()
                } label: {
                    Label(pairWithCodeTitle, systemImage: "keyboard")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(!isSDKBridgeEnabled || appState.sdkBridgePairingState == .starting || appState.sdkBridgePairingState == .completing)
            }
        }
        .frame(maxWidth: 540)
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

    private var pairWithCodeTitle: String {
        switch appState.sdkBridgePairingState {
        case .starting:
            "Starting Pairing"
        case .waiting:
            "Enter Pairing Code"
        case .completing:
            "Completing Pairing"
        default:
            "Pair with Code"
        }
    }

    private func handleScannedBridgeCode(_ rawValue: String) {
        guard let bridgeURL = RunlineBridgeScannedPayload.bridgeURL(from: rawValue) else {
            scanErrorMessage = "Scan the Runline setup QR code printed by runline-bridge up."
            return
        }

        isSDKBridgeEnabled = true
        sdkBridgeBaseURL = bridgeURL.absoluteString
        scanErrorMessage = nil
        isShowingQRScanner = false
        appState.syncSDKBridgeConfiguration(resetConnection: true)
    }

    private func startPairingAndShowCodeEntry() {
        if case .waiting = appState.sdkBridgePairingState {
            isShowingPairingCodeEntry = true
            return
        }

        Task {
            await startPairing()
            if case .waiting = appState.sdkBridgePairingState {
                isShowingPairingCodeEntry = true
            }
        }
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

private struct CursorSDKOnboardingPage: View {
    var step: RunlineBridgeOnboardingStep
    @Binding var copiedStepID: RunlineBridgeOnboardingStep.ID?
    @Binding var keepMacAwake: Bool
    @Binding var isSDKBridgeEnabled: Bool
    @Binding var sdkBridgeBaseURL: String
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
            Spacer(minLength: 10)
            pageContent
            Spacer(minLength: 10)
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
        VStack(spacing: step == .overview ? 12 : 14) {
            CursorSDKOnboardingHeader(step: step)

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
                    openSettings: openSettings
                )
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
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CursorSDKAPIKeyPanel()

            Divider()

            bridgeURLSummary

            Divider()

            statusRows

            Divider()

            Button("Open Full Settings") {
                openSettings()
            }
            .buttonStyle(.borderless)
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

    private var bridgeURLSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enable Runline Bridge", isOn: $isSDKBridgeEnabled)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Bridge URL")
                    .font(.subheadline)
                Spacer()
                Text(displayBridgeURL)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("Scan the setup QR printed by the terminal to set the iPhone URL automatically. Use Settings for manual URLs or hosted bridges.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let loopbackHelp = SDKBridgePreferences.deviceLoopbackHelp(for: SDKBridgePreferences.baseURL(from: sdkBridgeBaseURL)) {
                Text(loopbackHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
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

            if let pairingDetail {
                Text(pairingDetail)
                    .font(.caption)
                    .foregroundStyle(pairingDetailIsError ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 10)
    }

    private var displayBridgeURL: String {
        let trimmed = sdkBridgeBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Scan QR" : trimmed
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
}

private struct CursorSDKBenefitsList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(RunlineBridgeBenefit.all) { benefit in
                HStack(alignment: .top, spacing: 10) {
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
        .padding(14)
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

private struct RunlineBridgeQRScannerSheet: View {
    var errorMessage: String?
    var onCancel: () -> Void
    var onScan: (String) -> Void
    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                scannerContent

                VStack(spacing: 6) {
                    Text("Scan the QR code printed by runline-bridge up.")
                        .font(.callout)
                        .multilineTextAlignment(.center)

                    Text("Runline will set the bridge URL, then you can pair with the terminal code.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.bottom)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Scan Bridge QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onCancel()
                    }
                }
            }
        }
        .onAppear {
            requestCameraAccessIfNeeded()
        }
    }

    @ViewBuilder
    private var scannerContent: some View {
        switch authorizationStatus {
        case .authorized:
            QRCodeScannerView(onScan: onScan)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding()
        case .notDetermined:
            ProgressView("Preparing Camera")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied, .restricted:
            ContentUnavailableView(
                "Camera Access Needed",
                systemImage: "camera.viewfinder",
                description: Text("Allow camera access in Settings or enter the bridge URL manually in Runline Settings.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        @unknown default:
            ContentUnavailableView(
                "Camera Unavailable",
                systemImage: "camera.viewfinder",
                description: Text("Enter the bridge URL manually in Runline Settings.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func requestCameraAccessIfNeeded() {
        guard authorizationStatus == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                authorizationStatus = granted ? .authorized : .denied
            }
        }
    }
}

private struct QRCodeScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        QRCodeScannerViewController(onScan: onScan)
    }

    func updateUIViewController(_ uiViewController: QRCodeScannerViewController, context: Context) {}
}

private final class QRCodeScannerViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onScan: (String) -> Void
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didScan = false

    init(onScan: @escaping (String) -> Void) {
        self.onScan = onScan
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        didScan = false
        if !session.isRunning {
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configureSession() {
        guard
            let videoDevice = AVCaptureDevice.default(for: .video),
            let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
            session.canAddInput(videoInput)
        else {
            showCameraUnavailable()
            return
        }

        session.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            showCameraUnavailable()
            return
        }

        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    private func showCameraUnavailable() {
        let label = UILabel()
        label.text = "Camera unavailable"
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            !didScan,
            let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let stringValue = metadataObject.stringValue
        else { return }

        didScan = true
        session.stopRunning()
        onScan(stringValue)
    }
}

private struct PairingCodeEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var pairingCode: String
    var pairingState: SDKBridgePairingState
    var completePairing: () async -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pairing Code", text: $pairingCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($isFocused)
                        .accessibilityIdentifier("sdkOnboarding.pairingCode")

                    if let detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(detailIsError ? .red : .secondary)
                    }
                } header: {
                    Text("Runline Bridge")
                } footer: {
                    Text("Enter the code printed in the terminal after you tap Pair with Code.")
                }
            }
            .navigationTitle("Pair with Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Pair") {
                        Task {
                            await completePairing()
                        }
                    }
                    .disabled(pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pairingState == .completing)
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }

    private var detail: String? {
        switch pairingState {
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
        case .idle, .starting:
            nil
        }
    }

    private var detailIsError: Bool {
        if case .failed = pairingState {
            return true
        }
        return false
    }
}

#Preview {
    CursorSDKOnboardingView()
}
