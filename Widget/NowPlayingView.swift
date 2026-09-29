import AppKit
import SwiftUI

// The player pieces: animated waves, the shuffle / previous / play / next / repeat
// row, and the compact pill that opens into a full player card. The same row also
// sits at the bottom of the lyrics widget.
//
// No @State anywhere: the Command Line Tools toolchain can't build it in this SDK
// (see LyricsSceneModel), so view state lives in small ObservableObjects instead.

// MARK: - Motion

enum Motion {
    /// macOS "Reduce motion": springs and slides become short fades.
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Opening and closing the player: a soft spring with a hint of settle.
    static var open: Animation? { reduced ? .easeInOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.82) }
    static var quick: Animation? { reduced ? nil : .easeOut(duration: 0.18) }
    /// A new song's cover and title fading in.
    static var swap: Animation? { reduced ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.34) }
}

/// Buttons dip a little under your finger and spring back.
struct PressableStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.88
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Play and pause morph into each other on macOS 14 and later, and crossfade before that.
private struct SymbolMorph: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.contentTransition(.symbolEffect(.replace))
        } else {
            content
        }
    }
}

// MARK: - Waves

enum WaveShape {
    static let bars = AudioLevels.bandCount

    static func rest(bar i: Int) -> CGFloat { [0.38, 0.72, 0.48, 0.62][i % 4] }

    /// 0.18…1 for each bar. Every bar has its own speed and phase, so the row never
    /// visibly repeats. This is the animated stand-in used when live audio isn't available.
    static func active(bar i: Int, time t: TimeInterval) -> CGFloat {
        let speed = 2.1 + Double(i) * 0.71
        let a = sin(t * speed + Double(i) * 1.7)
        let b = sin(t * speed * 0.53 + Double(i) * 0.9)
        return CGFloat(min(1, max(0.18, 0.5 + 0.32 * a + 0.18 * b)))
    }
}

/// Eases the waves in when a song starts and out when it stops, instead of snapping.
final class WaveEase: ObservableObject {
    /// True while the bars are moving or settling; the timeline stops once they're at rest.
    @Published private(set) var running = false
    private var from = 0.0
    private var target = 0.0
    private var changedAt = Date.distantPast
    private var settle: DispatchWorkItem?

    func set(playing: Bool) {
        let now = Date()
        from = energy(at: now)
        target = playing ? 1 : 0
        changedAt = now
        settle?.cancel()
        running = true
        if !playing {
            let work = DispatchWorkItem { [weak self] in self?.running = false }
            settle = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
        }
    }

    /// 0 = resting shape, 1 = fully moving.
    func energy(at date: Date) -> Double {
        let p = min(1, max(0, date.timeIntervalSince(changedAt) / 0.6))
        return from + (target - from) * (p * p * (3 - 2 * p))
    }
}

struct WaveBars: View {
    var playing: Bool
    var color: Color = .white
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2.5
    var maxHeight: CGFloat = 22
    @StateObject private var ease = WaveEase()
    /// When the music app's real audio is being measured the bars follow it; otherwise they animate.
    @ObservedObject private var audio = AudioLevels.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !(ease.running || audio.isLive))) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let energy = CGFloat(ease.energy(at: timeline.date))
            let live = audio.isLive ? audio.snapshot() : nil
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<WaveShape.bars, id: \.self) { i in
                    let level: CGFloat = live.map { 0.14 + 0.86 * CGFloat($0[i]) }
                        ?? (WaveShape.rest(bar: i) + (WaveShape.active(bar: i, time: t) - WaveShape.rest(bar: i)) * energy)
                    Capsule().fill(color).frame(width: barWidth, height: maxHeight * level)
                }
            }
            .frame(height: maxHeight)
        }
        .onAppear { ease.set(playing: playing) }
        .onChange(of: playing) { ease.set(playing: $0) }
        .accessibilityHidden(true)
    }
}

// MARK: - Cover

struct ArtView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note").foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Controls

/// Shuffle, previous, play/pause, next, repeat. Sends to whichever app is playing.
struct PlayerControls: View {
    @ObservedObject var model: LyricsSceneModel
    static let height: CGFloat = 48

    private func send(_ command: PlaybackCommand) {
        Playback.send(command, to: model.playerBundleID)
    }

