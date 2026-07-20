# Agent permission attention (Orca-aligned)

**Date:** 2026-07-19  
**Status:** Implemented (unit-tested)  
**Related:** [`2026-07-18-history-live-continue-design.md`](2026-07-18-history-live-continue-design.md), Orca `src/main/agent-hooks/` + `src/shared/agent-hook-listener.ts`

## Problem

Under **default permissions** (`dangerouslySkipPermissions == false`), CLI agents pause on in-TUI approval prompts (Allow / Do you want…). TeamPilot’s History live-continue path keeps users on History, so the permission dialog lives only in the Alacritty PTY. Users often do not know they must switch to Terminal.

PTY quiet / `workingSessionIds` heuristics cannot distinguish “turn finished”, “thinking”, and “waiting for permission”. VS Code Claude Code extension avoids this by owning permission UI via `canUseTool`; TeamPilot (like Orca) keeps PTY as the runtime and must **detect + surface attention**, not re-implement Allow in History.

## Goals

- Definitive **waiting-for-user** signal for every launch CLI that Orca can cover the same way.
- Surface “needs you” while user is on History or another session: banner + sidebar marker + jump to Terminal.
- Keep Terminal as the only place to answer permission prompts.
- Suppress false waits when the seat launched with skip-permissions / YOLO.
- Work for local PTY and SSH/WSL member seats (hook HTTP reachable on the agent host, same pattern as TeamBus `/idle`).

## Non-goals

- In-chat Allow / diff approval (VS Code extension model).
- Making History answer CLI permission keypresses.
- Replacing TeamBus `/idle` Stop hooks or presence model.
- Perfect Cursor permission detection (upstream has no permission hook; title-only signal with required live OSC observation, as Orca).
- Copilot-style `blocked` vs `waiting` split in v1 (single `waiting` is enough).

## Product decisions (locked)

| Choice | Decision |
|--------|----------|
| Pattern | Copy Orca: managed hooks/plugins → loopback HTTP → normalize → UI attention |
| Confirmation UI | Terminal only; History/sidebar only notify + navigate |
| State vocabulary (v1) | `working` \| `waiting` \| `done` (per seat) |
| Primary signal | Hook / plugin events — **not** PTY quiet heuristics |
| Fallback | Terminal-title heuristic only where hooks cannot report permission wait (Cursor) |
| Cursor v1 | **Required** live title observation: parse OSC title from the seat PTY stream → Orca-aligned classifier → `waiting`. Fixture-only / docs-only Cursor attention is **out of scope** — either wire the title channel or Cursor has no attention surface (no fake waiting). |
| Skip-permissions | When effective launch uses skip/YOLO for that seat, do not show `waiting` attention |
| Scope | All five launch CLIs: Claude, flashskyai, Codex, OpenCode, Cursor |
| Multi-seat | Attention keyed by `sessionId` + TeamBus-style member instance id (`X-Member`); History banner for **selected** seat; sidebar marks session if **any** seat waiting |
| Seat key (`X-Member`) | Same as TeamBus idle provision: team seats use roster member instance id; simple/unteamed seats use `session.sessionId` as the member header value (not empty, not a separate sentinel) |
| Sidebar click | Jump opens session Terminal and focuses the waiting seat when the marker’s seat ≠ current selection |
| HTTP surface | `POST /agent-status` on the **same** `TeammateBusMcpGateway` loopback HTTP port as `/idle` and `/mcp` (separate route + handler; not a second `HttpServer`). SSH reverse tunnels that already target that port deliver status POSTs for free. |

## Per-CLI signal matrix (Orca-aligned)

