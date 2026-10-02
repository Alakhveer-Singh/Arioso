#!/bin/bash
# Builds Arioso.app: one universal (Apple silicon + Intel) app for direct
# distribution (not the Mac App Store): no private APIs or background helpers,
# but not sandboxed either, since ⌘⇧L needs Accessibility to move other apps' windows.
#
#   MUSIXMATCH_API_KEY=… ./build_app.sh
#       Local build: signed ad hoc, installed to /Applications on this Mac,
#       plus build/Arioso.zip and build/Arioso.dmg (copied into website/).
#
#   APP_STORE=1 TEAM_ID=… APP_SIGN_IDENTITY=… INSTALLER_SIGN_IDENTITY=… \
#   PROVISIONING_PROFILE=… ./build_app.sh
#       Also signs for the Mac App Store and makes build/Arioso.pkg to upload
#       with Apple's Transporter app. All values come from your Apple Developer
#       account (see the README note printed at the end).
#
# The direct-download build updates itself with Sparkle (downloaded once into
# build/.sparkle and checked against a pinned SHA-256). The App Store build has
# no updater, since the App Store delivers updates. Publishing an update is in
# make_appcast.sh. Other switches:
#   FEED_URL=…      where the app looks for updates (default: the website's appcast.xml)
#   SKIP_INSTALL=1  build and sign only: don't touch /Applications, settings, zip or dmg
#   BUNDLE_ID=…     build under another bundle ID, for testing without disturbing the real app
#   NO_SPARKLE=1    build without the updater
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Arioso.app"
CONTENTS="$APP/Contents"
VERSION="${VERSION:-1.0}"
BUNDLE_ID="${BUNDLE_ID:-com.alakhveer.Arioso}"
FEED_URL="${FEED_URL:-https://alakhveer.com/arioso/appcast.xml}"
SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
SPARKLE_DIR="build/.sparkle/$SPARKLE_VERSION"
USE_SPARKLE=1
if [ "${APP_STORE:-0}" = "1" ] || [ "${NO_SPARKLE:-0}" = "1" ]; then USE_SPARKLE=0; fi
# Unique and always increasing (App Store Connect requires that); the app
# also shows its welcome tour once per build number.
BUILD_STAMP="$(date +%Y%m%d%H%M)"
ENTITLEMENTS="App/Arioso.entitlements"

rm -rf "$APP" build/arm64 build/x86_64
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" build/arm64 build/x86_64

