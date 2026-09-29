import SwiftUI

/// "Recently Played" desktop widget, on the same moving background as the
/// lyrics widget.
struct RecentlyPlayedView: View {
    @ObservedObject var model: LyricsSceneModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var history: RecentlyPlayed
    let size: CGSize
    private let cornerRadius: CGFloat = 36
    /// The title strip: the part of the widget that drags it, since the rows below take clicks.
    static let headerHeight: CGFloat = 70

    var body: some View {
        ZStack {

            VStack(alignment: .leading, spacing: 16) {
                Text("Recently Played")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(22)
        }
        .frame(width: size.width, height: size.height)
        .liquidGlass(settings.settings.liquidGlass, clarity: settings.settings.glassClarity, backdrop: model.backdrop, look: settings.settings.widgets, cornerRadius: cornerRadius)
    }

    @ViewBuilder
    private var content: some View {
        let tracks = history.previous
        if tracks.isEmpty {
            Text("Songs you play will show up here.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
        } else {
            GeometryReader { geo in
                // Only as many whole rows as fit; extra ones would be squeezed.
                let fitting = max(1, Int((geo.size.height + Self.rowSpacing) / (Self.rowHeight + Self.rowSpacing)))
                // Refreshes the "5m ago" labels once a minute.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: Self.rowSpacing) {
                        ForEach(Array(tracks.prefix(fitting).enumerated()), id: \.element.id) { index, track in
                            // Older songs fade out: full opacity at the top, ~15% at the bottom.
                            HistoryRow(track: track, artwork: history.artwork[track.id], now: context.date,
                                       rowHeight: Self.rowHeight,
                                       onPlay: playAction(for: track))
                                .opacity(1 - 0.85 * Double(index) / Double(max(fitting - 1, 1)))
                        }
                    }
                }
            }
        }
    }

    private static let rowHeight: CGFloat = 48
    private static let rowSpacing: CGFloat = 12

    /// Nil when it can't be played again: an older entry, demo mode, or the option is off.
    private func playAction(for track: PlayedTrack) -> (() -> Void)? {
        guard settings.settings.historyPlayAgain, !Demo.isOn, let url = track.url else { return nil }
        return { Playback.send(.play(ref: url), to: track.player) }
    }

    static func timeAgo(from date: Date, to now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return "Just now"
        case ..<60: return "\(minutes)m ago"
        case ..<(24 * 60): return "\(minutes / 60)h ago"
        case ..<(48 * 60): return "Yesterday"
        default: return "\(minutes / (24 * 60))d ago"
        }
    }
}

/// One song in the list. When it can be played again, the pointer lights it up and shows a play
/// icon where the time was; a click plays it in the app it came from.
private struct HistoryRow: View {
    let track: PlayedTrack
    let artwork: NSImage?
    let now: Date
    let rowHeight: CGFloat
    let onPlay: (() -> Void)?
    @StateObject private var hover = HoverModel()

    var body: some View {
        let hovered = hover.isHovered && onPlay != nil
        let content = HStack(spacing: 12) {
            Group {
                if let artwork {
                    Image(nsImage: artwork).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note").foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .frame(width: rowHeight, height: rowHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            .lineLimit(1)

            Spacer(minLength: 8)

            if hovered {
                Image(systemName: "play.fill").font(.system(size: 13)).foregroundColor(.white.opacity(0.9))
            } else {
                Text(RecentlyPlayedView.timeAgo(from: track.playedAt, to: now))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .frame(height: rowHeight)

        if let onPlay {
            content
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(hovered ? 0.09 : 0)))
                .padding(.horizontal, -8)
                .contentShape(Rectangle())
                .onHover { hover.isHovered = $0 }
                .animation(.easeOut(duration: 0.18), value: hovered)
                .onTapGesture(perform: onPlay)
                .accessibilityLabel("Play \(track.title) by \(track.artist) again")
        } else {
            content
        }
    }
}
