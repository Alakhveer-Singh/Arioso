import AppKit
import Combine
#if canImport(Sparkle)
import Sparkle
#endif

/// Automatic updates for the direct-download build, through Sparkle.
///
/// build_app.sh only compiles Sparkle in (and embeds it) for the direct-download
/// build. The Mac App Store build has no updater, because the App Store delivers
/// updates itself, so there `isAvailable` is false and every update control hides.
///
/// A daily background check; when there's a newer version Sparkle opens its own window
/// offering to install it. Settings › About also has a Check Now button.
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    /// Posted when an update window closes, so the app can go back to menu-bar-only.
    static let sessionDidEndNotification = Notification.Name("AriosoUpdaterSessionDidEnd")

#if canImport(Sparkle)
    static let isAvailable = true

    private var controller: SPUStandardUpdaterController?
    private var updater: SPUUpdater? { controller?.updater }

    /// Starts the daily background check. Call once at launch.
    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    /// "Check for Updates…": always ends in a window, and brings a waiting update into focus.
    func checkForUpdates() {
        guard let controller else { return }
        bringForward()
        controller.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool { updater?.canCheckForUpdates ?? false }
    var lastChecked: Date? { updater?.lastUpdateCheckDate }

    var automaticallyChecks: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { objectWillChange.send(); updater?.automaticallyChecksForUpdates = newValue }
    }

    /// Only offered when Sparkle says this install can replace itself (e.g. the app's folder is writable).
    var allowsAutomaticInstall: Bool { updater?.allowsAutomaticUpdates ?? false }

    var automaticallyInstalls: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set { objectWillChange.send(); updater?.automaticallyDownloadsUpdates = newValue }
    }

    /// Without a Dock icon a window can open behind everything; show one while an update window is up.
    fileprivate func bringForward() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
#else
    static let isAvailable = false
    func start() {}
    func checkForUpdates() {}
    var canCheckForUpdates: Bool { false }
    var lastChecked: Date? { nil }
    var automaticallyChecks: Bool { get { false } set {} }
    var allowsAutomaticInstall: Bool { false }
    var automaticallyInstalls: Bool { get { false } set {} }
#endif
}

#if canImport(Sparkle)
extension Updater: SPUStandardUserDriverDelegate {
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        bringForward()
    }

    func standardUserDriverWillFinishUpdateSession() {
        objectWillChange.send()
        NotificationCenter.default.post(name: Updater.sessionDidEndNotification, object: nil)
    }
}
#endif
