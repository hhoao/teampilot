# Context-aware Mod+F: chord claims, double-shift-only workspace search, and full-transcript chat find

## Problem

`Mod+F` currently opens the **workspace search dialog** (`CommandIds.workspaceSearch`, bound to `KeyChord('f', mods: [mod])` in `CommandCatalog.v1`) in every context where a workspace is open (`when: hasWorkspace`). But Flutter's `KeyEventManager` always delivers the same key event to **both** the global `ShortcutDispatcher` (a `HardwareKeyboard` handler in `main.dart`) **and** the focused widget's `Shortcuts`/`Focus` handling. The consequence, exactly as documented in `terminal_passthrough_shortcuts.dart`:

- Pressing `Mod+F` in the **code editor** fires *both* re-editor's inline find (its own `Shortcuts` → `CodeShortcutFindIntent`) *and* the global workspace search dialog — a modal steals focus and the UX is broken.
- The **chat page** (`SessionChatView`) has no find at all, even though it renders long transcripts.
- The **terminal** deliberately routes `Mod+F` to workspace search (`terminalPassthrough: true`); its own scrollback find lives on `Ctrl+Shift+F` / `F3`.

The root architectural gap: there is **no mechanism for a focused surface to claim a chord** — to say "I own `Mod+F` while focused, do not fire a global command for it." The dispatcher's `when`/context guards are route-level and coarse (`hasWorkspace`, `inTextInput`, …), so they cannot express per-surface chord ownership.

## Decision

Make `Mod+F` **context-aware "find in the focused surface"**, and reduce workspace search to **double-tap Shift only**:

1. **Unbind `Mod+F` globally.** `workspaceSearch` keeps only `KeyChord.doubleTapShift()`.
2. **Add a chord-claim mechanism.** `ShortcutFocus` gains `claims: Set<KeyChord>`; the resolver skips a global command whose chord is claimed by the focused surface. Editors / chat / terminal each claim `{Mod+F}`.
3. **Each surface owns its `Mod+F` find:** re-editor (code editor) and a new full-transcript find (chat page). The **terminal deliberately does not claim `Mod+F`** — Ctrl+F passes through to the PTY (standard terminal behavior; the embedded CLI's own vim/fzf search needs it). Terminal scrollback find stays on `Ctrl+Shift+F` / `F3` (an existing locked decision in `flutter_alacritty`'s `defaultTerminalShortcuts`).
4. **Chat page find scans the in-memory transcript** and jumps by expanding the render window — no re-parse, no `loadOlder` loop, no file IO.

Extensibility: any future find-capable surface (markdown preview over rendered text, diff view, …) claims `Mod+F` and supplies its own `Shortcuts`; the global dispatcher respects claims, so no resolver changes are ever needed for a new surface. A future host that wants Ctrl+F inside a terminal to open scrollback find can add `Mod+F → ToggleSearchIntent` to that terminal's shortcuts and wire `onToggleSearch` — the mechanism already exists.

## Architecture

### Chord claims (extensible core)

```
ShortcutFocus(claims: {Mod+F}, kind: text)
        │  (wraps the focused surface)
        ▼
_liveShortcutContext ── primaryFocus.context ──ShortcutFocus.maybeOf()──► ShortcutContext.claimedChords
        │                                                                          │
        ▼                                                                          ▼
KeybindingResolver.match ── if a candidate chord ∈ context.claimedChords ──► skip that global command
```

- `ShortcutFocus` (`shortcut_focus.dart`) gains `final Set<KeyChord> claims` (default `const {}`). `kind` stays. `updateShouldNotify` compares claims too.
- `ShortcutContext` (`shortcut_context.dart`) gains `final Set<KeyChord> claimedChords` (default `const {}`).
- `_liveShortcutContext` (`main.dart`) collects `claims` as a **union over every `ShortcutFocus` ancestor** of `primaryFocus` (not just the nearest) and puts them in `claimedChords`. This makes claims inheritable through nesting — e.g. the chat page wraps its whole body in `ShortcutFocus(claims: {Mod+F})`, and a focus that sits in the compose field (its own inner `ShortcutFocus(kind: compose)`) still has the chat page's `Mod+F` claim visible. The `kind` classification still uses the nearest `ShortcutFocus`.
- `KeybindingResolver.match` (`keybinding_resolver.dart`): before returning a command id, if any of the command's matched chords is in `context.claimedChords`, skip it. This is checked per-chord, after the existing `when`/`inTextInput`/`terminalPassthrough` guards.

