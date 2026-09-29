import AppKit

/// `open -a Arioso --args --demo` plays a made-up song with original lyrics
/// and drawn artwork, so App Store screenshots and previews never show
/// copyrighted songs or covers. Nothing is read from Spotify or Music.
enum Demo {
    static var isOn: Bool { CommandLine.arguments.contains("--demo") }

    /// `--scene vinyl` shows that full-screen scene without changing saved settings.
    static var sceneOverride: LockScene? {
        let args = CommandLine.arguments
        guard isOn, let i = args.firstIndex(of: "--scene"), i + 1 < args.count else { return nil }
        return LockScene(rawValue: args[i + 1])
    }

    /// `--showcase`: a clean slate wallpaper over the whole screen with the
    /// widgets raised above it, so screenshots show nothing personal.
    static var isShowcase: Bool { isOn && CommandLine.arguments.contains("--showcase") }
    /// `--showcase-live`: the same clean wallpaper, but with the real song and audio.
    static var isLiveShowcase: Bool { CommandLine.arguments.contains("--showcase-live") }

    static func showWallpaper() -> NSWindow? {
        guard let screen = NSScreen.main else { return nil }
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = true
        window.contentView = NSImageView(image: wallpaper(size: screen.frame.size))
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        return window
    }

    private static func wallpaper(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.16, green: 0.21, blue: 0.25, alpha: 1),
                                NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)])?.draw(in: rect, angle: -60)
            for (x, y, r, a) in [(0.72, 0.7, 0.45, 0.35), (0.2, 0.25, 0.4, 0.25)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                let radius = r * rect.width
                NSGradient(colors: [NSColor(red: 0.43, green: 0.55, blue: 0.62, alpha: a), .clear])?
                    .draw(in: NSRect(x: x * rect.width - radius, y: y * rect.height - radius,
                                     width: radius * 2, height: radius * 2), relativeCenterPosition: .zero)
            }
            return true
        }
    }

    static let title = "Moonlit Room"
    static let artist = "The Late Hours"
    static let duration: TimeInterval = 204

    /// Original lines, written for Arioso's demos.
    static let lyrics: [LyricLine] = [
        (0, ""), (6, "Lights low, headphones on"), (11, "The city hums along"),
        (16, "Every word, every line"), (21, "Right here on the screen"),
        (26, "Until the song is done"), (31, "And I'll sing it back to you"),
        (37, ""), (42, "Moonlight on the window"), (47, "Paper stars across the wall"),
        (52, "I know every word by heart"), (57, "But I love to watch them fall"),
        (63, "Every word, every line"), (68, "Right here on the screen"),
        (73, "Until the song is done"), (78, "And I'll sing it back to you"),
    ].map { LyricLine(time: $0.0, text: $0.1) }

    /// Starts a few lines in, so screenshots show lyrics straight away.
    static func nowPlaying(startedAt start: Date) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: artist, album: "Night Songs", artwork: artwork,
                       duration: duration, elapsedTime: 14, timestamp: start, playbackRate: 1)
    }

    /// Made-up songs for the Recently Played widget, each with its own cover.
    static let history: [(title: String, artist: String, artwork: NSImage)] = [
        (title, artist, artwork),
        ("Paper Lanterns", "Juniper Coast", cover(0.62, 0.42, 0.30)),
        ("Slow Tide", "Harbor Lights", cover(0.30, 0.48, 0.52)),
        ("Neon Rain", "Glass Avenue", cover(0.45, 0.32, 0.55)),
        ("Late Bloom", "Wren & Oak", cover(0.40, 0.52, 0.34)),
        ("Northbound", "Ellis Park", cover(0.55, 0.50, 0.30)),
        ("Satellite Summer", "Coastline", cover(0.28, 0.36, 0.58)),
    ]

    /// A moon over the sea, drawn in Arioso's slate palette.
    static let artwork = cover(0.44, 0.50, 0.55)

    private static func cover(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSImage {
      NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
        NSGradient(colors: [NSColor(red: r, green: g, blue: b, alpha: 1),
                            NSColor(red: 0.12, green: 0.16, blue: 0.19, alpha: 1),
                            NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)])?.draw(in: rect, angle: 90)
        NSColor(white: 1, alpha: 0.08).setFill()
        NSBezierPath(ovalIn: NSRect(x: 330, y: 330, width: 190, height: 190)).fill()
        NSColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 385, y: 385, width: 80, height: 80)).fill()
        let hills = NSBezierPath()
        hills.move(to: NSPoint(x: 0, y: 210))
        for (x, y) in [(90, 280), (150, 240), (240, 330), (330, 245), (390, 280), (460, 235), (525, 290), (600, 240)] {
            hills.line(to: NSPoint(x: x, y: y))
        }
        hills.line(to: NSPoint(x: 600, y: 0)); hills.line(to: NSPoint(x: 0, y: 0)); hills.close()
        NSColor(red: 0.10, green: 0.13, blue: 0.16, alpha: 1).setFill()
        hills.fill()
        NSColor(red: 0.07, green: 0.09, blue: 0.11, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 600, height: 170).fill()
        NSColor(white: 0.95, alpha: 0.5).setFill()
        for (i, w) in [70, 110, 55, 130].enumerated() {
            NSRect(x: CGFloat(425 - w / 2), y: CGFloat(150 - i * 26), width: CGFloat(w), height: 5).fill()
        }
        return true
      }
    }
}
