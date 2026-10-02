import SwiftUI
import CoreImage
import AppKit

final class LyricsSceneModel: ObservableObject {
    /// Republished only when the track or its artwork changes, so the
    /// full-screen blurred background isn't re-rendered on every poll.
    @Published var nowPlaying: NowPlayingInfo? {
        didSet {
            if nowPlaying?.artwork !== oldValue?.artwork {
                backdrop = nowPlaying?.artwork.flatMap(Self.makeBackdrop)
                glow = nowPlaying?.artwork.flatMap(Self.makeGlow)
            }
        }
    }
    /// Blurred artwork with transparent margins that fade out, shown behind
    /// the cover. The cover occupies the middle half of the image.
    @Published var glow: NSImage?
    /// Small, pre-blurred copy of the artwork for the drifting background.
    @Published var backdrop: NSImage?
    @Published var lyricsResult: LyricsResult = .none
    /// Copyright line for the current lyrics (Musixmatch licence).
    @Published var lyricsCredit: LyricsCredit?
    /// The user declined Automation access, so nothing can be read.
    @Published var accessDenied = false
    @Published var currentLineIndex: Int?
    /// Whole seconds only, so the progress bar doesn't re-render the view 20×/s.
    @Published var elapsedSeconds = 0
    /// Measured heights of the synced lyric lines. Kept here rather than in
    /// view @State because the Command Line Tools toolchain lacks the SwiftUI
    /// macro plugin that @State requires in this SDK.
    @Published var lineHeights: [Int: CGFloat] = [:]
    /// Line index -> its romanized or translated subtitle (see AppSettings.lyricSubtitle).
    @Published var lyricSubtitles: [Int: String] = [:]

    private var playback: NowPlayingInfo?
    /// Live song position, for the word-by-word sing-along.
    var position: TimeInterval { playback?.estimatedElapsed ?? 0 }
    /// Playing right now (false while paused). `nowPlaying` itself only changes with the song.
    @Published private(set) var isPlaying = false
    @Published private(set) var shuffling = false
    @Published private(set) var repeatMode: RepeatMode = .off
    /// The app playing the current song, for the player buttons.
    var playerBundleID: String? { playback?.playerBundleID }
    private var lastTrackKey: String?
    private var tickTimer: Timer?
    private var settingsObserver: NSObjectProtocol?

