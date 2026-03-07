# HANDOVER (Tab Note)

## Completed in this pass (2026-03-07, visual architecture explainer)
- Created a self-contained visual architecture + flow explainer HTML for Tab Note at:
  - `/Users/kientran/.agent/diagrams/tab-note-architecture-flow.html`
- The page explains:
  - overall app architecture
  - inline AI request flow
  - frontend vs app-local service layer vs external backend systems
  - key source files to read first
- Important architectural framing captured in the explainer:
  - Tab Note does not have its own dedicated remote backend server
  - most "backend" behavior lives inside the macOS app process (`AppDelegate`, `NotesStore`, `SettingsManager`, `AIService`, `AppUpdater`)
  - external systems are mainly CloudKit, the configured AI endpoint, and Sparkle appcast/update delivery

## Completed in this pass (2026-03-07, unified prompt injection manifest)
- Replaced the hardcoded prompt injection enums/labels with a data-backed configuration layer shared with Octopus.AI.
- Added bundled manifest assets under:
  - `/Users/kientran/Desktop/KiensApps/Tab Note/Tab Note/PromptInjection/options.catalog.json`
  - `/Users/kientran/Desktop/KiensApps/Tab Note/Tab Note/PromptInjection/tab-note.profile.json`
- Runtime shared config path is now:
  - `~/Library/Application Support/KienConfig/PromptInjection/`
- App bootstraps the shared files into that folder if missing, then reads external files first so both apps can converge on the same catalog/profile model.
- Important runtime detail: Xcode currently copies these JSON files into top-level app `Resources`, not `Resources/PromptInjection`, so the loader now checks both bundle locations before failing.
- Canonical dimensions now match the Octopus system:
  - `response_length`
  - `response_mode`
  - `expert_mode`
  - `voice_mode`
- `SettingsManager`, footnote controls, inline AI options, and popup menus now render from manifest IDs instead of hardcoded Swift enums.
- Added legacy ID normalization so old saved selections still map into canonical IDs.

## User preferences and dislikes
- Prefers one unified, scalable, data-based prompt injection system across apps.
- Dislikes duplicated hardcoded prompt config living separately in each app.
- Prefers cleaner Swift with prompt rules/options stored in manifest-style data rather than embedded UI logic.
- Prefers visual, browser-openable architecture explanations with real flow diagrams instead of plain text-only summaries.
- Wants app flow split clearly into frontend, local app service layer, and external backend/integration systems.

## Completed in this pass (2026-03-07, speech task handoff checkpoint)
- Used `speech` skill path and validated environment for TTS generation request.
- Confirmed bundled CLI exists at:
  - `/Users/kientran/.codex/skills/speech/scripts/text_to_speech.py`
- Current blocker:
  - `OPENAI_API_KEY` is not set in this shell (and also missing in interactive `zsh`), so no live audio can be generated yet.
- Ready-to-run command once key is set:
  - `export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"`
  - `export TTS_GEN="$CODEX_HOME/skills/speech/scripts/text_to_speech.py"`
  - `python "$TTS_GEN" speak --input "<USER_TEXT>" --voice cedar --instructions "Voice Affect: Clear and grounded. Tone: Curious and practical. Pacing: Steady, slightly brisk. Emotion: Thoughtful and confident. Pronunciation: Enunciate SwiftUI, AI popup, and deterministic clearly. Pauses: Brief pause after each question block. Emphasis: Stress 'what does it really mean', 'can it really be achieved', and 'crash course'." --response-format mp3 --out "/Users/kientran/Desktop/KiensApps/output/speech/local-model-and-tab-note-questions.mp3"`

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

## Completed in this pass (2026-03-05, full Sparkle + release pipeline)
- Sparkle is now fully wired in project/target:
  - Added SPM package ref to `https://github.com/sparkle-project/Sparkle` (locked to `2.9.0` in `Package.resolved`).
  - Linked `Sparkle` product into app target frameworks.
- Updater runtime is production mode:
  - `AppUpdater.swift` now imports Sparkle directly (no fallback stub branch).
  - Updater config check now requires both `SUFeedURL` and `SUPublicEDKey`.
