# HANDOVER (Tab Note)

## Completed in this pass
- Fixed rich text persistence and tab-switch resets:
  - `NoteEditorView` now saves RTF on style changes.
  - `ContentView` now passes `noteId` into `NoteEditorView` so tab-change reload is reliable.
  - `NotesStore.updateNoteRTF` now updates `modifiedAt` and saves.
- Implemented functional on-demand search (`Cmd+F`):
  - Search bar toggles on demand.
  - Enter in search bar jumps to next match in editor.
  - First match auto-selected when query changes.
- Improved style actions:
  - Title/Heading/Subheading/Body now affect typing attributes even when no text is selected.
  - Added shared `TextStyleCommand` model.
- Added style options to status bar pull-down menu:
  - New `Text Style` submenu in tray menu.
  - Applies style to selected text in active editor.
- Added a proper About section in Quick Guide:
  - “Created by Kien Tran” with hyperlink to `https://kientran.ca`.
- Hotkey UX improvements:
  - Settings now shows current hotkey label.
  - Global hotkey re-registration is explicit and logs success/failure.
- Update menu improvements:
  - Status menu now includes `Check for Updates`, `Auto-check on Launch`, and a config status line.
  - Updater alert now clearly states Sparkle/SUFeedURL are missing.

## Completed in this pass (2026-03-05, later checkpoint)
- Created git checkpoint commit before additional work:
  - `checkpoint: stabilize editor styling/search and updater menu wiring`
- Removed search icon button from footnote bar (search remains `Cmd+F`).
- Fixed undo for styling/formatting operations:
  - Added explicit undo/redo registration for attribute-only style changes (Title/Heading/Subheading/Body, Bold/Italic, Highlight).
- Implemented drag tab detach/merge behavior:
  - Drag tab and drop outside any tab bar -> creates a separate window.
  - Drag tab onto a tab bar area (same or different window) -> merges/moves into that window.
  - Added per-window tab ownership (`TabNote.windowID`) and per-window selected tab state in `NotesStore`.
  - Added multi-panel management in `AppDelegate` for detached windows.
  - Detached window close merges remaining tabs back to main window.

## Completed in this pass (2026-03-05, real-time drag feedback)
- Added live drag state tracking:
  - `NotesStore.ActiveTabDrag` + `begin/update/endTabDrag` to track source, pointer, and live target window.
- Added real-time visual cues while dragging:
  - Dragged tab gets active drag styling (opacity/scale/dashed outline).
  - Target tab bar shows dashed drop-target border + “Drop to merge tab” hint.
  - Source window shows “Release to create a new window” hint when not hovering any tab bar.
- Added AppDelegate drag lifecycle bridging:
  - `beginTabDrag`, `updateTabDrag`, `finishTabDrag` wire gesture updates into store + existing detach/merge handler.
- Added tab context menu action:
  - Right-click tab -> `Open in New Window` now detaches that tab using existing `detachNoteToNewWindow(...)`.
- Build verification:
  - `xcodebuild -project 'Tab Note.xcodeproj' -scheme 'Tab Note' -configuration Debug -sdk macosx build` -> `BUILD SUCCEEDED`.

## Completed in this pass (2026-03-05, packaging)
- Used `macos-app-release-packager` skill workflow.
- Release gate check executed:
  - `~/.codex/skills/macos-app-release-packager/scripts/verify_release_readiness.sh '/Users/kientran/Desktop/KiensApps/Tab Note'`
  - Result: FAILED (`SUFeedURL` missing, `SUPublicEDKey` missing, `CFBundleShortVersionString` missing, `CFBundleVersion` missing, updater still has fallback/stub marker).
- Built Release app successfully:
  - `xcodebuild -project 'Tab Note.xcodeproj' -scheme 'Tab Note' -configuration Release -sdk macosx build`
- Created drag-and-drop installer DMG in Downloads (with `Applications` symlink):
  - `/Users/kientran/Downloads/Tab-Note-1.0.dmg`
  - SHA-256: `742d6a7a97a63cf2ab9b9507a1fec35c2ca77197a36d07e69f84ba94b0f3d99b`
- DMG content check passed:
  - Contains `Tab Note.app`
  - Contains `Applications -> /Applications` symlink

## Completed in this pass (2026-03-05, release skill setup)
- Created reusable skill: `~/.codex/skills/tab-note-release-packager`.
  - Includes release workflow + extra gates (Sparkle/appcast, Dock+Menu Bar behavior, notarize/staple, DMG packaging).
  - Scripts:
    - `scripts/verify_release_readiness.sh` (checks Info.plist keys, updater/menu wiring, and Sparkle stub presence).
    - `scripts/create_installer_dmg.sh` (creates DMG with app + `Applications` symlink; default output is `~/Downloads`).
  - Reference: `references/release-checklist.md`.
  - Metadata generated: `agents/openai.yaml`.
- Validation:
  - `quick_validate.py ~/.codex/skills/tab-note-release-packager` -> `Skill is valid!`
  - Readiness check against current repo fails on:
    - missing `SUFeedURL`
    - missing `SUPublicEDKey`
    - missing `CFBundleShortVersionString`
    - missing `CFBundleVersion`
    - Sparkle stub still present in `AppUpdater.swift`

## Completed in this pass (2026-03-05, generalized release skill)
- Added cross-app skill: `~/.codex/skills/macos-app-release-packager` for any macOS app release.
  - Generic readiness script: `scripts/verify_release_readiness.sh` with auto-detection + optional explicit file args.
  - Generic DMG script: `scripts/create_installer_dmg.sh` that derives app name from `.app` bundle and creates drag-and-drop DMG with `Applications` symlink.
  - Generic checklist: `references/release-checklist.md`.
- Validation:
  - `quick_validate.py ~/.codex/skills/macos-app-release-packager` -> `Skill is valid!`
  - DMG script tested with sample app bundle; mounted DMG contains `.app` + `Applications` symlink.

## Completed in this pass (2026-03-05, GitHub release push gate)
- Updated `~/.codex/skills/macos-app-release-packager` to include GitHub push/tag requirements.
  - Added script: `scripts/git_release_push.sh`:
    - requires clean working tree
    - creates annotated tag `v<version>` if needed
    - pushes branch + tag to remote (default `origin`)
  - Updated `SKILL.md` workflow + checklist reference with GitHub release-source gates.
- Validation:
  - `quick_validate.py ~/.codex/skills/macos-app-release-packager` -> `Skill is valid!`
  - `git_release_push.sh` tested with temp repo + bare remote (`main` + `v1.2.3` pushed).

## Known remaining item
- True auto-update is still not fully configured because:
  - Sparkle package is not linked in the Xcode project.
  - `SUFeedURL` (and Sparkle signing keys) are not set in Info.plist/build config.
- Drag behavior caveat:
  - Current detach/merge trigger is app-level (mouse location + tab-bar frame hit testing).
  - It now has live visual feedback, but is still not a full AppKit `NSDraggingSession` tab system.

## Next steps for next AI
1. Add Sparkle dependency to target in Xcode project.
2. Set `SUFeedURL` and `SUPublicEDKey`.
3. Verify update flow with a real appcast and signed release zip.
4. Manual QA:
   - Style from right-click + status menu.
   - Switch tabs repeatedly; confirm formatting stays.
   - `Cmd+F` search next-match behavior.
