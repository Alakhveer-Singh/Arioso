import AppKit
import Combine
import SwiftUI

/// Arioso is one app: the desktop widgets, the bottom-of-screen player,
/// ⌥⌘L full-screen lyrics and the Settings window all live in this process.
/// It runs without a Dock icon (LSUIElement) and shows one only while a
/// window of its own is open.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = SettingsStore.shared
    private let model = LyricsSceneModel()
    private let history = Demo.isOn ? RecentlyPlayed(demo: Demo.history) : RecentlyPlayed()
    private let monitor = PlayerMonitor()
    private var widgets: WidgetsController?
    private var nowPlayingWidget: NowPlayingWidget?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var subscription: AnyCancellable?
    private var launchedAtLogin = false
    private var showcaseWallpaper: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Only readable while launching: was this an "Open at Login" start?
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == AEEventID(kAEOpenApplication),
           event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
               == OSType(keyAELaunchedAsLogInItem) {
            launchedAtLogin = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        monitor.onChange = { [weak self] info in
            guard let self else { return }
            self.model.update(nowPlaying: info)
            self.model.accessDenied = info == nil && !self.monitor.deniedPlayers.isEmpty
            if let info {
                self.history.trackStarted(title: info.title, artist: info.artist, duration: info.duration,
                                          url: info.trackURL, player: info.playerBundleID)
            }
        }
        monitor.spotifyOnly = store.settings.spotifyOnly
        Playback.monitor = monitor
        if Demo.isOn {
            // Screenshot mode: a made-up song instead of the real players.
            let start = Date()
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.model.update(nowPlaying: Demo.nowPlaying(startedAt: start))
            }.fire()
        } else {
            monitor.start()
        }
        model.startTicking()

        FullScreenLyrics.shared.model = model
        HotKeys.shared.onFullScreen = { FullScreenLyrics.shared.toggle() }
        HotKeys.shared.onReframe = { Reframer.toggle() }
        widgets = WidgetsController(model: model, store: store, history: history)
        Reframer.widgetFrames = { [weak self] in self?.widgets?.visibleFrames ?? [] }
        nowPlayingWidget = NowPlayingWidget(model: model, store: store)
        AudioLevels.shared.attach(model: model, store: store)
        subscription = store.$settings.sink { [weak self] in self?.apply($0) }

        // Direct-download build only (see Updater.swift): checks for a new version once a day.
        Updater.shared.start()
        NotificationCenter.default.addObserver(forName: Updater.sessionDidEndNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.backToBackgroundIfIdle() }

        NotificationCenter.default.addObserver(forName: AppSettings.openSettingsNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.showSettings() }

        if Demo.isShowcase || Demo.isLiveShowcase {
            showcaseWallpaper = Demo.showWallpaper()
            widgets?.raiseForShowcase()
            nowPlayingWidget?.raiseForShowcase()
            return
        }
        // Screenshots: `--demo --fullscreen` opens straight into full-screen lyrics.
        if CommandLine.arguments.contains("--fullscreen") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { FullScreenLyrics.shared.show() }
            return
        }

        // `--settings` opens Settings directly (skips the tour), for screenshots.
        if CommandLine.arguments.contains("--settings") {
            showSettings()
            return
        }

        // Opened at login: stay quietly in the background.
        guard !launchedAtLogin else { return }
        if Onboarding.isDone { showSettings() } else { showOnboarding() }
    }

    /// Double-clicking the app again, or clicking it in the Dock, opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if onboardingWindow == nil { showSettings() }
        return true
    }

    /// arioso:// links (the website's "Open Arioso" button) open Settings, like a reopen.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "arioso" }) else { return }
        if onboardingWindow == nil { showSettings() }
    }

    /// Closing Settings keeps the widgets and shortcut running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func apply(_ settings: AppSettings) {
        monitor.spotifyOnly = settings.spotifyOnly
        widgets?.apply(settings)
        nowPlayingWidget?.apply(settings)
        HotKeys.shared.update(fullScreenEnabled: settings.isEnabled && settings.lockShortcutEnabled)
        HotKeys.shared.update(reframeEnabled: settings.isEnabled && settings.reframeShortcutEnabled)
        if !settings.isEnabled { FullScreenLyrics.shared.hide() }
    }

    // MARK: - Windows

    func showSettings() {
        if let settingsWindow {
            showInDock()
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        // Arioso's own look: the slate sidebar runs up under a clear title bar.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        // ⌘, opens this instantly, so — per Apple's guidance for a settings window — it doesn't
        // need the Dock or full screen: the minimize and zoom buttons are dimmed, present but
        // disabled, the same as System Settings' own window.
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.title = SettingsTab.general.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 860, height: 620)
        window.setFrameAutosaveName("AriosoSettings")
        window.contentView = NSHostingView(rootView: SettingsView())
        window.delegate = self
        window.center()
        settingsWindow = window
        // The title bar text itself is hidden (see above), but the window's title still names the
        // current pane, so Mission Control, the Window menu and VoiceOver do too.
        NotificationCenter.default.addObserver(forName: NavigationModel.tabChangedNotification,
                                               object: nil, queue: .main) { [weak self] note in
            guard let title = note.object as? String else { return }
            self?.settingsWindow?.title = title
        }
        showInDock()
        window.makeKeyAndOrderFront(nil)
    }

    /// First launch: the welcome tour, then Settings.
    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 820),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        let hosting = NSHostingView(rootView: OnboardingView { [weak self] in
            Onboarding.markDone()
            self?.onboardingWindow?.orderOut(nil)
            self?.onboardingWindow = nil
            self?.showSettings()
        })
        // Fixed-size window; don't let SwiftUI resize it.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
        onboardingWindow = window
        showInDock()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        settingsWindow = nil
        // Back to living on the desktop only.
        NSApp.setActivationPolicy(.accessory)
    }

    private func showInDock() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// An update window brings the Dock icon up while it's open; drop it again unless one of our own windows is showing.
    private func backToBackgroundIfIdle() {
        guard settingsWindow == nil, onboardingWindow == nil else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Menus (shown while Settings is open)

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Arioso",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        if Updater.isAvailable {
            let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "")
            updates.target = self
            appMenu.addItem(updates)
        }
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Arioso", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Arioso", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openSettingsFromMenu() { showSettings() }
    @objc private func checkForUpdatesFromMenu() { Updater.shared.checkForUpdates() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
