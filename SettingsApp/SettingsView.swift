import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Theme (black and white over deep slate blue-grey)

enum Theme {
    static let background = Color(red: 0.098, green: 0.125, blue: 0.153)      // #192027
    static let backgroundDeep = Color(red: 0.075, green: 0.094, blue: 0.110)  // #13181c
    static let sidebar = Color(red: 0.086, green: 0.114, blue: 0.141)         // #161d24
    static let paper = Color(red: 0.953, green: 0.965, blue: 0.973)           // #f3f6f8
    static let card = paper.opacity(0.05)
    static let cardBorder = paper.opacity(0.16)
    /// Lit lyrics are plain white; the accent follows them.
    static let accent = Color.white
    static let accentDeep = Color(red: 0.80, green: 0.85, blue: 0.88)         // #cdd8e0
    /// Icon-tile tints: shades of the slate palette instead of rainbow colours.
    static let slateMist = Color(red: 0.56, green: 0.64, blue: 0.69)          // #8fa3af
    static let slateSteel = Color(red: 0.44, green: 0.50, blue: 0.55)         // #6f808c
    static let slateTeal = Color(red: 0.31, green: 0.42, blue: 0.49)          // #4e6c7c
    static let slateDeep = Color(red: 0.23, green: 0.29, blue: 0.33)          // #3a4a55
    static let graphite = Color(white: 0.36)
    static let text = paper
    static let secondary = paper.opacity(0.6)
    static let tertiary = paper.opacity(0.36)
}

/// "Open at Login", through Apple's approved SMAppService. Off until the
/// user turns it on.
final class LoginItemModel: ObservableObject {
    @Published var enabled = SMAppService.mainApp.status == .enabled {
        didSet {
            guard enabled != oldValue, !syncing else { return }
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                syncing = true
                enabled = SMAppService.mainApp.status == .enabled
                syncing = false
            }
        }
    }
    private var syncing = false
    var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
}

/// Paper-like texture over the window, so flat slate doesn't look digital.
struct PaperGrain: View {
    private static let image: NSImage = {
        let size = 128
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                   bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                                   colorSpaceName: .deviceWhite, bytesPerRow: size, bitsPerPixel: 8)!
        var seed: UInt32 = 0x2545F491
        for i in 0..<(size * size) {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            rep.bitmapData![i] = UInt8(96 + Int(seed % 64))
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }()

    var body: some View {
        Image(nsImage: Self.image)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(0.22)
            .allowsHitTesting(false)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, fullScreen, widgets, player, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .fullScreen: return "Full Screen"
        case .widgets: return "Widgets"
        case .player: return "Player"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "What Arioso follows and how you start it."
        case .fullScreen: return "The lyrics that fill your screen when you press ⌥⌘L."
        case .widgets: return "The cards that live on your desktop."
        case .player: return "The slim player stuck to the bottom of your screen, and its controls."
        case .about: return "Arioso"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .fullScreen: return "arrow.up.left.and.arrow.down.right"
        case .widgets: return "square.grid.2x2.fill"
        case .player: return "play.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Theme.graphite
        case .fullScreen: return Theme.slateTeal
        case .widgets: return Theme.slateSteel
        case .player: return Theme.slateDeep
        case .about: return Theme.slateMist
        }
    }
}

/// UI-only state (no @State: this toolchain has no SwiftUI macro plugin).
final class NavigationModel: ObservableObject {
    /// The window's own title bar isn't shown (see showSettings()), but this still updates its
    /// underlying title — for the Window menu, Mission Control and VoiceOver — to name the pane
    /// on screen, as the Human Interface Guidelines ask for a settings window.
    static let tabChangedNotification = Notification.Name("com.alakhveer.Arioso.settingsTabChanged")

    /// Screenshots: `--settings --tab=player` opens on that page.
    @Published var tab: SettingsTab = {
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--tab=") }),
           let tab = SettingsTab(rawValue: String(arg.dropFirst(6))) { return tab }
        return .general
    }() {
        didSet { NotificationCenter.default.post(name: Self.tabChangedNotification, object: tab.title) }
    }
}

