import SwiftUI

enum AppLayoutMode: Equatable {
    case compactTabs
    case regularSplit

    static func resolve(horizontalSizeClass: UserInterfaceSizeClass?) -> AppLayoutMode {
        horizontalSizeClass == .regular ? .regularSplit : .compactTabs
    }
}