    init() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshSubtitles() }
    }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    /// Runs on its own timer rather than ScreenSaverView's animateOneFrame,
    /// which does not fire reliably for third-party screensavers.
    func startTicking() {
        stopTicking()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    func update(nowPlaying info: NowPlayingInfo?) {
        // Keep the running clock unless the new reading really disagrees
        // (seek, pause, skip). Replacing it every second made the current line
        // and word highlight twitch by a few milliseconds each time.
        if let info, let current = playback,
           current.title == info.title, current.artist == info.artist,
           current.playbackRate == info.playbackRate,
           abs(current.estimatedElapsed - info.estimatedElapsed) < 0.3 {
            var kept = current
            kept.artwork = info.artwork
            playback = kept
        } else {
            playback = info
        }
        let playing = (info?.playbackRate ?? 0) > 0
        if playing != isPlaying { isPlaying = playing }
        if let info {
            if info.shuffling != shuffling { shuffling = info.shuffling }
            if info.repeatMode != repeatMode { repeatMode = info.repeatMode }
        }
        guard let info else {
            if lastTrackKey != nil {
                lastTrackKey = nil
                nowPlaying = nil
                lyricsResult = .none
                lyricsCredit = nil
                currentLineIndex = nil
                lineHeights = [:]
                lyricSubtitles = [:]
            }
            return
        }

        let key = "\(info.artist)::\(info.title)"
        if key != lastTrackKey {
            lastTrackKey = key
            nowPlaying = info
            lyricsResult = .none
            lyricsCredit = nil
            currentLineIndex = nil
            lineHeights = [:]
            lyricSubtitles = [:]
            LyricsService.shared.fetchLyrics(
                artist: info.artist,
                title: info.title,
                duration: info.duration
            ) { [weak self] result, credit in
                guard self?.lastTrackKey == key else { return }
                self?.lyricsCredit = credit
                LyricsService.shared.reportDisplayed(credit)
                if case .synced(let lines) = result {
                    self?.lyricsResult = .synced(LyricsService.addingInstrumentalMarkers(to: lines))
                } else {
                    self?.lyricsResult = result
                }
                self?.refreshSubtitles()
            }
        } else if let art = info.artwork, art !== nowPlaying?.artwork {
            // A better cover arrived (e.g. the real one replacing a search guess).
            nowPlaying = info
        }
    }

    /// Blurred once per track at low resolution so the background can move
    /// every frame without re-blurring a full-screen image.
    private static func makeBackdrop(from image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation, let source = CIImage(data: tiff) else { return nil }
        let scale = 240 / max(source.extent.width, source.extent.height)
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let processed = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 14)
            .cropped(to: small.extent)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5])
        guard let cg = CIContext().createCGImage(processed, from: processed.extent) else { return nil }
        return NSImage(cgImage: cg, size: processed.extent.size)
    }

    private static func makeGlow(from image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation, let source = CIImage(data: tiff) else { return nil }
        let scale = 160 / max(source.extent.width, source.extent.height)
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let canvas = small.extent.insetBy(dx: -small.extent.width / 2, dy: -small.extent.height / 2)
        // Not clamped, so the blur spreads the colours out into transparency.
        let processed = small
            .applyingGaussianBlur(sigma: 20)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 2.0, kCIInputBrightnessKey: 0.18])
            .cropped(to: canvas)
        guard let cg = CIContext().createCGImage(processed, from: canvas) else { return nil }
        return NSImage(cgImage: cg, size: canvas.size)
    }

    func tick() {
        guard let playback else { return }
        let elapsed = playback.estimatedElapsed
        if Int(elapsed) != elapsedSeconds {
            elapsedSeconds = Int(elapsed)
        }
        guard case .synced(let lines) = lyricsResult else { return }
        let index = lines.lastIndex { $0.time <= elapsed }
        if index != currentLineIndex {
            currentLineIndex = index
        }
    }

    /// Fills `lyricSubtitles` from AppSettings.lyricSubtitle: romanized synchronously,
    /// translated asynchronously via LyricTranslator (macOS 15+; a no-op before that).
    private func refreshSubtitles() {
        guard case .synced(let lines) = lyricsResult else {
            if !lyricSubtitles.isEmpty { lyricSubtitles = [:] }
            return
        }
        let settings = AppSettings.load()
        switch settings.lyricSubtitle {
        case .off:
            if !lyricSubtitles.isEmpty { lyricSubtitles = [:] }
        case .romanized:
            var result: [Int: String] = [:]
            for (i, line) in lines.enumerated() {
                if let romanized = Romanizer.romanize(line.text) { result[i] = romanized }
            }
            lyricSubtitles = result
        case .translated:
            guard #available(macOS 15.0, *) else {
                if !lyricSubtitles.isEmpty { lyricSubtitles = [:] }
                return
            }
            let target = settings.translationLanguage
            LyricTranslator.shared.request(lines.map(\.text), target: target) { [weak self] in
                guard let self, case .synced(let current) = self.lyricsResult else { return }
                var result: [Int: String] = [:]
                for (i, line) in current.enumerated() {
                    guard line.text != LyricsService.instrumentalMarker,
                          let translated = LyricTranslator.shared.cached(line.text, target: target) else { continue }
                    // Skip a "translation" that just echoes the original line unchanged.
                    if translated.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(line.text) != .orderedSame {
                        result[i] = translated
                    }
                }
                self.lyricSubtitles = result
            }
        }
    }
}

