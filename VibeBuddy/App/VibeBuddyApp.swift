import SwiftUI

@main
struct VibeBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var updater = SparkleUpdaterController()

    var body: some Scene {
        MainWindowScene(updater: updater)
        MenuBarScene(updater: updater)
    }
}
