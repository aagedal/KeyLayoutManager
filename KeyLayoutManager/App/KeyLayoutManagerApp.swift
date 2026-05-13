import SwiftUI
import AppKit

@main
struct KeyLayoutManagerApp: App {
    init() {
        _ = SparkleUpdater.shared
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            TempStage.shared.wipe()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    SparkleUpdater.shared.controller.checkForUpdates(nil)
                }
            }
        }
    }
}
