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
    @State private var appState = AppState()

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
}
