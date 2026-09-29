import AppKit
import Combine
import SwiftUI

/// Transparent layer over the widget: drags the window on the first click
/// (this background app is never the active one), and resizes it from any
/// edge or corner like a normal macOS window.
final class DragOverlayView: NSView {
    static let minimumSize = CGSize(width: 240, height: 240)
    private let grip: CGFloat = 10

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Height of a strip along the bottom that belongs to the SwiftUI content (the
    /// player controls) instead: clicks there pass through this overlay. The window
    /// can still be resized from its very edge, and dragged from everywhere else.
    var passThroughBottom: CGFloat = 0
    /// When set, only a strip this tall along the top (the drag handle) and the resize edges
    /// belong to the overlay; the rest goes to the SwiftUI content, which handles its own clicks.
    var dragHandleHeight: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        if dragHandleHeight > 0 {
            let local = convert(point, from: superview)
            return edges(at: local).any || local.y > bounds.height - dragHandleHeight ? self : nil
        }
        if passThroughBottom > 0 {
            let local = convert(point, from: superview)
            if local.y > grip, local.y < passThroughBottom, local.x > 16, local.x < bounds.width - 16 { return nil }
        }
        return self
    }

    private struct Edges { var left = false, right = false, bottom = false, top = false
        var any: Bool { left || right || bottom || top } }

    private func edges(at p: NSPoint) -> Edges {
        Edges(left: p.x < grip, right: p.x > bounds.width - grip,
              bottom: p.y < grip, top: p.y > bounds.height - grip)
    }

    override func resetCursorRects() {
        let w = bounds.width, h = bounds.height, g = grip
        let zones: [(NSRect, NSCursor)] = [
            (NSRect(x: g, y: 0, width: w - 2 * g, height: g), cursor(.bottom, fallback: .resizeUpDown)),
            (NSRect(x: g, y: h - g, width: w - 2 * g, height: g), cursor(.top, fallback: .resizeUpDown)),
            (NSRect(x: 0, y: g, width: g, height: h - 2 * g), cursor(.left, fallback: .resizeLeftRight)),
            (NSRect(x: w - g, y: g, width: g, height: h - 2 * g), cursor(.right, fallback: .resizeLeftRight)),
            (NSRect(x: 0, y: 0, width: g, height: g), cursor(.bottomLeft, fallback: .crosshair)),
            (NSRect(x: w - g, y: 0, width: g, height: g), cursor(.bottomRight, fallback: .crosshair)),
            (NSRect(x: 0, y: h - g, width: g, height: g), cursor(.topLeft, fallback: .crosshair)),
            (NSRect(x: w - g, y: h - g, width: g, height: g), cursor(.topRight, fallback: .crosshair)),
        ]
        for (rect, cursor) in zones { addCursorRect(rect, cursor: cursor) }
    }

    private enum Zone { case top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight }

