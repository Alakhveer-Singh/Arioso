import AppKit

struct NowPlayingInfo {
    var title: String
    var artist: String
    var album: String
    var artwork: NSImage?
    var duration: TimeInterval
    /// Position at `timestamp` — a snapshot, not a live value.
    var elapsedTime: TimeInterval
    var timestamp: Date
    var playbackRate: Double
    /// Which app is playing it (Spotify or Apple Music), so the player buttons reach the right one.
    var playerBundleID: String?
    var shuffling = false
    var repeatMode: RepeatMode = .off
    /// Spotify's link to the song, or Apple Music's ID for it: lets Recently Played play it again.
    var trackURL: String?

    var estimatedElapsed: TimeInterval {
        let position = elapsedTime + Date().timeIntervalSince(timestamp) * playbackRate
        return duration > 0 ? min(max(position, 0), duration) : max(position, 0)
    }
}

enum RepeatMode {
    case off, all, one
    /// Apple Music's order: off, then all, then one, then off again.
    var next: RepeatMode { self == .off ? .all : (self == .all ? .one : .off) }
}

enum PlaybackCommand {
    case playPause, next, previous
    case seek(TimeInterval)
    case toggleShuffle
    /// Carries the current mode, because Apple Music steps through three states.
    case toggleRepeat(from: RepeatMode)
    /// Plays a song from Recently Played: a Spotify link, or an Apple Music library ID.
    case play(ref: String)
}

/// Where the player buttons send their commands: the one monitor the app runs.
enum Playback {
    static weak var monitor: PlayerMonitor?
    static func send(_ command: PlaybackCommand, to bundleID: String?) {
        guard let bundleID else { return }   // demo mode has no real player
        monitor?.send(command, to: bundleID)
    }
}

/// Reads what Spotify or Apple Music is playing through their public
/// AppleScript interfaces: the App Store–safe route (no private frameworks,
/// no helper processes). macOS asks the user once per player for permission
/// (Privacy & Security › Automation). A player is only asked while it's
/// already running, so Arioso never launches it.
final class PlayerMonitor {
    var onChange: ((NowPlayingInfo?) -> Void)?
    /// Only follow Spotify; when off, Apple Music is followed too.
    var spotifyOnly = true
    /// Players the user declined Automation access for. Written on the
    /// polling queue, read on the main thread.
    var deniedPlayers: Set<String> { lock.lock(); defer { lock.unlock() }; return denied }
    private var denied: Set<String> = []
    private let lock = NSLock()

    private var timer: Timer?
    private var artworkRequested: Set<String> = []
    /// Each query takes ~30 ms; running them here keeps the main thread (and
    /// every animation) free. Scripts are only ever used on this queue.
    private let queue = DispatchQueue(label: "com.alakhveer.Arioso.PlayerMonitor", qos: .userInitiated)
    private var polling = false

    private enum Player: CaseIterable {
        case spotify, music

        var bundleID: String {
            switch self {
            case .spotify: return AppSettings.spotifyBundleID
            case .music: return AppSettings.musicBundleID
            }
        }

        /// Returns {state, title, artist, album, duration (s), position (s), artwork URL,
        /// shuffle, repeat} or an empty list when nothing is loaded.
        var source: String {
            switch self {
            case .spotify: return """
                tell application id "com.spotify.client"
                    with timeout of 2 seconds
                        if player state is stopped then return {}
                        set t to current track
                        -- Shuffle and repeat are extras: never let them break reading the song.
                        set sh to "false"
                        set rp to "false"
                        try
                            set sh to shuffling as text
                            set rp to repeating as text
                        end try
                        set u to ""
                        try
                            set u to spotify url of t
                        end try
                        return {player state as text, name of t, artist of t, album of t, ¬
                            (duration of t) / 1000, player position, artwork url of t, sh, rp, u}
                    end timeout
                end tell
                """
            case .music: return """
                tell application id "com.apple.Music"
                    with timeout of 2 seconds
                        if player state is stopped then return {}
                        set t to current track
                        -- Shuffle and repeat are extras: never let them break reading the song.
                        set sh to "false"
                        set rp to "off"
                        try
                            set sh to shuffle enabled as text
                            set rp to song repeat as text
                        end try
                        set u to ""
                        try
                            set u to (persistent ID of t) as text
                        end try
                        return {player state as text, name of t, artist of t, album of t, ¬
                            duration of t, player position, "", sh, rp, u}
                    end timeout
                end tell
                """
            }
        }
    }

    private lazy var scripts: [Player: NSAppleScript] = Dictionary(uniqueKeysWithValues:
        Player.allCases.compactMap { player in NSAppleScript(source: player.source).map { (player, $0) } })

    private static let musicArtworkScript = NSAppleScript(source: """
        tell application id "com.apple.Music"
            with timeout of 3 seconds
                try
                    return raw data of artwork 1 of current track
                end try
            end timeout
        end tell
        """)

    func start() {
        poll()
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard !polling else { return }
        polling = true
        let spotifyOnly = spotifyOnly
        queue.async { [weak self] in
            self?.pollOnQueue(spotifyOnly: spotifyOnly)
            DispatchQueue.main.async { self?.polling = false }
        }
    }

