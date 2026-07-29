# Shell tool card in History (Cursor-style)

**Date:** 2026-07-29  
**Status:** Approved

## Goal

Render shell/terminal tool calls in chat History as Cursor-like cards: a
human-readable header, expandable `$ command` + dimmed output. Keep them
inside the existing Chain-of-Thought grouping. Non-shell tools keep their
current chrome (file summary / subagent / legacy).

## Locked decisions

| Topic | Choice |
|-------|--------|
| Visual target | Option B: header summary + `$ command` + dim output (no syntax highlight) |
| CoT grouping | Unchanged — shell tools stay inside CoT |
| Default expand | Collapsed: header only; expand shows command + output |
| Header title | Prefer `description`; else truncated `command` (~80 chars, single line) |
| Tool scope | All shell-like names across CLIs (see set below) |
| Missing `command` | Fall back to legacy `Used tool: …` |
| Architecture | Approach 1: fourth branch in `AiToolCallPartView` + `AiShellToolTargetResolver` |
| Transcript adapters | Unchanged — extract from existing `args` / `argsText` / `result` |
| Out of scope | Syntax highlight, exit-code / `git, 2+` meta, splitting out of CoT, live permission preview, new user preference |

## Problem

1. Shell tools (`Bash`, `Shell`, `shell_command`, …) use legacy chrome:
   `Used tool: {name}` with JSON args on expand — hard to scan what ran.
2. File tools already have summary chrome; subagents have dedicated chrome;
   shell has neither.
3. Cursor shows a terminal icon, short description, `$` prompt, and dimmed
   stdout — TeamPilot History does not.

## Architecture

```
AiToolCallPart
      │
      ▼
AiToolCallPartView branch order:
  1. Subagent chrome (unchanged)
  2. AiShellToolTargetResolver.resolve(part)  ← new
  3. AiToolFileTargetResolver.resolve(part)   (unchanged)
  4. Legacy Used-tool chrome                  (unchanged)
      │
      ▼
Shell hit → _ShellToolTrigger + expanded terminal panel
```

When shell chrome is used, the **expanded body is the dedicated terminal
panel only** — it replaces (does not stack on top of) the shared legacy
args JSON + `Result:` + result block in `AiToolCallPartView`.

`DefaultAiShellToolTargetResolver` is constructed as `const` inside the
view (no `InheritedWidget` / host injection unless a later change needs
custom rules).

CoT (`groupMessageParts` / `AiChainOfThoughtView`), `initiallyExpanded`, and
`cotExpandToolsOnOpen` stay as today.

### Core types (`ai_message_core`)

```dart
class AiShellToolTarget {
  const AiShellToolTarget({
    required this.command,
    this.description,
  });

  final String command;
  final String? description;

  /// Header label: non-empty description, else truncated command.
  String get summary;
}

abstract class AiShellToolTargetResolver {
  AiShellToolTarget? resolve(AiToolCallPart part);
}
```

Built-in `DefaultAiShellToolTargetResolver`:

- Match `toolName.toLowerCase()` against the shell name set.
- Extract `command` from `args` keys in order: `command`, `cmd`, `CommandLine`.
  If missing, try parse `argsText` as JSON and read the same keys.
- Extract optional `description` from `args` / parsed `argsText` (`description`).
- Return `null` if the name does not match or `command` is empty → legacy path.

Shell name set (v1, case-insensitive):

```
bash, shell, shell_command, exec_command,
run_shell_command, run_terminal_cmd, execute
```

(Extendable via constructor rules if needed later; default set is enough for
Claude / Cursor / Codex / OpenCode transcripts already parsed into
`AiToolCallPart`.)

Export from `ai_message_core.dart` alongside `tool_file_target.dart`.

### UI (`ai_message_ui`)

**Collapsed header (`_ShellToolTrigger`):**

- Leading: terminal icon + existing status indicator (running / complete /
  error / incomplete / cancelled)
- Center: `summary` (single-line ellipsis)
- Trailing: chevron
- Tap toggles expand (same as other tool rows)

**Expanded body:**

- Muted panel (`panelRadius` / tool panel colors from `AiMessageTheme`)
- Line 1: `$` (accent) + full `command` in monospace (wrap; no syntax highlight)
- Below (if `result != null`): dimmer monospace output text
- No `Result:` label
- On `isError`: output uses error color; status icon already reflects error

Default collapsed; honors `initiallyExpanded` when CoT preference expands nested
tools.

## Behavior matrix

| Case | Behavior |
|------|----------|
| Shell name + command + description | Header = description; expand = `$` + command + output |
| Shell name + command, no description | Header = truncated command |
| Shell name, no command | Legacy `Used tool: …` |
| File tool (Read/Write/…) | File summary chrome (unchanged) |
| Subagent tool with actions | Subagent chrome wins over shell |
| Cancelled / incomplete | Same status icons as other tools |
| Very long command/output | Full text in body; only header summary truncates |

## Non-goals

- Command syntax highlighting or language-aware coloring
- Exit code, duration, or Cursor-style `git, 2+` chips in the header
- Pulling shell tools out of CoT or changing CoT step counts
- Changing live agent-status / permission previews
- Per-user preference dedicated to shell card expand

## Testing

**`ai_message_core`:** resolver unit tests for name set, key order
(`command`/`cmd`/`CommandLine`), description preference, null when no command,
`argsText` JSON fallback.

**`ai_message_ui`:** widget tests — Bash with command uses shell chrome (not
`Used tool:`); collapsed shows summary only; expanded shows `$`, command, and
output without `Result:`; Read still file chrome; unknown tool still legacy;
CoT nesting still wraps consecutive tools.

## Implementation touchpoints

| Area | Path |
|------|------|
| Model + resolver | `client/packages/ai_message_core/lib/src/tool_shell_target.dart` |
| Barrel export | `client/packages/ai_message_core/lib/ai_message_core.dart` |
| UI branch + panel | `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` |
| Resolver tests | `client/packages/ai_message_core/test/tool_shell_target_resolver_test.dart` |
| UI tests | `client/packages/ai_message_ui/test/` (extend tool-call chrome tests) |