| CLI | Install | → `waiting` | Clear `waiting` | Notes |
|-----|---------|-------------|-----------------|-------|
| Claude | `settings.json` hooks: `PermissionRequest`, `PreToolUse`/`PostToolUse`/`Stop` (and AskUserQuestion on PreToolUse) | `PermissionRequest`; AskUserQuestion PreToolUse | Matching PostToolUse / Stop / new UserPromptSubmit working edge | Sticky wait across concurrent subagents until clear signal (Orca `shouldKeepClaudePermissionVisible`) — v1 may ship simplified sticky (clear on Stop or any PostToolUse for that seat) if full tool_use_id matching is deferred |
| flashskyai | Same event set in flashskyai config dir (Claude-compatible) | Same | Same | Verify event names + settings path in profile capability; treat as Claude-family |
| Codex | `hooks.json` `PermissionRequest` + trust entries | `PermissionRequest` | PostToolUse / Stop | Suppress when `--dangerously-bypass-approvals-and-sandbox` (or TeamPilot equivalent) on launch |
| OpenCode | Per-session plugin overlay (not global home install) — map `permission.asked` / `question.asked` | Plugin events normalized to waiting | SessionIdle / subsequent working | Mirror Orca `OPENCODE_CONFIG_DIR` + plugin file; TeamPilot already has OpenCode idle plugin pattern |
| Cursor | **No permission hook** | OSC/title classifier only (`action required`, permission keywords, Orca-aligned rules; bare `Cursor Agent` ≠ waiting) | Title no longer matches | Do **not** map shell-before hooks to waiting. v1 **must** observe live titles from PTY (see Product decisions). |

## Architecture

```
Session runtime provision (CliToolDefinition / config profile)
  → install managed status hooks / OpenCode plugin
  → stamp env: `TEAMPILOT_AGENT_STATUS_URL` (same `TEAMPILOT_*` prefix as other session env), session + `X-Member` headers (or file endpoint like Orca)

CLI fires hook
  → POST TeammateBusMcpGateway /agent-status (loopback HTTP; SSH: reverse tunnel to same httpBusPort as /idle)
  → AgentStatusNormalizer (per CliTool)
  → AgentAttentionCubit.setSeatState(sessionId, seatId, working|waiting|done)

UI
  → History: waiting banner + “Open Terminal”
  → Sidebar session tile: needs-you affordance when any seat waiting
  → setSessionWorkbenchView(terminal) on jump
```

### Components

| Unit | Responsibility |
|------|----------------|
| `/agent-status` on `TeammateBusMcpGateway` | Same bind/port as `/idle`; auth headers; route by session/seat; does **not** call TeamBus idle/park |
| `AgentStatusNormalizer` | Per-CLI map raw hook JSON → `{ state, toolName?, clearedBy? }` |
| Managed hook installers | Claude/flashskyai settings merge; Codex hooks.json+trust; OpenCode session plugin (extend existing idle plugin or sibling) |
| `AgentAttentionCubit` | Seat-keyed attention state; skip-permissions gate; stale TTL |
| History banner | Shown when selected seat is `waiting` and workbench is History |
| Sidebar marker | Session-level “needs you” if any roster seat waiting |
| Title observer (Cursor) | Required PTY OSC-title parse + classifier; never overrides fresher hook state for hook-capable CLIs |

### Relation to existing TeamBus `/idle`

- TeamBus Stop `/idle` remains for mixed-team park / idle coordination.
- Agent status is a **separate route** (`/agent-status`) on the **same** gateway HTTP server so permission attention does not overload idle semantics, while SSH tunnels stay one port.
- Shared: loopback bind, `X-Session` / bus token for remote, provision into session runtime trees via `RuntimeLayout` / config profiles.
- Simple / non-mixed sessions that never install TeamBus still **register** on the gateway for status auth (session id ± remote token) without creating a TeamBus handler.

### SSH / WSL reachability (locked)