final class HoverModel: ObservableObject {
    @Published var isHovered = false
}

// MARK: - Root

struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @StateObject private var nav = NavigationModel()

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(nav: nav)
                .frame(width: 230)
            Rectangle().fill(Theme.paper.opacity(0.14)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    page
                }
                .padding(.horizontal, 36)
                .padding(.top, 48)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(nav.tab)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .scrollIndicators(.never)
            .background(
                LinearGradient(colors: [Theme.background, Theme.backgroundDeep],
                               startPoint: .top, endPoint: .bottom)
            )
        }
        .overlay(PaperGrain())
        .frame(minWidth: 860, minHeight: 620)
        .background(Theme.backgroundDeep)
        .tint(.accentColor)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(nav.tab.title)
                .font(.system(size: 32, weight: .semibold, design: .serif))
                .foregroundColor(Theme.text)
            if nav.tab != .about {
                Text(nav.tab.subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.secondary)
            }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch nav.tab {
        case .general: GeneralPage(store: store)
        case .fullScreen: FullScreenPage(store: store)
        case .widgets: WidgetsPage(store: store)
        case .player: PlayerPage(store: store)
        case .about: AboutPage()
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var nav: NavigationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 52)
            VStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    SidebarItem(tab: tab, isSelected: nav.tab == tab) {
                        withAnimation(.easeOut(duration: 0.22)) { nav.tab = tab }
                    }
                }
            }
            .padding(.horizontal, 10)
            Spacer()
            FullScreenButton()
                .padding(14)
        }
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
    }
}

private struct SidebarItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void
    @StateObject private var hover = HoverModel()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                IconTile(symbol: tab.symbol, tint: tab.tint, size: 26)
                Text(tab.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? Theme.text : Theme.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.18)
                          : (hover.isHovered ? Color.white.opacity(0.05) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.35) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovered = $0 }
    }
}

private struct FullScreenButton: View {
    @StateObject private var hover = HoverModel()

    var body: some View {
        Button { FullScreenLyrics.shared.show() } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                Text("Open Full Screen").font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(Theme.backgroundDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                         startPoint: .top, endPoint: .bottom))
            )
            .brightness(hover.isHovered ? 0.06 : 0)
            .shadow(color: Theme.accent.opacity(0.3), radius: hover.isHovered ? 10 : 4, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hover.isHovered)
    }
}

// MARK: - Pages

