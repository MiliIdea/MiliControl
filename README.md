# MiliControl

Arrange your Mac's desktops into a **grid of rows** and move around it with the
keyboard. Every move is macOS's own native slide — MiliControl decides *where*
to go, macOS does the switch.

```
Row 1:   [1] [2] [3]
Row 2:   [4] [5] [6] [7] [8]
```

| Shortcut | Action |
|---|---|
| **⌃⌥ ← / →** | Previous / next desktop **in the current row** (wraps within the row) |
| **⌃⌥ ↑ / ↓** | Previous / next row (lands on the first desktop of that row, or the same column — your choice) |
| **⌃↑** (or ⌃⌥Space) | Open the grid editor |

What happens depends on how long you hold the **arrow**:

- **Tap** the arrow → instant slide to the next desktop, no overlay. Keep
  holding ⌃⌥ and tap again to keep moving.
- **Hold** the arrow 0.3 s → the grid appears. Tap arrows to choose,
  release ⌃⌥ → one slide straight there (like ⌘-Tab).

The grid is **your** arrangement: open the editor and drag desktops between
rows, add or remove rows. It's saved automatically.

---

## Install

1. Open `MiliControl.xcodeproj` in Xcode 15 or later (macOS 13+).
2. Press **⌘R**. After every successful build the scheme automatically
   installs **/Applications/MiliControl.app** (quitting any running copy
   first) and runs that installed copy.
3. The Settings window opens with a setup checklist — follow it until
   everything is green.

> **Why /Applications?** Accessibility permission is tied to one stable copy
> of the app. Installing to the same place on every build keeps the
> permission working. Install log: `/tmp/MiliControl-install.log`.

## One-time macOS setup

The Settings window checks all of these live and has a button for each.

1. **Accessibility** — System Settings ▸ Privacy & Security ▸ Accessibility ▸
   enable **MiliControl**, then quit & reopen it. (Needed to send the switch
   shortcut.)
2. **Switch to Desktop N** — System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸
   Mission Control ▸ check **Switch to Desktop 1 … N** for every desktop.
3. **Automatically rearrange Spaces** — System Settings ▸ Desktop & Dock ▸
   Mission Control ▸ **off** (otherwise macOS renumbers your desktops).
4. **Mission Control ⌃↑** — uncheck **Mission Control** in Keyboard Shortcuts ▸
   Mission Control, *or* choose ⌃⌥Space for the grid editor in MiliControl.

### Recommended workflow

One app per desktop, filling the screen (Window ▸ Fill, or ⌥-click the green
button — not fullscreen). Pin each app to its desktop: right-click its Dock
icon ▸ Options ▸ Assign To ▸ **This Desktop**.

## Limitations (macOS, not MiliControl)

- **Up to 16 desktops** (macOS's maximum). Desktops 1–9 switch in one slide
  out of the box. Desktops 10–16 work immediately via a short multi-slide
  route; give each a "Switch to Desktop N" shortcut (Settings ▸ Desktops
  10–16 walks you through it) for one instant slide.
- **Fullscreen apps aren't in the grid.** They aren't numbered desktops. Use
  Fill-sized windows on regular desktops instead.
- **Four-finger swipes** (optional, Settings ▸ Navigation) move through the
  grid, but switch after the swipe rather than following your fingers — turn
  macOS's own four-finger gestures off or set them to three fingers.
- **Single display** is the supported setup.

## How it works

| Layer | Files |
|---|---|
| Rules (pure, tested) | `Core/GridLayout.swift`, `Core/Navigator.swift` |
| macOS integration | `System/` — reads Spaces (read-only private CGS calls), reads your keyboard-shortcut table, sends "Switch to Desktop N", global hotkeys, setup checks |
| Features | `Features/Navigation` (hotkeys → HUD → switch), `Features/GridEditor`, `Features/Settings`, `Features/MenuBar`, `Features/Updates` (Sparkle) |

MiliControl never switches or modifies Spaces through private API — it only
reads them — and never writes system preferences.

## Download

Get the latest DMG from
[Releases](https://github.com/MiliIdea/MiliControl/releases/latest), open it
and drag MiliControl onto Applications. After that MiliControl updates itself
(Settings ▸ Updates).

## Releasing

Releases live on GitHub; each one has two assets — the notarized DMG and
`appcast.xml`, the update feed. Installed copies read
`releases/latest/download/appcast.xml`, so publishing a release is what ships
the update. Updates are [Sparkle](https://sparkle-project.org), EdDSA-signed.

### One-time setup

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

### Every release

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

## Development

```bash
swift test                               # grid + navigation rules
python3 Scripts/generate_project.py .    # regenerate the Xcode project after adding files
```

Logs: Console.app, subsystem `com.mili.MiliControl`.