- Info.plist update config is set:
  - `SUFeedURL = https://raw.githubusercontent.com/tw9b9c8bpn-code/Tab-Note/main/appcast.xml`
  - `SUPublicEDKey = //TvgDdI78p/XZUGdsSHtrhnU0yZ9/YaBEX/XHvxGnU=`
  - Added `CFBundleShortVersionString=$(MARKETING_VERSION)` and `CFBundleVersion=$(CURRENT_PROJECT_VERSION)` for release gating.
- Version bumped to release:
  - `MARKETING_VERSION = 1.0.1`
  - `CURRENT_PROJECT_VERSION = 2`
- Sparkle feed/artifacts shipped:
  - Added `appcast.xml` at repo root.
  - Created Sparkle update ZIP from notarized app:
    - `/Users/kientran/Downloads/Tab-Note-1.0.1.zip`
    - `sparkle:edSignature="galItskxC4uEvsxYMKZKU4YkEpdvfLJBp1BKrRUcd+PD7gvos7mlTwwe+ss0yW+wORsiyUHBXMNIP257Xju0BA=="`
    - `length="1698322"`
- GitHub release published:
  - Repo: `https://github.com/tw9b9c8bpn-code/Tab-Note` (set to public for appcast access)
  - Tag/Release: `v1.0.1`
  - URL: `https://github.com/tw9b9c8bpn-code/Tab-Note/releases/tag/v1.0.1`
  - Assets:
    - `Tab-Note-1.0.1.zip` (Sparkle update payload)
    - `Tab-Note-1.0.1.dmg` (manual installer)
- Notarization/stapling status:
  - Archive exported for `developer-id` and uploaded to Apple notarization service via Xcode CLI.
  - Notarized app exported with `xcodebuild -exportNotarizedApp`.
  - Stapled/validated app:
    - `/Users/kientran/Downloads/TabNote-1.0.1-notarized/Tab Note.app`
    - `spctl`: `accepted` / `source=Notarized Developer ID`
  - DMG is rebuilt from notarized app and includes `Applications` symlink in Downloads.

## Known remaining item
- DMG itself was not separately notarized+stapled in this run:
  - `stapler` on DMG failed with missing ticket (`Record not found`), which means no DMG notarization ticket yet.
  - App inside DMG is notarized and stapled already.

## Next steps for next AI
1. If strict notarized-DMG is required, submit `/Users/kientran/Downloads/Tab-Note-1.0.1.dmg` to notary service and staple the DMG ticket.
2. Manual smoke test on a clean user account:
   - install DMG
   - run app
   - `Check for Updates` should parse `appcast.xml` from GitHub raw.
3. For next release, repeat this flow with incremented version/build and new Sparkle ZIP signature.

## Completed in this pass (2026-03-05, skill hardening)
- Updated skill: `~/.codex/skills/macos-app-release-packager` for full routine reuse.
  - Added orchestrator script:
    - `scripts/release_end_to_end.sh` (readiness -> archive/export -> notarization upload/poll -> app stapling -> Sparkle ZIP/signature -> appcast rewrite -> DMG -> optional DMG notary -> git tag/push -> GitHub release upload).
  - Improved readiness script:
    - `scripts/verify_release_readiness.sh` now also checks Sparkle pin in `Package.resolved` and GitHub CLI auth status.
  - Updated docs and checklist:
    - `SKILL.md`, `references/release-checklist.md`, `agents/openai.yaml`.
  - Validation:
    - `quick_validate.py ~/.codex/skills/macos-app-release-packager` -> `Skill is valid!`

## Completed in this pass (2026-03-05, docs sync)
- Added root `README.md` with:
  - app overview + current version/build metadata
  - updated feature list (configurable hotkey, search, styling, drag detach/merge, updater)
  - keyboard shortcuts
  - local build commands
  - Sparkle update notes
  - DMG packaging convention (`~/Downloads`, includes `Applications` symlink)
- Updated handover log for continuity before context handoff.

## Completed in this pass (2026-03-05, inline AI question answer)
- Added inline AI answer trigger from footnote bar:
  - New `?` button next to AI controls posts an editor-targeted action for current window.
