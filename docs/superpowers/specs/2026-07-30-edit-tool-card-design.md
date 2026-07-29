# Edit tool card in History (Cursor-style)

**Date:** 2026-07-30  
**Status:** Approved

## Goal

Render edit/write tool calls in chat History as Cursor-like cards: filename
header, `+N`/`−N` badges, and a compact syntax-highlighted diff snippet.
Keep them inside the existing Chain-of-Thought grouping. Read and other
non-edit file tools keep today’s summary chrome.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Tool scope | Edit-class only: Write / StrReplace / ApplyPatch / Edit / Create / … |
| Visual target | Always-visible card: basename + badges + ~3–5 line mini-diff |
| Syntax highlight | Yes; port-based highlighter with plain fallback |
| Diff data | Args-first hunk codecs; optional disk context enricher |
| Interaction | Tap filename → `onOpenFile`; chevron → expand full hunk |
| CoT grouping | Unchanged — edit cards stay inside CoT |
| Architecture | Parallel to shell card: edit branch + hunk codecs + ports |
| Transcript adapters | Unchanged — extract from existing `args` / `argsText` |
| Missing / unparseable edit | Fall back to file summary or legacy |
| Out of scope | Read cards, Loader precomputed hunks, changing adapters, `store.db` |

## Problem

1. Edit tools (`Write`, `StrReplace`, `ApplyPatch`, …) share file-summary
   chrome with Read: tool name + basename + optional line range. Expand still
   dumps JSON args — hard to scan *what changed*.
2. Shell tools already have dedicated Cursor-like chrome; edits do not.
3. Cursor shows filename, green `+N` badge, and a few highlighted diff lines
   with real context — TeamPilot History does not.

## Architecture

```
AiToolCallPart
      │
      ▼
AiToolCallPartView branch order:
  1. Subagent chrome                          (unchanged)
  2. AiShellToolTargetResolver                (unchanged)
  3. AiEditToolTargetResolver → edit card     ← new
  4. AiToolFileTargetResolver → file summary  (Read etc.)
  5. Legacy Used-tool chrome
```

When edit chrome is used:

- **Collapsed (default):** always shows header **and** mini-diff preview
  (not header-only like shell).
- **Expanded:** full hunk replaces any shared args JSON / `Result:` block
  (same “dedicated body only” rule as shell).

CoT (`groupMessageParts` / `AiChainOfThoughtView`), `initiallyExpanded`, and
`cotExpandToolsOnOpen` stay as today. `initiallyExpanded` expands the **full
hunk** body; the mini-diff remains visible either way.

### Layering (extensibility-first)

```
args ──► AiEditHunkCodec (per tool shape)
              │
              ▼
         AiEditHunk  (path, lines, counts, startLine?)
              │
     ┌────────┴────────┐
     ▼                 ▼
 resolver          AiEditContextEnricher  (optional, async)
 (sync dispatch)         │
     │                   ▼
     └────────► enriched AiEditHunk
                       │
                       ▼
              _EditToolCard + AiEditLineHighlighter
```

UI and enrichers never parse raw tool args. New CLI edit shapes = new codec
registration. New context sources = new enricher. New highlight engines =
new highlighter port implementation.

## Core (`ai_message_core`)

### Hunk model

```dart
enum AiEditLineKind { context, add, remove }

class AiEditLine {
  const AiEditLine({
    required this.kind,
    required this.text,
    this.lineNumber,
  });

  final AiEditLineKind kind;
  final String text;
  final int? lineNumber;
}

class AiEditHunk {
  const AiEditHunk({
    required this.path,
    required this.lines,
    required this.addedCount,
    required this.removedCount,
    this.startLine,
  });

  final String path;
  final List<AiEditLine> lines;
  final int addedCount;
  final int removedCount;
  final int? startLine;
}

class AiEditToolTarget {
  const AiEditToolTarget({required this.hunk});

  final AiEditHunk hunk;
}
```

`addedCount` / `removedCount` are **authoritative totals** for badges (may
exceed visible preview lines). Preview truncation is a UI concern over
`hunk.lines`.

### Codecs

```dart
abstract class AiEditHunkCodec {
  /// Whether this codec owns [toolName] (case-insensitive match).
  bool matches(String toolName);

  /// Build a hunk from the tool part, or null if args are insufficient.
  AiEditHunk? encode(AiToolCallPart part);
}
```

Built-in codecs (v1):

| Codec | Tool names (case-insensitive) | Args |
|-------|-------------------------------|------|
| `StrReplaceEditHunkCodec` | `strreplace`, `edit`, `editnotebook`, `notebookedit` | `file_path`/`path`/… + `old_string`/`oldString` + `new_string`/`newString` |
| `WriteEditHunkCodec` | `write`, `writefile`, `write_file`, `create`, `create_file` | path + `contents`/`content` (all lines as `add`) |
| `UnifiedDiffEditHunkCodec` | `applypatch`, `apply_patch` | path (if present) + patch/diff text (`patch`, `diff`, `input`, …) |

Path key order mirrors `DefaultAiToolFileTargetResolver`:
`file_path`, `path`, `file`, `target_file`. Also accept JSON parsed from
`argsText` when `args` is empty.

Encode rules:

- Require non-empty path **or** (for unified diff only) a parseable `---`/`+++`
  path header.
- Require at least one `add` or `remove` line after encode.
- Optional `start_line` / `startLine` on StrReplace → set `hunk.startLine`
  and number consecutive lines when disk enricher has not run yet.
- Very large Write contents: codec may cap **encoded** `lines` for memory
  (e.g. first N add lines) while still computing full `addedCount` from the
  source string. Spec floor: keep at least enough lines for UI preview +
  expand (implementation may use a generous cap such as 500 lines).

