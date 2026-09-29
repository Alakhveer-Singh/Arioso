import AppKit
import Combine
import SwiftUI

/// The compact player, docked to the bottom edge of the screen: cover, title, artist and
/// moving waves. Click it and it opens upward into the full player card; click the top
/// row of the card to fold it back. It stays put at the bottom centre.
///
/// A borderless, non-activating panel that floats above every app's windows (and over
/// full-screen apps), so clicking it never takes focus from what you're typing in. It rises
/// in from below the screen edge when a song loads and slides back down when it stops.
/// Settings › Player can drop it back to the desktop level, under app windows.
///
/// Opening and closing animate the window's frame itself (the glass fills the window) on a
/// damped spring that settles with a slight overshoot; SwiftUI only crossfades what's inside.
final class NowPlayingWidget {
    private let window: NSWindow
    private let state = NowPlayingPanelState()
    private let store: SettingsStore
    private var cancellables = Set<AnyCancellable>()
    private var wanted = false
    private var hasSong = false
    /// True from the moment it starts sliding in until it has slid out.
    private var shown = false
    private var scale: CGFloat
    private var springTimer: Timer?
    private var cover: CGFloat

    init(model: LyricsSceneModel, store: SettingsStore) {
        self.store = store
        scale = CGFloat(store.settings.playerScale)
        cover = CGFloat(store.settings.playerLook.coverSize)
        let floating = NSPanel(contentRect: NSRect(origin: .zero, size: NowPlayingPill.size(cover: 1)),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        floating.isFloatingPanel = true
        floating.becomesKeyOnlyIfNeeded = true
        floating.hidesOnDeactivate = false   // panels hide when their app isn't active; this one must stay
        window = floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.level = Self.level(floats: store.settings.playerFloats)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // A GeometryReader has no natural size of its own, so SwiftUI never tries to resize the
        // window to fit its content (which would fight the frame animation below). The other
        // widgets do the same.
        let panel = state
        window.contentView = FirstMouseHostingView(rootView: GeometryReader { _ in
            NowPlayingWidgetView(model: model, settings: store, state: panel,
                                 onLyrics: { FullScreenLyrics.shared.show() })
        })
        window.setFrame(targetFrame(expanded: false), display: false)

        state.$expanded.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.expandedChanged($0) }
            .store(in: &cancellables)
        model.$nowPlaying.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.hasSong = $0 != nil; self?.refresh() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)
        // Screenshots: `--player-open` opens the full player card a moment after launch.
        if CommandLine.arguments.contains("--player-open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                withAnimation(Motion.open) { self?.state.expanded = true }
            }
        }
    }

    /// Above every app's windows, or (Settings › Player) on the desktop like the other widgets.
    private static func level(floats: Bool) -> NSWindow.Level {
        floats ? .statusBar : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
    }

    /// Screenshot showcase: above everything, like the other widgets.
    func raiseForShowcase() {
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.orderFrontRegardless()
    }

    /// Shown when the user turned it on and Arioso is on.
    func apply(_ settings: AppSettings) {
        wanted = settings.isEnabled && settings.showNowPlaying
        window.level = Self.level(floats: settings.playerFloats)
        if CGFloat(settings.playerScale) != scale || CGFloat(settings.playerLook.coverSize) != cover {
            scale = CGFloat(settings.playerScale)
            cover = CGFloat(settings.playerLook.coverSize)
            relayout()
        }
        refresh()
    }

    private func refresh() {
        if wanted && hasSong { present() } else { dismiss() }
    }

    // MARK: - Opening and closing

    private func expandedChanged(_ expanded: Bool) {
        let target = targetFrame(expanded: expanded)
        guard shown else { window.setFrame(target, display: true); return }
        // Opening springs up and settles with a touch of overshoot; closing eases down without bouncing.
        spring(to: target, response: expanded ? 0.5 : 0.36, damping: expanded ? 0.72 : 1)
    }

    /// Moves the window to `target` on a damped spring, one frame at a time. (AppKit's own window
    /// animation ignores timing curves, so it can't overshoot or run longer than about 0.2 s.)
    private func spring(to target: NSRect, response: Double, damping: Double) {
        springTimer?.invalidate()
        guard !Motion.reduced else { window.setFrame(target, display: true); return }
        let start = window.frame
        let began = CACurrentMediaTime()
        let omega = 2 * Double.pi / response
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = CACurrentMediaTime() - began
            if t > response * 2.5 {
                self.window.setFrame(target, display: true)
                timer.invalidate()
                return
            }
            let p = CGFloat(Self.springValue(t, omega: omega, damping: damping))
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
            self.window.setFrame(NSRect(x: mix(start.minX, target.minX), y: mix(start.minY, target.minY),
                                        width: mix(start.width, target.width), height: max(1, mix(start.height, target.height))),
                                 display: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        springTimer = timer
    }

    /// 0 → 1 (overshooting when under-damped) for a spring with angular frequency `omega`.
    private static func springValue(_ t: Double, omega: Double, damping z: Double) -> Double {
        if z < 1 {
            let wd = omega * (1 - z * z).squareRoot()
            return 1 - exp(-z * omega * t) * (cos(wd * t) + (z * omega / wd) * sin(wd * t))
        }
        return 1 - exp(-omega * t) * (1 + omega * t)
    }

    // MARK: - Sliding in and out

    private static let easeOut = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)

    /// Rises in from below the screen edge, fading up.
    private func present() {
        guard !shown else { return }
        shown = true
        springTimer?.invalidate()
        let final = targetFrame(expanded: state.expanded)
        var start = final
        if !Motion.reduced { start.origin.y -= final.height * 0.6 }
        window.alphaValue = 0
        window.setFrame(start, display: false)
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduced ? 0.15 : 0.55
            context.timingFunction = Self.easeOut
            window.animator().setFrame(final, display: true)
            window.animator().alphaValue = 1
        }
    }

    /// Folds away and slides back below the edge.
    private func dismiss() {
        guard shown else { window.orderOut(nil); return }
        shown = false
        if state.expanded { state.expanded = false }
        var end = window.frame
        if !Motion.reduced { end.origin.y -= end.height * 0.6 }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.reduced ? 0.15 : 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(end, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.shown else { return }   // it came back while sliding out
            self.window.orderOut(nil)
            self.window.alphaValue = 1
        })
    }

    // MARK: - Placement

    private func relayout() {
        springTimer?.invalidate()
        guard shown else { window.setFrame(targetFrame(expanded: false), display: false); return }
        window.setFrame(targetFrame(expanded: state.expanded), display: true)
    }

    /// Bottom centre of the screen. With the Dock hidden the glass runs a little below the
    /// screen edge, so only its top corners show; with the Dock up it sits on top of the Dock.
    private func targetFrame(expanded: Bool) -> NSRect {
        let screen = window.screen ?? NSScreen.main
        let base = expanded ? NowPlayingCard.size(cover: cover) : NowPlayingPill.size(cover: cover)
        let size = CGSize(width: base.width * scale, height: base.height * scale)
        guard let screen else { return NSRect(origin: .zero, size: size) }
        let visible = screen.visibleFrame
        let dockShowing = visible.minY > screen.frame.minY + 1
        let overhang: CGFloat = dockShowing ? 0 : 26
        return NSRect(x: screen.frame.midX - size.width / 2, y: visible.minY - overhang,
                      width: size.width, height: size.height + overhang)
    }
}
