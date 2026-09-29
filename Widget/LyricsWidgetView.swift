import SwiftUI

/// Full-height desktop widget: cover, progress and title on top, live lyrics
/// below, on the same moving artwork background as the full-screen view.
struct LyricsWidgetView: View {
    @ObservedObject var model: LyricsSceneModel
    @ObservedObject var settings: SettingsStore
    /// 350 wide like a macOS large widget; the height fills the screen.
    let size: CGSize
    /// Told where the cover area ends, so only that part drags the window (see HitRegions).
    var regions: HitRegions? = nil
    private let cornerRadius: CGFloat = 36
    private static let horizontalPadding: CGFloat = 22
    /// The controls row plus the padding under it (12), from the window's bottom edge.
    static let controlsHeight: CGFloat = PlayerControls.height + 12
    /// Cover, progress bar and title span the full inner width.
    private var contentWidth: CGFloat { size.width - Self.horizontalPadding * 2 }
    /// The cover follows the width but never takes more than ~40% of the height.
    private var coverSize: CGFloat { max(80, min(contentWidth, size.height * 0.4 * settings.settings.widgets.coverSize)) }

    var body: some View {
        ZStack {
            // Invisible; mounted once here (this view stays alive for the app's lifetime) so a
            // TranslationSession is always ready when "Translate" needs one. See LyricTranslation.swift.
            if #available(macOS 15.0, *) { TranslationHost() }

            if let np = model.nowPlaying {
                VStack(spacing: 8) {
                    VStack(spacing: 0) {
                        GlowingCover(artwork: np.artwork, glow: settings.settings.widgets.coverGlow ? model.glow : nil, size: coverSize)
                        PlaybackProgress(elapsedSeconds: model.elapsedSeconds, duration: np.duration, width: contentWidth, fontSize: 10)
                            .padding(.top, 14)
                        VStack(spacing: 2) {
                            Text(np.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Text(np.artist)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .lineLimit(1)
                        .frame(width: contentWidth)
                        .padding(.top, 10)
                    }
                    .background(GeometryReader { header in
                        Color.clear.preference(key: HeaderBottomKey.self,
                                               value: header.frame(in: .named("lyricsWidget")).maxY + 8)
                    })
                    LyricsContent(model: model, fontSize: 23 * settings.settings.widgets.lyricsSize, focusPosition: 0.3,
                                  singAlong: settings.settings.widgets.singAlong,
                                  onSelectLine: settings.settings.lyricsTapToJump ? { time in
                                      // A little before the line, so its first word isn't clipped.
                                      Playback.send(.seek(max(0, time - 0.2)), to: model.playerBundleID)
                                  } : nil)
                        // Clickable lines inset their text by 10 pt (see TappableLine); widen to match.
                        .padding(.horizontal, settings.settings.lyricsTapToJump ? -10 : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.lyricsCredit != nil {
                        LyricsAttribution(credit: model.lyricsCredit, fontSize: 9)
                            .frame(width: contentWidth)
                    }
                    // Shuffle, previous, play/pause, next, repeat. WidgetsController lets clicks
                    // through to this area (see `controlsHeight`).
                    if settings.settings.lyricsWidgetControls {
                        PlayerControls(model: model)
                            .frame(width: contentWidth)
                    }
                }
                .padding(.top, Self.horizontalPadding)
                .padding(.bottom, 12)
                .padding(.horizontal, Self.horizontalPadding)
            } else {
                NothingPlaying(accessDenied: model.accessDenied)
            }
        }
        .coordinateSpace(name: "lyricsWidget")
        .onPreferenceChange(HeaderBottomKey.self) { regions?.header = $0 }
        .frame(width: size.width, height: size.height)
        .liquidGlass(settings.settings.liquidGlass, clarity: settings.settings.glassClarity, backdrop: model.backdrop, look: settings.settings.widgets, cornerRadius: cornerRadius)
    }
}

private struct HeaderBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