/// Mirrors Apple Music's full-screen player: artwork, progress and track info
/// on the left, left-aligned lyrics on the right, blurred artwork behind.
struct LyricsSceneView: View {
    @ObservedObject var model: LyricsSceneModel
    let look: AppSettings.Look
    var scene: LockScene = .classic

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                if let np = model.nowPlaying {
                    sceneView(np, size: geo.size)
                } else {
                    NothingPlaying(accessDenied: model.accessDenied, scale: 1.4)
                }
            }
            .overlay(alignment: .bottom) {
                if model.nowPlaying != nil, model.lyricsCredit != nil {
                    LyricsAttribution(credit: model.lyricsCredit, fontSize: 11).padding(.bottom, 18)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black)
    }

    /// The real desktop picture, read once — Native shows your own wallpaper rather than a
    /// blurred derivative of the album art, so it sits closer to what the actual lock screen
    /// looks like when nothing is playing.
    private static let wallpaperImage: NSImage? = {
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }()

    @ViewBuilder
    private var background: some View {
        if scene == .native {
            Group {
                if let wallpaper = Self.wallpaperImage {
                    Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.19), Color(red: 0.03, green: 0.04, blue: 0.05)],
                                  startPoint: .bottomLeading, endPoint: .topTrailing)
                }
            }
            .ignoresSafeArea()
        } else if let backdrop = model.backdrop {
            DriftingBackground(image: backdrop, look: look)
        } else {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.16, blue: 0.19), Color(red: 0.03, green: 0.04, blue: 0.05)],
                startPoint: .bottomLeading, endPoint: .topTrailing
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Scenes

    @ViewBuilder
    private func sceneView(_ np: NowPlayingInfo, size: CGSize) -> some View {
        switch resolvedScene(for: np) {
        case .spotlight: spotlight(np, size: size)
        case .vinyl: vinyl(np, size: size)
        case .minimal: minimal(np, size: size)
        case .native: native(np, size: size)
        case .classic, .shuffle: classic(np, size: size)
        }
    }

    /// Shuffle picks a scene per song; the same song always gets the same one.
    private func resolvedScene(for np: NowPlayingInfo) -> LockScene {
        guard scene == .shuffle else { return scene }
        let choices: [LockScene] = [.classic, .spotlight, .vinyl, .minimal]
        let hash = (np.title + np.artist).unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }
        return choices[abs(hash % choices.count)]
    }

    private func artSize(_ size: CGSize) -> CGFloat {
        min(min(size.width * 0.31, size.height * 0.5) * look.coverSize, size.height * 0.72, size.width * 0.45)
    }

    private func sideLyrics(_ size: CGSize) -> some View {
        lyricsBody(fontSize: max(28, size.height * 0.046))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.leading, size.width * 0.02)
            .padding(.trailing, size.width * 0.06)
    }

    private func classic(_ np: NowPlayingInfo, size: CGSize) -> some View {
        HStack(spacing: 0) {
            trackColumn(np, artSize: artSize(size))
                .frame(width: size.width / 2, height: size.height)
            sideLyrics(size)
        }
    }

    private func spotlight(_ np: NowPlayingInfo, size: CGSize) -> some View {
        VStack(spacing: size.height * 0.04) {
            HStack(spacing: 16) {
                GlowingCover(artwork: np.artwork, glow: nil, size: size.height * 0.09 * look.coverSize)
                VStack(alignment: .leading, spacing: 4) {
                    Text(np.title).font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
                    Text(np.artist).font(.system(size: 17)).foregroundColor(.white.opacity(0.6))
                }
                .lineLimit(1)
            }
            LyricsContent(model: model, fontSize: max(34, size.height * 0.062) * look.lyricsSize,
                          focusPosition: 0.4, centered: true, singAlong: look.singAlong)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, size.height * 0.08)
        .padding(.bottom, size.height * 0.04)
        .padding(.horizontal, size.width * 0.12)
    }

    private func vinyl(_ np: NowPlayingInfo, size: CGSize) -> some View {
        let record = artSize(size) * 1.1
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                VinylRecord(artwork: np.artwork, size: record, spinning: np.playbackRate > 0)
                VStack(spacing: 4) {
                    Text(np.title).font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
                    Text(np.artist).font(.system(size: 19)).foregroundColor(.white.opacity(0.6))
                }
                .lineLimit(1)
                .frame(width: record)
                .padding(.top, record * 0.1)
            }
            .frame(width: size.width / 2, height: size.height)
            sideLyrics(size)
        }
    }

    private func minimal(_ np: NowPlayingInfo, size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 6) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: size.height * 0.2, weight: .thin, design: .rounded).monospacedDigit())
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: size.height * 0.026, weight: .medium))
                        .opacity(0.7)
                }
            }
            currentLine(size: size)
                .frame(height: size.height * 0.22)
                .padding(.top, size.height * 0.05)
            Spacer()
            HStack(spacing: 12) {
                GlowingCover(artwork: np.artwork, glow: nil, size: 40 * look.coverSize)
                Text("\(np.title) · \(np.artist)")
                    .font(.system(size: 15, weight: .medium))
                    .opacity(0.75)
                    .lineLimit(1)
            }
            .padding(.bottom, size.height * 0.06)
        }
        .foregroundColor(.white)
        .padding(.horizontal, size.width * 0.1)
    }

    /// Your own wallpaper, with a system-style clock and login chrome, and a small frosted
    /// card for the song — closer to the real lock screen than the other scenes, which take
    /// the screen over with derived album-art backgrounds.
    private func native(_ np: NowPlayingInfo, size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: size.height * 0.08)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 4) {
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 17, weight: .medium))
                        .opacity(0.85)
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 68, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.3), radius: 10)
            Spacer()
            nativeCard(np)
                .padding(.bottom, 22)
            VStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.white.opacity(0.95))
                Text(NSFullUserName())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text("Touch ID or Enter Password")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.65))
            }
            .shadow(color: .black.opacity(0.25), radius: 6)
            Spacer().frame(height: size.height * 0.07)
        }
    }

    /// The frosted "Now Playing" card, matching the system's own media-controls widget.
    private func nativeCard(_ np: NowPlayingInfo) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                GlowingCover(artwork: np.artwork, glow: nil, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(np.title).font(.system(size: 15, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                    Text(np.artist).font(.system(size: 13)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "waveform").font(.system(size: 15)).foregroundColor(.white.opacity(0.7))
            }
            PlaybackProgress(elapsedSeconds: model.elapsedSeconds, duration: np.duration, width: 300, fontSize: 12)
            PlayerControls(model: model).frame(width: 260)
        }
        .padding(20)
        .frame(width: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
    }

    /// Only the line being sung, crossfading as it changes.
    private func currentLine(size: CGSize) -> some View {
        var text = "", subtitle: String?
        if case .synced(let lines) = model.lyricsResult, let i = model.currentLineIndex, lines.indices.contains(i) {
            text = lines[i].text
            subtitle = model.lyricSubtitles[i]
        }
        return VStack(spacing: 8) {
            Text(text)
                .font(.system(size: max(30, size.height * 0.05) * look.lyricsSize, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: max(16, size.height * 0.026) * look.lyricsSize, weight: .semibold).italic())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .opacity(0.7)
            }
        }
        .id(text)
        .transition(.opacity.combined(with: .offset(y: 14)))
        .animation(.easeOut(duration: 0.5), value: text)
    }

    private func trackColumn(_ np: NowPlayingInfo, artSize: CGFloat) -> some View {
        let barWidth = artSize * 0.9
        return VStack(spacing: 0) {
            GlowingCover(artwork: np.artwork, glow: look.coverGlow ? model.glow : nil, size: artSize)

            PlaybackProgress(elapsedSeconds: model.elapsedSeconds, duration: np.duration, width: barWidth)
                .padding(.top, artSize * 0.11)

            VStack(spacing: 4) {
                Text(np.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                Text(np.album.isEmpty ? np.artist : "\(np.artist) — \(np.album)")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            .lineLimit(1)
            .frame(width: barWidth)
            .padding(.top, 18)
        }
    }

    private func lyricsBody(fontSize: CGFloat) -> some View {
        LyricsContent(model: model, fontSize: fontSize * look.lyricsSize, focusPosition: 0.45, singAlong: look.singAlong)
    }
}

/// The album art as the label of a spinning black record.
struct VinylRecord: View {
    let artwork: NSImage?
    let size: CGFloat
    let spinning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !spinning)) { context in
            let angle = (context.date.timeIntervalSinceReferenceDate * 80).truncatingRemainder(dividingBy: 360)
            ZStack {
                Circle().fill(Color(white: 0.05))
                ForEach(0..<16, id: \.self) { i in
                    Circle()
                        .stroke(Color.white.opacity(0.04), lineWidth: 1)
                        .padding(size * (0.035 + CGFloat(i) * 0.018))
                }
                Group {
                    if let artwork {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        Color(red: 0.44, green: 0.50, blue: 0.55)
                    }
                }
                .frame(width: size * 0.4, height: size * 0.4)
                .clipShape(Circle())
                Circle().fill(Color.black).frame(width: size * 0.025, height: size * 0.025)
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
        }
        // The light reflection stays still while the record turns.
        .overlay(
            Circle().fill(AngularGradient(
                colors: [.clear, .white.opacity(0.09), .clear, .clear, .white.opacity(0.07), .clear],
                center: .center))
        )
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.55), radius: 30, y: 14)
    }
}