private struct GeneralPage: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var loginItem = LoginItemModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Card(title: "Arioso") {
                SettingRow(symbol: "power", tint: store.settings.isEnabled ? Theme.slateMist : Color.gray,
                           title: store.settings.isEnabled ? "Arioso is on" : "Arioso is off",
                           detail: store.settings.isEnabled
                               ? "Widgets and ⌥⌘L keep running in the background when this window is closed."
                               : "No widgets and no shortcut until you turn it back on.") {
                    Switch(isOn: $store.settings.isEnabled)
                }
                RowDivider()
                SettingRow(symbol: "sunrise.fill", tint: Theme.slateSteel,
                           title: "Open at login",
                           detail: loginItem.needsApproval
                               ? "Allow Arioso in System Settings › General › Login Items."
                               : "Start quietly when you log in, so your widgets are always there.") {
                    Switch(isOn: $loginItem.enabled)
                }
            }

            Card(title: "Music") {
                SettingRow(symbol: "music.note", tint: Theme.slateMist,
                           title: "Only follow Spotify",
                           detail: store.settings.spotifyOnly
                               ? "Apple Music is ignored."
                               : "Follows Spotify and Apple Music, whichever is playing.") {
                    Switch(isOn: $store.settings.spotifyOnly)
                }
                RowDivider()
                SettingRow(symbol: "hand.raised.fill", tint: Theme.slateSteel,
                           title: "Music access",
                           detail: "If lyrics never appear, allow Arioso for Spotify and Music under Automation.") {
                    Button("Open…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Card(title: "Lyrics") {
                SettingRow(symbol: "text.bubble", tint: Theme.slateTeal,
                           title: "Under each line",
                           detail: store.settings.lyricSubtitle.detail) {
                    Picker("", selection: $store.settings.lyricSubtitle) {
                        ForEach(LyricSubtitle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 130)
                }
                if store.settings.lyricSubtitle == .translated {
                    RowDivider()
                    SettingRow(symbol: "globe", tint: Theme.slateSteel,
                               title: "Translate into",
                               detail: "On macOS 15 and later, with Apple's on-device Translation. macOS may ask, once, to download the language.") {
                        Picker("", selection: $store.settings.translationLanguage) {
                            ForEach(TranslationLanguage.common) { Text($0.name).tag($0.code) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }
            }

            Card(title: "Shortcut") {
                SettingRow(symbol: "keyboard", tint: Theme.slateDeep,
                           title: "Full-screen lyrics",
                           detail: "Press the shortcut anywhere and your song fills the screen. Esc or a click closes it.") {
                    Switch(isOn: $store.settings.lockShortcutEnabled)
                }
                RowDivider()
                HStack(spacing: 8) {
                    Keycap("⌥")
                    Keycap("⌘")
                    Keycap("L")
                    Spacer()
                    Text(store.settings.lockShortcutEnabled ? "Active" : "Off")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(store.settings.lockShortcutEnabled ? Theme.accent : Theme.tertiary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .opacity(store.settings.lockShortcutEnabled ? 1 : 0.4)
                .padding(.vertical, 14)
                .animation(.easeOut(duration: 0.2), value: store.settings.lockShortcutEnabled)
            }

            Card(title: "Window Shortcut") {
                SettingRow(symbol: "rectangle.center.inset.filled", tint: Theme.slateMist,
                           title: "Fit windows between widgets",
                           detail: "Resizes the front app's windows into the space next to your widgets. Press again to undo. Needs Accessibility permission.") {
                    Switch(isOn: $store.settings.reframeShortcutEnabled)
                }
                RowDivider()
                HStack(spacing: 8) {
                    Keycap("⌘")
                    Keycap("⇧")
                    Keycap("L")
                    Spacer()
                    Text(store.settings.reframeShortcutEnabled ? "Active" : "Off")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(store.settings.reframeShortcutEnabled ? Theme.accent : Theme.tertiary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .opacity(store.settings.reframeShortcutEnabled ? 1 : 0.4)
                .padding(.vertical, 14)
                .animation(.easeOut(duration: 0.2), value: store.settings.reframeShortcutEnabled)
            }
        }
    }
}

private struct FullScreenPage: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            LookPreview(look: store.settings.lockScreen, scene: store.settings.lockScene)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1))
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Scene")
                HStack(spacing: 10) {
                    ForEach(LockScene.choosable, id: \.self) { scene in
                        SceneTile(scene: scene, isSelected: store.settings.lockScene == scene) {
                            withAnimation(.easeOut(duration: 0.25)) { store.settings.lockScene = scene }
                        }
                    }
                }
                .opacity(store.settings.shuffleScenes ? 0.5 : 1)
            }
            Card {
                SettingRow(symbol: "shuffle", tint: Theme.slateTeal,
                           title: "Shuffle scenes",
                           detail: "A different scene for each song. The same song always gets the same one.") {
                    Switch(isOn: $store.settings.shuffleScenes)
                }
            }
            LookCard(look: $store.settings.lockScreen)
        }
    }
}

private struct WidgetsPage: View {
    @ObservedObject var store: SettingsStore

    /// Saving replaces the previous layout for good, so it asks first.
    private func confirmSaveLayout() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Save this as your layout?"
        alert.informativeText = "Your widgets' current positions and sizes replace your previously saved layout."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("On your desktop")
                HStack(spacing: 14) {
                    WidgetTile(title: "Lyrics", symbol: "quote.bubble.fill",
                               tint: Theme.slateTeal, isOn: $store.settings.showLyricsWidget)
                    WidgetTile(title: "Recently Played", symbol: "clock.arrow.circlepath",
                               tint: Theme.slateSteel, isOn: $store.settings.showRecentlyPlayed)
                }
            }

            Card(title: "Recently Played widget") {
                SettingRow(symbol: "play.circle.fill", tint: Theme.slateSteel,
                           title: "Click a song to play it again",
                           detail: store.settings.historyPlayAgain
                               ? "Songs played from now on can be played again with a click, in the app they came from. The widget drags by its title."
                               : "The list is just for looking. The widget drags from anywhere.") {
                    Switch(isOn: $store.settings.historyPlayAgain)
                }
            }

            Card(title: "Lyrics widget") {
                SettingRow(symbol: "hand.tap.fill", tint: Theme.slateTeal,
                           title: "Click a line to jump",
                           detail: store.settings.lyricsTapToJump
                               ? "Click any lyric and the song jumps there. The widget drags by its cover area."
                               : "Lyrics are just for reading. The widget drags from anywhere.") {
                    Switch(isOn: $store.settings.lyricsTapToJump)
                }
            }

            Card(title: "Style") {
                SettingRow(symbol: "drop.fill", tint: Theme.slateMist,
                           title: "Liquid glass",
                           detail: store.settings.liquidGlass
                               ? "Your wallpaper shows through, tinted by the song playing."
                               : "Solid cards filled with the song's moving album art.") {
                    Switch(isOn: $store.settings.liquidGlass)
                }
                if store.settings.liquidGlass {
                    RowDivider()
                    SliderRow(symbol: "circle.lefthalf.filled", tint: Theme.slateDeep, title: "Glass clarity",
                              value: $store.settings.glassClarity, range: 0...1) {
                        Text("Frosted")
                    } max: {
                        Text("Clear")
                    }
                }
            }

            LookCard(look: $store.settings.widgets)

            Card(title: "Layout") {
                SettingRow(symbol: "square.and.arrow.down", tint: Theme.slateMist,
                           title: "Save my layout",
                           detail: "Arrange and resize the widgets how you like, then save it.") {
                    Button("Save Current") { if confirmSaveLayout() { post(AppSettings.saveLayoutNotification) } }
                }
                RowDivider()
                SettingRow(symbol: "arrow.uturn.backward", tint: Theme.slateSteel,
                           title: "Back to my layout",
                           detail: "Moved things around? Snap every widget back to your saved layout.") {
                    Button("Reset") { post(AppSettings.resetPositionsNotification) }
                }
                RowDivider()
                SettingRow(symbol: "rectangle.3.group", tint: Theme.graphite,
                           title: "Original layout",
                           detail: "Forget your saved layout and use the built-in one.") {
                    Button("Restore") { post(AppSettings.originalLayoutNotification) }
                }
            }
        }
    }
}

