import SwiftUI

struct MainWindowScene: Scene {
    @ObservedObject var updater: SparkleUpdaterController

    var body: some Scene {
        WindowGroup("VibeBuddy", id: MainWindowScene.windowID) {
            AppShellView()
                .environmentObject(updater)
                .frame(minWidth: 840, minHeight: 520)
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