    var body: some View {
        HStack(spacing: 0) {
            toggle("shuffle", on: model.shuffling, label: "Shuffle") { send(.toggleShuffle) }
            Spacer(minLength: 0)
            skip("backward.fill", label: "Previous") { send(.previous) }
            Spacer(minLength: 0)
            Button { send(.playPause) } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32))
                    .modifier(SymbolMorph())
                    .frame(width: 54, height: Self.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(pressedScale: 0.9))
            .animation(Motion.quick, value: model.isPlaying)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            Spacer(minLength: 0)
            skip("forward.fill", label: "Next") { send(.next) }
            Spacer(minLength: 0)
            toggle(model.repeatMode == .one ? "repeat.1" : "repeat", on: model.repeatMode != .off, label: "Repeat") {
                send(.toggleRepeat(from: model.repeatMode))
            }
        }
        .foregroundColor(.white.opacity(0.88))
        .frame(height: Self.height)
    }

    private func skip(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 23))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    /// Lit up (a soft circle and a dot underneath) while it's switched on.
    private func toggle(_ symbol: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white.opacity(0.18))
                    .scaleEffect(on ? 1 : 0.55).opacity(on ? 1 : 0)
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Circle().fill(Color.white.opacity(0.9)).frame(width: 4, height: 4).offset(y: 12)
                    .scaleEffect(on ? 1 : 0.2).opacity(on ? 1 : 0)
            }
            .frame(width: 40, height: 40)
            .contentShape(Circle())
            .animation(Motion.quick, value: on)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
    }
}

// MARK: - Progress with seeking

final class ShareToast: ObservableObject {
    @Published var message: String?
    func show(_ text: String) {
        message = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.message = nil }
    }
}

final class ScrubState: ObservableObject {
    /// Where the finger is while dragging the bar; nil the rest of the time.
    @Published var fraction: Double?
}

private struct SeekBar: View {
    let fraction: Double
    let enabled: Bool
    /// Glide between the half-second updates; not while dragging, so the bar follows the pointer.
    let glide: Bool
    let onDrag: (Double) -> Void
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule().fill(Color.white.opacity(0.9)).frame(width: width * CGFloat(min(max(fraction, 0), 1)))
                    .animation(glide && !Motion.reduced ? .linear(duration: 0.5) : nil, value: fraction)
            }
            .frame(height: 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { if enabled { onDrag(min(max(Double($0.location.x / width), 0), 1)) } }
                .onEnded { if enabled { onCommit(min(max(Double($0.location.x / width), 0), 1)) } })
        }
        .frame(height: 18)
    }
}

// MARK: - The pill and the card

private func clock(_ seconds: TimeInterval) -> String {
    let t = max(0, Int(seconds))
    return String(format: "%d:%02d", t / 60, t % 60)
}

/// Changes when the song (or its cover) does; the cover and title fade to the new ones.
private func trackKey(_ info: NowPlayingInfo?) -> String {
    guard let info else { return "" }
    return "\(info.artist)::\(info.title)"
}
private func artKey(_ info: NowPlayingInfo?) -> String {
    trackKey(info) + "#" + (info?.artwork.map { "\(ObjectIdentifier($0).hashValue)" } ?? "none")
}

struct NowPlayingPill: View {
    @ObservedObject var model: LyricsSceneModel
    var showWaves = true
    /// Multiplier from the Cover size slider.
    var coverSize: CGFloat = 1
    static func size(cover: CGFloat) -> CGSize { CGSize(width: 360, height: 44 * cover + 20) }

    var body: some View {
        HStack(spacing: 12) {
            ArtView(image: model.nowPlaying?.artwork, size: 44 * coverSize, radius: 12 * coverSize)
                .id(artKey(model.nowPlaying))
                .transition(.opacity)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.nowPlaying?.title ?? "")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Text(model.nowPlaying?.artist ?? "")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
            }
            .lineLimit(1)
            .id(trackKey(model.nowPlaying))
            .transition(.opacity)
            Spacer(minLength: 8)
            if showWaves { WaveBars(playing: model.isPlaying, color: .white.opacity(0.6), maxHeight: 26) }
        }
        .animation(Motion.swap, value: artKey(model.nowPlaying))
        .padding(.horizontal, 16)
        .frame(width: Self.size(cover: coverSize).width, height: Self.size(cover: coverSize).height)
    }
}

struct NowPlayingCard: View {
    @ObservedObject var model: LyricsSceneModel
    /// Set in the desktop widget: tapping the top row folds the card back into the pill.
    var onCollapse: (() -> Void)?
    var onLyrics: () -> Void
    var showWaves = true
    var coverSize: CGFloat = 1
    @StateObject private var scrub = ScrubState()
    @StateObject private var toast = ShareToast()

    static func size(cover: CGFloat) -> CGSize { CGSize(width: 360, height: 236 + 64 * (cover - 1)) }