- Added typing trigger:
  - Typing exactly `???` in editor now triggers inline AI answer for the sentence at cursor.
- Implemented sentence-level AI answer flow in editor:
  - Detects sentence around caret, calls AI with strict constraints (plain text, one paragraph, <100 words), and inserts response on a new line below that sentence.
  - Preserves rich-text/undo pipeline by inserting through editor undo-aware replacement.
  - Guards against duplicate in-flight requests and cross-tab note switches during response.
## Completed in this pass (2026-03-06, inline AI popup + status streaming)
- Changed inline question-answer behavior (`?` and `???`):
  - AI no longer inserts text into the note body.
  - AI response now opens in a transient popover anchored near the current caret position in the editor.
- Added live status streaming for inline AI jobs to footnote bar:
  - Introduced `.inlineAIStatusDidChange` notification.
  - Footnote now updates status text + spinner in real time while inline AI is working.
- Added cancellation/status safety:
  - If user switches notes mid-request, inline job is marked cancelled and status is cleared cleanly.
## Completed in this pass (2026-03-06, AI matrix panel + popup sizing)
- Inline AI answer popover now adapts size to response length (dynamic width/height with min/max bounds).
- Revamped footnote AI controls:
  - Removed `?` button.
  - Stars button now toggles an AI prompt-injection panel (second footnote row, same height) with:
    - Response Length presets: `XS`, `S`, `M`, `L`, `XL`
    - Response Mode dropdown: `A`, `S`, `D`, `I`, `M`, `R`, `IS`, `T`, `80`, `2O`, `TL`, `FP`
- `???` remains the master trigger for inline AI response generation.
- Added local hotkey `Cmd+Option+A` to toggle AI matrix panel per active window.
- AI inline generation now injects selected matrix instructions from settings into the prompt pipeline.
## Completed in this pass (2026-03-06, ??? paragraph capture fix)
- Changed inline AI trigger context extraction from sentence-level to paragraph-level:
  - `???` now sends the full paragraph containing the cursor to AI.
- Added trigger cleanup:
  - trailing `???` marker is stripped from paragraph before sending to AI context.
- Updated inline status phrasing from sentence -> paragraph for clarity.
- Updated AI prompt wording to reflect paragraph context.
## Completed in this pass (2026-03-06, AI footnote icon matrix + Cmd+Opt+A fix)
- AI matrix controls updated in footnote panel:
  - Removed visible `Length` / `Mode` text labels.
  - Replaced large dropdown/chips with compact icon-based popup menus:
    - Length icon
    - Response mode icon
    - Expert discipline icon
    - Voice figure icon
  - Added right-side `Clear` button to reset all AI prompt injections to neutral.
- Added full Expert/Voice mode persistence + prompt injection plumbing:
  - `SettingsManager` now stores:
    - `aiExpertDisciplinePreset`
    - `aiVoiceFigurePreset`
  - Added enum-backed helpers + injection accessors for both.
  - Inline AI prompt builder now merges length + mode + expert + voice instructions.
- Cmd+Option+A reliability fix:
  - Local key monitor now uses tolerant modifier matching (ignores extra helper flags and accepts keycode or charactersIgnoringModifiers).
- Defaults adjusted to neutral behavior:
  - response length default -> `L` (no forced limit instruction)
  - response mode default -> `None`
## Completed in this pass (2026-03-06, AI footnote polish + new trigger)
- Main footnote AI control is now icon-only (`wand.and.stars`) with no background shape.
- AI matrix row refinements:
  - `Clear all` is now a simple trash icon (no fill/border/text).
  - Response length moved to inline quick-picks (`XS/S/M/L/XL`) with outlined-circle selection style.
  - Mode/Expert/Voice controls use subtler small icons with hidden menu arrows and active-opacity emphasis.
- Hotkey update:
  - AI matrix toggle changed from `Cmd+Option+A` to `Cmd+Shift+I` (including quick guide/help text).
- Inline AI trigger update:
  - Added `?` then `Tab` trigger (in addition to existing `???` trigger).
