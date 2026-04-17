import Foundation
import Sparkle

final class SparkleUpdaterController: NSObject, ObservableObject {
    @Published var canCheckForUpdates: Bool = false

    private let controller: SPUStandardUpdaterController

    override init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()

        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
