import SwiftUI

@main
struct VibeBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var updater = SparkleUpdaterController()
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var sessionTitleStore = SessionTitleStore()
    @StateObject private var agentStore = AgentStore()
    @StateObject private var skillStore = SkillStore()
    @StateObject private var commandStore = CommandStore()
    @StateObject private var hooksStore = HooksStore()
    @StateObject private var pluginsStore = PluginsStore()
    @StateObject private var marketplacesStore = MarketplacesStore()
    @StateObject private var statuslineStore = StatuslineStore()
    @StateObject private var mcpStore = MCPStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var navigator = Navigator()

    var body: some Scene {
        MainWindowScene(
            updater: updater,
            sessionStore: sessionStore,
            sessionTitleStore: sessionTitleStore,
            agentStore: agentStore,
            skillStore: skillStore,
            commandStore: commandStore,
            hooksStore: hooksStore,
            pluginsStore: pluginsStore,
            marketplacesStore: marketplacesStore,
            statuslineStore: statuslineStore,
            mcpStore: mcpStore,
            settingsStore: settingsStore,
            navigator: navigator
        )
        MenuBarScene(
            updater: updater,
            sessionStore: sessionStore,
            sessionTitleStore: sessionTitleStore,
            navigator: navigator
        )
    }
}
