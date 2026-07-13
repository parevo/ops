import Foundation
import Sparkle

/// Thin wrapper around Sparkle's standard updater for menu + Settings.
@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    nonisolated static let feedURLString = "https://parevo.github.io/ops/appcast.xml"

    private lazy var controller: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }()

    private override init() {
        super.init()
        _ = controller
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        Self.feedURLString
    }
}
