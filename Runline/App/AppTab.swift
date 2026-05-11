import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case chats
    case sdk
    case repositories
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chats:
            "Chats"
        case .sdk:
            "SDK"
        case .repositories:
            "Repositories"
        case .settings:
            "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .chats:
            "message"
        case .sdk:
            "terminal"
        case .repositories:
            "folder"
        case .settings:
            "gearshape"
        }
    }
}