private struct PlayerPage: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Card(title: "At the bottom of your screen") {
                SettingRow(symbol: "play.circle.fill", tint: Theme.slateMist,
                           title: "Show the player",
                           detail: "A slim player with the cover, song and artist. Click it to open the full player; click its top row to fold it back.") {
                    Switch(isOn: $store.settings.showNowPlaying)
                }
                if store.settings.showNowPlaying {
                    RowDivider()
                    SettingRow(symbol: "square.stack.3d.up.fill", tint: Theme.slateDeep,
                               title: "Float above other apps",
                               detail: store.settings.playerFloats
                                   ? "The player stays on top of every window, and clicking it never takes focus from what you're typing in."
                                   : "The player sits on the desktop, behind your app windows, like the widgets.") {
                        Switch(isOn: $store.settings.playerFloats)
                    }
                    RowDivider()
                    SliderRow(symbol: "arrow.up.left.and.arrow.down.right", tint: Theme.slateSteel, title: "Size",
                              value: $store.settings.playerScale, range: 0.6...1.2) {
                        Image(systemName: "capsule").imageScale(.small)
                    } max: { Image(systemName: "capsule").imageScale(.large) }
                    RowDivider()
                    SettingRow(symbol: "waveform", tint: Theme.slateTeal,
                               title: "Moving waves",
                               detail: "The bars beside the song move while it plays.") {
                        Switch(isOn: $store.settings.playerWaves)
                    }
                    if #available(macOS 14.2, *), store.settings.playerWaves {
                        RowDivider()
                        SettingRow(symbol: "waveform.badge.mic", tint: Theme.slateSteel,
                                   title: "Follow the music",
                                   detail: "The waves move with the real audio of Spotify or Apple Music. Arioso only measures how loud it is: nothing is recorded, saved or sent. macOS asks permission the first time; if the bars never react, allow Arioso under Privacy & Security › Screen & System Audio Recording.") {
                            Switch(isOn: $store.settings.playerLiveWaves)
                        }
                        if store.settings.playerLiveWaves {
                            RowDivider()
                            SliderRow(symbol: "dial.medium", tint: Theme.slateMist, title: "Wave sensitivity",
                                      value: $store.settings.waveSensitivity, range: 0.2...1) {
                                Text("Calm")
                            } max: {
                                Text("Lively")
                            }
                        }
                    }
                }
            }

            if store.settings.showNowPlaying {
                Card(title: "Style") {
                    SettingRow(symbol: "drop.fill", tint: Theme.slateMist,
                               title: "Liquid glass",
                               detail: store.settings.playerLiquidGlass
                                   ? "Your wallpaper shows through."
                                   : "A solid card instead.") {
                        Switch(isOn: $store.settings.playerLiquidGlass)
                    }
                    if store.settings.playerLiquidGlass {
                        RowDivider()
                        SliderRow(symbol: "circle.lefthalf.filled", tint: Theme.slateDeep, title: "Glass clarity",
                                  value: $store.settings.playerGlassClarity, range: 0...1) {
                            Text("Frosted")
                        } max: {
                            Text("Clear")
                        }
                    }
                }

                PlayerLookCard(store: store)
            }

            Card(title: "Controls") {
                SettingRow(symbol: "backward.end.fill", tint: Theme.slateDeep,
                           title: "Controls in the lyrics widget",
                           detail: "Shuffle, previous, play or pause, next and repeat at the bottom of the lyrics widget.") {
                    Switch(isOn: $store.settings.lyricsWidgetControls)
                }
                RowDivider()
                SettingRow(symbol: "hand.tap.fill", tint: Theme.graphite,
                           title: "Where the buttons go",
                           detail: "They control Spotify or Apple Music, whichever is playing. macOS asks your permission the first time.") { EmptyView() }
            }
        }
    }
}