- AI response popover improvements:
  - Header now shows active AI summary chip (e.g. `M • FP • Psy • Rand`) instead of static `AI Answer`.
  - Response body now renders rich text from Markdown when present.
  - Prompt instructions now explicitly allow readability-focused lightweight Markdown output.
## Completed in this pass (2026-03-06, AI footnote sizing/UI tune)
- AI footnote mode icon sizing normalized:
  - mode/expert/voice/trash now share unified compact icon metrics for visual consistency.
- Response length quick-picks refined:
  - no fill/background shape
  - inactive = gray text
  - active = tight circle stroke + high-contrast text
- Inline AI response popover sizing made more adaptive:
  - short answers now use compact widths/heights
  - longer answers expand width/height via measured text layout up to larger caps.
## Completed in this pass (2026-03-06, compactness pass per UI feedback)
- Compressed AI footnote layout to remove spaced-out look:
  - reduced row horizontal padding
  - reduced inter-control spacing
  - length quick-picks now tightly packed (`spacing = 1`)
  - controls no longer split by a large middle gap.
- Shrunk mode icons further and reduced inactive opacity:
  - mode/expert/voice/trash icon frame + glyph sizes reduced.
  - inactive opacity lowered for clearer active/inactive contrast.
- Length selector visual tightening:
  - no background/fill shapes; text + optional tight circle stroke only.
  - inactive text now dimmed directly (no inactive ring/shape).
## Completed in this pass (2026-03-06, remove default control chrome from AI footnote)
- Root cause of “big gray capsules” identified:
  - length buttons were still inheriting default macOS button chrome.
  - mode/expert/voice `Menu` controls still rendered system-sized control shells.
- Fixes implemented:
  - length picker buttons now explicitly `buttonStyle(.plain)` (no default background shapes).
  - mode/expert/voice switched from `Menu` controls to plain icon buttons + compact custom popovers.
  - icon metrics and inactive opacity reduced again for subtle appearance.
## Completed in this pass (2026-03-06, paragraph formatting + icon scale tweak)
- Inline AI answer readability improvements:
  - prompt now explicitly requires blank lines between paragraphs and avoids heading-body merges.
  - client-side normalization now fixes common punctuation spacing and injects paragraph breaks for dense wall-of-text responses.
  - added extra line spacing for rendered answer text in the popover.
- AI footnote UI sizing updates:
  - all AI matrix icons increased (about 50%) via shared control metrics.
  - added explicit spacer gap between response-length picker and mode/expert/voice icons.
  - length picker text/circle also scaled up accordingly.
## Completed in this pass (2026-03-06, markdown rendering + focus hotkey)
- Inline AI popover markdown rendering hardened:
  - Added preprocessing for malformed speaker-label markdown and glued heading/body text.
  - Added multi-stage markdown parsing fallback (`full` -> `inline preserving whitespace` -> plain sanitized fallback).
  - Switched popover body rendering to paragraph-based rich text blocks with explicit spacing for readable breaklines.
- Inline AI popover sizing now measures prepared text (post-normalization), improving short vs long response fit.
- Focus-mode hotkey robustness:
  - `Cmd+Shift+H` detection now uses layout-safe matching (physical keycode or character), mirroring the `Cmd+Shift+I` approach.
## Completed in this pass (2026-03-06, AI popover metrics + font toggle fix)
- AI response popover header now shows compact metadata at top-right: word count, estimated token count, and estimated cost.
- Popover sizing logic expanded to use screen-aware width/height caps and larger candidates so long responses require less scrolling.
- Fixed unwanted line breaks before normal inline bold text by narrowing paragraph-splitting regex to speaker/label patterns only.
- Font toggle now truly applies selected font family to existing rich-text content (preserving point size and bold/italic traits), not just future typing.
- Removed background shape from the font toggle control in footnote (plain icon/text style only).
## Completed in this pass (2026-03-06, copy UX + reopen mechanism)
- AI popover content now renders as one continuous rich-text block (still preserving paragraph breaks), allowing cross-paragraph selection/copy in a single drag.
- Added spacing normalization around inline bold markers so text no longer glues to `**bold**` tokens.
- Metadata line now always includes estimated dollar cost explicitly (`est $...`) alongside words and token estimate.
- Added inline recovery control near the AI trigger area:
  - After an AI response is generated, a tiny reopen icon appears near that position.
  - Clicking it reopens the last AI response popover after transient dismissal.
