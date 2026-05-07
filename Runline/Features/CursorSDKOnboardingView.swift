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
            detail: "Your Mac runs the Cursor SDK while iPhone stays the native remote."
        ),
        RunlineBridgeBenefit(
            symbolName: "message.badge.waveform",
            title: "Session chat",
            detail: "Plan, continue, and execute against the same SDK session."
        ),
        RunlineBridgeBenefit(
            symbolName: "point.3.connected.trianglepath.dotted",
            title: "MCP profiles",
            detail: "Expose bridge-side tools and subagents without storing them on device."
        ),
        RunlineBridgeBenefit(
            symbolName: "key",
            title: "Per-request keys",
            detail: "Runline sends your Cursor key only as a bearer token for each request."
        ),
    ]
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
            "Prepare the bridge"
        case .start:
            "Start the bridge"
        case .connect:
            "Pair and verify"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            "Cloud Agent remains the default. Cursor SDK is an optional mode for local SDK sessions, MCP profiles, files, images, planning, and execution."
        case .bridge:
            "Install Runline Bridge from npm. It keeps Cursor SDK execution on your Mac."
        case .start:
            "Start the bridge on your Mac. For iPhone testing, use your Mac LAN address instead of localhost."
        case .connect:
            "Enter the bridge URL, pair with the code printed in your Mac terminal, then verify the connection before making Cursor SDK your default."
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
        switch self {
        case .overview, .connect:
            nil
        case .bridge:
            "npm install -g runline-bridge"
        case .start:
            "CURSOR_API_KEY=your-cursor-key runline-bridge up"
        }
    }

    var footnote: String? {
        switch self {
        case .overview:
            nil
        case .bridge:
            "Only install this if you want Cursor SDK mode. Cloud Agent mode works without the bridge."
        case .start:
            "Simulator can use http://localhost:8787. A physical iPhone needs a reachable Mac LAN URL such as http://192.168.1.10:8787."
        case .connect:
            "Cloud Agent does not require this setup and remains available even when Cursor SDK is unavailable."
        }
    }
}

struct CursorSDKOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @AppStorage(SDKBridgePreferences.isEnabledKey) private var isSDKBridgeEnabled = SDKBridgePreferences.defaultIsEnabled
    @AppStorage(SDKBridgePreferences.baseURLKey) private var sdkBridgeBaseURL = SDKBridgePreferences.defaultBaseURLString
    var onUseCloud: (() -> Void)?
    var onUseSDK: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    @State private var selectedStep: RunlineBridgeOnboardingStep = .overview
    @State private var copiedStepID: RunlineBridgeOnboardingStep.ID?
    @State private var pairingCode = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selectedStep) {
                    ForEach(RunlineBridgeOnboardingStep.allCases) { step in
                        CursorSDKOnboardingPage(
                            step: step,
                            copiedStepID: $copiedStepID,
                            isSDKBridgeEnabled: $isSDKBridgeEnabled,
                            sdkBridgeBaseURL: $sdkBridgeBaseURL,
                            pairingCode: $pairingCode,
                            openSettings: openSettings
                        )
                        .tag(step)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                VStack(spacing: 10) {
                    Button(primaryButtonTitle) {
                        handlePrimaryAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(isPrimaryButtonDisabled)

                    Button("Use Cloud Agent for Now") {
                        onUseCloud?()
                        dismiss()
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal)
                .padding(.vertical, 14)
                .background(.bar)
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
    @Binding var isSDKBridgeEnabled: Bool
    @Binding var sdkBridgeBaseURL: String
    @Binding var pairingCode: String
    var openSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: step.symbolName)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 88, height: 88)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(spacing: 8) {
                    Text(step.eyebrow.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)

                    Text(step.title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text(step.subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if step == .overview {
                    CursorSDKBenefitsList()
                }

                if step == .connect {
                    CursorSDKBridgeSetupPanel(
                        isSDKBridgeEnabled: $isSDKBridgeEnabled,
                        sdkBridgeBaseURL: $sdkBridgeBaseURL,
                        pairingCode: $pairingCode,
                        openSettings: openSettings
                    )
                }

                if let command = step.command {
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
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 52)
            .padding(.bottom, 96)
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
            Toggle("Enable Runline Bridge", isOn: $isSDKBridgeEnabled)
                .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
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
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 12)

            Divider()

            statusRows

            Divider()

            setupActions
                .padding(.vertical, 12)
        }
        .padding(.horizontal, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            if !isSDKBridgeEnabled {
                isSDKBridgeEnabled = true
            }
            appState.syncSDKBridgeConfiguration(resetConnection: false)
        }
    }

    private var statusRows: some View {
        VStack(spacing: 10) {
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
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Cursor SDK is ready.", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var setupActions: some View {
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

            if let pairingDetail {
                Text(pairingDetail)
                    .font(.footnote)
                    .foregroundStyle(pairingDetailIsError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Button("Open Full Settings") {
            openSettings()
        }
        .buttonStyle(.borderless)
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
        VStack(alignment: .leading, spacing: 14) {
            ForEach(RunlineBridgeBenefit.all) { benefit in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: benefit.symbolName)
                        .font(.headline)
                        .foregroundStyle(.tint)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(benefit.title)
                            .font(.headline)

                        Text(benefit.detail)
                            .font(.subheadline)
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
