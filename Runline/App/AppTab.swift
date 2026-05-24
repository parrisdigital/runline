import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case cursorChat
    case cursorCloud
    case repositories
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursorChat:
            "Cursor Chat"
        case .cursorCloud:
            "Cursor Cloud"
        case .repositories:
            "Repositories"
        case .settings:
            "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .cursorChat:
            "message"
        case .cursorCloud:
            "cloud"
        case .repositories:
            "folder"
        case .settings:
            "gearshape"
        }
    }

    init(runtimeMode: AgentRuntimeMode) {
        switch runtimeMode {
        case .cloud:
            self = .cursorCloud
        case .sdkBridge:
            self = .cursorChat
        }
    }

    var runtimeMode: AgentRuntimeMode? {
        switch self {
        case .cursorChat:
            .sdkBridge
        case .cursorCloud:
            .cloud
        case .repositories, .settings:
            nil
        }
    }
}
