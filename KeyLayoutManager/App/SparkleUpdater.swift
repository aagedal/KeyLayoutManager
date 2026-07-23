import Foundation
import Sparkle
import SwiftUI

/// Selects the website mirror for one retry when the primary appcast cannot
/// be downloaded or parsed. Failures after the appcast loads (for example,
/// signature validation or installation errors) must not switch feeds.
private final class SparkleFeedFallbackDelegate: NSObject, SPUUpdaterDelegate {
    private let backupFeedURL: String
    private var isUsingBackupFeed = false
    private var didLoadAppcast = false

    init(backupFeedURL: String) {
        self.backupFeedURL = backupFeedURL
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        didLoadAppcast = false
        return isUsingBackupFeed ? backupFeedURL : nil
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        didLoadAppcast = true
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        let shouldRetry = !isUsingBackupFeed
            && !didLoadAppcast
            && Self.isFeedLoadFailure(error)

        if isUsingBackupFeed {
            isUsingBackupFeed = false
        }
        didLoadAppcast = false

        guard shouldRetry else { return }
        isUsingBackupFeed = true

        switch updateCheck {
        case .updates:
            updater.checkForUpdates()
        case .updatesInBackground:
            updater.checkForUpdatesInBackground()
        case .updateInformation:
            updater.checkForUpdateInformation()
        @unknown default:
            updater.checkForUpdatesInBackground()
        }
    }

    private static func isFeedLoadFailure(_ error: Error?) -> Bool {
        guard let error = error as NSError?,
              error.domain == SUSparkleErrorDomain
        else { return false }

        return error.code == SUError.downloadError.rawValue
            || error.code == SUError.appcastParseError.rawValue
            || error.code == SUError.appcastError.rawValue
    }
}

@MainActor
final class SparkleUpdater: ObservableObject {
    static let shared = SparkleUpdater()

    let controller: SPUStandardUpdaterController
    private let feedFallbackDelegate: SparkleFeedFallbackDelegate

    private init() {
        let feedFallbackDelegate = SparkleFeedFallbackDelegate(
            backupFeedURL: "https://aagedal.me/apps/appcast/keylayoutmanager.xml"
        )
        self.feedFallbackDelegate = feedFallbackDelegate
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: feedFallbackDelegate,
            userDriverDelegate: nil
        )
    }
}
