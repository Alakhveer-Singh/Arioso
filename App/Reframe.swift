import AppKit
import ApplicationServices

/// ⌘⇧L: fits every window of the frontmost app into the free space between
/// the desktop widgets, animating into place. Pressing it again puts the
/// windows back, also animated.
///
/// This moves *other* apps' windows via the Accessibility APIs, which the
/// App Sandbox never allows — Arioso must be built without it for this to
/// work at all (see App/Arioso.entitlements).
enum Reframer {
    /// Set once at launch: the desktop widgets' current frames, so the free
    /// area can be computed without needing another process's window list.
    static var widgetFrames: () -> [CGRect] = { [] }

    private static let gap: CGFloat = 12
    /// Windows moved by the last press, per app, with where they came from.
    private static var saved: [pid_t: [(window: AXUIElement, origin: CGPoint, size: CGSize)]] = [:]
    /// Keeps the animation timer alive while it runs.
    private static var animationTimer: Timer?

    static func toggle() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(prompt) else {
            NSLog("⌘⇧L needs Accessibility permission (System Settings › Privacy & Security › Accessibility).")
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let pid = app.processIdentifier
        let windows = standardWindows(of: AXUIElementCreateApplication(pid))
        let target = freeArea()

        // Second press while the windows are still where we put them: restore.
        if let previous = saved[pid], windows.allSatisfy({ frame(of: $0) == target }) {
            let steps: [(AXUIElement, CGRect, CGRect)] = zip(windows, previous).compactMap { window, entry in
                guard let from = frame(of: window) else { return nil }
                return (window, from, CGRect(origin: entry.origin, size: entry.size))
            }
            saved[pid] = nil
            animate(steps)
            return
        }
        saved[pid] = windows.compactMap { w in frame(of: w).map { (w, $0.origin, $0.size) } }
        let steps: [(AXUIElement, CGRect, CGRect)] = windows.compactMap { window in
            guard let from = frame(of: window) else { return nil }
            return (window, from, target)
        }
        animate(steps)
    }

    /// Eases every window from its current frame to its target, so the fit-in glides rather
    /// than snapping. Driven by elapsed wall-clock time rather than a fixed step count, so a
    /// late-firing tick (another app briefly hogging the main thread, common when moving ITS
    /// windows over Accessibility IPC) skips ahead to where it should be instead of falling
    /// behind and looking like it's catching up.
    private static func animate(_ moves: [(window: AXUIElement, from: CGRect, to: CGRect)]) {
        animationTimer?.invalidate()
        guard !moves.isEmpty else { return }
        guard !Motion.reduced else {
            for move in moves { set(move.window, origin: move.to.origin, size: move.to.size, final: true) }
            return
        }
        let duration = 0.34
        let began = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { timer in
            let t = min(1, (CACurrentMediaTime() - began) / duration)
            let finished = t >= 1
            // Ease *in* and out (zero velocity, zero acceleration at both ends), not just out: an
            // ease-out alone jumps from standing still to full speed in one frame, then coasts to a
            // stop, which reads as a fast snap. This ramps up first, so it reads as a glide.
            let eased = t * t * t * (t * (t * 6 - 15) + 10)   // smootherstep
            for move in moves {
                let origin = CGPoint(x: move.from.minX + (move.to.minX - move.from.minX) * eased,
                                     y: move.from.minY + (move.to.minY - move.from.minY) * eased)
                let size = CGSize(width: move.from.width + (move.to.width - move.from.width) * eased,
                                  height: move.from.height + (move.to.height - move.from.height) * eased)
                // The safety re-assert of size (some apps clamp size to their old position's screen
                // space) only runs on the landing frame: doing it every tick was three Accessibility
                // IPC round trips per window, per frame, which is what made this feel rough with more
                // than a window or two open.
                set(move.window, origin: origin, size: size, final: finished)
            }
            if finished {
                timer.invalidate()
                animationTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    /// Screen area not covered by widgets, in top-left-origin coordinates
    /// (what the Accessibility APIs use, unlike AppKit's bottom-left).
    private static func freeArea() -> CGRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let primaryHeight = NSScreen.screens[0].frame.height
        let vis = screen.visibleFrame
        var left = vis.minX + gap, right = vis.maxX - gap
        let top = primaryHeight - vis.maxY + gap, bottom = primaryHeight - vis.minY - gap

        for f in widgetFrames() {
            if f.midX < vis.midX { left = max(left, f.maxX + gap) } else { right = min(right, f.minX - gap) }
        }
        return CGRect(x: left, y: top, width: max(right - left, 300), height: bottom - top)
    }

    private static func standardWindows(of app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        return (value as? [AXUIElement] ?? []).filter { w in
            var role: CFTypeRef?, minimized: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minimized)
            return role as? String == kAXStandardWindowSubrole as String && minimized as? Bool != true
        }
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &p)
        AXValueGetValue(size as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    /// `final`: also re-asserts size after moving (some apps clamp size to their old position's
    /// screen space); skipped on every mid-animation frame to keep the glide light on IPC calls.
    private static func set(_ window: AXUIElement, origin: CGPoint, size: CGSize, final: Bool) {
        var o = origin, s = size
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &o)!)
        if final {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
        }
    }
}