/// The player's Appearance card: the same sliders as the widgets, minus the lyrics-only ones.
private struct PlayerLookCard: View {
    @ObservedObject var store: SettingsStore

    private var isDefault: Bool {
        store.settings.playerLook == AppSettings.Look.player && !store.settings.playerAlbumColors
    }

    var body: some View {
        Card(title: "Appearance", trailing: isDefault ? nil : AnyView(
            Button("Reset to Defaults") {
                store.settings.playerLook = .player
                store.settings.playerAlbumColors = false
            }.buttonStyle(.link))) {
            SettingRow(symbol: "sparkles", tint: Theme.slateTeal, title: "Album colors",
                       detail: "Tint the player with the song's colors. Off keeps it neutral grey.") {
                Switch(isOn: $store.settings.playerAlbumColors)
            }
            if store.settings.playerAlbumColors {
                RowDivider()
                SliderRow(symbol: "wind", tint: Theme.slateMist, title: "Background motion",
                          value: $store.settings.playerLook.backgroundSpeed, range: 0...8) {
                    Image(systemName: "tortoise")
                } max: { Image(systemName: "hare") }
            }
            RowDivider()
            SliderRow(symbol: "moon.fill", tint: Theme.slateDeep, title: "Background darkness",
                      value: $store.settings.playerLook.backgroundDarkness, range: 0.3...0.9) {
                Image(systemName: "sun.max")
            } max: { Image(systemName: "moon") }
            RowDivider()
            SliderRow(symbol: "photo.fill", tint: Theme.slateMist, title: "Cover size",
                      value: $store.settings.playerLook.coverSize, range: 0.7...1.3) {
                Image(systemName: "photo").imageScale(.small)
            } max: { Image(systemName: "photo").imageScale(.large) }
        }
    }
}

