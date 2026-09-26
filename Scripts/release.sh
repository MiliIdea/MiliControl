#!/usr/bin/env bash
#
# release.sh — publishes a MiliControl release on GitHub.
#
#   Scripts/release.sh [path/to/MiliControl.app]
#
# Input:  the notarized app from Xcode ▸ Archive ▸ Distribute App ▸ Direct
#         Distribution ▸ Export (default: ~/Desktop/MiliControl.app), and
#         release notes in ReleaseNotes/<version>.md.
# Output: GitHub release v<version> on MiliIdea/MiliControl with two assets:
#           MiliControl-<version>.dmg   the installer (signed, notarized)
#           appcast.xml                 the update feed for this version
#
# Installed copies read
#   https://github.com/MiliIdea/MiliControl/releases/latest/download/appcast.xml
# which always resolves to the newest release — so publishing IS updating.
#
# Needs (once): Scripts/setup_updates.sh, notarization credentials (see
# make_dmg.sh), and the GitHub CLI signed in (gh auth login).
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# --publish-only: upload the DMG + feed already in dist/ (after an earlier
# run that built them but didn't publish).
PUBLISH_ONLY=0
if [[ "${1:-}" == "--publish-only" ]]; then PUBLISH_ONLY=1; shift; fi
APP="${1:-$HOME/Desktop/MiliControl.app}"
FEED="https://github.com/$REPO/releases/latest/download/appcast.xml"

# ---------------------------------------------------------------------------
step "Checking everything before building"

command -v gh >/dev/null || fail "GitHub CLI missing. Install:  brew install gh   then:  gh auth login"
gh auth status >/dev/null 2>&1 || fail "GitHub CLI isn't signed in. Run:  gh auth login"
ok "GitHub CLI signed in"

[[ -d "$APP" ]] || fail "Not found: $APP — export it from Xcode first, or pass its path."
APP_PLIST="$APP/Contents/Info.plist"
VERSION="$(plist_value "$APP_PLIST" CFBundleShortVersionString)"
BUILD="$(plist_value "$APP_PLIST" CFBundleVersion)"
MIN_OS="$(plist_value "$APP_PLIST" LSMinimumSystemVersion)"
[[ "$BUILD" =~ ^[0-9]+$ ]] || fail "Build number must be a whole number (got '$BUILD')."
TAG="v$VERSION"
ok "MiliControl $VERSION (build $BUILD)"

# The app must trust the key we're about to sign with.
APP_KEY="$(plist_value "$APP_PLIST" SUPublicEDKey)"
[[ -n "$APP_KEY" ]] || fail "This build has no update key. Run Scripts/setup_updates.sh, commit, then archive again."
TOOLS="$(sparkle_tools)"
KEY="$("$TOOLS/generate_keys" -p 2>/dev/null)" || fail "No update-signing key in your Keychain. Run Scripts/setup_updates.sh."
[[ "$KEY" == "$APP_KEY" ]] || fail "The app's public key doesn't match the key in your Keychain."
ok "Update key matches"

NOTES="$ROOT/ReleaseNotes/$VERSION.md"
[[ -s "$NOTES" ]] || fail "Write the release notes first: ReleaseNotes/$VERSION.md (a few '- ' bullet lines)."
ok "Release notes found"

gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 \
    && fail "Release $TAG already exists. Bump the version in Xcode (target ▸ General)."
PUBLISHED="$(curl -fsSL "$FEED" 2>/dev/null \
    | sed -n 's:.*<sparkle\:version>\([0-9]*\)</sparkle\:version>.*:\1:p' | head -1 || true)"
if [[ -n "$PUBLISHED" ]]; then
    (( BUILD > PUBLISHED )) || fail "Build $BUILD isn't newer than the published build $PUBLISHED — installed copies would ignore it. Bump the build in Xcode."
    ok "Newer than the published build ($PUBLISHED)"
else
    ok "First release with updates"
fi

# The release is tagged at your current commit, so it must be on GitHub.
git -C "$ROOT" fetch --quiet origin 2>/dev/null || fail "Couldn't reach the git remote 'origin'."
[[ -n "$(git -C "$ROOT" branch -r --contains HEAD 2>/dev/null)" ]] \
    || fail "Your latest commit isn't on GitHub yet. Run:  git push"
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || warn "You have uncommitted changes — they won't be in the tagged source."
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
ok "Commit ${COMMIT:0:7} is on GitHub"