    private func cursor(_ zone: Zone, fallback: NSCursor) -> NSCursor {
        guard #available(macOS 15.0, *) else { return fallback }
        let position: NSCursor.FrameResizePosition
        switch zone {
        case .top: position = .top
        case .bottom: position = .bottom
        case .left: position = .left
        case .right: position = .right
        case .topLeft: position = .topLeft
        case .topRight: position = .topRight
        case .bottomLeft: position = .bottomLeft
        case .bottomRight: position = .bottomRight
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let e = edges(at: convert(event.locationInWindow, from: nil))
        guard e.any else { return window.performDrag(with: event) }

        let start = NSEvent.mouseLocation, startFrame = window.frame
        let minW = Self.minimumSize.width, minH = Self.minimumSize.height
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type != .leftMouseUp {
            let dx = NSEvent.mouseLocation.x - start.x, dy = NSEvent.mouseLocation.y - start.y
            var f = startFrame
            if e.right { f.size.width = max(minW, startFrame.width + dx) }
            if e.left { f.size.width = max(minW, startFrame.width - dx); f.origin.x = startFrame.maxX - f.width }
            if e.top { f.size.height = max(minH, startFrame.height + dy) }
            if e.bottom { f.size.height = max(minH, startFrame.height - dy); f.origin.y = startFrame.maxY - f.height }
            window.setFrame(f, display: true)
        }
        window.invalidateCursorRects(for: self)
    }
}

/// Where a widget's drag handle ends. With "Click a line to jump" on, only the top of the Lyrics
/// widget (the cover, progress and title) drags the window; everything below belongs to the lyrics
/// and the controls, which handle their own clicks.
final class HitRegions {
    weak var overlay: DragOverlayView?
    /// From the top of the window down to the end of the cover area, measured by the view.
    var header: CGFloat = 0 { didSet { apply() } }
    var tapToJump = true { didSet { apply() } }
    private func apply() { overlay?.dragHandleHeight = tapToJump ? header : 0 }
}

/// The two desktop widgets. Borderless windows at the level macOS uses for
/// its own desktop widgets; each remembers its position and size.
final class WidgetsController {
    private let model: LyricsSceneModel
    private let store: SettingsStore
    private let lyricsWindow: NSWindow
    private let historyWindow: NSWindow
    /// Where the Lyrics widget's drag handle ends (see HitRegions).
    private let lyricsRegions = HitRegions()
    private let historyRegions = HitRegions()
    private let windows: [(window: NSWindow, name: String)]
    private let customLayoutKey = "customLayout"

    init(model: LyricsSceneModel, store: SettingsStore, history: RecentlyPlayed) {
        self.model = model
        self.store = store
        let regions = lyricsRegions
        lyricsWindow = Self.makeWindow(passThroughBottom: LyricsWidgetView.controlsHeight, regions: regions) {
            LyricsWidgetView(model: model, settings: store, size: $0, regions: regions)
        }
        let historyRegions = historyRegions
        historyWindow = Self.makeWindow(regions: historyRegions) {
            RecentlyPlayedView(model: model, settings: store, history: history, size: $0)
        }
        historyRegions.header = RecentlyPlayedView.headerHeight
        windows = [(lyricsWindow, "LyricsWidget"), (historyWindow, "RecentlyPlayedWidget")]
        for (window, name) in windows { place(window, name: name) }

        for (name, action) in [(AppSettings.resetPositionsNotification, resetPositions),
                               (AppSettings.saveLayoutNotification, saveLayout),
                               (AppSettings.originalLayoutNotification, restoreOriginalLayout)] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        }
    }

    /// Screenshot showcase: widgets above everything, over Demo's wallpaper.
    func raiseForShowcase() {
        // Inside the middle 16:10 of the screen, so App Store crops keep every widget whole.
        let screen = NSScreen.main?.frame ?? visible
        let width = min(screen.width, screen.height * 1.6)
        let area = NSRect(x: screen.midX - width / 2, y: screen.minY, width: width, height: screen.height)
            .insetBy(dx: 48, dy: 48)
        lyricsWindow.setFrame(NSRect(x: area.maxX - 380, y: area.minY, width: 380, height: area.height), display: true)
        historyWindow.setFrame(NSRect(x: area.minX, y: area.minY + area.height * 0.35, width: 380, height: area.height * 0.65), display: true)
        for (window, _) in windows {
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            window.orderFrontRegardless()
        }
    }

    /// Current on-screen frames of every widget, for Reframer to avoid.
    var visibleFrames: [CGRect] {
        windows.map(\.window).filter { $0.isVisible }.map { $0.frame }
    }