- Recovery UI is cleared on tab switches to avoid stale anchors.
## Completed in this pass (2026-03-06, inline AI markers + cancel + resizable popover)
- `Escape` now cancels in-flight inline AI generation through a cancelable `AIService` request path.
- Replaced floating recovery button with inline `ℹ` markers stored in rich text via custom link payloads:
  - each AI answer inserts its own marker,
  - markers can be clicked to reopen the answer,
  - markers can be right-clicked and deleted,
  - markers move with the surrounding text because they are inline content.
- Paragraph extraction now strips inline AI markers before sending text back to AI.
- AI popover now:
  - attempts full markdown rendering first, then falls back more safely,
  - supports a bottom-right `Copy All` action,
  - uses flexible layout so resize can expand content instead of fighting a fixed frame.
- Popover window is configured as resizable after presentation; manual runtime verification still recommended for the actual resize affordance feel on macOS.
## Completed in this pass (2026-03-06, AI popover renderer + sizing hardening)
- AI marker placement is now anchored to the actual inline trigger/question mark location instead of a looser cursor position:
  - new markers stack immediately to the right of existing markers at that trigger.
- AI response popover now uses a custom attributed-text markdown renderer instead of `Text(AttributedString)`:
  - strips markdown control symbols,
  - renders headings, bullets, numbered lists, quotes, bold/italic/code,
  - preserves readable paragraph spacing in one selectable text surface.
- AI popover header/footer refinements:
  - top-right metadata now shows `words • ~tokens • $cost` (no `est`),
  - added hover `$` icon with model-family pricing heuristic info,
  - `Copy All` is now a subtle icon button.
- Added explicit bottom-right resize grip inside the popover and kept hard caps at `380w x 600h`.
- Marker icon was enlarged to a filled `info.circle.fill` attachment for easier hit-testing.
## Completed in this pass (2026-03-06, AI marker anchor + pricing popover + appearance sync)
- Exact trigger locations are now captured at the moment `???` or `?`+`Tab` fires:
  - this removes the loose fallback path that could insert the AI marker at the document start,
  - markers should now insert beside the trigger question mark more reliably.
- Replaced the hover-only `$` help text with a real click popover showing token-based dollar estimates for:
  - current active model,
  - Claude Sonnet / Opus,
  - GPT/Codex flagship + mini,
  - Grok,
  - DeepSeek,
  - MiniMax,
  - Local.
- Removed the extra resize icon from the AI panel footer while keeping the panel itself resizable.
- AI panel appearance now follows app dark/light mode:
  - panel window appearance is synced,
  - the embedded attributed text view also updates its appearance.
- Reduced editor churn by no longer bouncing local `currentRTF` state on every rich-text change from typing.
- Added a forced editor appearance/color normalization pass on reload/theme changes to reduce text invisibility/flicker caused by stale foreground colors.
## Completed in this pass (2026-03-06, popup-only AI answers + tab-state repair)
- Removed inline AI marker insertion from the live response flow:
  - AI answers now open only in the popover and no new inline `i` attachment is inserted into the note text.
- Added load-time sanitization for old inline AI marker attachments when RTF is restored, so previously saved marker icons stop appearing in the editor.
- Reworked `ContentView` editor ownership to bind `NoteEditorView` directly to the currently selected note instead of mirroring note text/RTF through local `@State`.
  - this avoids stale note content/RTF being replayed into the editor during tab switches.
- Added `.id(selectedNoteID)` on `NoteEditorView` so AppKit editor state is rebuilt cleanly when switching tabs.
## Completed in this pass (2026-03-06, persistent streaming AI panel + adjacent tab hotkeys)
- Added real-time AI response streaming for inline-question answers:
  - `AIService.answerQuestionSentence(...)` now streams partial output for both Ollama (`/api/chat`, NDJSON) and OpenAI-compatible chat endpoints (`stream: true`, SSE/line parsing),
  - `Escape` cancellation still works against the shared in-flight request.
