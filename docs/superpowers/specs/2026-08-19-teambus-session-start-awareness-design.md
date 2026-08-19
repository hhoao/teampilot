# TeamBus SessionStart awareness

## Goal

Mixed-mode members learn they are on a TeamBus team the same way Superpowers
forces skill use: inject the protocol into live model context at session start,
instead of relying only on a buried `role.md` / `AGENTS.md`.

## Problem

Today mixed TeamBus awareness is a one-shot role prompt plus MCP tools plus a
Stop idle hook. Models treat the session as a solo agent until a human mentions
the team. Superpowers avoids that by a `SessionStart` command hook that prints
`additionalContext` containing `using-superpowers`.

## Design

### Injected text

One Superpowers-style envelope wrapping the existing mixed role addendum for
that seat (lead / worker / Cursor push). Do not re-inject the member's
responsibilities or playbook.

```
<EXTREMELY_IMPORTANT>
You are on a mixed TeamPilot team. You MUST coordinate through teammate-bus
MCP tools. Do not wait for the human to mention the team.

**Below is the TeamBus protocol for this seat:**

{mixed lead | worker | push addendum}
</EXTREMELY_IMPORTANT>
```

### Claude, flashskyai, Codex, Cursor

Managed command hook, mixed sessions only:

| Field | Value |
|---|---|
| id | `teampilot-bus-awareness-sessionStart` |
| source | `managed` |
| event | `sessionStart` |
| matcher | none (fire on startup, resume, clear, compact) |
| action | command script that prints CLI-specific JSON |
| timeout | 5s |
| blockOnDecision | false |

Stdout JSON:

- Claude / flashskyai / Codex: `hookSpecificOutput.hookEventName=SessionStart` +
  `additionalContext`
- Cursor: top-level `additional_context`

No matcher on purpose: resume is when the model most often forgets the team.
Superpowers skips resume; TeamBus does not.

Assembly: new `BusAwarenessHookContributionProvider` next to bus-idle in
`_launchHookProviders` and each CLI's local hook assemble fallback. The
provider contributes nothing for OpenCode (`sessionStart` unsupported; a
managed unsupported event would fail closed).

### OpenCode

OpenCode has no `sessionStart`. A dedicated plugin
`teampilot-bus-awareness.js` uses `experimental.chat.system.transform` to
unshift the same envelope onto `output.system` on every LLM request (skip if
already present). Plugin options carry `{ prompt }`. Installed in mixed
`contributeLaunch` beside the idle plugin, not through the hook writer.

`chat.message` cannot inject system context, so it is not used.

## Non-goals

- UserPromptSubmit / every-user-message injection on Claude-family CLIs
- Changing idle Stop behavior, MCP tools, or role.md contents
- Simple (non-mixed) sessions
