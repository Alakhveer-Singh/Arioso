import Foundation

/// Everything the user can change, stored as one JSON entry in the app's own
/// (sandboxed) preferences. Arioso is a single process, so the Settings
/// window, the widgets and full-screen lyrics all share
/// `SettingsStore.shared`.
///
/// Some names predate the App Store version: `lockScreen`, `lockScene` and
/// `lockShortcutEnabled` now describe the full-screen lyrics view (⌥⌘L).
/// They keep their names so existing settings still decode.
struct AppSettings: Codable, Equatable {
    struct Look: Codable, Equatable {
        /// Drift speed of the moving background; 0 keeps it still.
        var backgroundSpeed: Double = 4
        /// Opacity of the black layer over the background (0.3–0.9).
        var backgroundDarkness: Double = 0.7
        var coverGlow = true
        /// Multiplier on the lyric text size.
        var lyricsSize: Double = 1
        /// Optional so settings saved before this existed still decode.
        private var coverSizeSetting: Double?
        /// Multiplier on the album cover size.
        var coverSize: Double {
            get { coverSizeSetting ?? 1 }
            set { coverSizeSetting = newValue }
        }
        /// The player's starting look: light enough to read as frosted grey.
        static var player: Look {
            var look = Look()
            look.backgroundDarkness = 0.3
            return look
        }
        private var singAlongSetting: Bool?
        /// Words of the current line light up one by one as it's sung.
        var singAlong: Bool {
            get { singAlongSetting ?? true }
            set { singAlongSetting = newValue }
        }
    }

    /// Follow only Spotify; off follows Apple Music too.
    var spotifyOnly = true
    /// ⌥⌘L opens full-screen lyrics.
    var lockShortcutEnabled = true
    /// Look of the full-screen lyrics view.
    var lockScreen = Look()
    var widgets = Look()
    var showLyricsWidget = true
    var showRecentlyPlayed = true
    private var historyPlayAgainSetting: Bool?
    /// Click a song in Recently Played to play it again. (The widget then drags by its title.)
    var historyPlayAgain: Bool {
        get { historyPlayAgainSetting ?? true }
        set { historyPlayAgainSetting = newValue }
    }
    private var lyricsTapSetting: Bool?
    /// Click a line in the Lyrics widget to jump the song there. (The widget then drags by its
    /// cover area, since the lyrics below need the clicks.)
    var lyricsTapToJump: Bool {
        get { lyricsTapSetting ?? true }
        set { lyricsTapSetting = newValue }
    }
    /// Optional so settings saved before this existed still decode.
    private var liquidGlassSetting: Bool?
    private var glassClaritySetting: Double?
    private var lockSceneSetting: String?
    private var enabledSetting: Bool?
    private var shuffleSetting: Bool?
    /// Scene used by the full-screen lyrics view (never .shuffle: shuffling
    /// is its own switch, below).
    var lockScene: LockScene {
        get { lockSceneSetting.flatMap(LockScene.init).flatMap { $0 == .shuffle ? nil : $0 } ?? .classic }
        set { lockSceneSetting = newValue.rawValue }
    }
    /// A different scene for each song. Older settings stored this as the
    /// "shuffle" scene.
    var shuffleScenes: Bool {
        get { shuffleSetting ?? (lockSceneSetting == LockScene.shuffle.rawValue) }
        set { shuffleSetting = newValue }
    }
    /// What the full-screen view should actually draw.
    var effectiveScene: LockScene { shuffleScenes ? .shuffle : lockScene }
    /// 0 = frosted and tinted by the album art, 1 = clear glass.
    var glassClarity: Double {
        get { glassClaritySetting ?? 0.5 }
        set { glassClaritySetting = newValue }
    }
    private var waveSensitivitySetting: Double?
    /// How strongly the live waves react: low is calm, high jumps with every beat.
    var waveSensitivity: Double {
        get { waveSensitivitySetting ?? 0.5 }
        set { waveSensitivitySetting = newValue }
    }
    private var playerLiveWavesSetting: Bool?
    /// The waves follow the music app's real audio (macOS 14.2 and later, with permission)
    /// instead of animating on their own.
    var playerLiveWaves: Bool {
        get { playerLiveWavesSetting ?? true }
        set { playerLiveWavesSetting = newValue }
    }
    private var playerFloatsSetting: Bool?
    /// The player floats above every app's windows; off keeps it on the desktop like the other widgets.
    var playerFloats: Bool {
        get { playerFloatsSetting ?? true }
        set { playerFloatsSetting = newValue }
    }
    private var playerScaleSetting: Double?
    /// Size of the player at the bottom of the screen; 1 is the regular size.
    var playerScale: Double {
        get { playerScaleSetting ?? 0.8 }
        set { playerScaleSetting = newValue }
    }
    private var playerGlassSetting: Bool?
    var playerLiquidGlass: Bool {
        get { playerGlassSetting ?? true }
        set { playerGlassSetting = newValue }
    }
    private var playerClaritySetting: Double?
    /// 0 = frosted, 1 = clear glass.
    var playerGlassClarity: Double {
        get { playerClaritySetting ?? 0.4 }
        set { playerClaritySetting = newValue }
    }
    private var playerLookSetting: Look?
    /// Motion, darkness and cover size of the player. Lighter than the widgets, so it reads as frosted grey.
    var playerLook: Look {
        get { playerLookSetting ?? .player }
        set { playerLookSetting = newValue }
    }
    private var playerColorsSetting: Bool?
    /// Tints the glass with the song's colours. Off by default: the player stays neutral grey.
    var playerAlbumColors: Bool {
        get { playerColorsSetting ?? false }
        set { playerColorsSetting = newValue }
    }
    private var playerWavesSetting: Bool?
    /// The bars beside the song move while it plays.
    var playerWaves: Bool {
        get { playerWavesSetting ?? true }
        set { playerWavesSetting = newValue }
    }
    private var lyricsControlsSetting: Bool?
    /// Shuffle, previous, play/pause, next and repeat at the bottom of the lyrics widget.
    var lyricsWidgetControls: Bool {
        get { lyricsControlsSetting ?? true }
        set { lyricsControlsSetting = newValue }
    }
    private var nowPlayingSetting: Bool?
    /// The compact player at the bottom of the desktop; click it for the full player.
    var showNowPlaying: Bool {
        get { nowPlayingSetting ?? true }
        set { nowPlayingSetting = newValue }
    }
    var liquidGlass: Bool {
        get { liquidGlassSetting ?? true }
        set { liquidGlassSetting = newValue }
    }
    /// Master switch: off hides the widgets and turns off ⌥⌘L.
    var isEnabled: Bool {
        get { enabledSetting ?? true }
        set { enabledSetting = newValue }
    }
    private var reframeShortcutSetting: Bool?
    /// ⌘⇧L: fits the front app's windows between the widgets. Needs
    /// Accessibility permission and only works in non-sandboxed builds.
    var reframeShortcutEnabled: Bool {
        get { reframeShortcutSetting ?? true }
        set { reframeShortcutSetting = newValue }
    }
    private var lyricSubtitleSetting: LyricSubtitle?
    /// A second line under each lyric: off, sounded out in Latin letters, or translated.
    var lyricSubtitle: LyricSubtitle {
        get { lyricSubtitleSetting ?? .off }
        set { lyricSubtitleSetting = newValue }
    }
    private var translationLanguageSetting: String?
    /// BCP-47 language the "Translate" subtitle is translated into.
    var translationLanguage: String {
        get { translationLanguageSetting ?? Locale.current.language.languageCode?.identifier ?? "en" }
        set { translationLanguageSetting = newValue }
    }