private struct AboutPage: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }
    private var licensedLyrics: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "MusixmatchAPIKey") as? String).map { !$0.isEmpty } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Version \(version)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.secondary)
                    Text("Live, synced lyrics for Spotify and Apple Music,\nfull screen and on your desktop.")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.text)
                }
            }
            if Updater.isAvailable { UpdatesCard() }
            Card(title: "Credits") {
                SettingRow(symbol: "text.quote", tint: Theme.slateTeal,
                           title: "Lyrics", detail: licensedLyrics ? "Musixmatch" : "lrclib.net") { EmptyView() }
                RowDivider()
                SettingRow(symbol: "photo", tint: Theme.slateSteel,
                           title: "Album artwork", detail: "Spotify and Apple Music") { EmptyView() }
            }
        }
    }
}

/// Only shown in the direct-download build, which updates itself (see Updater.swift).
private struct UpdatesCard: View {
    @ObservedObject private var updater = Updater.shared

    private var lastChecked: String {
        guard let date = updater.lastChecked else { return "Not checked yet." }
        let ago = RelativeDateTimeFormatter()
        ago.unitsStyle = .full
        return "Last checked \(ago.localizedString(for: date, relativeTo: Date()))."
    }

    var body: some View {
        Card(title: "Updates") {
            SettingRow(symbol: "arrow.down.circle", tint: Theme.slateTeal,
                       title: "Check for updates",
                       detail: lastChecked) {
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            RowDivider()
            SettingRow(symbol: "arrow.triangle.2.circlepath", tint: Theme.slateSteel,
                       title: "Check automatically",
                       detail: "Once a day, Arioso asks the website whether there's a newer version.") {
                Switch(isOn: Binding(get: { updater.automaticallyChecks },
                                     set: { updater.automaticallyChecks = $0 }))
            }
            if updater.allowsAutomaticInstall {
                RowDivider()
                SettingRow(symbol: "square.and.arrow.down", tint: Theme.slateMist,
                           title: "Install automatically",
                           detail: "Download new versions in the background and install them when you quit Arioso.") {
                    Switch(isOn: Binding(get: { updater.automaticallyInstalls },
                                         set: { updater.automaticallyInstalls = $0 }))
                }
            }
        }
    }
}

/// The look shared by the full-screen view and the widgets.
private struct LookCard: View {
    @Binding var look: AppSettings.Look