/// Album cover with rounded corners and a glow made from its own colours.
struct GlowingCover: View {
    let artwork: NSImage?
    let glow: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.25))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.06, style: .continuous))
        .background {
            if let glow {
                ZStack {
                    // Two layers: a wide soft halo plus a tighter, brighter core.
                    Image(nsImage: glow).resizable()
                        .frame(width: size * 2.6, height: size * 2.6)
                    Image(nsImage: glow).resizable()
                        .frame(width: size * 2.1, height: size * 2.1)
                }
            }
        }
    }
}

/// Elapsed / remaining times above a progress bar.
struct PlaybackProgress: View {
    let elapsedSeconds: Int
    let duration: TimeInterval
    let width: CGFloat
    var fontSize: CGFloat = 14

    var body: some View {
        let progress = duration > 0 ? min(Double(elapsedSeconds) / duration, 1) : 0
        VStack(spacing: 8) {
            HStack {
                Text(Self.time(Double(elapsedSeconds)))
                Spacer()
                Text("-" + Self.time(max(0, duration - Double(elapsedSeconds))))
            }
            .font(.system(size: fontSize, weight: .semibold).monospacedDigit())
            .foregroundColor(.white.opacity(0.55))

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule().fill(Color.white.opacity(0.9))
                    .frame(width: width * progress)
                    .animation(.linear(duration: 1), value: elapsedSeconds)
            }
            .frame(width: width, height: 5)
        }
        .frame(width: width)
    }

    private static func time(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Synced, plain, or missing lyrics for the current track.
struct LyricsContent: View {
    @ObservedObject var model: LyricsSceneModel
    let fontSize: CGFloat
    let focusPosition: CGFloat
    var centered = false
    var singAlong = true
    /// When set, lines can be clicked; called with the line's start time.
    var onSelectLine: ((TimeInterval) -> Void)? = nil

    var body: some View {
        switch model.lyricsResult {
        case .synced(let lines):
            SyncedLyricsView(
                lines: lines,
                currentIndex: model.currentLineIndex,
                fontSize: fontSize,
                focusPosition: focusPosition,
                rightToLeft: LyricsService.isRightToLeft(lines.map(\.text).joined()),
                subtitles: model.lyricSubtitles,
                lineHeights: model.lineHeights,
                onMeasure: { heights in
                    if heights != model.lineHeights { model.lineHeights = heights }
                },
                centered: centered,
                singAlong: singAlong,
                position: { [weak model] in model?.position ?? 0 },
                onSelect: onSelectLine.map { select in { index in select(lines[index].time) } }
            )
            .id(model.nowPlaying.map { "\($0.artist)::\($0.title)" })
        case .plain(let text):
            let rightToLeft = LyricsService.isRightToLeft(text)
            ScrollView {
                Text(text)
                    .font(.system(size: fontSize * 0.8, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(centered ? .center : rightToLeft ? .trailing : .leading)
                    .frame(maxWidth: .infinity, alignment: centered ? .center : rightToLeft ? .trailing : .leading)
                    .padding(.vertical, 40)
            }
            .scrollIndicators(.never)
        case .none:
            Text("No lyrics found")
                .font(.system(size: fontSize * 0.7, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        }
    }
}

struct LineHeightsKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Lays every line out at the same size and moves them with offsets and
/// opacity only — both GPU-animatable — so layout never shifts mid-animation.
struct SyncedLyricsView: View {
    let lines: [LyricLine]
    let currentIndex: Int?
    let fontSize: CGFloat
    /// Where the active line sits, as a fraction of the available height.
    let focusPosition: CGFloat
    /// Urdu, Arabic, Hebrew etc. are right-aligned, as in Apple Music.
    let rightToLeft: Bool
    /// Line index -> its romanized or translated subtitle (Settings › General › Lyrics).
    var subtitles: [Int: String] = [:]
    let lineHeights: [Int: CGFloat]
    let onMeasure: ([Int: CGFloat]) -> Void
    var centered = false
    var singAlong = true
    var position: () -> TimeInterval = { 0 }
    /// When set, a line can be clicked (with a soft highlight on hover); called with its index.
    var onSelect: ((Int) -> Void)? = nil
    private var spacing: CGFloat { fontSize * 1.0 }

    /// When the current line's words are sung: singers stretch a line almost
    /// until the next one starts, so sweep across that whole span. Long pauses
    /// already become their own ♪ line, and 10 s caps anything unusual.
    private func timing(of index: Int) -> ClosedRange<TimeInterval> {
        let start = lines[index].time
        let next = index + 1 < lines.count ? lines[index + 1].time : start + 6
        return start...max(start + 0.5, min(next - 0.25, start + 10))
    }
    /// Fraction of the height faded out at the top edge.
    private static let topFade: CGFloat = 0.03

    /// Heights are measured rather than positions: a line's size is unaffected
    /// by its own animated offset, so measuring can't feed back into the offset.
    private func center(of index: Int) -> CGFloat {
        let above = (0..<index).reduce(CGFloat(0)) { $0 + (lineHeights[$1] ?? 0) + spacing }
        return above + (lineHeights[index] ?? 0) / 2
    }

    var body: some View {
        GeometryReader { geo in
            let focus = currentIndex ?? 0
            // Early in a song the first lines sit at the top (just below the fade)
            // instead of at the focus point, which would leave a gap above them.
            let topInset = geo.size.height * Self.topFade
            let offset = min(topInset, geo.size.height * focusPosition - center(of: focus))

            VStack(alignment: centered ? .center : rightToLeft ? .trailing : .leading, spacing: spacing) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    TappableLine(onTap: onSelect.map { select in { select(index) } }) { hovered in
                        LyricLineView(text: line.text, fontSize: fontSize, rightToLeft: rightToLeft,
                                      distance: currentIndex.map { index - $0 }, centered: centered,
                                      emphasized: hovered, subtitle: subtitles[index],
                                      sweep: singAlong && index == currentIndex ? timing(of: index) : nil,
                                      position: position)
                    }
                        .background(GeometryReader { lineGeo in
                            Color.clear.preference(key: LineHeightsKey.self, value: [index: lineGeo.size.height])
                        })
                        .offset(y: offset)
                        .animation(
                            .spring(response: 0.75, dampingFraction: 0.88)
                                .delay(Double(min(abs(index - focus), 6)) * 0.04),
                            value: currentIndex
                        )
                        // A subtitle (Romanize/Translate) can pop in a moment after the lyrics
                        // themselves, making some lines taller and pushing the ones below down.
                        // Without this, that push happened instantly; this makes it glide instead.
                        .animation(.easeOut(duration: 0.4), value: subtitles[index])
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: geo.size.width, height: geo.size.height,
                   alignment: centered ? .top : rightToLeft ? .topTrailing : .topLeading)
            .onPreferenceChange(LineHeightsKey.self) { onMeasure($0) }
        }
        .clipped()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: Self.topFade),
                    .init(color: .black, location: 0.85),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .opacity(lineHeights.isEmpty ? 0 : 1)
        .animation(.easeOut(duration: 0.5), value: lineHeights.isEmpty)
    }
}

/// Makes a lyric line clickable. Under the pointer the line comes into focus and gets a soft
/// rounded highlight. The text is inset 10 pt inside the highlight, and the widget widens the
/// lyrics by the same amount, so the words stay lined up with the cover and title.
private struct TappableLine<Content: View>: View {
    let onTap: (() -> Void)?
    @ViewBuilder let content: (Bool) -> Content
    @StateObject private var hover = HoverModel()

    var body: some View {
        if let onTap {
            content(hover.isHovered)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(hover.isHovered ? 0.09 : 0)))
                .padding(.vertical, -6)            // the highlight reaches past the line; the layout doesn't change
                .contentShape(Rectangle())
                .onHover { hover.isHovered = $0 }
                .animation(.easeOut(duration: 0.18), value: hover.isHovered)
                .onTapGesture(perform: onTap)
        } else {
            content(false)
        }
    }
}

struct LyricLineView: View {
    let text: String
    let fontSize: CGFloat
    let rightToLeft: Bool
    /// Lines from the active one; nil before the first line starts.
    let distance: Int?
    var centered = false
    /// The pointer is over this (clickable) line: bring it into focus like the current one.
    var emphasized = false
    /// Romanized or translated version of `text` (Settings › General › Lyrics), shown underneath.
    var subtitle: String? = nil
    /// Set on the current line when sing-along is on: when its words are sung.
    var sweep: ClosedRange<TimeInterval>? = nil
    var position: () -> TimeInterval = { 0 }

    private var textAlignment: Alignment { centered ? .center : rightToLeft ? .trailing : .leading }

    var body: some View {
        VStack(alignment: centered ? .center : rightToLeft ? .trailing : .leading, spacing: fontSize * 0.16) {
            if let sweep, text != LyricsService.instrumentalMarker {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
                    // A per-word-colored, concatenated Text (for the sung highlight) can under-report
                    // its own wrapped height, so a plain, invisible Text of the same words reserves the
                    // real layout space underneath; the colored version is drawn on top of it, same
                    // font and wrapping, so it lines up exactly.
                    ZStack(alignment: textAlignment) {
                        styled(Text(text)).opacity(0)
                        styled(Self.sungText(text, progress: (position() - sweep.lowerBound)
                                                / (sweep.upperBound - sweep.lowerBound)))
                    }
                }
            } else {
                styled(Text(text))
            }
            if let subtitle {
                styledSubtitle(subtitle)
                    .transition(.opacity)
            }
        }
    }

    private func styledSubtitle(_ text: String) -> some View {
        let isCurrent = distance == 0
        let far = CGFloat(min(abs(distance ?? 1), 4))
        return Text(text)
            .font(.system(size: fontSize * 0.52, weight: .semibold).italic())
            .foregroundColor(.white.opacity(isCurrent ? 0.75 : emphasized ? 0.65 : max(0.1, 0.25 - (far - 1) * 0.04)))
            .multilineTextAlignment(centered ? .center : rightToLeft ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: centered ? .center : rightToLeft ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(2)
            .blur(radius: isCurrent || emphasized ? 0 : max(0, far - 1) * 0.8)
    }

    /// Each word brightens as the sweep passes it; longer words take longer.
    private static func sungText(_ text: String, progress: Double) -> Text {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let weights = words.map { Double(max($0.count, 2)) }
        let total = weights.reduce(0, +)
        var start = 0.0
        return words.enumerated().reduce(Text("")) { result, item in
            let (i, word) = item
            let length = weights[i] / total
            let lit = min(max((progress - start) / length, 0), 1)
            start += length
            let piece = Text(i < words.count - 1 ? word + " " : word)
                .foregroundColor(.white.opacity(0.32 + 0.68 * lit))
            return result + piece
        }
    }

    private func styled(_ content: Text) -> some View {
        let isCurrent = distance == 0
        let far = CGFloat(min(abs(distance ?? 1), 4))
        return content
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(.white)
            .multilineTextAlignment(centered ? .center : rightToLeft ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: centered ? .center : rightToLeft ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(isCurrent ? 1 : emphasized ? 0.92 : max(0.14, 0.34 - (far - 1) * 0.06))
            .blur(radius: isCurrent || emphasized ? 0 : max(0, far - 1) * 0.8)
    }
}

/// Apple Music–style moving background: overlapping copies of the blurred
/// artwork that slowly rotate and wander. Only transforms change per frame.
struct DriftingBackground: View {
    let image: NSImage
    let look: AppSettings.Look

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // Big enough that the rotating base layer always covers the corners.
            let side = max(w, h) * 1.8
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: look.backgroundSpeed == 0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate * look.backgroundSpeed
                ZStack {
                    layer(side: side, angle: t * 3, x: cos(t / 11) * w * 0.12, y: sin(t / 13) * h * 0.12)
                    layer(side: side * 0.75, angle: -t * 4 + 120, x: sin(t / 9) * w * 0.25, y: cos(t / 12) * h * 0.22)
                        .opacity(0.8)
                    layer(side: side * 0.55, angle: t * 6 + 240, x: cos(t / 7) * w * 0.3, y: sin(t / 10) * h * 0.28)
                        .opacity(0.65)
                }
                .frame(width: w, height: h)
                .drawingGroup()
            }
        }
        .clipped()
        .overlay(Color.black.opacity(look.backgroundDarkness))
        .ignoresSafeArea()
    }

    private func layer(side: CGFloat, angle: Double, x: CGFloat, y: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .mask(RadialGradient(colors: [.black, .black, .clear], center: .center, startRadius: 0, endRadius: side / 2))
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
    }
}