    /// Shows the widgets the user turned on (none while Arioso is switched off).
    func apply(_ settings: AppSettings) {
        // Clicks reach the player controls only while they're showing (see DragOverlayView).
        if let overlay = lyricsWindow.contentView?.subviews.compactMap({ $0 as? DragOverlayView }).first {
            overlay.passThroughBottom = settings.lyricsWidgetControls ? LyricsWidgetView.controlsHeight : 0
        }
        lyricsRegions.tapToJump = settings.lyricsTapToJump
        historyRegions.tapToJump = settings.historyPlayAgain
        for (window, shown) in [(lyricsWindow, settings.showLyricsWidget),
                                (historyWindow, settings.showRecentlyPlayed)] {
            if settings.isEnabled && shown { window.orderFront(nil) } else { window.orderOut(nil) }
        }
    }

    /// A borderless, draggable, resizable window at the desktop-widget level.
    /// The content is rebuilt with the window's live size.
    private static func makeWindow<Content: View>(passThroughBottom: CGFloat = 0, regions: HitRegions? = nil,
                                                  content: @escaping (CGSize) -> Content) -> NSWindow {
        let size = CGSize(width: 350, height: 500)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        // The same level macOS uses for desktop widgets: above the desktop icons,
        // below every app window.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.minSize = DragOverlayView.minimumSize
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let hosting = FirstMouseHostingView(rootView: GeometryReader { geo in content(geo.size) })
        let overlay = DragOverlayView()
        overlay.passThroughBottom = passThroughBottom
        regions?.overlay = overlay
        for view in [hosting, overlay] as [NSView] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        window.contentView = container
        return window
    }

    private var visible: NSRect {
        NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Default layout: lyrics full height on the right, Recently Played on the
    /// left at about two thirds of the screen's height.
    private var defaultFrames: [String: NSRect] {
        let visible = visible, margin: CGFloat = 16
        let historyHeight = (visible.height - margin * 2) * 0.65
        return [
            "LyricsWidget": NSRect(x: visible.maxX - 350 - margin, y: visible.minY + margin,
                                   width: 350, height: visible.height - margin * 2),
            "RecentlyPlayedWidget": NSRect(x: visible.minX + margin, y: visible.maxY - margin - historyHeight,
                                           width: 350, height: historyHeight),

        ]
    }

    /// Restores the widget's saved position and size (or the default), kept on screen.
    /// Remembers each widget's frame ourselves: macOS's frame autosave missed
    /// programmatic changes and sometimes restored a stale size after a restart.
    private func place(_ window: NSWindow, name: String) {
        let key = "frame." + name
        if let saved = UserDefaults.standard.string(forKey: key) {
            window.setFrame(NSRectFromString(saved), display: false)
        } else {
            window.setFrame(defaultFrames[name]!, display: false)
        }
        for event in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(forName: event, object: window, queue: .main) { _ in
                guard !Demo.isOn else { return }   // screenshots never move your real layout
                UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: key)
            }
        }
        let visible = visible
        var f = window.frame
        f.size.width = min(max(f.width, DragOverlayView.minimumSize.width), visible.width)
        f.size.height = min(max(f.height, DragOverlayView.minimumSize.height), visible.height)
        f.origin.x = min(max(f.minX, visible.minX), visible.maxX - f.width)
        f.origin.y = min(max(f.minY, visible.minY), visible.maxY - f.height)
        window.setFrame(f, display: false)
    }

    /// The layout the user saved, if any: widget name -> frame.
    private func customLayout() -> [String: NSRect]? {
        (UserDefaults.standard.dictionary(forKey: customLayoutKey) as? [String: String])?
            .mapValues { NSRectFromString($0) }
    }

    private func saveLayout() {
        UserDefaults.standard.set(
            Dictionary(uniqueKeysWithValues: windows.map { ($0.name, NSStringFromRect($0.window.frame)) }),
            forKey: customLayoutKey)
    }

    /// Puts every widget back in the user's saved layout, or the original one.
    private func resetPositions() {
        let layout = customLayout() ?? defaultFrames
        for (window, name) in windows {
            window.setFrame(layout[name] ?? defaultFrames[name]!, display: true, animate: true)
        }
    }

    private func restoreOriginalLayout() {
        UserDefaults.standard.removeObject(forKey: customLayoutKey)
        resetPositions()
    }
}
