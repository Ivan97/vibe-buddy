import SwiftUI

struct MenuBarScene: Scene {
    @ObservedObject var updater: SparkleUpdaterController
    @ObservedObject var sessionStore: SessionStore

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(updater: updater, sessionStore: sessionStore)
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var updater: SparkleUpdaterController
    @ObservedObject var sessionStore: SessionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open VibeBuddy") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: MainWindowScene.windowID)
        }
        .keyboardShortcut("o")

        Divider()

        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)

        Divider()

        Button("Quit VibeBuddy") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