**Consumers of a claim, one declaration:**

| Consumer | What it does with a claimed chord |
|----------|-----------------------------------|
| `KeybindingResolver.match` | Skips the global command for that chord (future-proofing; no global command binds `Mod+F` today, but a future binding on `Mod+Shift+F` / `Ctrl+Alt+K` is automatically suppressed on claiming surfaces). |
| The surface's own `Shortcuts` widget | The single handler that fires find. |

(The terminal claims nothing, so `terminalPassthroughShortcutOverlay` is unchanged — Ctrl+F simply stops being claimed once `Mod+F` is removed from `workspaceSearch`.)

### Workspace search shortcut

`CommandCatalog.v1.workspaceSearch`:
```dart
defaultChords: [KeyChord.doubleTapShift()],  // was [KeyChord('f', mods: [mod]), KeyChord.doubleTapShift()]
```
l10n `shortcutsWorkspaceSearch` description updated to say double-Shift only. `shortcut_dispatcher_test.dart` updated (drop the `Mod+F → workspaceSearch` assertion).

### Editor

`Mod+F` is globally unbound, so re-editor's own `Shortcuts` (`code_shortcuts.dart`, `SingleActivator(LogicalKeyboardKey.keyF, meta/control: true)`) is the only consumer. `_CodeEditorPane` (`file_editor_surface.dart`) wraps its subtree in `ShortcutFocus(claims: {Mod+F})` to document ownership and feed the claim pipeline (its `findBuilder` → `CodeEditorFindPanel` is unchanged).

### Terminal