    static let spotifyBundleID = "com.spotify.client"
    static let musicBundleID = "com.apple.Music"
    static let changedNotification = Notification.Name("com.alakhveer.Arioso.settingsChanged")
    static let resetPositionsNotification = Notification.Name("com.alakhveer.Arioso.resetWidgetPositions")
    static let saveLayoutNotification = Notification.Name("com.alakhveer.Arioso.saveWidgetLayout")
    static let originalLayoutNotification = Notification.Name("com.alakhveer.Arioso.originalWidgetLayout")
    static let openSettingsNotification = Notification.Name("com.alakhveer.Arioso.openSettings")
    static let reframeNotification = Notification.Name("com.alakhveer.Arioso.reframeWindows")
    private static let key = "settings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }
}

/// The one live copy of the settings. Every change is saved at once; changes
/// saved elsewhere flow back in.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: AppSettings {
        didSet { if settings != oldValue { settings.save() } }
    }

    private init() {
        settings = AppSettings.load()
        NotificationCenter.default.addObserver(
            forName: AppSettings.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            let latest = AppSettings.load()
            if self?.settings != latest { self?.settings = latest }
        }
    }
}


/// A second line shown under each lyric.
enum LyricSubtitle: String, Codable, CaseIterable, Identifiable {
    case off, romanized, translated
    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .romanized: return "Romanize"
        case .translated: return "Translate"
        }
    }

    var detail: String {
        switch self {
        case .off: return "Just the lyrics, as they're licensed."
        case .romanized: return "Non-Latin scripts (Punjabi, Hindi, Japanese, Korean, Arabic…) sounded out in Latin letters, entirely on your Mac."
        case .translated: return "Every line translated on your Mac, with Apple's Translation. Nothing is sent anywhere."
        }
    }
}

/// A language "Translate" can target, and Apple Translation's identifier for it.
struct TranslationLanguage: Identifiable {
    let code: String
    let name: String
    var id: String { code }

    /// Common languages people ask Arioso's lyrics to be translated into.
    static let common: [TranslationLanguage] = [
        ("en", "English"), ("es", "Spanish"), ("pt", "Portuguese"), ("fr", "French"), ("de", "German"),
        ("hi", "Hindi"), ("ur", "Urdu"), ("ar", "Arabic"), ("tr", "Turkish"), ("id", "Indonesian"),
        ("ja", "Japanese"), ("ko", "Korean"), ("zh-Hans", "Chinese (Simplified)"), ("ru", "Russian"), ("it", "Italian"),
    ].map { TranslationLanguage(code: $0.0, name: $0.1) }

    static func name(for code: String) -> String {
        common.first { $0.code == code }?.name ?? Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}

/// Layouts for the full-screen lyrics view.
enum LockScene: String, Codable, CaseIterable {
    case classic, spotlight, vinyl, minimal, shuffle

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .spotlight: return "Spotlight"
        case .vinyl: return "Vinyl"
        case .minimal: return "Minimal"
        case .shuffle: return "Shuffle"
        }
    }

    var symbol: String {
        switch self {
        case .classic: return "rectangle.split.2x1.fill"
        case .spotlight: return "text.aligncenter"
        case .vinyl: return "record.circle"
        case .minimal: return "clock.fill"
        case .shuffle: return "shuffle"
        }
    }

    /// The looks you can pick; shuffling is a separate switch.
    static var choosable: [LockScene] { allCases.filter { $0 != .shuffle } }

    var detail: String {
        switch self {
        case .classic: return "Cover on the left, lyrics on the right, like Apple Music."
        case .spotlight: return "Giant lyrics in the middle of the screen."
        case .vinyl: return "Your album spinning on a record."
        case .minimal: return "A big clock and just the line being sung."
        case .shuffle: return "A different scene for every song."
        }
    }
}