/// Shown when no song can be read: says what to do, so the app never just
/// looks broken (e.g. no player open, or Automation access declined).
struct NothingPlaying: View {
    let accessDenied: Bool
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 10 * scale) {
            Image(systemName: accessDenied ? "hand.raised.fill" : "music.note")
                .font(.system(size: 36 * scale))
            Text(accessDenied ? "Arioso can't see your music" : "Nothing playing")
                .font(.system(size: 17 * scale, weight: .semibold))
            Text(accessDenied
                 ? "Allow Arioso in System Settings › Privacy & Security › Automation."
                 : "Play a song in Spotify or Apple Music.")
                .font(.system(size: 12 * scale))
                .multilineTextAlignment(.center)
                .opacity(0.8)
        }
        .foregroundColor(.white.opacity(0.5))
        .padding(.horizontal, 24)
    }
}

/// The copyright line and credit Musixmatch's licence requires with lyrics.
struct LyricsAttribution: View {
    let credit: LyricsCredit?
    var fontSize: CGFloat = 10

    var body: some View {
        let parts = [credit?.copyright ?? "", "Lyrics powered by Musixmatch"].filter { !$0.isEmpty }
        Text(parts.joined(separator: " · "))
            .font(.system(size: fontSize))
            .foregroundColor(.white.opacity(0.4))
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }
}
