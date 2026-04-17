import SwiftUI

@main
struct VibeBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var updater = SparkleUpdaterController()
    @StateObject private var sessionStore = SessionStore()

    var body: some Scene {
        MainWindowScene(updater: updater, sessionStore: sessionStore)
        MenuBarScene(updater: updater, sessionStore: sessionStore)
    }
}