    var body: some View {
        Card(title: "Appearance", trailing: look != AppSettings.Look()
             ? AnyView(Button("Reset to Defaults") { look = AppSettings.Look() }.buttonStyle(.link))
             : nil) {
            SliderRow(symbol: "wind", tint: Theme.slateMist, title: "Background motion",
                      value: $look.backgroundSpeed, range: 0...8) {
                Image(systemName: "tortoise")
            } max: { Image(systemName: "hare") }
            RowDivider()
            SliderRow(symbol: "moon.fill", tint: Theme.slateDeep, title: "Background darkness",
                      value: $look.backgroundDarkness, range: 0.3...0.9) {
                Image(systemName: "sun.max")
            } max: { Image(systemName: "moon") }
            RowDivider()
            SliderRow(symbol: "photo.fill", tint: Theme.slateMist, title: "Cover size",
                      value: $look.coverSize, range: 0.6...1.5) {
                Image(systemName: "photo").imageScale(.small)
            } max: { Image(systemName: "photo").imageScale(.large) }
            RowDivider()
            SliderRow(symbol: "textformat.size", tint: Theme.slateSteel, title: "Lyrics size",
                      value: $look.lyricsSize, range: 0.7...1.4) {
                Image(systemName: "textformat.size.smaller")
            } max: { Image(systemName: "textformat.size.larger") }
            RowDivider()
            SettingRow(symbol: "music.mic", tint: Theme.slateTeal, title: "Sing-along",
                       detail: "Words light up one by one as the line is sung.") {
                Switch(isOn: $look.singAlong)
            }
            RowDivider()
            SettingRow(symbol: "sparkles", tint: Theme.slateTeal, title: "Cover glow",
                       detail: "A soft light behind the album art, in its colors.") {
                Switch(isOn: $look.coverGlow)
            }
        }
    }
}

// MARK: - Components

/// The standard macOS switch, as in System Settings.
private struct Switch: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden()
    }
}

private struct Card<Content: View>: View {
    let title: String?
    var trailing: AnyView?
    let content: Content

    init(title: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack {
                    SectionLabel(title)
                    Spacer()
                    if let trailing { trailing.font(.system(size: 12)) }
                }
            }
            VStack(spacing: 0) { content }
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.cardBorder, lineWidth: 1))
                )
        }
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.1)
            .foregroundColor(Theme.tertiary)
            .padding(.leading, 4)
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.leading, 44)
    }
}

struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundColor(.white)
            )
            .shadow(color: tint.opacity(0.3), radius: 3, y: 1)
    }
}

private struct SettingRow<Control: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String?
    let control: Control

    init(symbol: String, tint: Color, title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.vertical, 13)
    }
}

/// A row with the standard macOS slider and small icons at each end.
private struct SliderRow: View {
    let symbol: String
    let tint: Color
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let min: AnyView
    let max: AnyView

    init(symbol: String, tint: Color, title: String, value: Binding<Double>, range: ClosedRange<Double>,
         @ViewBuilder min: () -> some View, @ViewBuilder max: () -> some View) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        _value = value
        self.range = range
        self.min = AnyView(min())
        self.max = AnyView(max())
    }

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, tint: tint)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)
            Spacer(minLength: 16)
            Slider(value: $value, in: range) { Text(title) } minimumValueLabel: { min } maximumValueLabel: { max }
                .labelsHidden()
                .foregroundColor(Theme.secondary)
                .frame(width: 280)
        }
        .padding(.vertical, 13)
    }
}

struct Keycap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundColor(Theme.text)
            .frame(minWidth: 34, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.06)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 0, y: 2)
    }
}

/// A big card that shows and toggles one desktop widget.
private struct WidgetTile: View {
    let title: String
    let symbol: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: isOn ? tint : Color.gray.opacity(0.5), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isOn ? "Showing" : "Hidden")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondary)
            }
            Spacer()
            Switch(isOn: $isOn)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isOn ? tint.opacity(0.12) : Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isOn ? tint.opacity(0.45) : Theme.cardBorder, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.2), value: isOn)
    }
}

/// One choice in the full-screen scene picker.
private struct SceneTile: View {
    let scene: LockScene
    let isSelected: Bool
    let action: () -> Void
    @StateObject private var hover = HoverModel()

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(scene.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(scene.detail)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.14)
                          : (hover.isHovered ? Color.white.opacity(0.07) : Theme.card))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.6) : Theme.cardBorder,
                                  lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovered = $0 }
    }
}

