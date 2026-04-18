import Foundation

/// App-wide navigation state. Lives at `@StateObject` scope so the menu bar
/// popover and the main window's shell can both drive it.
@MainActor
final class Navigator: ObservableObject {
    @Published var route: ModuleRoute? = .sessions
    @Published var pendingSessionID: SessionSummary.ID?
    @Published var pendingPluginID: String?
    @Published var pendingSkillID: String?
    @Published var pendingCommandID: String?
    @Published var pendingAgentID: String?
    @Published var pendingMCPServerName: String?

    func openSession(id: SessionSummary.ID) {
        route = .sessions
        pendingSessionID = id
    }

    func openPlugin(id: String) {
        route = .plugins
        pendingPluginID = id
    }

    func openSkill(id: String) {
        route = .skills
        pendingSkillID = id
    }

    func openCommand(id: String) {
        route = .prompts
        pendingCommandID = id
    }

    func openAgent(id: String) {
        route = .subagents
        pendingAgentID = id
    }

    func openMCPServer(name: String) {
        route = .mcp
        pendingMCPServerName = name
    }
}
