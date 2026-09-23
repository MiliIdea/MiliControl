#!/usr/bin/env bash
#
# make_dmg.sh — builds a signed, notarized, drag-to-install MiliControl DMG.
#
#   Scripts/make_dmg.sh [path/to/MiliControl.app]
#
# Input: the app from Xcode ▸ Archives ▸ Distribute App ▸ Direct Distribution ▸
#        Export (default: ~/Desktop/MiliControl.app).
# Output: dist/MiliControl-<version>.dmg, ready to share.
#
# One-time setup, so the script can notarize for you (stored in your Keychain):
#
#   xcrun notarytool store-credentials "MiliControl-notary" \
#       --apple-id "you@example.com" --team-id "JK772YMH8E"
#
#   (It asks for an app-specific password — create one at appleid.apple.com ▸
#    Sign-In and Security ▸ App-Specific Passwords.)
#
# Options (environment variables):
#   NOTARY_PROFILE   keychain profile name        (default: MiliControl-notary)
#   SIGN_IDENTITY    "Developer ID Application: …" (default: auto-detected)
#   SKIP_NOTARIZE=1  build and sign only (for a quick local test)
#
set -euo pipefail

APP="${1:-$HOME/Desktop/MiliControl.app}"
NOTARY_PROFILE="${NOTARY_PROFILE:-MiliControl-notary}"
VOLUME_NAME="MiliControl"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS="$SCRIPT_DIR/dmg"
DIST="$ROOT/dist"

# Window geometry — must match Design/dmg-background.svg.
WINDOW_W=660; WINDOW_H=400
ICON_SIZE=112
APP_X=170; APPS_X=490; ICONS_Y=205

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
step()  { printf "\n\033[1;34m▸ %s\033[0m\n" "$*"; }
ok()    { printf "  \033[32m✓\033[0m %s\n" "$*"; }
fail()  { printf "\n\033[1;31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
step "Checking the app"

[[ -d "$APP" ]] || fail "Not found: $APP
  Export it first: Xcode ▸ Window ▸ Organizer ▸ Archives ▸ Distribute App ▸
  Direct Distribution ▸ Export — or pass its path to this script."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "0")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null || echo "0")"
ok "MiliControl $VERSION ($BUILD)"

# Stray Finder metadata breaks strict signature checks on other Macs.
xattr -cr "$APP"
codesign --verify --deep --strict "$APP" 2>/dev/null \
    || fail "The app's signature isn't valid. Re-export it from Xcode (Direct Distribution)."
ok "Signature valid"

ASSESSMENT="$(spctl -a -t exec -vv "$APP" 2>&1 || true)"
if [[ "$ASSESSMENT" != *"Notarized Developer ID"* ]]; then
    fail "This app isn't notarized (Gatekeeper says: $(echo "$ASSESSMENT" | head -2 | tr '\n' ' ')).
  Export it with Distribute App ▸ Direct Distribution, and wait for 'Ready to distribute'."
fi
ok "App is notarized"

# Prefer the certificate in the login keychain: other keychains (e.g. one a CI
# tool created) may hold a same-named key behind a password you don't know.
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"
SIGN_KEYCHAIN_ARGS=()
SIGN_LABEL="${SIGN_IDENTITY:-}"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    find_id() {  # prints "<sha1> <name>" of the first Developer ID Application identity
        security find-identity -v -p codesigning "$@" 2>/dev/null \
            | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "\(Developer ID Application:[^"]*\)".*/\1 \2/p' | head -1
    }
    FOUND="$(find_id "$LOGIN_KC")"
    if [[ -n "$FOUND" ]]; then
        SIGN_KEYCHAIN_ARGS=(--keychain "$LOGIN_KC")
    else
        FOUND="$(find_id)"
        [[ -n "$FOUND" ]] && printf "  \033[33m!\033[0m Certificate isn't in your login keychain — macOS may ask for another keychain's password.\n"
    fi
    SIGN_IDENTITY="${FOUND%% *}"          # SHA-1: unambiguous even with duplicate names
    SIGN_LABEL="${FOUND#* }"
fi
if [[ -n "$SIGN_IDENTITY" ]]; then
    ok "Signing as: $SIGN_LABEL"
else
    # Xcode's Direct Distribution signs with a cloud-managed certificate that
    # never lands in the Keychain. The app inside is already signed and
    # notarized, so the DMG can still be notarized — just not signed itself.
    printf "  \033[33m!\033[0m No local 'Developer ID Application' certificate — the DMG won't be signed\n"
    printf "    itself (the app inside is). To add one: Xcode ▸ Settings ▸ Accounts ▸ Manage\n"
    printf "    Certificates… ▸ + ▸ Developer ID Application.\n"
fi

# ---------------------------------------------------------------------------
step "Preparing the installer window"