    private func pollOnQueue(spotifyOnly: Bool) {
        let players: [Player] = spotifyOnly ? [.spotify] : [.spotify, .music]
        var paused: (NowPlayingInfo, Player, String)?
        for player in players where isRunning(player) {
            guard let (info, artworkURL) = read(player) else { continue }
            if info.playbackRate > 0 { return emit(info, from: player, artworkURL: artworkURL) }
            if paused == nil { paused = (info, player, artworkURL) }
        }
        if let (info, player, artworkURL) = paused {
            emit(info, from: player, artworkURL: artworkURL)
        } else {
            DispatchQueue.main.async { self.onChange?(nil) }
        }
    }

    /// Play/pause, skip and seek for the player buttons. Same Automation permission as reading.
    func send(_ command: PlaybackCommand, to bundleID: String) {
        // Only ever our own two players, never a string from outside, and never launching one.
        guard bundleID == AppSettings.spotifyBundleID || bundleID == AppSettings.musicBundleID,
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return }
        let action: String
        switch command {
        case .playPause: action = "playpause"
        case .next: action = "next track"
        case .previous: action = "previous track"
        case .seek(let seconds): action = String(format: "set player position to %.1f", max(0, seconds))
        case .play(let ref):
            // The saved link goes into a script, so it must be exactly what we expect.
            if bundleID == AppSettings.spotifyBundleID {
                guard ref.range(of: #"^spotify:(track|episode):[A-Za-z0-9]{10,32}$"#, options: .regularExpression) != nil else { return }
                action = "play track \"\(ref)\""
            } else {
                guard ref.range(of: #"^[0-9A-Fa-f]{16}$"#, options: .regularExpression) != nil else { return }
                action = "play (first track of library playlist 1 whose persistent ID is \"\(ref)\")"
            }
        case .toggleShuffle:
            action = bundleID == AppSettings.spotifyBundleID
                ? "set shuffling to not shuffling" : "set shuffle enabled to not shuffle enabled"
        case .toggleRepeat(let mode):
            switch (bundleID == AppSettings.spotifyBundleID, mode.next) {
            case (true, _): action = "set repeating to not repeating"
            case (false, .off): action = "set song repeat to off"
            case (false, .all): action = "set song repeat to all"
            case (false, .one): action = "set song repeat to one"
            }
        }
        queue.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: "tell application id \"\(bundleID)\" to \(action)")?.executeAndReturnError(&error)
            // Show the result now instead of waiting for the next one-second poll.
            DispatchQueue.main.async { self?.poll() }
        }
    }

    private func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    private func read(_ player: Player) -> (NowPlayingInfo, String)? {
        guard let script = scripts[player] else { return nil }
        var error: NSDictionary?
        let started = Date()
        let result = script.executeAndReturnError(&error)
        // The position was read somewhere during the call; its midpoint is the best guess.
        let readAt = started.addingTimeInterval(Date().timeIntervalSince(started) / 2)
        if let code = error?[NSAppleScript.errorNumber] as? Int {
            // -1743: the user said no to Automation access.
            if code == -1743 { lock.lock(); denied.insert(player.bundleID); lock.unlock() }
            return nil
        }
        lock.lock(); denied.remove(player.bundleID); lock.unlock()
        guard result.numberOfItems >= 6 else { return nil }
        func text(_ i: Int) -> String { result.atIndex(i)?.stringValue ?? "" }
        func number(_ i: Int) -> Double { result.atIndex(i)?.doubleValue ?? 0 }
        let title = text(2)
        guard !title.isEmpty else { return nil }
        let info = NowPlayingInfo(
            title: title, artist: text(3), album: text(4), artwork: nil,
            duration: number(5), elapsedTime: number(6), timestamp: readAt,
            playbackRate: text(1) == "playing" ? 1 : 0, playerBundleID: player.bundleID)
        var full = info
        if result.numberOfItems >= 10 {
            let link = text(10)
            full.trackURL = link.isEmpty ? nil : link
        }
        if result.numberOfItems >= 9 {
            full.shuffling = text(8) == "true"
            switch (player, text(9)) {
            case (.spotify, "true"), (.music, "all"): full.repeatMode = .all
            case (.music, "one"): full.repeatMode = .one
            default: full.repeatMode = .off
            }
        }
        return (full, result.numberOfItems >= 7 ? text(7) : "")
    }

    private func emit(_ info: NowPlayingInfo, from player: Player, artworkURL: String) {
        var artworkData: Data?
        if player == .music, !artworkRequested.contains(ArtworkService.key(artist: info.artist, title: info.title)) {
            var error: NSDictionary?
            artworkData = Self.musicArtworkScript?.executeAndReturnError(&error).data
        }
        DispatchQueue.main.async {
            var info = info
            info.artwork = ArtworkService.shared.cached(artist: info.artist, title: info.title)
            if info.artwork == nil { self.requestArtwork(for: info, from: player, url: artworkURL, musicData: artworkData) }
            self.onChange?(info)
        }
    }

    /// Fetches the cover once per song; the next poll picks it up from the cache.
    private func requestArtwork(for info: NowPlayingInfo, from player: Player, url: String, musicData: Data?) {
        let key = ArtworkService.key(artist: info.artist, title: info.title)
        guard artworkRequested.insert(key).inserted else { return }
        switch player {
        case .spotify:
            ArtworkService.shared.download(from: url, artist: info.artist, title: info.title)
        case .music:
            if let musicData, let image = NSImage(data: musicData) {
                ArtworkService.shared.store(image, artist: info.artist, title: info.title)
            }
        }
    }
}
