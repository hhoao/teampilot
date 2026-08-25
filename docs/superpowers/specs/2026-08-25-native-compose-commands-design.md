# Native compose commands

## Goal

Let the TeamPilot chat compose suggest a deliberately small set of useful,
CLI-native slash commands alongside installed skills and plugin commands.  A
selection inserts the command into the compose field; the running CLI remains
the sole executor and owner of command state.

## Scope

The first release supports static, CLI-owned command declarations only.  It
does not probe a running terminal, parse command results, manage a goal, or
replace a CLI's own command picker.

The initial command set is intentionally small:

| Command | CLIs | Purpose |
| --- | --- | --- |
| `/goal <objective>` | Codex, Claude Code, Cursor | Keep a durable objective for long-running work.  Cursor is marked experimental because availability is rollout/version dependent. |
| `/compact [instructions]` | Codex, Claude Code, OpenCode | Summarize/compact the active context. |
| `/plan [task]` | Claude Code | Switch the current session into a planning workflow. |
| `/help [command]` | Every launch-supported CLI | Ask the actual CLI for its available command surface. |

Commands that duplicate TeamPilot controls (`/model`, `/permissions`), alter
TeamPilot-owned session lifecycle (`/new`, `/clear`, `/resume`, `/sessions`),
or require a standalone terminal/external editor (`/quit`, `/logout`,
`/editor`, `/export`) are excluded.

## Capability model

Add `NativeCommandCapability` under the CLI registry capabilities.  It exposes
an immutable list of `NativeCommand` values.  A command contains:

- its slash `name`, without the leading slash;
- localized display description key (with English/Chinese strings owned by
  TeamPilot l10n);
- optional argument placeholder, such as `<objective>`;
- an optional availability badge, initially `experimental` for Cursor goal.

The capability has no materialization, persistence, or terminal dependencies.
Each `CliToolDefinition` supplies it only when it has commands to declare;
callers treat an absent capability as an empty list.  This keeps per-CLI facts
in the registry and avoids UI conditionals on `CliTool`.

## Compose behavior

`ComposeSlashCandidate` gains an explicit source: skill, plugin command, or
native command.  The candidate builder accepts the selected CLI definition and
merges native commands with existing skills and plugin commands.

Native commands always insert `/name`; skill insertion continues to use
`SkillCapability.skillInvocationText`, preserving Codex's `$skill` syntax.
Selecting a command inserts only `/name` followed by one space when it accepts
an argument; users provide the argument and submit it through the existing
compose path.  Zero-argument commands insert exactly `/name`.

The menu groups results in this stable order:

1. Skills;
2. Commands, with each row marked `Native` or `Plugin` and optional
   `Experimental` availability badge.

Search matches command name and description.  Existing keyboard navigation,
escape behavior, replacement range, and file-reference suggestions are
unchanged.

## Context resolution and failure behavior

Landing compose uses the already-resolved CLI for the current draft.  A session
compose uses the selected member's effective CLI.  If neither can be resolved,
the native command list is empty; skills retain today's `/` fallback behavior.

Static declarations are deliberately version-agnostic.  The Help entry is the
escape hatch for commands that are unavailable in a particular installation,
remote host, or rollout.  TeamPilot does not preflight command support and does
not turn a CLI's rejection into a TeamPilot error.

## Tests

Add unit tests for command declaration lookup and candidate merging, including:

- the initial five-CLI command matrix and the Cursor experimental marker;
- native `/` insertion versus Codex `$` skill insertion;
- command argument spacing and zero-argument insertion;
- deterministic grouping, source labeling, de-duplication, and filtering;
- no native commands when no effective CLI is available.

Add focused widget tests for the landing and existing-session compose menus to
verify that both render the same CLI-appropriate native suggestions while
retaining installed skills and plugin commands.

## Non-goals

- dynamic command discovery from terminal output or a CLI SDK;
- exposing every CLI terminal command;
- executing commands outside the normal user submit pipeline;
- TeamPilot-owned goal lifecycle, status UI, or completion enforcement;
- changing command availability based on a remote CLI version.
