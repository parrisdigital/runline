import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isConnected {
                AppShellView()
            } else {
                WelcomeView()
            }
        }
        .task {
            await appState.restoreConnectionIfAvailable()
        }
        .onOpenURL { url in
            appState.handleDeepLink(url)
        }
        .alert("Runline", isPresented: isShowingError) {
            Button("OK") {
                appState.errorMessage = nil
            }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if appState.isConnected, let message = appState.statusMessage {
                StatusBanner(message: message) {
                    appState.dismissStatusMessage()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: appState.statusMessage)
    }

    private var isShowingError: Binding<Bool> {
        Binding {
            appState.errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                appState.errorMessage = nil
            }
        }
    }
}

private struct StatusBanner: View {
    var message: String
    var dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)

            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss status")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 8, y: 4)
    }
}

struct AppShellView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: $appState.selectedTab) {
            ChatsView()
                .tabItem { Label(AppTab.chats.title, systemImage: AppTab.chats.symbolName) }
                .tag(AppTab.chats)
                .accessibilityIdentifier("tab.chats")

            RepositoriesView()
                .tabItem { Label(AppTab.repositories.title, systemImage: AppTab.repositories.symbolName) }
                .tag(AppTab.repositories)
                .accessibilityIdentifier("tab.repositories")

            SettingsView()
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.symbolName) }
                .tag(AppTab.settings)
                .accessibilityIdentifier("tab.settings")
        }
    }
}
