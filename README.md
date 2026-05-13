# Key Layout Manager

Small native macOS utility for moving Adobe Premiere Pro keyboard layout
(`.kys`) files between machines. SwiftUI, non-sandboxed, Developer ID
signed for distribution.

Premiere stores per-user keyboard layouts at:

```
~/Documents/Adobe/Premiere Pro/<version>/Profile-<username>/Mac/<Name>.kys
```

Moving those layouts between Macs today means hunting through nested
Adobe folders in Finder. This app collapses that to one window:

- **Export** — browse all `.kys` files Premiere has on the local machine,
  multi-select, and either drag them straight into Slack / Mail / Finder
  or export to a folder, iCloud Drive, or Dropbox.
- **Restore** — drop a `.kys` file from anywhere onto the window (or
  pick via file panel); the app auto-detects the Premiere profile on the
  current machine and copies the file in, with collision prompts
  (Overwrite / Keep both / Skip, plus "Apply to all remaining").

The data model is shaped so phase 2 can add workspace XMLs
(`Profile-*/Layouts/`) and presets (`Profile-*/Settings/`) without a
rewrite — hence the broader project name.

## Requirements

- macOS 14 or later
- Xcode 15+ for development
- An Apple Developer ID for signed, notarized distribution

## Setup

```bash
./setup.sh
```

This installs [XcodeGen](https://github.com/yonaskolb/XcodeGen) via
Homebrew if needed, then generates `KeyLayoutManager.xcodeproj` from
`project.yml`. The `.xcodeproj` is gitignored — never hand-edit it; change
`project.yml` and re-run `xcodegen`.

If `xcode-select -p` points at Command Line Tools, switch it:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

Then:

```bash
open KeyLayoutManager.xcodeproj
```

Set your Team in **Signing & Capabilities**, hit Run.

## Project layout

```
KeyLayoutManager/
  App/        # @main + RootView (TabView root)
  Models/     # PremiereItemKind, ProfileLocation, KeyboardLayout, PremiereInstall
  Services/   # PremiereScanner, CopyService, CloudTargets, TempStage
  Features/
    Export/   # source list, drag source, four export targets
    Restore/  # drop zone, destination picker, collision alert
  Resources/  # Info.plist, entitlements
  Assets.xcassets/
KeyLayoutManagerTests/
  PremiereScannerTests.swift
  CopyServiceTests.swift
project.yml   # XcodeGen config
setup.sh      # bootstrap
```

## Run the unit tests

```bash
xcodebuild test -scheme KeyLayoutManager -destination 'platform=macOS'
```

Tests cover the scanner (empty `Mac/`, missing `Mac/`, multi-digit
version sort, non-version sibling dirs) and `CopyService` policies
(overwrite, keepBoth name-bumping, skip, prompt routing).

## Manual test plan

1. **Empty-version edge.** Launch app. Export tab shows newest Premiere
   version → profile → `.kys` rows. Older versions with no `.kys` files
   render an "(no .kys files)" line, not a crash.
2. **Drag.** Drag a row from Export into Finder → file lands. Drag into
   a Slack compose / Mail compose → attaches.
3. **Export to…** Pick a folder via Save panel, confirm file arrives.
4. **iCloud backup.** If `~/Library/Mobile Documents/com~apple~CloudDocs/`
   exists, the button is visible and writes to
   `KeyLayoutManager/<version>/<filename>` in iCloud Drive.
5. **Dropbox backup.** If `~/Library/CloudStorage/Dropbox*` (or
   `~/Dropbox`) exists, the Dropbox button mirrors the iCloud behavior.
   Hidden otherwise.
6. **Restore.** Drop a `.kys` file on the Restore tab. Destination
   picker auto-selects the only profile if there's one; defaults to
   newest version otherwise. Click Restore.
7. **Collision prompt.** Restore the same file again — Overwrite / Keep
   both / Skip alert appears with an "Apply to all remaining" toggle.
   `Keep both` produces `Name (2).kys`.
8. **TCC.** First launch shows a one-time "Documents folder" access
   prompt. Approve once.

## Distribution

Non-sandboxed, hardened runtime, empty entitlements file. After Archive
→ Distribute App → Developer ID → Export:

```bash
xcrun notarytool submit KeyLayoutManager.zip \
  --keychain-profile "Notary" --wait
xcrun stapler staple KeyLayoutManager.app
```

## Roadmap

- Phase 1 (current): `.kys` keyboard layouts only.
- Phase 2: workspace XMLs (`Profile-*/Layouts/UserWorkspace.xml`,
  `WorkspaceConfig.xml`) and presets (`Profile-*/Settings/`).
