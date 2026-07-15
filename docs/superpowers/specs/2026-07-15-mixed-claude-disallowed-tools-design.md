# Mixed Claude `--disallowedTools` for native team tools

**Status:** Approved  
**Date:** 2026-07-15

## Problem

In `TeamMode.mixed`, Claude Code members coordinate via teammate-bus MCP, not Claude's native swarm. Native tools (`TeamCreate`, `SendMessage`, `Task*`, …) remain enabled and can confuse the model into spawning a parallel native team. Native mode already denies `TeamCreate`/`TeamDelete` via `permissions.deny`; mixed mode intentionally omits that deny (unknown-tool deny can abort CLI startup). We need a CLI-flag deny that works in mixed without touching settings deny.

## Decisions

1. **Mechanism:** append Claude Code `--disallowedTools` in `ClaudeCodeCliToolAdapter.buildArguments` when `team.teamMode == mixed`.
2. **Who:** every Claude Code member in a mixed team (lead and workers).
3. **Shared deny list:** `TeamCreate`, `TeamDelete`, `SendMessage`, `TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`, `TaskStop`, `TaskOutput`.
4. **Lead-only extra:** `Agent` (blocks native teammate spawn via Agent; workers keep Agent for ordinary subagents).
5. **Constants:** live next to `MemberRoleProvision.teamSessionDenyTools` / `mixedTeamSessionAllowTools`, with a small helper `disallowedToolsForMixedClaude({required bool isLead})`. Adapter only calls the helper.
6. **Flag shape:** `--disallowedTools` followed by space-separated tool names (Claude Code `parseToolListFromCLI` accepts space/comma separators).
7. **extraArgs:** do not parse or merge user `extraArgs` for this flag (YAGNI). TeamPilot always emits its own `--disallowedTools` as separate argv tokens (`['--disallowedTools', 'TeamCreate', …]`). If the user also passes `--disallowedTools` in `extraArgs`, behavior depends on Claude Code/Commander (may replace or accumulate) — not a hard guarantee; do not add merge logic in this change.
8. **Planning-only lead:** out of this change. Keep existing `forceTeamLeadDelegateMode` PreToolUse hooks; do not fold Bash/Edit/Write into `--disallowedTools` yet. Lists stay easy to extend later.

## Architecture

```
ClaudeCodeCliToolAdapter.buildArguments
  → if teamMode != mixed: unchanged (native still uses --team-name / permissions.deny)
  → if mixed:
       tools = MemberRoleProvision.disallowedToolsForMixedClaude(
         isLead: TeamMemberNaming.isTeamLead(member),
       )
       args += ['--disallowedTools', ...tools]
  → then settings / append-system-prompt / skip-permissions / extraArgs
```

## Key constants

| Constant | Tools |
|----------|--------|
| `mixedClaudeDisallowedTools` | TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet, TaskStop, TaskOutput |
| `mixedClaudeLeadExtraDisallowedTools` | Agent |

Helper returns `[...mixedClaudeDisallowedTools, if isLead ...mixedClaudeLeadExtraDisallowedTools]`.

## Tests

In `cli_tool_adapter_test.dart`:

1. mixed + worker → `--disallowedTools` includes shared list; does **not** include `Agent`; no `--team-name`.
2. mixed + `team-lead` → shared list **plus** `Agent`.
3. native Claude → no `--disallowedTools`.

## Out of scope

- Changing `applyTeamSessionPolicy` / `permissions.deny` for mixed
- `forceTeamLeadDelegateMode` / planning-only tool bans via CLI
- UI or team-config toggles for the deny list
- Non-Claude CLIs
