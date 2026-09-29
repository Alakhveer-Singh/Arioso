#!/bin/bash
# Publishes an update for the direct-download build.
#
#   1. VERSION=1.1 ./build_app.sh        builds build/Arioso.app and build/Arioso.zip
#   2. ./make_appcast.sh                 signs the zip and adds it to website/appcast.xml
#   3. Upload website/appcast.xml and website/updates/Arioso-<version>.zip to the site
#      (and the new Arioso.dmg, for people downloading fresh). Installed copies of
#      Arioso find the new version the next time they check.
#
# The zip is signed with your Sparkle key, which lives in your login Keychain (made
# once with build/.sparkle/*/bin/generate_keys). Installed copies only accept updates
# signed by it, so keep a backup:  generate_keys -x sparkle-private-key  (store it safely).
#
# Release notes: put an HTML snippet in release-notes/<version>.html (a <ul> is fine).
# Without one, the update window just says "Arioso <version>".
#
# Switches (all optional): APP, ZIP, APPCAST, UPDATES_DIR, NOTES_FILE, and
# ARCHIVE_URL_PREFIX (where the zip will be hosted; default: the website's updates/ folder;
# use https://github.com/<you>/Arioso/releases/download/v<version>/ to host it on GitHub Releases).
set -euo pipefail
cd "$(dirname "$0")"

APP="${APP:-build/Arioso.app}"
ZIP="${ZIP:-build/Arioso.zip}"
APPCAST="${APPCAST:-website/appcast.xml}"
UPDATES_DIR="${UPDATES_DIR:-website/updates}"
URL_PREFIX="${ARCHIVE_URL_PREFIX:-https://alakhveer.com/arioso/updates/}"
SITE_URL="${SITE_URL:-https://alakhveer.com/arioso/}"
SPARKLE_BIN="build/.sparkle/2.10.0/bin"

die() { echo "make_appcast: $*" >&2; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist"; }

[ -x "$SPARKLE_BIN/sign_update" ] || die "Sparkle isn't downloaded yet. Run ./build_app.sh once first."
[ -d "$APP" ] || die "$APP not found. Run ./build_app.sh first."
[ -f "$ZIP" ] || die "$ZIP not found. Run ./build_app.sh first (without SKIP_INSTALL)."
[ "$(plist SUFeedURL 2>/dev/null)" != "" ] || die "$APP has no updater in it (built with NO_SPARKLE or APP_STORE?)."

VERSION="$(plist CFBundleShortVersionString)"
BUILD="$(plist CFBundleVersion)"
MIN_OS="$(plist LSMinimumSystemVersion)"
NOTES_FILE="${NOTES_FILE:-release-notes/$VERSION.html}"
NAME="Arioso-$VERSION.zip"

if [ -f "$APPCAST" ] && grep -q "<sparkle:version>$BUILD</sparkle:version>" "$APPCAST"; then
    die "build $BUILD ($VERSION) is already in $APPCAST. Build again to get a new build number."
fi
if [ -f "$APPCAST" ] && grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$APPCAST"; then
    die "version $VERSION is already in $APPCAST. Use a new VERSION (e.g. VERSION=1.0.1 ./build_app.sh)."
fi

# Signs with the key in your Keychain; prints: sparkle:edSignature="…" length="…"
SIGNATURE="$("$SPARKLE_BIN/sign_update" "$ZIP")" || die "couldn't sign the zip (is the Sparkle key in your Keychain?)"
case "$SIGNATURE" in *edSignature=*) ;; *) die "unexpected output from sign_update: $SIGNATURE" ;; esac

mkdir -p "$UPDATES_DIR"
cp "$ZIP" "$UPDATES_DIR/$NAME"

if [ -f "$NOTES_FILE" ]; then NOTES="$(cat "$NOTES_FILE")"; else NOTES="<p>Arioso $VERSION</p>"; fi
PUBDATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"

APPCAST="$APPCAST" VERSION="$VERSION" BUILD="$BUILD" MIN_OS="$MIN_OS" NOTES="$NOTES" PUBDATE="$PUBDATE" \
URL="$URL_PREFIX$NAME" SIGNATURE="$SIGNATURE" SITE_URL="$SITE_URL" python3 - <<'PY'
import os, pathlib
p = pathlib.Path(os.environ["APPCAST"])
notes = os.environ["NOTES"].replace("]]>", "]]]]><![CDATA[>")
item = f"""    <item>
      <title>Version {os.environ['VERSION']}</title>
      <pubDate>{os.environ['PUBDATE']}</pubDate>
      <sparkle:version>{os.environ['BUILD']}</sparkle:version>
      <sparkle:shortVersionString>{os.environ['VERSION']}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{os.environ['MIN_OS']}</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes}]]></description>
      <enclosure url="{os.environ['URL']}" {os.environ['SIGNATURE']} type="application/octet-stream"/>
    </item>
"""
if p.exists():
    text = p.read_text(encoding="utf-8")
    marker = "    <item>" if "    <item>" in text else "  </channel>"
    text = text.replace(marker, item + marker, 1)   # newest first
else:
    p.parent.mkdir(parents=True, exist_ok=True)
    text = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Arioso</title>
    <link>{os.environ['SITE_URL']}</link>
    <description>Updates for Arioso</description>
    <language>en</language>
{item}  </channel>
</rss>
"""
p.write_text(text, encoding="utf-8")
PY

echo "Added Arioso $VERSION (build $BUILD) to $APPCAST"
echo "Upload: $APPCAST and $UPDATES_DIR/$NAME  ->  $URL_PREFIX$NAME"
