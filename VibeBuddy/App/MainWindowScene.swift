import SwiftUI

struct MainWindowScene: Scene {
    @ObservedObject var updater: SparkleUpdaterController
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var agentStore: AgentStore
    @ObservedObject var skillStore: SkillStore
    @ObservedObject var hooksStore: HooksStore
    @ObservedObject var pluginsStore: PluginsStore
    @ObservedObject var navigator: Navigator

    var body: some Scene {
        WindowGroup("VibeBuddy", id: MainWindowScene.windowID) {
            AppShellView()
                .environmentObject(updater)
                .environmentObject(sessionStore)
                .environmentObject(agentStore)
                .environmentObject(skillStore)
                .environmentObject(hooksStore)
                .environmentObject(pluginsStore)
                .environmentObject(navigator)
                .frame(minWidth: 840, minHeight: 520)
                .task {
                    if sessionStore.summaries.isEmpty {
                        await sessionStore.reload()
                    }
                    sessionStore.startWatching()
                }
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }
    }

    static let windowID = "main"
}
