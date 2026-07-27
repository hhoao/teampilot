# Clickable Tool-Call File Targets

## Goal

Render read/write tool calls in chat History as agent-style summary rows
(`Read ai_history_seat.dart L110-189`) where the filename opens the workspace
editor and selects the referenced line range. Keep non-file tools on the
existing “Used tool: …” chrome.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Row chrome | Agent summary: `{tool} {basename} [Lstart–Lend?]` |
| Tool scope (v1) | Read/write/edit family only |
| Click filename | Open in workbench editor + select line range |
| Click rest of row | Toggle expand args/result |
| Architecture | Pluggable resolver → structured target → host open handler |
| Transcript adapters | Unchanged — extract from existing `args` / `argsText` |
| Non-file tools | Keep current “Used tool: {name}” row |

## Problem

1. `AiToolCallPartView` only shows `Used tool: {toolName}` and dumps JSON args on
   expand — hard to scan which file was touched.
2. There is no path from History tool rows into `WorkbenchEditorOpener` /
   editor selection.
3. Hard-coding Read/Write parsing inside the widget would block adding Grep /
   Glob later and diverge across CoT nested rows vs standalone tools.

## Architecture

```
AiToolCallPart
      │
      ▼
AiToolFileTargetResolver.resolve(part)
      → AiToolFileTarget? { path, startLine?, endLine? }
      │
      ▼
AiToolCallPartView
  · target ≠ null → summary chrome + tappable basename
  · target == null → legacy Used-tool chrome
  · onOpenFile(target) via AiToolFileActions
      │
      ▼
Host (session chat / History)
  · resolve path against workspace / cwd / runtime fs
  · WorkbenchEditorOpener.openFile
  · EditorCubit select CodeLineSelection for [startLine, endLine]
```

### Core types (`ai_message_core`)

```dart
class AiToolFileTarget {
  const AiToolFileTarget({
    required this.path,
    this.startLine, // 1-based inclusive
    this.endLine,   // 1-based inclusive; null → start-only / whole open
  });

  final String path;
  final int? startLine;
  final int? endLine;
}

abstract class AiToolFileTargetResolver {
  AiToolFileTarget? resolve(AiToolCallPart part);
}
```

Built-in `DefaultAiToolFileTargetResolver`:

- Match tool names case-insensitively against a rule table (v1: read / write /
  edit family).
- Path keys (first non-empty string wins): `file_path`, `path`, `file`,
  `target_file` (and rule-specific aliases).
- Line extraction (best-effort):
  - `start_line` / `end_line` (or `startLine` / `endLine`)
  - Claude-style `offset` + `limit` → `start = offset`, `end = offset+limit-1`
    when both look like line numbers
  - Fallback parse from `argsText` patterns like `L110-189` / `L110`
- Empty / unparseable path → `null` (legacy chrome).

Rules are data-driven (`AiToolFileTargetRule`) so hosts can compose
`CompositeAiToolFileTargetResolver([custom, Default…])` without forking the
widget.

### UI (`ai_message_ui`)

**Summary row (when target present)**

- Leading status icon (unchanged).
- Body: tool short name + space + **tappable basename** (link styling) + optional
  muted `L{start}` or `L{start}–{end}`.
- Trailing chevron for expand.
- Hit testing:
  - Basename (and its line-range text treated as same action) → `onOpenFile`
  - Remaining row / chevron → toggle expand
- Do **not** prefix with “Used tool:” on summary rows.

**Legacy row (no target)** — current chrome unchanged.

**Injection**

```dart
class AiToolFileActions {
  const AiToolFileActions({
    this.resolver = const DefaultAiToolFileTargetResolver(),
    this.onOpenFile,
  });

  final AiToolFileTargetResolver resolver;
  final Future<void> Function(AiToolFileTarget target)? onOpenFile;
}
```

Provided via InheritedWidget / Theme-adjacent scope from the chat host. If
`onOpenFile` is null, still render summary text but basename is not interactive
(or no-op with disabled cursor).

Nested CoT tool rows and standalone tool rows share the same `AiToolCallPartView`
path — one chrome implementation.

### Host (TeamPilot)

`AiToolFileOpenCoordinator` (or extend `WorkbenchEditorOpener`):

```dart
Future<void> openToolFile({
  required String workspaceId,
  required AiToolFileTarget target,
  Filesystem? fs,
});
```

Behavior:

1. Normalize `target.path` (expand relative to active workspace folder / session
   working directory using existing path helpers).
2. If file cannot be resolved / does not exist → user-visible error (snackbar /
   l10n); do not throw into the gesture handler.
3. `WorkbenchEditorOpener.openFile(workspaceId, absolutePath)`.
4. After content is ready, apply selection:
   - Lines are 1-based in the target; convert to 0-based `CodeLineSelection`
     spanning start line offset 0 through end line end-of-line (clamp to
     document).
   - Reveal selection in viewport.
5. SSH / WSL: use the workspace’s bound filesystem — same as file-tree open.

Wire `AiToolFileActions` in `session_chat_view` Theme / strings scope so History
and live chat inherit one handler.

### Editor selection API

Add a focused API on `EditorCubit` (or file surface controller accessor), e.g.
`selectLines(workspaceId, path, {required int startLine, int? endLine})`,
reusing `CodeLineSelection` patterns already used in diff decorations. Do not
reimplement selection math in the chat widget.

## Testing

- Resolver unit tests: each v1 tool name + path key; offset/limit; L-range
  fallback; unknown tool → null; missing path → null.
- Widget tests: summary shows basename; tap basename invokes handler with
  target; tap chevron expands args without opening; legacy row when no target.
- Editor helper / cubit test: selectLines clamps and sets expected
  `CodeLineSelection`.
- Optional: path resolve unit test for relative → absolute under workspace.

## Out of scope

- Grep / Glob / Shell / MCP path linking (add rules later)
- Mutating CLI transcript adapters or persisting targets on disk
- Multi-file tool calls opening many tabs
- Special remote-only preview UX beyond existing opener

## Files (expected)

| Area | Path |
|------|------|
| Target + resolver | `client/packages/ai_message_core/lib/src/tool_file_target.dart` (+ export) |
| Resolver tests | `client/packages/ai_message_core/test/tool_file_target_resolver_test.dart` |
| Tool row UI | `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` |
| Actions scope | `client/packages/ai_message_ui/lib/src/tool_file_actions.dart` |
| UI tests | `client/packages/ai_message_ui/test/tool_call_file_target_test.dart` |
| Open coordinator | `client/lib/services/workbench/` (new or extend opener) |
| Editor select | `client/lib/cubits/editor_cubit.dart` (+ tests) |
| Host wire | `client/lib/pages/chat/session_chat_view.dart` |
| l10n | only if new user-visible errors need copy |