- Replaced the text-view-owned AI popover lifecycle with a shared panel controller:
  - the AI response panel now opens immediately and updates live as text streams in,
  - it no longer closes when switching tabs because it is no longer tied to the current `NSTextView` instance,
  - explicit manual close via the window close button suppresses the rest of that response instead of reopening itself mid-stream.
- Removed visible scrollbars from the AI response panel while preserving scroll behavior inside the text area.
- Added adjacent tab switching hotkeys:
  - `Cmd+Option+Shift+Left` selects the tab to the left,
  - `Cmd+Option+Shift+Right` selects the tab to the right,
  - existing `Cmd+Option+Left/Right` tab-reordering hotkeys were kept intact.
- Important implementation detail: the old inline-marker code paths still exist for legacy payload decoding/cleanup, but new live AI answers use only the shared panel controller.
## Completed in this pass (2026-03-06, popover titlebar transparency + Cmd+Space tab close hardening)
- Created a pre-change checkpoint commit before this pass: `3007c75` (`checkpoint: persistent streaming AI panel and tab hotkeys`).
- Hardened `Cmd+Space` tab closing in two places:
  - App-level local monitor now uses normalized modifier matching instead of raw exact flag matching,
  - editor-level `performKeyEquivalent` also closes the selected tab directly when the text view has focus.
- AI response panel window chrome was reduced further:
  - titlebar is now transparent / separatorless,
  - panel window background is clear + non-opaque,
  - content is pushed down with a transparent top clearance so the close button sits over clear space instead of over the content card.
## Completed in this pass (2026-03-06, borderless AI panel + inline close control)
- AI response panel no longer uses a native titlebar or standard red close button.
- Panel window is now borderless/resizable, and the close action is a low-profile inline `xmark` button in the top-left of the popover header, positioned left of the summary chip.
- Removed the old titlebar spacer logic from the popover sizing/layout and rebalanced chrome height for the borderless presentation.
## Completed in this pass (2026-03-06, close-tab behavior revert + draggable AI header polish)
- Reverted the extra `Cmd+Space` tab-close interception back to the original app/editor handling so the user's restored global shortcut setup is no longer overridden by new matching logic.
- Fixed post-close tab selection to choose the immediate visual left neighbor of the closed tab instead of jumping to the first tab.
- Made the borderless AI response panel header draggable by using a dedicated drag region across the full top strip.
- Improved the custom close button with a larger hit target, hover feedback, and a subtle scale/background animation.
- Added a monochrome animated gradient treatment for the `Thinking...` state before streamed response text arrives.- Manual runtime check still recommended: close a middle tab and confirm selection moves to the immediate left tab, then drag the AI panel from its header and verify the custom close button feels reliable.

## Completed in this pass (2026-03-06, compact AI header alignment fix)
- Reduced the animated `Thinking...` label back down to a smaller size (`12pt`) so it no longer overpowers the panel while streaming.
- Fixed the borderless AI panel top-strip layout so the header remains a fixed-height bar and the full panel content stays pinned to the top-left when the window is manually resized larger.
## Completed in this pass (2026-03-06, editable AI prompt chip + replay)
- Narrowed the AI panel footer interaction strip so the copy control now occupies roughly 70% of the panel width instead of spanning the full footer row.
- Replaced the static summary chip with live per-answer prompt controls in the AI panel header:
  - response length is always editable from the header,
  - active response mode / expert discipline / voice selections are editable in place from the same header,
  - added a replay button to regenerate the answer using the updated local prompt selections.
