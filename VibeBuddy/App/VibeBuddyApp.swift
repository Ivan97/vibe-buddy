import SwiftUI

@main
struct VibeBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var updater = SparkleUpdaterController()
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var navigator = Navigator()

    var body: some Scene {
        MainWindowScene(
            updater: updater,
            sessionStore: sessionStore,
            navigator: navigator
        )
        MenuBarScene(
            updater: updater,
            sessionStore: sessionStore,
            navigator: navigator
        )
    }
}