| Seat | How `/agent-status` is reachable |
|------|----------------------------------|
| Local PTY | `http://127.0.0.1:<gatewayPort>/agent-status` |
| Mixed + SSH | Existing `RemoteBusMount` HTTP tunnel to gateway `httpBusPort`; stamp `agentStatusUrl` on same remote loopback port as `idleUrl` |
| Simple or non-mixed + SSH | Provision an HTTP reverse tunnel to the **same** gateway `httpBusPort` (reuse `RemoteBusMount` HTTP-only bind or equivalent); register remote token; stamp `agentStatusUrl`. Do **not** leave these seats on unreachable local `127.0.0.1` of the app host. |
| Tunnel failure | Launch succeeds; log warning; seat has no attention (same as hook install failure) |

### Skip-permissions / YOLO

Effective skip for a seat (launch args / continue overrides / member `dangerouslySkipPermissions`) ⇒:

- Still accept hooks if fired, but **do not** emit UI `waiting` (or normalizer maps permission events to `working` / ignore).
- Matches Orca Codex auto-approval notification suppression intent.

### Clearing `waiting`

| Event | Effect |
|-------|--------|
| Seat Stop / turn done hook | `done` (clears waiting) |
| PostToolUse after permission (when identifiable) | `working` or clear wait |
| UserPromptSubmit / new turn working | `working` |
| PTY dispose / seat disconnect | clear seat entry |
| Stale TTL (e.g. 30 min, Orca-like) | drop attention if no refresh |

Claude concurrent-subagent sticky: prefer Orca’s tool_use_id inheritance when payloads include ids; if flashskyai/Claude payloads omit ids, clear on Stop or seat-level PostToolUse (document as known softer behavior).

## UX details

- Banner copy (l10n): needs Terminal confirmation; primary action jumps to Terminal for that session/seat.
- Do not auto-switch workbench on waiting (user may be reading History); badge + banner only unless later preference says otherwise.
- Sidebar: distinct from “working” spinner — waiting is attention, not progress.
- Optional synthetic title **write** `"{Agent} - action required"` when waiting (Orca); v1 may defer OSC **write**. OSC **read** for Cursor classifier is required.
- This spec is the concrete attention surface for history-live-continue’s “jump-to-Terminal only” permission non-goal.

## Error handling

| Case | Behavior |
|------|----------|
| Hook POST fails / gateway down | No false waiting; log diagnostic; Cursor still uses live title channel only |
| Corrupt payload | Ignore event; keep prior state |
| Remote SSH cannot reach gateway | Must provision tunnel/headers like TeamBus idle; otherwise document seat as no attention |
| Hook install fails at provision | Launch still succeeds; attention unavailable for that seat; log warning |

## Testing

- Normalizer unit tests per CLI fixture payloads (PermissionRequest → waiting; Stop → done; YOLO → no UI waiting).
- Gateway auth: reject missing session/seat headers.
- Cubit: multi-seat session; clear on dispose; stale TTL.
- Widget: History banner visible only for waiting + History view; jump sets terminal view.
- OpenCode plugin event mapping (permission.asked → waiting).
- Cursor title fixtures → waiting; bare “Cursor Agent” → not waiting (Orca rule).
- Integration (tag `integration`): Claude/Codex local hook fire against gateway when feasible.

## Success criteria

1. On Claude/Codex/OpenCode/flashskyai (Claude-family) with default permissions, a real permission prompt surfaces History banner and sidebar needs-you without relying on PTY quiet.
2. Jump opens Terminal so user can approve in TUI.
3. Skip-permissions seats do not show waiting attention.
4. Cursor attention uses live title observation + classifier (not hooks); bare native title does not mark waiting; no false hook-grade certainty in copy/UI.
5. TeamBus idle / mixed park behavior unchanged.

## Implementation notes (guidance, not a plan)

- Prefer registry/capabilities under `services/cli/registry/` for installers; avoid scattered `if (cli == …)`.
- Reuse OpenCode idle plugin packaging for status plugin.
- Keep `AgentAttentionCubit` thin; normalizers pure and testable.
- Extend history-live-continue non-goal (“jump-to-Terminal only”) with this concrete attention surface.
