import Foundation

enum RunlineWorkflowPreferences {
    static let didChooseDefaultRunModeKey = "workflow.didChooseDefaultRunMode"
    static let defaultRunModeKey = "workflow.defaultRunMode"
    static let defaultRunMode = AgentRunMode.cloudAgent

    static func runMode(from rawValue: String?) -> AgentRunMode {
        guard let rawValue,
              let mode = AgentRunMode(rawValue: rawValue) else {
            return defaultRunMode
        }
        return mode
    }
}
