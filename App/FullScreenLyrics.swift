import AppKit
import SwiftUI

/// ⌥⌘L: the song fills the screen, using the scene and look chosen in
/// Settings › Full Screen. Esc, any key or a click closes it.
///
/// App Store apps can't draw on the real lock screen or install a screen
/// saver, so this is the same scene, shown on demand instead.
final class FullScreenLyrics {
    static let shared = FullScreenLyrics()

    /// Set once at launch; the same model drives the widgets.
    var model: LyricsSceneModel?
    private var window: StageWindow?

    var isShowing: Bool { window != nil }

    func toggle() { isShowing ? hide() : show() }

    func show() {
        guard window == nil, let model else { return }
        // The screen the pointer is on, like a screen saver would pick.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }

        let window = StageWindow(contentRect: screen.frame, styleMask: [.borderless],
                                 backing: .buffered, defer: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .black
        window.isOpaque = true
        window.onDismiss = { [weak self] in self?.hide() }

        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let hosting = NSHostingView(rootView: FullScreenLyricsView(model: model, store: .shared))
        let catcher = ClickCatcher()
        catcher.onClick = { [weak self] in self?.hide() }
        for view in [hosting, catcher] as [NSView] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        window.contentView = container
        window.setFrame(screen.frame, display: true)
        window.alphaValue = 0

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.35; window.animator().alphaValue = 1 }
        NSCursor.setHiddenUntilMouseMoves(true)
        self.window = window
    }

    func hide() {
        guard let window else { return }
        self.window = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; window.animator().alphaValue = 0 },
                                            completionHandler: { window.orderOut(nil) })
    }
}

private struct FullScreenLyricsView: View {
    @ObservedObject var model: LyricsSceneModel
    @ObservedObject var store: SettingsStore

    var body: some View {
        LyricsSceneView(model: model, look: store.settings.lockScreen,
                        scene: Demo.sceneOverride ?? store.settings.effectiveScene)
            .ignoresSafeArea()
    }
}

/// Borderless windows can't take key focus by default; this one needs it for Esc.
private final class StageWindow: NSWindow {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { onDismiss?() }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

/// Transparent layer over the scene that closes it on click.
private final class ClickCatcher: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
