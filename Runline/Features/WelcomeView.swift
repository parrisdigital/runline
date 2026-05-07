import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @State private var apiKey = ""
    @FocusState private var isAPIKeyFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                RunlineLogoMarkView()
                    .frame(width: 56, height: 56)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .accessibilityHidden(true)

                Spacer(minLength: 24)

                VStack(spacing: 14) {
                    Form {
                        Section {
                            SecureField("Cursor API key", text: $apiKey)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($isAPIKeyFocused)
                                .submitLabel(.go)
                                .onSubmit(connect)
                                .accessibilityIdentifier("welcome.apiKey")

                            Button {
                                connect()
                            } label: {
                                HStack {
                                    Spacer(minLength: 0)
                                    if appState.isLoading {
                                        ProgressView()
                                    } else {
                                        Text("Connect")
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            .disabled(!canConnect || appState.isLoading)
                            .accessibilityIdentifier("welcome.connect")
                        } header: {
                            Text("Cursor")
                        }
                    }
                    .frame(height: 164)
                    .scrollDisabled(true)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "lock.fill")
                            .imageScale(.small)
                        Text("Keys are stored in Keychain and used directly with Cursor's Cloud Agents API.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 24)

                Text("Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color(.systemGroupedBackground))
        }
    }

    private var canConnect: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func connect() {
        guard canConnect, !appState.isLoading else { return }
        isAPIKeyFocused = false
        Task {
            await appState.connect(apiKey: apiKey)
        }
    }
}

private struct RunlineLogoMarkView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RunlineChevronShape()
                .stroke(
                    colorScheme == .dark ? Color(red: 0.35, green: 0.56, blue: 1.0) : Color(red: 0.07, green: 0.08, blue: 0.10),
                    style: StrokeStyle(lineWidth: 8.25, lineCap: .round, lineJoin: .round)
                )

            Circle()
                .fill(Color(red: 0.15, green: 0.42, blue: 1.0))
                .frame(width: 9, height: 9)
                .offset(x: 10, y: 10)
        }
        .frame(width: 56, height: 56)
    }
}

private struct RunlineChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.27))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.minY + rect.height * 0.50))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.73))
        return path
    }
}

#Preview {
    WelcomeView()
        .environment(AppState(provider: MockAgentProvider(), apiKeyStore: InMemoryAPIKeyStore()))
}
