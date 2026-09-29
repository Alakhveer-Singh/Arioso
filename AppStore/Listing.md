# Arioso: App Store Connect listing

Everything to paste into App Store Connect for the Mac app. Limits are Apple's.

## App information

| Field | Value |
|---|---|
| Name (30) | Arioso |
| Subtitle (30) | Live lyrics, word by word |
| Bundle ID | com.alakhveer.Arioso |
| Primary category | Music |
| Secondary category | Utilities |
| Age rating | Answer the questionnaire; song lyrics can contain explicit words, so answer "Infrequent/Mild" for profanity/crude humor, which usually gives 12+ |
| Privacy Policy URL | https://alakhveer.com/arioso/privacy.html (check it matches where you host the site) |
| Support URL | https://alakhveer.com/arioso/ |
| Marketing URL | https://alakhveer.com/arioso/ |

Keep "Spotify" out of the name, subtitle, icon and keywords. Mentioning it in the description as a supported app is fine.

## Promotional text (170)

Your song, word by word. Live, synced lyrics on your Mac's desktop, and full screen whenever you press ⌥⌘L.

## Description (4000)

Arioso shows live, synced lyrics for the song you're playing, right on your Mac.

FULL-SCREEN LYRICS
Press ⌥⌘L anywhere and your song fills the screen: the cover glowing in its own colors, the time, and every line lighting up word by word as it's sung. Press Esc to go back.

FIVE SCENES
Classic, Spotlight, Vinyl, Minimal, or Shuffle for a different look every song. Choose how much the background moves, how dark it gets, and how big the lyrics are.

DESKTOP WIDGETS
Your lyrics and your Recently Played songs live on your desktop, beside your work. Click any lyric line to jump the song there. Drag and resize them, save your layout, and choose frosted Liquid Glass or solid cards filled with the album art.

PLAYER AT THE BOTTOM
A slim player sits at the bottom of your screen with the cover, song and artist. Click it for shuffle, previous, play or pause, next and repeat, a progress bar you can drag, and a button that turns the current line into a shareable card. Turn on Open at Login and your widgets are there every time you start your Mac.

WAVES THAT FOLLOW THE MUSIC
On macOS 14.2 and later, the waves beside the song move with your music's real loudness. Arioso only measures it, in memory, and never records anything.

WORKS WITH
Spotify and Apple Music. Arioso reads the song that's playing, with your permission. The player buttons (play/pause, skip, shuffle, repeat) send a command only when you press them; Arioso never changes playback on its own.

LICENSED LYRICS
Lyrics are licensed from Musixmatch, so songwriters get paid.

PRIVATE BY DESIGN
No account, no analytics, no ads. Everything stays on your Mac.

## Keywords (100)

lyrics,synced lyrics,karaoke,music,widget,desktop,full screen,sing along,song words,now playing

## What's New (first version)

Welcome to Arioso: live, synced lyrics for your Mac.

## App Review notes

Paste this into "Notes" under App Review Information (add your own explanation of the Apple Events entitlement where marked).

> **How to test Arioso (about 1 minute):**
> 1. Open the Music app (built into macOS) and play any song in the library or any free station under Radio (no subscription needed). Spotify works too if installed.
> 2. Open Arioso and click through the short welcome tour.
> 3. In Settings › General, turn OFF "Only follow Spotify" so Arioso follows Music.
> 4. When macOS asks "Arioso wants access to control Music", click Allow. Arioso then shows the song and its lyrics in the desktop widgets.
> 5. Press Option-Command-L for full-screen lyrics. Press Esc to close.
>
> If "Nothing playing" or "Arioso can't see your music" appears, access was declined: allow it in System Settings › Privacy & Security › Automation, or via Settings › General › Music access › Open.
>
> Arioso has no account or sign-in. Lyrics are licensed from Musixmatch.
>
> **Audio capture (optional):** on macOS 14.2 and later, Arioso can use a Core Audio process tap on Spotify or Music to measure loudness for the player's animated waves (Settings › Player › Follow the music). It listens only to that app's output while a song plays, analyses it in memory into seven levels and discards it. Nothing is recorded, stored or transmitted. The usage description is in NSAudioCaptureUsageDescription. Turning the setting off, or declining the permission, keeps the waves as a simple animation.
>
> **Apple Events entitlement:** [your explanation here]

## App Privacy ("nutrition label")

Apple counts data sent to a third party as "collected", and the song title and artist go to Musixmatch. Answer:

- **Do you collect data?** Yes
- **Data type:** Other Data › Other Data Types (song title and artist)
- **Linked to the user's identity?** No
- **Used for tracking?** No
- **Purpose:** App Functionality
- Everything else (contact info, identifiers, location, usage data, diagnostics): not collected

## Screenshots (Mac: 2880×1800)

Use demo mode so no copyrighted songs or covers appear:

```bash
open -a Arioso --args --demo              # widgets with the made-up song
open -a Arioso --args --demo --fullscreen # straight into full-screen lyrics
```

Add `--scene vinyl` (or classic, spotlight, minimal) to pick the full-screen scene, or use `--showcase` for the widgets over a clean wallpaper. None of these change your saved settings.

Done, all 2880×1800, in `screenshots/`:
1. `1-full-screen-classic.png`
2. `2-full-screen-vinyl.png`
3. `3-full-screen-spotlight.png`
4. `4-full-screen-minimal.png`
5. `5-desktop-widgets.png`

## Before you submit (checklist)

- [ ] Musixmatch API key with a plan that allows synced lyrics in a commercial app, set as `MUSIXMATCH_API_KEY` when building
- [ ] Replace `[your contact email]` in `website/privacy.html`, and upload the website
- [ ] Apple Developer account: App ID, Apple Distribution + Mac Installer Distribution certificates, Mac App Store provisioning profile
- [ ] Build with `APP_STORE=1 …` (see the top of `build_app.sh`) and upload `build/Arioso.pkg` with Transporter
- [x] Screenshots from demo mode
- [ ] Apple Events explanation in the review notes