SWIFT_FLAGS=(-O)
if [ "$USE_SPARKLE" = "1" ]; then
    if [ ! -d "$SPARKLE_DIR/Sparkle.framework" ]; then
        echo "Downloading Sparkle $SPARKLE_VERSION (for auto-updates)..."
        mkdir -p build/.sparkle
        SPARKLE_ARCHIVE="build/.sparkle/Sparkle-$SPARKLE_VERSION.tar.xz"
        curl -fsSL -o "$SPARKLE_ARCHIVE" \
            "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
        if ! echo "$SPARKLE_SHA256  $SPARKLE_ARCHIVE" | shasum -a 256 -c - >/dev/null 2>&1; then
            rm -f "$SPARKLE_ARCHIVE"
            echo "Sparkle's checksum doesn't match the pinned one, so it won't be used." >&2
            exit 1
        fi
        mkdir -p "$SPARKLE_DIR"
        tar -xJf "$SPARKLE_ARCHIVE" -C "$SPARKLE_DIR"
    fi
    SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-$(tr -d '[:space:]' < App/sparkle_public_key.txt)}"
    SWIFT_FLAGS+=(-F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
fi

# "Translate" (Settings › General › Lyrics) uses Apple's Translation framework, only present in
# SDKs from Xcode 16 / macOS 15 on. Link it only when it's actually there; Swift's own
# `#if canImport(Translation)` already keeps the app building without it (as "Romanize" only).
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [ -n "$SDK_PATH" ] && [ -d "$SDK_PATH/System/Library/Frameworks/Translation.framework" ]; then
    SWIFT_FLAGS+=(-framework Translation)
else
    echo "Note: this SDK has no Translation.framework, so lyrics can be Romanized but not Translated."
fi

echo "Compiling Arioso (universal)..."
for arch in arm64 x86_64; do
    swiftc App/*.swift Sources/*.swift Widget/*.swift SettingsApp/*.swift \
        -target "$arch-apple-macos13.0" "${SWIFT_FLAGS[@]}" -o "build/$arch/Arioso"
done
lipo -create build/arm64/Arioso build/x86_64/Arioso -output "$CONTENTS/MacOS/Arioso"
rm -rf build/arm64 build/x86_64

cp AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
cp Illustrations/*.jpg "$CONTENTS/Resources/"

SPARKLE_PLIST=""
if [ "$USE_SPARKLE" = "1" ]; then
    mkdir -p "$CONTENTS/Frameworks"
    ditto "$SPARKLE_DIR/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"
    # Arioso isn't sandboxed, so Sparkle's XPC helper services aren't needed.
    rm -rf "$CONTENTS/Frameworks/Sparkle.framework/Versions/B/XPCServices"
    rm -f "$CONTENTS/Frameworks/Sparkle.framework/XPCServices"
    SPARKLE_PLIST="	<key>SUFeedURL</key>
	<string>$FEED_URL</string>
	<key>SUPublicEDKey</key>
	<string>$SPARKLE_PUBLIC_KEY</string>
	<key>SUEnableAutomaticChecks</key>
	<true/>"
fi

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Arioso</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleName</key>
	<string>Arioso</string>
	<key>CFBundleDisplayName</key>
	<string>Arioso</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD_STAMP</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.music</string>
	<!-- No Dock icon until a window opens; widgets and the player run in the background. -->
	<!-- arioso:// lets the website's "Open Arioso" button launch the app. -->
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>Arioso</string>
			<key>CFBundleURLSchemes</key>
			<array><string>arioso</string></array>
		</dict>
	</array>
	<key>LSUIElement</key>
	<true/>
	<key>NSAppleEventsUsageDescription</key>
	<string>Arioso reads which song is playing in Spotify or Apple Music to show its lyrics, and sends play, pause, skip, shuffle and repeat when you press the player buttons.</string>
	<key>NSAccessibilityUsageDescription</key>
	<string>Arioso uses Accessibility to fit the front app's windows next to your widgets when you press ⌘⇧L.</string>
	<key>NSAudioCaptureUsageDescription</key>
	<string>Arioso listens to the audio of Spotify or Apple Music only to measure how loud it is, so the player's waves can move with the music. Nothing is recorded or saved.</string>
	<key>NSHumanReadableCopyright</key>
	<string>© 2026 Alakhveer Singh</string>
	<key>MusixmatchAPIKey</key>
	<string>${MUSIXMATCH_API_KEY:-}</string>
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
${SPARKLE_PLIST}
</dict>
</plist>
EOF

if [ -z "${MUSIXMATCH_API_KEY:-}" ]; then
    echo "Note: no MUSIXMATCH_API_KEY, so this build uses lrclib.net for lyrics (fine for testing, not for the App Store)."
fi

if [ "${APP_STORE:-0}" = "1" ]; then
    : "${MUSIXMATCH_API_KEY:?Set MUSIXMATCH_API_KEY (your Musixmatch API key); the App Store build needs lyrics}"
    : "${TEAM_ID:?Set TEAM_ID (10 characters, from developer.apple.com › Membership)}"
    : "${APP_SIGN_IDENTITY:?Set APP_SIGN_IDENTITY, e.g. \"Apple Distribution: Your Name (TEAMID)\"}"
    : "${INSTALLER_SIGN_IDENTITY:?Set INSTALLER_SIGN_IDENTITY, e.g. \"3rd Party Mac Developer Installer: Your Name (TEAMID)\"}"
    : "${PROVISIONING_PROFILE:?Set PROVISIONING_PROFILE to your Mac App Store .provisionprofile}"

    echo "Signing for the Mac App Store..."
    cp "$PROVISIONING_PROFILE" "$CONTENTS/embedded.provisionprofile"
    STORE_ENTITLEMENTS="build/store.entitlements"
    cp "$ENTITLEMENTS" "$STORE_ENTITLEMENTS"
    /usr/libexec/PlistBuddy \
        -c "Add :com.apple.application-identifier string $TEAM_ID.com.alakhveer.Arioso" \
        -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$STORE_ENTITLEMENTS"
    codesign --force --options runtime --entitlements "$STORE_ENTITLEMENTS" --sign "$APP_SIGN_IDENTITY" "$APP"
    productbuild --component "$APP" /Applications --sign "$INSTALLER_SIGN_IDENTITY" build/Arioso.pkg
    echo "Made build/Arioso.pkg: upload it with Apple's Transporter app."
    exit 0
fi

# Signed with a stable local certificate (not ad-hoc "-"): ad-hoc signatures
# change on every build, which resets Accessibility permission each time.
# This one-time certificate keeps the same identity across rebuilds, so
# ⌘⇧L's Accessibility grant survives. Made automatically on first run.
LOCAL_CERT="Arioso Local Dev"
if ! security find-certificate -c "$LOCAL_CERT" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
    echo "Making a one-time local signing certificate ($LOCAL_CERT)..."
    TMP="$(mktemp -d)"
    cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $LOCAL_CERT
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
    openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
        -days 3650 -nodes -config "$TMP/cert.cnf" -sha256 >/dev/null 2>&1
    openssl pkcs12 -export -out "$TMP/cert.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
        -passout pass:arioso -legacy >/dev/null 2>&1
    security import "$TMP/cert.p12" -k ~/Library/Keychains/login.keychain-db -P arioso -T /usr/bin/codesign -A >/dev/null
    rm -rf "$TMP"
fi
APP_ENTITLEMENTS="$ENTITLEMENTS"
if [ "$USE_SPARKLE" = "1" ]; then
    # Sparkle's own code is signed first (inside out), with the same certificate as the app.
    SPARKLE_FW="$CONTENTS/Frameworks/Sparkle.framework"
    codesign --force --options runtime --sign "$LOCAL_CERT" "$SPARKLE_FW/Versions/B/Autoupdate"
    codesign --force --options runtime --sign "$LOCAL_CERT" "$SPARKLE_FW/Versions/B/Updater.app"
    codesign --force --options runtime --sign "$LOCAL_CERT" "$SPARKLE_FW"
    # This certificate has no Apple Team ID, so macOS's library validation would refuse to
    # load Sparkle next to the app. Only this build gets the exception; the App Store build has no Sparkle.
    APP_ENTITLEMENTS="build/direct.entitlements"
    cp "$ENTITLEMENTS" "$APP_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$APP_ENTITLEMENTS"
fi
codesign --force --options runtime --entitlements "$APP_ENTITLEMENTS" --sign "$LOCAL_CERT" "$APP"
file "$CONTENTS/MacOS/Arioso"

if [ "${SKIP_INSTALL:-0}" = "1" ]; then
    echo "Built and signed $APP (SKIP_INSTALL: nothing installed, no zip or dmg)."
    exit 0
fi

echo "Retiring old launch agents and screensaver pieces on this Mac..."
for label in com.alakhveer.Arioso.LockShortcut com.alakhveer.Arioso.Widget \
             com.alakhveer.LyricsSaver.LockShortcut com.alakhveer.LyricsSaver.Widget; do
    plist="$HOME/Library/LaunchAgents/$label.plist"
    if [ -f "$plist" ]; then
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
        rm -f "$plist"
    fi
done
rm -rf "$HOME/Library/Screen Savers/Arioso.saver" "$HOME/Library/Screen Savers/LyricsSaver.saver"
if defaults -currentHost read com.apple.screensaver moduleDict 2>/dev/null | grep -qE 'Arioso|LyricsSaver'; then
    defaults -currentHost delete com.apple.screensaver moduleDict
fi
defaults delete -g com.alakhveer.Arioso.settings 2>/dev/null || true
defaults delete -g com.alakhveer.LyricsSaver.settings 2>/dev/null || true
rm -rf "/Applications/LyricsSaver.app" "/Applications/LyricsSaver Settings.app"

echo "Installing to /Applications on this Mac..."
osascript -e 'quit app id "com.alakhveer.Arioso"' 2>/dev/null || true
rm -rf "/Applications/Arioso.app"
ditto "$APP" "/Applications/Arioso.app"

echo "Zipping build/Arioso.zip..."
rm -f build/Arioso.zip
ditto -c -k --sequesterRsrc --keepParent "$APP" build/Arioso.zip

echo "Making build/Arioso.dmg (styled drag-to-Applications window)..."
# dmgbuild lays out the window (background, icon positions) without scripting
# Finder. It lives in a private venv under build/ so nothing is installed globally.
DMG_TOOLS="build/.dmgtools"
if [ ! -x "$DMG_TOOLS/bin/dmgbuild" ]; then
    python3 -m venv "$DMG_TOOLS"
    "$DMG_TOOLS/bin/pip" install --quiet dmgbuild
fi
rm -f build/Arioso.dmg
"$DMG_TOOLS/bin/dmgbuild" -s dmg/settings.py -D app="$APP" "Arioso" build/Arioso.dmg 2>/dev/null
cp build/Arioso.dmg website/Arioso.dmg

echo ""
echo "Built and installed /Applications/Arioso.app (universal, not sandboxed)."
echo "Open it from Spotlight (\"Arioso\"). Press ⌥⌘L for full-screen lyrics."
echo ""
echo "For the Mac App Store, run again with APP_STORE=1 and your signing details"
echo "(see the top of this script), then upload build/Arioso.pkg with Transporter."
