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
| Tool scope (v1) | Explicit name set below (read / write / edit family) |
| Click basename **or** line-range text | Same `onOpenFile` — open editor + select line range |
| Click rest of row | Toggle expand args/result |
| Path resolve | Prefer session working directory, then active workspace folder roots; absolute paths as-is |
| Architecture | Pluggable resolver → structured target → host open handler |
| Transcript adapters | Unchanged — extract from existing `args` / `argsText` |
| Non-file tools | Keep current “Used tool: {name}” row |
| No `onOpenFile` | Render summary; basename uses default cursor and is non-interactive (not a fake button) |

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
    this.endLine,   // 1-based inclusive
  });

  final String path;
  final int? startLine;
  final int? endLine;
  // Selection when opening:
  // - both null → open file only (no selection)
  // - start only → select that single line
  // - start+end → select inclusive line range
}

abstract class AiToolFileTargetResolver {
  AiToolFileTarget? resolve(AiToolCallPart part);
}
```

Built-in `DefaultAiToolFileTargetResolver`:

**v1 tool names** (case-insensitive exact match):

- Read family: `Read`, `ReadFile`, `read_file`
- Write family: `Write`, `WriteFile`, `write_file`, `Create`, `create_file`
- Edit family: `Edit`, `StrReplace`, `ApplyPatch`, `EditNotebook`, `NotebookEdit`

**`AiToolFileTargetRule` shape:**

```dart
class AiToolFileTargetRule {
  const AiToolFileTargetRule({
    required this.toolNames,   // lowercased match set
    this.pathKeys = const ['file_path', 'path', 'file', 'target_file'],
    this.startLineKeys = const ['start_line', 'startLine'],
    this.endLineKeys = const ['end_line', 'endLine'],
    this.useOffsetLimit = false, // Read: offset+limit → line range
  });
}
```

- Path keys (first non-empty string wins) per rule.
- Line extraction (best-effort):
  - `start_line` / `end_line` (or camelCase variants) from args
  - When `useOffsetLimit`: Claude-style `offset` + `limit` →
    `start = offset`, `end = offset+limit-1` when both parse as ints ≥ 1
  - Fallback parse from `argsText` patterns like `L110-189` / `L110`
- Empty / unparseable path → `null` (legacy chrome).

Hosts may compose
`CompositeAiToolFileTargetResolver([custom, Default…])` without forking the
widget.

### UI (`ai_message_ui`)

**Summary row (when target present)**

- Leading status icon (unchanged).
- Body: tool short name + space + **tappable basename** (link styling) + optional
  muted `L{start}` or `L{start}–{end}` (same tap target as basename).
- Trailing chevron for expand.
- Hit testing:
  - Basename **or** line-range text → `onOpenFile`
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
`onOpenFile` is null, still render summary text; basename is plain text
(non-interactive, default cursor) — do not wrap in a no-op button.

Nested CoT tool rows and standalone tool rows share the same `AiToolCallPartView`
path — one chrome implementation.

### Host (TeamPilot)

`AiToolFileOpenCoordinator` (or extend `WorkbenchEditorOpener`):

```dart
Future<void> openToolFile({
  required String workspaceId,
  required AiToolFileTarget target,
  required Filesystem fs,
});
```

Host must pass the workspace-bound `Filesystem` (same instance for resolve + open).

Behavior:

1. Normalize `target.path`:
   - Absolute → use as-is (still subject to workspace fs existence checks).
   - Relative → try resolve against **session working directory first**, then
     each **active workspace folder root**; first existing **file** wins
     (`(await fs.stat(p)).isFile`).
   - If none exist → user-visible error (`AppToast` / l10n); do not throw into
     the gesture handler.
2. `WorkbenchEditorOpener.openFile(workspaceId, absolutePath, fs: fs)`.
3. After content is ready, apply selection:
   - Lines are 1-based in the target; convert to 0-based `CodeLineSelection`
     spanning start line offset 0 through end line end-of-line (clamp to
     document).
   - Reveal selection in viewport when feasible; v1 may be selection-only.
4. SSH / WSL: use the workspace’s bound filesystem — same as file-tree open.

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
- Path resolve tests (required): relative hits session cwd; falls back to
  workspace folder; absolute as-is; missing → error path.

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
