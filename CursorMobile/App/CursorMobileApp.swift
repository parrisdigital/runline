import SwiftUI
import UIKit

final class CursorMobileAppDelegate: NSObject, UIApplicationDelegate {
    weak var appState: AppState?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor [weak self] in
            self?.appState?.updateDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.appState?.updateDeviceTokenRegistrationFailure(error)
        }
    }
}

@main
struct CursorMobileApp: App {
    @UIApplicationDelegateAdaptor(CursorMobileAppDelegate.self) private var appDelegate
    @AppStorage("appearance.mode") private var appearanceMode = AppAppearanceMode.system.rawValue
    @State private var appState = Self.makeAppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(AppAppearanceMode(rawValue: appearanceMode)?.colorScheme)
                .onAppear {
                    appDelegate.appState = appState
                }
        }
    }

    private static func makeAppState() -> AppState {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--runline-mock-provider") {
            return AppState(
                apiKeyStore: InMemoryAPIKeyStore(apiKey: "runline-debug-key"),
                providerFactory: { _ in MockAgentProvider() }
            )
        }
        #endif

        return AppState()
    }
}
