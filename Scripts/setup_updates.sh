#!/usr/bin/env bash
#
# setup_updates.sh — one-time setup for automatic updates (Sparkle).
#
#   Scripts/setup_updates.sh
#
# 1. Downloads Sparkle's tools.
# 2. Creates the update-signing key in your login Keychain (or reuses it).
# 3. Writes the matching public key into MiliControl/Resources/Info.plist.
# 4. Checks the GitHub CLI is ready for Scripts/release.sh.
#
# Safe to run again: it never replaces an existing key.
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

step "Sparkle tools"
TOOLS="$(sparkle_tools)"
ok "Ready ($(basename "$(dirname "$TOOLS")"))"

step "Update-signing key"
if KEY="$("$TOOLS/generate_keys" -p 2>/dev/null)" && [[ -n "$KEY" ]]; then
    ok "Using the key already in your Keychain"
else
    # Stored in the default keychain — make sure that's your login keychain.
    DEFAULT_KC="$(security default-keychain | tr -d ' "')"
    [[ "$DEFAULT_KC" == *login.keychain* ]] || fail "Your default keychain is $DEFAULT_KC.
  Switch it first:  security default-keychain -s ~/Library/Keychains/login.keychain-db"
    "$TOOLS/generate_keys" >/dev/null
    KEY="$("$TOOLS/generate_keys" -p)"
    ok "Created a new key in your login Keychain"
fi

step "Info.plist"
CURRENT="$(plist_value "$INFO_PLIST" SUPublicEDKey)"
if [[ "$CURRENT" == "$KEY" ]]; then
    ok "Public key already set"
else
    [[ -z "$CURRENT" ]] || warn "Replacing a different public key — builds with the old key can't update to new ones."
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $KEY" "$INFO_PLIST"
    ok "Public key written (commit this change)"
fi

step "GitHub CLI"
if ! command -v gh >/dev/null; then
    warn "Not installed. Install it:  brew install gh   then:  gh auth login"
elif ! gh auth status >/dev/null 2>&1; then
    warn "Not signed in. Run:  gh auth login"
else
    ok "Signed in"
fi

printf "\n"
bold "✅ Updates are set up."
cat <<EOF
   Back up the private key somewhere safe (a password manager). If it's lost,
   installed copies can't accept updates any more:

     "$TOOLS/generate_keys" -x ~/Desktop/MiliControl-update-key.txt

   Then store that file safely and delete it from the Desktop.
EOF