- Added an `AIService.InlineAnswerOptions` snapshot so panel replay regenerates from the original paragraph context without mutating the global footnote settings.
- Kept compatibility with the old legacy inline-answer payload presenter path so historical saved payloads still open.
## Completed in this pass (2026-03-06, AI panel placeholders + follow-up field)
- The AI response panel header now always shows all prompt groups as selectable controls: length, mode, expert, and voice. Unselected groups render as placeholders (`Mode`, `Expert`, `Voice`) so they can be chosen directly from the top bar before replay.
- Added a compact pill-style follow-up text field to the center of the AI panel footer while keeping the copy action at the right edge of the reduced-width footer strip.
- Added per-answer follow-up request handling in the shared AI panel controller, including replay of follow-up answers with the correct preserved context and restoring the previous answer if a replay/follow-up is cancelled or fails.
## Completed in this pass (2026-03-06, AI panel min-width + footer cleanup)
- Raised the AI response panel minimum width to `366pt` across its seeded content size, preferred sizing logic, window min size, and SwiftUI frame so the initial open state no longer clips the right edge / rounded corner.
- Removed the footer copy button entirely.
- Shifted the follow-up field lower by reducing the panel's bottom padding, kept it centered in the reduced-width footer strip, and made the `Follow up` placeholder more subtle with lower-opacity prompt styling.
## Completed in this pass (2026-03-06, web architecture diagram)
- The requested `visualizer explainer plugin` was not available in this session, so a direct fallback was created instead.
- Added a standalone clickable web architecture diagram for the app at `docs/tab-note-architecture-diagram.html`.
- The diagram maps the app shell, NotesStore/persistence, editor surface, AI panel, settings layer, updater path, and external model-provider flow.

## Completed in this pass (2026-03-06, shared prompt-routing skill package)
- Added shared reusable skill package at:
  `/Users/kientran/Desktop/KiensApps/skills/prompt-injection-routing-kit`
- Captured the current Tab Note inline pattern as one host archetype inside the skill:
  - compact inline/header controls,
  - single-select mode/expert/voice caps,
  - developer/system-prompt routing profile.
- Paired that with the Octopus multi-surface web-overlay archetype so future apps can reuse one shared 4-dimension system instead of re-deriving enums/prompts/UI rules from scratch.

## Completed in this pass (2026-03-06, AI popup font + hotkey + thinking duration)
- Synced the inline AI popup body typography with the main editor font choice while keeping code blocks and inline code on a fixed monospaced treatment.
- Made the app’s global show/hide hotkey temporarily hide and restore the inline AI popup together with the main panel instead of leaving the popup stranded onscreen.
- Replaced the transient thinking-only treatment with elapsed timing: the popup now shows live `Thinking... Ns` updates while running and preserves a static `Thought for Ns` label after completion.

## Completed in this pass (2026-03-07, inline AI popup replication skill package)
- Added a dedicated shared skill package at:
  `/Users/kientran/Desktop/KiensApps/skills/inline-ai-response-panel`
- The skill captures the exact working Tab Note popup stack:
  - shared panel controller + model architecture,
  - manual markdown-to-attributed-text renderer,
  - top prompt capsule header + replay behavior,
  - top-right metrics + pricing popover,
  - bottom follow-up pill,
  - borderless adaptive panel chrome and drag behavior.
- It also documents the important drift warning that Tab Note has its own extra `E (example)` response mode on top of the Octopus-style prompt dimensions.

## Completed in this pass (2026-03-07, Codex GUI install + skill-creator safeguard)
- Installed the popup replication skill into Codex-visible locations:
  - `~/.codex/skills/inline-ai-response-panel`
  - `~/.agents/skills/inline-ai-response-panel`
- Updated `~/.codex/skills/.system/skill-creator` so future skill work explicitly includes:
  - syncing finished skills into `$CODEX_HOME/skills` for Codex GUI visibility,
  - a dedicated installer script: `scripts/install_skill_to_codex.py`,
  - a warning that `default_prompt` values containing `$skill-name` must be shell-quoted correctly so `$` is not expanded away before `openai.yaml` generation.

## Completed in this pass (2026-03-07, generate-web-diagram skill)
- Created a reusable Codex-visible skill at `~/.codex/skills/generate-web-diagram`.
- The skill packages the exact browser-openable architecture-diagram workflow used for Tab Note:
  - inspect app shell, state, UI surfaces, and integrations first,
  - generate one standalone HTML file with inline CSS/JS,
  - prefer an interactive board plus inspector over ASCII or prose-only output.
- Added proper Codex UI metadata in `agents/openai.yaml` and a reusable starter asset at `assets/interactive-architecture-template.html`.
