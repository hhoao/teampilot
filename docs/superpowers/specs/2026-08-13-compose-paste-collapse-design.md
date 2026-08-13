# Compose Paste Collapse — Design

Date: 2026-08-13

## Problem

Pasting a very long passage (e.g. 152 lines of code) into the chat composer
makes the field janky and leaves most of the text invisible below the fold.

Root cause: the compose field is `ComposeTriggerField` → `TpTextareaShell`
(height clamped to 3–6 lines, resizable) → `TpTokenTextField`. Because
`TpTokenTextField` is built with `expands: true`, it hands `TextField`
`minLines/maxLines = null` (`tp_token_text_field.dart`), so `EditableText`
lays out **every pasted line** even though the shell only shows ~6. That is
the jank, and overflow beyond the shell is the "invisible text at the bottom".

Goal: when pasted text exceeds **25 lines** (newline count + 1), collapse it
into a compact **"Pasted text · N lines"** badge (mirroring the reference
`zcode-chat-input.html`), keeping the input small and never laying out the
long text in the always-visible field.

## Confirmed UX decisions

1. **Expand = modal/full-screen editor** (not inline growth).
2. **Collapsed state = badge + empty input**: the badge "粘贴文本 · N 行" sits
   above a normal empty input that shows the placeholder hint.
3. **Paste-only trigger**: only a single change that crosses the 25-line
   threshold collapses (typing cannot cross one line per keystroke, so
   paste-only holds naturally). Badge label stays "粘贴文本".
4. **Collapsed input is live**: the user keeps typing a follow-up in the empty
   input; on send, the pasted block and the follow-up are joined.

## Design

### 1. `ComposeClip` state object

New file `client/lib/services/compose/compose_clip.dart`:

```dart
class ComposeClip extends ChangeNotifier {
  String _text = '';
  bool get collapsed => _text.isNotEmpty;
  String? get text => _text.isEmpty ? null : _text;
  int get lineCount;                 // '\n' count + 1

  /// A single oversized paste collapsed the whole current draft into the clip.
  void setPasted(String fullText);

  /// Write-back from the editor (stays collapsed; line count may change).
  void setExpanded(String newText);

  /// Final message: non-empty parts joined with '\n\n' (block first, follow-up last).
  String composeMessage(String followUp);

  void clear();
}
```

### 2. Ownership and plumbing

Owned alongside the existing `TextEditingController`, passed through the same
prop chain:

| Layer | Change |
|---|---|
| `SessionChatView` / `_UnboundComposeBodyState` | create `_clip = ComposeClip()`, dispose it |
| `SessionChatComposeSection` / `unbound_compose_body.dart` | thread `clip` through |
| `WorkspaceComposeCard` | new `clip` param; renders the badge bar; opens the editor |
| `ComposeTriggerField` | new `clip` param; owns paste detection |

### 3. Paste detection

In `ComposeTriggerField._handleControllerChanged`: track `_lastLineCount`.
When a single change makes the line count jump from `<= 25` to `> 25`, treat
it as an oversized paste and run:

```dart
widget.clip?.setPasted(widget.controller.text);
widget.controller.clear();
```

`onChanged` fires synchronously after `EditableText` commits the paste into
the controller but **before** the widget rebuilds, so clearing inside the
callback means build never sees 152 lines — no jank, not even one frame.

Appending: a second oversized paste into the empty follow-up input appends to
the existing clip (joined with `\n`), one badge, running line count. One clip
per compose input (multi-block is out of scope).

Self-healing: Ctrl+Z that restores the long text re-crosses the threshold and
re-collapses; `clear()` lowers the count so it never loops.

### 4. Badge bar

New `client/lib/widgets/compose/compose_paste_clip_bar.dart`, rendered by
`WorkspaceComposeCard` above `ComposeTriggerField` (same slot as the at-file
ref chip row), only when `clip.collapsed`:

```
[📋 粘贴文本 · 152 行]   ⛶ ✕
```

- Left: clipboard icon + `粘贴文本 · N 行` using `WorkspaceChatLandingPalette`
  + `TpHover` (existing chip visuals).
- `⛶` expands → opens the editor; `✕` removes → `clip.clear()`.
- The badge body is also clickable to expand. Tooltips via new l10n keys.