/// A miniature full-screen view that reacts live to every Appearance setting.
struct LookPreview: View {
    let look: AppSettings.Look
    var scene: LockScene = .classic

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: look.backgroundSpeed == 0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate * look.backgroundSpeed * 0.15
                    ZStack {
                        blob(Color(red: 0.44, green: 0.52, blue: 0.58), size: geo.size.width * 0.7)
                            .offset(x: cos(t) * geo.size.width * 0.18, y: sin(t * 1.3) * geo.size.height * 0.2)
                        blob(Color(red: 0.14, green: 0.19, blue: 0.23), size: geo.size.width * 0.6)
                            .offset(x: sin(t * 0.8) * geo.size.width * 0.25, y: cos(t) * geo.size.height * 0.25)
                        blob(Color(red: 0.80, green: 0.86, blue: 0.90), size: geo.size.width * 0.4)
                            .offset(x: cos(t * 1.4 + 2) * geo.size.width * 0.2, y: sin(t * 0.9 + 1) * geo.size.height * 0.2)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .blur(radius: 40)
                }
                .background(Color(red: 0.10, green: 0.13, blue: 0.155))
                Color.black.opacity(look.backgroundDarkness)

                sceneLayout(geo.size)
            }
            .animation(.easeOut(duration: 0.25), value: look)
            .animation(.easeOut(duration: 0.3), value: scene)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            Text("PREVIEW")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .padding(12)
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    @ViewBuilder
    private func sceneLayout(_ size: CGSize) -> some View {
        switch scene {
        case .classic, .shuffle:
            HStack(spacing: size.width * 0.07) {
                cover(104)
                lyricsStack(alignment: .leading)
            }
            .padding(.horizontal, 34)
            .overlay(alignment: .bottomTrailing) {
                if scene == .shuffle {
                    Label("A different scene every song", systemImage: "shuffle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                        .padding(12)
                }
            }
        case .spotlight:
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    cover(26, glow: false)
                    Text("Song · Artist").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                }
                lyricsStack(alignment: .center, scale: 1.25)
            }
        case .vinyl:
            HStack(spacing: size.width * 0.07) {
                ZStack {
                    Circle().fill(Color.black).frame(width: 128 * look.coverSize, height: 128 * look.coverSize)
                    ForEach(1..<5) { ring in
                        Circle().stroke(Color.white.opacity(0.06), lineWidth: 1)
                            .frame(width: CGFloat(128 - ring * 18) * look.coverSize)
                    }
                    Image(nsImage: NSApp.applicationIconImage).resizable()
                        .frame(width: 46 * look.coverSize, height: 46 * look.coverSize)
                        .clipShape(Circle())
                }
                .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
                lyricsStack(alignment: .leading)
            }
            .padding(.horizontal, 34)
        case .minimal:
            VStack(spacing: 6) {
                Text("9:41").font(.system(size: 64, weight: .thin, design: .rounded)).foregroundColor(.white)
                Text("Friday, 25 September").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.7))
                lyric("Every word, every line", opacity: 1).padding(.top, 10)
            }
        }
    }

    private func cover(_ side: CGFloat, glow: Bool = true) -> some View {
        ZStack {
            if glow && look.coverGlow {
                Image(nsImage: NSApp.applicationIconImage).resizable()
                    .frame(width: side * 1.13 * look.coverSize, height: side * 1.13 * look.coverSize)
                    .blur(radius: 26).opacity(0.9)
            }
            Image(nsImage: NSApp.applicationIconImage).resizable()
                .frame(width: side * look.coverSize, height: side * look.coverSize)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.1, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
        }
    }

    private func lyricsStack(alignment: HorizontalAlignment, scale: CGFloat = 1) -> some View {
        VStack(alignment: alignment, spacing: 9 * look.lyricsSize) {
            lyric("And I'll sing it back to you", opacity: 0.3, scale: scale)
            lyric("Every word, every line", opacity: 1, scale: scale)
            lyric("Right here on the screen", opacity: 0.3, scale: scale)
            lyric("Until the song is done", opacity: 0.15, scale: scale)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle().fill(color).frame(width: size, height: size)
    }

    private func lyric(_ text: String, opacity: Double, scale: CGFloat = 1) -> some View {
        Text(text)
            .font(.system(size: 17 * look.lyricsSize * scale, weight: .bold))
            .foregroundColor(.white.opacity(opacity))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