**No change to terminal key handling.** Removing `Mod+F` from `workspaceSearch` means `terminalPassthroughShortcutOverlay` no longer claims Ctrl+F, so Ctrl+F naturally passes through to the PTY (the CLI's own search). Terminal scrollback find remains on `Ctrl+Shift+F` / `F3` via the existing `TerminalFindShortcuts` + `ToggleSearchIntent` path. `TeampilotAlacrittyTerminal`'s `ShortcutFocus(kind: terminal)` stays claim-free.

### Chat page find (full transcript)

The transcript is **already in memory**: `AiHistoryLoader.load()` (`ai_history_loader.dart`) parses the whole transcript once (`cap.adapter.parse(bundle)`) and `AiHistorySeat._allMessages` holds the full message list; `loadOlder()` (`ai_history_seat.dart`) merely grows the render window `_visibleCount`, with **no file paging**. Therefore:

```
seat.loadedMessages ──buildTranscriptDoc()──► SessionTranscriptDoc{text, messageStarts}
        (in-memory, indices align 1:1 with the message list)
                     │
        scan all case-insensitive occurrences of the query
                     ▼
      List<TranscriptHit{messageIndex, snippet}>
                     │
   jump: seat.revealMessage(messageIndex)  →  thread scrolls to ValueKey(message.id) + bubble highlight
```

New/changed pieces:

- **`buildTranscriptDoc` reuse** (`workspace_session_content_index.dart`): already a public pure function — project `seat.loadedMessages` into a searchable doc whose `messageStarts[i]` maps 1:1 to `loadedMessages[i]`. No locate, no re-parse, no second file read.
- **`ChatTranscriptFindController`** (new, pure Dart): owns query → doc → all matches (`caseInsensitiveIndexOf` per match, advancing offset) → `List<TranscriptHit>`, and the current-match index (n/N). Emits changes to the find bar.
- **`AiHistorySeat.revealMessage(int index)`** (new): commit all held content and grow `_visibleCount` so the render window includes `index` (`_visibleCount = max(_visibleCount, _allMessages.length - index)`), then `_emitReadyWindow`. Reuses the existing window machinery — no new loading path.
- **Find bar in `SessionChatView`** (`session_chat_view.dart`): top overlay `TpFindBar` with query field, n/N counter, prev/next, close, and a collapsible **results list** (each row: member label + highlighted snippet — reuse the `_HighlightedSnippet` pattern from `workspace_search_dialog.dart`). Prev/next and row-tap both call `revealMessage` then scroll.
- **Scroll + highlight**: `SessionHistoryThread` gains a reveal API (`revealMessage(int index)` → `revealMessage(String messageId)`) that computes the target scroll offset from its existing virtualized scroll model (same mechanism as its internal `_jumpTo` at `session_history_thread.dart`) and applies a short-lived bubble highlight (a colored ring/border on the current match row). It must not rely on `Scrollable.ensureVisible(contextOf(key))` — rows are built lazily by `VirtualThreadViewport`, so a not-yet-mounted target row has no `BuildContext`.
- **Highlight scope**: in-thread highlight is **bubble-level** (rich markdown renders as custom `AiMessage` bubbles; inline text highlight would require forking the markdown renderer). Text-level highlight lives in the results-list snippets, which are plain text.

`SessionChatView` is wrapped in `ShortcutFocus(claims: {Mod+F})` and hosts its own `Shortcuts` for `Mod+F` → toggle the find bar (mirroring `TerminalFindShortcuts`).

### Shared find bar

Extract the shared interaction/visual into `TpFindBar` (in `client/packages/shared_ui`): query input + counter + prev/next + close + optional results list. Editor's `CodeEditorFindPanel`, terminal's `TerminalFindBar`, and the new chat find bar converge on it (incremental — each surface migrates when convenient; the chat bar is the first new consumer and can adopt the shared widget immediately).

## Data flow

1. User presses `Mod+F` in the chat page.
2. `KeyEventManager` delivers the key to (a) the global `ShortcutDispatcher` — no command binds `Mod+F` anymore, so it no-ops; and (b) the focused `Shortcuts` tree — the chat page's `Shortcuts` matches → toggles the find bar.
3. Typing in the find bar → `ChatTranscriptFindController` scans `buildTranscriptDoc(seat.loadedMessages)` → matches (n/N). No IO, synchronous after the transcript is loaded.
4. User hits next/prev or a result row → `seat.revealMessage(index)` expands the window → thread scrolls to `ValueKey(ai.id)` and highlights the bubble.

## Edge cases

- **Transcript not yet loaded** (seat `loading`/`empty`): find bar shows "indexing…" state until `loadedMessages` is non-empty, then searches. Same graceful path as the workspace search dialog's indexing hint.
- **Match in a held trailing tip** while awaiting: `revealMessage` commits held content for the jump; the awaiting chrome re-applies on the next live refresh.
- **`String.toLowerCase()` length changes** (e.g. `ß`): reuse `caseInsensitiveIndexOf`'s case-insensitive `RegExp` matching on the original text so offsets stay valid for slicing.
- **Mailbox-merged seats**: doc is built from `_allMessages` (which already merges mailbox records via `buildConversationTimeline`), so `messageStarts` stay aligned with the rendered thread; mailbox text is searchable too.
- **Subagent attachments / tool bubbles**: only the message's own parts (`AiTextPart`/`AiReasoningPart`/`AiToolCallPart`) project into the doc, matching existing workspace-search behavior; the jump lands on the owning message bubble.
- **Very long transcripts**: search is a single pass over an in-memory doc (no per-keystroke file IO); debounce the query like the workspace dialog (180 ms) and cap the results list.

## Testing

- `keybinding_resolver_test.dart`: a claimed chord suppresses a global command that binds it; unclaimed chord still fires; `when`/`inTextInput`/`terminalPassthrough` guards still apply.
- `command_catalog` / `shortcut_dispatcher_test.dart`: `workspaceSearch` has only double-shift; `Mod+F` does not invoke it.
- `ai_history_seat_test.dart`: `revealMessage` expands `_visibleCount` to cover `index`, commits held content, emits a ready window; no-op when already visible.
- New `chat_transcript_find_test.dart`: all-match scan (n/N, next wraps), `messageIndex` maps to `loadedMessages[i]`, snippet highlighting, empty-query behavior.
- `terminal` find: `Ctrl+Shift+F` / `F3` still toggle the bar; Ctrl+F is **not** claimed (passes through to the PTY) — existing terminal tests stay green.
- Existing editor find tests stay green (re-editor owns `Mod+F`).

## l10n

- `app_en.arb` / `app_zh.arb`: `shortcutsWorkspaceSearch` description → double-Shift only; new `chatFind*` strings (hint, no-results, results-list header, indexing state).

## Out of scope

- Inline text highlight inside rendered markdown bubbles (requires markdown-renderer integration) — bubble-level highlight + snippet text highlight cover the UX.
- Markdown preview / image preview find (they claim nothing → `Mod+F` is inert until they gain a find surface; workspace search is double-Shift only).
- Global "search across conversations" beyond the existing workspace search dialog.
