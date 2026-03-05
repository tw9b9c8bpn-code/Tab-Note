# Tab Note

Tab Note is a menu-bar-first macOS notes app with tabbed notes, rich text editing, AI actions, detachable tab windows, and Sparkle auto-updates.

## Current Release

- Version: `1.0.1` (build `2`)
- Bundle ID: `Kien-Tran.Tab-Note`
- Repository: [tw9b9c8bpn-code/Tab-Note](https://github.com/tw9b9c8bpn-code/Tab-Note)
- Website: [kientran.ca](https://kientran.ca)

## Highlights

- Configurable global hotkey (default `Cmd+Shift+S`).
- Rich text styling (Title, Heading, Subheading, Body, Bulleted/Dashed/Numbered lists).
- On-demand search bar with `Cmd+F`.
- Formatting persistence across tab switches.
- Undo/redo support for styling changes.
- Drag tab out to detach into a new window; drag back to merge.
- Tab context action: **Open in New Window**.
- Sparkle update integration (`Check for Updates`, auto-check on launch).

## Keyboard Shortcuts

- `Cmd+T`: New note
- `Cmd+Space`: Delete note / close tab
- `Cmd+Shift+T`: Recover deleted tab
- `Cmd+1..9`: Switch to tab 1-9
- `Cmd+Option+Left/Right`: Move tab left/right
- `Cmd+L`: Rename current tab
- `Cmd+B` / `Cmd+I`: Bold / Italic
- `Cmd+U`: Highlight text
- `Cmd+F`: Toggle search bar

## Build Locally

Requirements:

- macOS + Xcode with Swift 5 toolchain
- Deployment target configured in project: `macOS 26.2`

Build debug:

```bash
xcodebuild -project "Tab Note.xcodeproj" -scheme "Tab Note" -configuration Debug -sdk macosx build
```

Build release:

```bash
xcodebuild -project "Tab Note.xcodeproj" -scheme "Tab Note" -configuration Release -sdk macosx build
```

## Auto Update (Sparkle)

Auto update is configured through Sparkle with:

- `SUFeedURL` in `Info.plist` (points to repo `appcast.xml`)
- `SUPublicEDKey` in `Info.plist`

Menu/status entry and Settings both expose update actions.

## Packaging Convention

When distributing releases, generate a drag-and-drop DMG in `~/Downloads` that includes:

- `Tab Note.app`
- `Applications` symlink (`/Applications`)

This is the artifact intended for Gumroad/manual distribution.

## Credits

Created by [Kien Tran](https://kientran.ca)