# ---------------------------------------------------------------------------
DMG="$ROOT/dist/MiliControl-$VERSION.dmg"
APPCAST="$ROOT/dist/appcast.xml"
if [[ "$PUBLISH_ONLY" == "1" ]]; then
    [[ -f "$DMG" && -f "$APPCAST" ]] || fail "No built release in dist/ for $VERSION — run without --publish-only."
    grep -q "<sparkle:version>$BUILD</sparkle:version>" "$APPCAST" \
        || fail "dist/appcast.xml isn't for build $BUILD — run without --publish-only."
    ok "Using dist/$(basename "$DMG") and dist/appcast.xml"
else
"$SCRIPTS_DIR/make_dmg.sh" "$APP"
[[ -f "$DMG" ]] || fail "make_dmg.sh didn't produce $DMG"

# ---------------------------------------------------------------------------
step "Writing the update feed"

SIGNATURE="$("$TOOLS/sign_update" "$DMG")"
ED_SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGNATURE")"
LENGTH="$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<<"$SIGNATURE")"
[[ -n "$ED_SIGNATURE" && -n "$LENGTH" ]] || fail "sign_update gave unexpected output: $SIGNATURE"
ok "Signed the DMG for Sparkle"

# Release notes: a tiny Markdown subset (# headings, - bullets, paragraphs) → HTML.
NOTES_HTML="$(awk '
    function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
    function close_list() { if (inlist) { print "</ul>"; inlist = 0 } }
    /^[[:space:]]*$/                 { close_list(); next }
    /^#+[[:space:]]/                 { close_list(); sub(/^#+[[:space:]]+/, ""); print "<h3>" esc($0) "</h3>"; next }
    /^[[:space:]]*[-*][[:space:]]/   { if (!inlist) { print "<ul>"; inlist = 1 }
                                       sub(/^[[:space:]]*[-*][[:space:]]+/, ""); print "<li>" esc($0) "</li>"; next }
                                     { close_list(); print "<p>" esc($0) "</p>" }
    END                              { close_list() }
' "$NOTES")"

APPCAST="$ROOT/dist/appcast.xml"
DOWNLOAD="https://github.com/$REPO/releases/download/$TAG/$(basename "$DMG")"
PUB_DATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"
cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MiliControl</title>
    <link>https://github.com/$REPO</link>
    <language>en</language>
    <item>
      <title>MiliControl $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_OS:-13.0}</sparkle:minimumSystemVersion>
      <description><![CDATA[
$NOTES_HTML
      ]]></description>
      <enclosure url="$DOWNLOAD"
                 type="application/octet-stream"
                 length="$LENGTH"
                 sparkle:edSignature="$ED_SIGNATURE"/>
    </item>
  </channel>
</rss>
XML
if command -v xmllint >/dev/null; then
    xmllint --noout "$APPCAST" || fail "dist/appcast.xml isn't valid XML."
fi
ok "dist/appcast.xml"
fi

# ---------------------------------------------------------------------------
step "Publishing"
printf "  Release %s on github.com/%s with:\n    %s\n    appcast.xml\n" "$TAG" "$REPO" "$(basename "$DMG")"
# Ask on the terminal itself: earlier steps (notarization, Finder scripting)
# can swallow keys typed ahead on stdin. RELEASE_YES=1 skips the question.
if [[ "${RELEASE_YES:-0}" != "1" ]]; then
    # Drop anything typed while the build was running, then ask.
    while read -r -t 1 -n 1000 _ < /dev/tty; do :; done    # (whole seconds: macOS bash 3.2)
    printf "  Publish now? Everyone with MiliControl will be offered it. [y/N] "
    read -r ANSWER < /dev/tty || ANSWER=""
    ANSWER="$(printf "%s" "$ANSWER" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    if [[ "$ANSWER" != "y" && "$ANSWER" != "yes" ]]; then
        warn "Not published. Files are in dist/ — publish them without rebuilding:"
        printf "    Scripts/release.sh --publish-only\n"
        exit 0
    fi
fi

gh release create "$TAG" "$DMG" "$APPCAST" \
    --repo "$REPO" --target "$COMMIT" \
    --title "MiliControl $VERSION" --notes-file "$NOTES" >/dev/null
ok "Published $TAG"

# GitHub's "latest" redirect can lag a few seconds.
for _ in 1 2 3 4 5 6; do
    if curl -fsSL "$FEED" 2>/dev/null | grep -q "<sparkle:version>$BUILD</sparkle:version>"; then
        ok "Update feed now serves $VERSION"
        break
    fi
    sleep 5
done

printf "\n"
bold "✅ MiliControl $VERSION is out: https://github.com/$REPO/releases/tag/$TAG"
printf "   Installed copies pick it up within a day, or right away via Check for Updates….\n"