### Resolver

```dart
abstract class AiEditToolTargetResolver {
  AiEditToolTarget? resolve(AiToolCallPart part);
}

class DefaultAiEditToolTargetResolver implements AiEditToolTargetResolver {
  const DefaultAiEditToolTargetResolver({this.codecs = defaultCodecs});
  final List<AiEditHunkCodec> codecs;
  // try each matching codec; first non-null hunk wins
}
```

Return `null` → fall through to file summary / legacy.

Export from `ai_message_core.dart` alongside shell/file targets.

## UI (`ai_message_ui`)

### Card chrome (`_EditToolCard`)

**Always visible:**

- Leading: file-type icon (extension-based; simple map OK) + existing tool
  status indicator
- Title: basename of `hunk.path` (single-line ellipsis)
- Badges: green `+N` when `addedCount > 0`; red `−N` when `removedCount > 0`
  (omit zero-side). Extremely large counts may display capped label
  (e.g. `+99+`) while tooltip / semantics keep the real count if cheap.
- Mini-diff: first ~3–5 lines of `hunk.lines` (prefer including at least one
  add/remove). Context lines dimmed; add/remove use green/red background
  bars; monospace. Line numbers shown when present.
- Trailing chevron toggles expand

**Expanded body:**

- Full `hunk.lines` in the same diff styling (scroll if long)
- No JSON args, no `Result:` label
- On `isError`: keep hunk; status icon already reflects error

**Open file:**

- Tap basename (and optional line-number gutter) calls
  `AiToolFileActions.onOpenFile` with
  `AiToolFileTarget(path: hunk.path, startLine: hunk.startLine ?? first numbered line, endLine: …)`
- If `onOpenFile` is null, title is non-interactive (same as file summary)

### Highlighter port

```dart
abstract class AiEditLineHighlighter {
  InlineSpan highlight({
    required String path,
    required String text,
    required AiEditLineKind kind,
    required TextStyle baseStyle,
  });
}
```

- Default: `ReHighlightEditLineHighlighter` (reuse editor `re_highlight` /
  `EditorSyntaxTheme` palettes by extension → language).
- Fallback: `PlainEditLineHighlighter` (base style only).
- Per-line try/catch → plain for that line; never fail the card.

Host may override via `AiToolFileActions` (or a dedicated
`AiEditCardActions` scope if file actions grow too wide — prefer extending
`AiToolFileActions` first for one InheritedWidget).

### Context enricher port

```dart
abstract class AiEditContextEnricher {
  Future<AiEditHunk> enrich(AiEditHunk hunk);
}

class NoOpAiEditContextEnricher implements AiEditContextEnricher { … }
```

Optional on `AiToolFileActions`:

```dart
Future<AiEditHunk> Function(AiEditHunk hunk)? enrichEditContext;
```

Card behavior:

1. Resolve sync hunk from codec → render immediately.
2. If `enrichEditContext != null`, call after first frame; on success
   `setState` with enriched hunk (better context + line numbers).
3. Failure / timeout / cancel: keep args hunk; log at debug only.

Workspace host implementation: resolve path against workspace FS, locate
`old_string` (or patch anchor), attach ±1–2 context lines and absolute line
numbers. If the file no longer matches, return the input hunk unchanged.

## Behavior matrix

| Case | Behavior |
|------|----------|
| StrReplace with old/new + path | Edit card; badges from line delta; mini-diff |
| Write with contents | Edit card; all-add hunk; large file truncated in lines, full count in badge |
| ApplyPatch with unified diff | Edit card from parsed diff |
| Edit args missing path/content | File summary or legacy |
| Read / Grep | Unchanged (summary / legacy) |
| Shell | Unchanged (shell branch wins before edit) |
| Subagent | Unchanged (wins first) |
| Enricher unavailable | Args-only card |
| Enricher finds file | Context + real line numbers |
| Cancelled tool | Cancelled styling; hunk still shown when parseable |

## Non-goals

- Redesigning Read tool chrome
- Precomputing hunks inside `AiHistoryLoader` / transcript adapters
- Decrypting Cursor `store.db` for richer diffs
- Side-by-side diff editor inside History
- Pulling edit tools out of CoT
- Per-user preference dedicated to edit-card expand

## Testing

**`ai_message_core`:**

- Each codec: happy path, missing keys → null, `argsText` JSON fallback
- StrReplace line counts; Write addedCount vs truncated lines
- Unified diff parse; path-from-header
- Resolver dispatches to the correct codec; unknown tool → null

**`ai_message_ui`:**

- StrReplace uses edit card (not `Used tool:` / not Read-style summary alone)
- Always-visible mini-diff; expand shows full hunk without `Result:`
- Badges `+N`/`−N`; tap basename invokes `onOpenFile`
- Highlighter failure still paints plain lines
- Enricher success updates line numbers; enricher throw leaves args hunk
- Read / Shell / Subagent / Legacy regressions

## Implementation touchpoints

| Area | Path |
|------|------|
| Hunk model + codecs + resolver | `client/packages/ai_message_core/lib/src/tool_edit_target.dart` (split files if large) |
| Barrel export | `client/packages/ai_message_core/lib/ai_message_core.dart` |
| Card + branch | `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` (+ extract widgets if needed) |
| Highlighter | `client/packages/ai_message_ui/lib/src/edit/…` |
| File actions enrich hook | `client/packages/ai_message_ui/lib/src/tool_file_actions.dart` |
| Host enricher | History / workspace seat wiring under `client/lib/…` |
| Core tests | `client/packages/ai_message_core/test/tool_edit_*.dart` |
| UI tests | `client/packages/ai_message_ui/test/tool_call_edit_target_test.dart` |