    var body: some View {
        VStack(spacing: 10) {
            if let onCollapse {
                Button(action: onCollapse) { header }
                    .buttonStyle(PressableStyle(pressedScale: 0.98)).accessibilityLabel("Collapse player")
            } else {
                header
            }
            progress
            PlayerControls(model: model)
            HStack {
                smallButton("text.quote", "Full-screen lyrics", onLyrics)
                Spacer()
                if let message = toast.message {
                    Text(message).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.65))
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                smallButton("square.and.arrow.up", "Share current line", share)
            }
            .frame(height: 22)
            .animation(Motion.quick, value: toast.message)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .frame(width: Self.size(cover: coverSize).width, height: Self.size(cover: coverSize).height)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ArtView(image: model.nowPlaying?.artwork, size: 64 * coverSize, radius: 18 * coverSize)
                .id(artKey(model.nowPlaying))
                .transition(.opacity)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.nowPlaying?.title ?? "Nothing playing")
                    .font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                Text(model.nowPlaying?.artist ?? "")
                    .font(.system(size: 15)).foregroundColor(.white.opacity(0.6))
            }
            .lineLimit(1)
            .id(trackKey(model.nowPlaying))
            .transition(.opacity)
            Spacer(minLength: 8)
            if showWaves { WaveBars(playing: model.isPlaying, color: .white.opacity(0.6), maxHeight: 32) }
        }
        .animation(Motion.swap, value: artKey(model.nowPlaying))
        .contentShape(Rectangle())
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let duration = model.nowPlaying?.duration ?? 0
            let fraction = scrub.fraction ?? (duration > 0 ? min(max(model.position / duration, 0), 1) : 0)
            HStack(spacing: 10) {
                Text(clock(fraction * duration)).frame(width: 38, alignment: .leading)
                SeekBar(fraction: fraction, enabled: duration > 0, glide: scrub.fraction == nil,
                        onDrag: { scrub.fraction = $0 },
                        onCommit: { value in
                            scrub.fraction = nil
                            Playback.send(.seek(value * duration), to: model.playerBundleID)
                        })
                Text("-" + clock(duration - fraction * duration)).frame(width: 42, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundColor(.white.opacity(0.65))
        }
    }

    /// A square card of the line on screen: copied and saved to Pictures › Arioso.
    private func share() {
        guard let image = ShareCard.generate(from: model) else { toast.show("Nothing to share"); return }
        toast.show(ShareCard.share(image) != nil ? "Copied — saved to Pictures" : "Copied to clipboard")
    }

    private func smallButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 34, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.85))
        .accessibilityLabel(label)
    }
}

// MARK: - Desktop widget content

final class NowPlayingPanelState: ObservableObject {
    @Published var expanded = false
}

/// Docked to the bottom edge of the screen, like a Now Playing tab: rounded on top and running
/// off the bottom. Frosted grey unless "Album colors" is on in Settings › Player.
///
/// The glass always fills the window, and NowPlayingWidget animates the window's frame, so the
/// shape's size has one source. Here the pill and card just crossfade inside it, both anchored
/// to the top, and the corners soften as it opens.
struct NowPlayingWidgetView: View {
    @ObservedObject var model: LyricsSceneModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var state: NowPlayingPanelState
    let onLyrics: () -> Void

    var body: some View {
        let s = settings.settings
        let expanded = state.expanded
        let scale = CGFloat(s.playerScale)
        let cover = CGFloat(s.playerLook.coverSize)
        let pill = NowPlayingPill.size(cover: cover)
        let card = NowPlayingCard.size(cover: cover)
        let calm = Motion.reduced
        // The glass is a flexible view that takes exactly the window's size; the pill and card sit on
        // top of it as an overlay, so their own size can never push the window or the shape around.
        Color.clear
            .liquidGlass(s.playerLiquidGlass, clarity: s.playerGlassClarity,
                         backdrop: s.playerAlbumColors ? model.backdrop : nil,
                         look: s.playerLook, cornerRadius: (expanded ? 46 : 34) * scale)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    Button { withAnimation(Motion.open) { state.expanded = true } } label: {
                        NowPlayingPill(model: model, showWaves: s.playerWaves, coverSize: cover)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(pressedScale: 0.97))
                    .accessibilityLabel("Open player")
                    .frame(width: pill.width, height: pill.height)
                    .opacity(expanded ? 0 : 1)
                    .allowsHitTesting(!expanded)
                    .animation(.easeOut(duration: expanded ? 0.16 : 0.2).delay(expanded ? 0 : 0.1), value: expanded)

                    NowPlayingCard(model: model,
                                   onCollapse: { withAnimation(Motion.open) { state.expanded = false } },
                                   onLyrics: onLyrics, showWaves: s.playerWaves, coverSize: cover)
                        .frame(width: card.width, height: card.height)
                        .opacity(expanded ? 1 : 0)
                        .offset(y: expanded || calm ? 0 : 8)
                        .allowsHitTesting(expanded)
                        .animation(.easeOut(duration: expanded ? 0.26 : 0.12).delay(expanded ? 0.07 : 0), value: expanded)
                }
                .frame(width: card.width, height: card.height, alignment: .top)
                // Laid out at regular size, then scaled by the Size slider.
                .scaleEffect(scale, anchor: .top)
                .frame(width: card.width * scale, height: card.height * scale, alignment: .top)
            }
            .animation(calm ? nil : .easeInOut(duration: 0.4), value: expanded)
    }
}

/// A hosting view that also takes the click that first brings the window forward:
/// Arioso is a background app, so its windows are never active when you click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
