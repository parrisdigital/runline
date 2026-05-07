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
            "Connect Runline"
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
            "Enable Cursor SDK in Settings, enter the bridge URL, start pairing, then type the code printed in your Mac terminal."
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
    var onUseCloud: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    @State private var selectedStep: RunlineBridgeOnboardingStep = .overview
    @State private var copiedStepID: RunlineBridgeOnboardingStep.ID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selectedStep) {
                    ForEach(RunlineBridgeOnboardingStep.allCases) { step in
                        CursorSDKOnboardingPage(
                            step: step,
                            copiedStepID: $copiedStepID
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
    }

    private var primaryButtonTitle: String {
        selectedStep == .connect ? "Open Bridge Settings" : "Continue"
    }

    private func handlePrimaryAction() {
        guard selectedStep == .connect else {
            advance()
            return
        }
        onOpenSettings?()
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
}

private struct CursorSDKOnboardingPage: View {
    var step: RunlineBridgeOnboardingStep
    @Binding var copiedStepID: RunlineBridgeOnboardingStep.ID?

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
