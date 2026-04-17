import Foundation

/// App-wide navigation state. Lives at `@StateObject` scope so the menu bar
/// popover and the main window's shell can both drive it.
@MainActor
final class Navigator: ObservableObject {
    @Published var route: ModuleRoute? = .sessions
    @Published var pendingSessionID: SessionSummary.ID?

    func openSession(id: SessionSummary.ID) {
        route = .sessions
        pendingSessionID = id
    }
}
