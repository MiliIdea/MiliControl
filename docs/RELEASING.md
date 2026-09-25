# Releasing MiliControl

Releases live on GitHub. Each one has two assets — the notarized DMG and
`appcast.xml`, the update feed. Installed copies read
`releases/latest/download/appcast.xml`, so publishing a release is what ships
the update. Updates use [Sparkle](https://sparkle-project.org) and are
EdDSA-signed.

## One-time setup

1. Notarization credentials, stored in your Keychain (app-specific password
   from appleid.apple.com):
   ```bash
   xcrun notarytool store-credentials "MiliControl-notary" \
       --apple-id "you@example.com" --team-id "JK772YMH8E"
   ```
2. A **Developer ID Application** certificate in your *login* keychain:
   Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID
   Application.
3. The update-signing key and the GitHub CLI:
   ```bash
   Scripts/setup_updates.sh     # creates the key, writes the public key into Info.plist
   brew install gh && gh auth login
   ```
   Back up the private key as the script explains — without it, installed
   copies can't be updated.

## Every release

1. Bump **Version** and **Build** in Xcode (target ▸ General). The build
   number must go up every time.
2. Write `ReleaseNotes/<version>.md` (a few `- ` bullets), commit, `git push`.
3. **Product ▸ Archive** ▸ Distribute App ▸ **Direct Distribution**; when it's
   "Ready to distribute", **Export** to your Desktop.
4. Publish:
   ```bash
   Scripts/release.sh ~/Desktop/MiliControl.app
   ```
   It checks versions and keys, builds the notarized DMG (`make_dmg.sh`),
   writes the feed, asks once, then creates GitHub release `v<version>`.

`Scripts/make_dmg.sh` alone builds just the installer. Installer artwork:
`Design/dmg-background.svg` (rendered to `Scripts/dmg/background*.png`).

> Share the **GitHub link**, not the DMG file itself over Telegram: files
> saved by the App Store version of Telegram are tagged so macOS refuses to
> open the app.