WORK="$(mktemp -d -t milicontrol-dmg)"
trap 'hdiutil detach "$MOUNT_DIR" -quiet -force >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
MOUNT_DIR=""
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"

ditto "$APP" "$STAGE/MiliControl.app"
ln -s /Applications "$STAGE/Applications"

# Retina-ready background: combine 1x + 2x into one multi-resolution TIFF.
if [[ -f "$ASSETS/background@2x.png" ]]; then
    tiffutil -cathidpicheck "$ASSETS/background.png" "$ASSETS/background@2x.png" \
        -out "$STAGE/.background/background.tiff" >/dev/null 2>&1
    BACKGROUND="background.tiff"
else
    cp "$ASSETS/background.png" "$STAGE/.background/background.png"
    BACKGROUND="background.png"
fi
ok "Staged app, Applications shortcut and background"

# Make sure no older "MiliControl" volume is mounted (Finder would get confused).
if [[ -d "/Volumes/$VOLUME_NAME" ]]; then
    hdiutil detach "/Volumes/$VOLUME_NAME" -quiet -force || true
fi

RW_DMG="$WORK/rw.dmg"
# Headroom for the Finder layout file and the volume icon added below.
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -quiet -volname "$VOLUME_NAME" -srcfolder "$STAGE" \
    -fs HFS+ -format UDRW -size "${SIZE_MB}m" -ov "$RW_DMG"
MOUNT_DIR="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" \
    | sed -n 's|.*\(/Volumes/.*\)$|\1|p' | tail -1)"
[[ -d "$MOUNT_DIR" ]] || fail "Couldn't mount the temporary disk image."

# Lay out the Finder window: size, icon positions, background, no toolbars.
LEFT=200; TOP=120
if osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {$LEFT, $TOP, $((LEFT + WINDOW_W)), $((TOP + WINDOW_H))}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to $ICON_SIZE
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:$BACKGROUND"
        set position of item "MiliControl.app" of container window to {$APP_X, $ICONS_Y}
        set position of item "Applications" of container window to {$APPS_X, $ICONS_Y}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
then
    ok "Styled the window"
else
    printf "  \033[33m!\033[0m Couldn't style the Finder window (allow Terminal to control Finder in\n"
    printf "    System Settings ▸ Privacy & Security ▸ Automation). The DMG still works, just unstyled.\n"
fi

# Hide the background folder and give the volume the app's icon.
SetFile -a V "$MOUNT_DIR/.background" 2>/dev/null || true
if [[ -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

sync
hdiutil detach "$MOUNT_DIR" -quiet
MOUNT_DIR=""

# ---------------------------------------------------------------------------
step "Compressing and signing the DMG"

mkdir -p "$DIST"
OUT="$DIST/MiliControl-$VERSION.dmg"
rm -f "$OUT"
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT"
if [[ -n "$SIGN_IDENTITY" ]]; then
    if ! codesign ${SIGN_KEYCHAIN_ARGS[@]+"${SIGN_KEYCHAIN_ARGS[@]}"} --sign "$SIGN_IDENTITY" --timestamp "$OUT"; then
        fail "Couldn't sign the DMG. Usually the Keychain is locked or blocked codesign:
  1. security unlock-keychain ~/Library/Keychains/login.keychain-db
  2. Run this script again. If macOS asks to let codesign use your key,
     enter your Mac password and click 'Always Allow'.
  Still failing? Install the 'Developer ID - G2' intermediate certificate from
  https://www.apple.com/certificateauthority/ (double-click it), then retry."
    fi
    ok "Signed $(basename "$OUT")"
else
    ok "Built $(basename "$OUT") (unsigned container; notarization still applies)"
fi

# ---------------------------------------------------------------------------
if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
    step "Skipping notarization (SKIP_NOTARIZE=1)"
    bold "Built: $OUT  (not notarized — fine for testing on this Mac only)"
    exit 0
fi

step "Notarizing with Apple (usually 1–5 minutes)"
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    fail "No notarization credentials named '$NOTARY_PROFILE'. Run once:
  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id \"you@example.com\" --team-id \"JK772YMH8E\"
  then run this script again. (The signed DMG is at $OUT.)"
fi
xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait \
    || fail "Notarization failed. See details with:
  xcrun notarytool log <submission-id> --keychain-profile \"$NOTARY_PROFILE\""
xcrun stapler staple -q "$OUT"
ok "Notarized and stapled"

step "Final check"
if [[ -n "$SIGN_IDENTITY" ]]; then
    spctl -a -t open --context context:primary-signature -v "$OUT" 2>&1 | sed 's/^/  /'
fi
xcrun stapler validate -q "$OUT" && ok "Ticket attached — opens offline on any Mac"

printf "\n"
bold "✅ Ready to share: $OUT"
printf "   Send it as a file. Double-click opens the installer window; drag MiliControl onto Applications.\n"