### 5. Collapsed input

No special rendering: `controller` is empty after collapse, so
`ComposeTriggerField` shows the normal placeholder and is live for the
follow-up message.

### 6. Editor dialog

New `client/lib/widgets/compose/compose_paste_editor_dialog.dart`. Triggered
by tapping the badge / expand icon. Full-screen `showDialog` reusing the
existing `TpTextarea` (shared_ui: outlined, scrollable, resizable):

```
编辑已粘贴文本 · 152 行
┌────────────────────────────┐
│ #include <stdio.h>         │
│ int main() { ...           │
│ (full scrollable text)     │
└────────────────────────────┘
[移除]              [取消]  [完成]
```

- Open: seed a dialog-local `TextEditingController` with `clip.text`.
- `完成` → `clip.setExpanded(editor.text)` (stays collapsed, count updates).
- `取消` → discard; `移除` → `clip.clear()` and close.
- 152 lines in this on-demand, isolated editor is acceptable layout cost.

### 7. canSubmit / submit composition / refs / enhance

- **canSubmit** (both parents):
  `!permissionWaiting && (clip.collapsed || !composeTextEmpty) && !isSubmitting`
  — a collapsed block alone can be sent. Parents wrap with
  `ListenableBuilder(listenable: clip, …)`.
- **Submit text**: `onSubmit(clip.composeMessage(controller.text.trim()))`.
  On success both parents clear `clip` and `controller` together (next to the
  existing `_controller.clear()` sites). On failure the restored composed text
  re-collapses via detection if >25 lines.
- **At-file refs**: `WorkspaceComposeCard` scans `composeMessage(...)` instead
  of `controller.text` so `@`-refs inside the block still render chips.
- **Enhance**: reads `composeMessage(...)` where it currently reads
  `controller.text`. Voice only writes into the follow-up input (unchanged).

### 8. l10n

Add to `client/lib/l10n/app_en.arb` and `app_zh.arb`:

| Key | en | zh |
|---|---|---|
| `composePasteClipLabel` | Pasted text | 粘贴文本 |
| `composePasteClipLines` | {lines} lines | {lines} 行 |
| `composePasteClipEdit` | Edit pasted text | 编辑已粘贴文本 |
| `composePasteClipRemove` | Remove pasted text | 移除已粘贴文本 |
| `composePasteEditorTitle` | Edit pasted text · {lines} lines | 编辑已粘贴文本 · {lines} 行 |
| `composePasteEditorDone` | Done | 完成 |
| `composePasteEditorCancel` | reuse existing `cancel` | reuse existing `cancel` |
| `composePasteEditorRemove` | Remove | 移除 |

### 9. Tests

1. Unit: `ComposeClip` (setPasted / composeMessage / clear / lineCount).
2. Widget: `ComposeTriggerField` paste detection — a single controller change
   inserting >25 lines → `clip.collapsed == true` and `controller` cleared;
   a <25-line paste does not collapse.
3. Widget: `ComposePasteClipBar` renders line count; expand opens the editor;
   remove clears.
4. Widget: editor dialog save / cancel / remove write-back paths.
5. Regression: existing compose widget tests, `flutter analyze
   --no-fatal-infos --no-fatal-warnings`, `flutter test --exclude-tags
   integration`.

## Files

- Add `services/compose/compose_clip.dart`
- Add `widgets/compose/compose_paste_clip_bar.dart`
- Add `widgets/compose/compose_paste_editor_dialog.dart`
- Edit `widgets/compose/compose_trigger_field.dart` (detection + `clip` param)
- Edit `widgets/compose/workspace_compose_card.dart` (badge bar + `clip` param)
- Edit `pages/chat/session_chat_view.dart`, `session_chat_compose_section.dart`,
  `pages/home_workspace/workspace/unbound_compose_body.dart` (create/thread
  `clip`, canSubmit, submit composition)
- Edit `l10n/app_en.arb`, `l10n/app_zh.arb`

## Known trade-offs

- One paste-block per compose input; a second oversized paste merges into the
  first. Multi-block is future work.
- Detection is "single change crosses the threshold" — indistinguishable
  internal-paste/drag-drop scenarios behave the same as a paste.
