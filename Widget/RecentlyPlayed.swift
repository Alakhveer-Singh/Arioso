import AppKit

struct PlayedTrack: Codable, Identifiable {
    let title: String
    let artist: String
    var playedAt: Date
    /// Spotify link or Apple Music ID, and which app: what it takes to play it again.
    /// Songs saved before this existed have neither, and just aren't clickable.
    var url: String? = nil
    var player: String? = nil

    var id: String { ArtworkService.key(artist: artist, title: title) }
}

/// Local play history, built from the Now Playing updates the lyrics widget
/// already receives, and saved between launches.
final class RecentlyPlayed: ObservableObject {
    /// Newest first; the song playing now is included at the top.
    @Published private(set) var tracks: [PlayedTrack] = []
    @Published private(set) var artwork: [String: NSImage] = [:]
    @Published private(set) var currentID: String?

    private let maxTracks = 30
    private let file = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Arioso/recently_played.json")

    /// Songs played before the current one.
    var previous: [PlayedTrack] { tracks.filter { $0.id != currentID } }

    /// Demo mode: made-up songs with drawn covers, never saved.
    init(demo: [(title: String, artist: String, artwork: NSImage)]) {
        let now = Date()
        tracks = demo.enumerated().map { i, song in
            PlayedTrack(title: song.title, artist: song.artist, playedAt: now.addingTimeInterval(Double(-i) * 260))
        }
        for (track, song) in zip(tracks, demo) { artwork[track.id] = song.artwork }
        currentID = tracks.first?.id
        isDemo = true
    }

    private var isDemo = false

    init() {
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([PlayedTrack].self, from: data) {
            tracks = saved
        }
        tracks.forEach(loadArtwork)
    }

    /// Spotify ads are 15–30 s long, real songs almost never under 40 s.
    private let minimumSongDuration: TimeInterval = 40

    func trackStarted(title: String, artist: String, duration: TimeInterval, url: String? = nil, player: String? = nil) {
        let track = PlayedTrack(title: title, artist: artist, playedAt: Date(), url: url, player: player)
        guard track.id != currentID else { return }
        currentID = track.id
        // Unknown duration (0) is kept; a short known one is an ad.
        guard !isDemo, duration == 0 || duration >= minimumSongDuration else { return }
        tracks.removeAll { $0.id == track.id }
        tracks.insert(track, at: 0)
        tracks = Array(tracks.prefix(maxTracks))
        save()
        loadArtwork(track)
    }

    private func loadArtwork(_ track: PlayedTrack) {
        ArtworkService.shared.fetch(artist: track.artist, title: track.title) { [weak self] image in
            self?.artwork[track.id] = image
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file)
    }
}
