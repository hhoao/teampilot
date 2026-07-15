# Mixed-team machine visibility (Members UI) + TeamBus MCP JSON

**Status:** Approved  
**Date:** 2026-07-15

## Problem

1. **UI:** In a mixed-team hybrid workspace, the right-tools **Members** panel shows presence and CLI/model but not which machine each member is pinned to. Operators cannot tell at a glance who runs locally vs on SSH/WSL.
2. **MCP:** TeamBus tool success bodies from `TeammateBusToolFormat` are line-oriented prose. Agents parse them brittlely; empty results are English sentences. Separately, roster output still lacks stable machine identity (see sibling install snapshot work).

## Goal

- **Track A:** When a mixed session spans ≥2 machines, group the Members list by machine (icon + label). Otherwise keep today’s flat list.
- **Track B:** Make every encoder in `TeammateBusToolFormat` return compact JSON. Empty successes use empty collections. Expose install-time `machine` / `machine_kind` / `machine_id` (+ correct per-member `cwd`) on `list_teammates` members.

## Non-goals

- Member detail dialog machine fields.
- Grouping for native teams or single-machine mixed sessions.
- Mid-session placement refresh without bus reinstall.
- Changing artifact transfer APIs.
- Converting tools that do **not** go through `TeammateBusToolFormat` (e.g. `send_message` → `"sent"`, artifact list prose) in this change.
- Wrapping successes in `{ok, data}` envelopes; errors stay `toolError` text.
- Exposing SSH credentials / private keys.
- Enriching `local` with OS hostname (literal `"local"`).

## Relationship to other specs

Install-time machine snapshot + per-member cwd wiring is specified in [`2026-07-15-list-teammates-machine-design.md`](./2026-07-15-list-teammates-machine-design.md). **This document supersedes that spec’s prose output shape** (`machine:` lines). Profile fields, `rosterMachineFromTarget`, and `installBusForTab` injection remain as in the machine design; Track B emits those fields as JSON keys instead.

---

## Track A — Members panel grouping

### Behavior

| Condition | UI |
|-----------|----|
| Team mode ≠ mixed, or distinct resolved `targetId`s among listed members &lt; 2 | Flat list (unchanged) |
| Mixed and ≥2 distinct targets | Sections with headers |

**Header:** machine icon + display label (reuse `workspaceFolderTargetIcon` / `workspaceFolderTargetLabel`). Do **not** show member count in the header (narrow panel).

**Group order:** machine that contains the team lead first; remaining groups by first appearance of that `targetId` in the incoming roster order.

**Within group:** lead first, then preserve roster order for the rest.

**Member rows:** unchanged subtitle (`presence · provider/model`) and presence indicator. Machine is only on the section header.

### Data flow

```
memberTargets resolve:
  if active session present → AppSession.memberTargets
  else → rememberedMemberTargets(workspace.memberTargetsByTeam, teamId)
memberTargetForInstanceId(memberTargets, member.id)
HomeTargetController.listSelectable()  →  label/icon for targetId
pure groupMembersByMachine(...)  →  MembersPanel render
```

- Wire resolved `memberTargets` (and selectable targets) from `_ScopedMembersPanel` into `MembersPanel`.
- **Unresolved pin rule (single):** missing / empty pin → bucket key `"local"`. Non-empty unknown `targetId` (not in selectable list) → keep that id as the bucket key; use generic computer icon + raw id (or profile-less label helper) for the header. Do not invent a second fallback key.

### Testing

- Pure function: 2 machines / 1 machine / non-mixed / lead’s machine first / lead within group.
- Widget (optional light): headers appear only when ≥2 targets.

---

## Track B — `TeammateBusToolFormat` → JSON

### Principles

1. Success path: `jsonEncode` of a `Map` / `List` (compact, no pretty-print).
2. Omit empty optional fields (`''`, empty lists, null).
3. Empty collections for empty success (no English “No teammates…” strings).
4. `claim_task` success = single **task object** (same shape as a `list_tasks` item with `brief`). Post-claim / auto-claim workflow (`update_task` then `wait_for_message`) lives in tool **descriptions** (`claim_task` and `wait_for_message`), not in the payload.
5. Errors remain human `toolError` strings. `unknownRecipientHint` becomes a compact JSON object string appended after a short reason (newline-separated) so agents can still parse recipients.
6. **Prerequisite:** sibling install/profile/cwd work ([list-teammates-machine design](./2026-07-15-list-teammates-machine-design.md)) must land before or as earlier tasks in the same plan; Track B only JSON-encodes profile fields once they exist.

### Shapes

#### `encodeRoster` / `list_teammates`

```json
{
  "caller": "<memberId>",
  "team": {
    "team_id": "...",
    "team_name": "...",
    "cli_team_name": "...",
    "team_mode": "...",
    "lead_agent_id": "...",
    "app_session_id": "...",
    "cwd": "...",
    "description": "...",
    "additional_paths": ["..."]
  },
  "members": [ /* see member object */ ]
}
```

- No members: `{"caller":"...","members":[]}` (include `team` when present).
- Member object (illustrative; omit empties):

```json
{
  "member_id": "...",
  "display_name": "...",
  "agent_id": "...",
  "agent_type": "...",
  "role": "leader|worker",
  "cli": "...",
  "backend_type": "...",
  "model": "...",
  "provider": "...",
  "agent": "...",
  "task_id": "...",
  "machine": "root@host:22",
  "machine_kind": "ssh",
  "machine_id": "ssh:<profileId>",
  "cwd": "...",
  "self": true,
  "joined_at": 0,
  "extra_args": "...",
  "dangerously_skip_permissions": false,
  "responsibilities": "...",
  "bus": {
    "lifecycle": "...",
    "activity": "...",
    "phase": "...",
    "unread": 0
  },
  "claude_is_active": true,
  "pty_running": true
}
```

Machine keys: emit all three iff `machineId.isNotEmpty` (same rule as the machine design’s empty rule). Production install always fills them.

#### `encodeTasks` / `list_tasks`

`{"tasks":[ ... ]}` — empty → `{"tasks":[]}`.

Task object: `id`, `status`, `title`, optional `assignee`, `depends_on`, `required_capabilities`, `eligible_for_you`, `match_score`, `result`, `brief` (when full / assignment).

#### `encodeTaskAssignment` / `claim_task`

Single task object (with `brief`), not wrapped in `{tasks:[...]}`.

#### `encodeMessagePage` / `read_messages`

```json
{
  "messages": [ /* message objects */ ],
  "total_unread": 0,
  "has_more": false,
  "next_after_id": "..."
}
```

Empty page: `messages: []` still includes `total_unread` / `has_more` (and `next_after_id` if set).

#### `encodeBatch` / `wait_for_message`

`{"messages":[ ... ]}` — empty → `{"messages":[]}`.

**Dual success shapes on `wait_for_message`:** the tool may return either `encodeBatch` (message page) **or** `encodeTaskAssignment` (bare task object when auto-claiming). After prose removal, agents distinguish by JSON shape: object with top-level `messages` vs object with top-level `id`/`status`/`title` (task). Document both in `WaitForMessageTool.description`.

#### Message object

```json
{ "from": "user|<memberId>", "kind": "message|idle", "content": "..." }
```

- Operator: `from: "user"`, `kind: "message"`.
- Idle notification: `kind: "idle"`, `content` = leader-oriented summary from `IdleNotification`.
- Normal peer mail: `kind: "message"`.

#### `unknownRecipientHint`

```json
{ "known_recipients": [ { "member_id": "...", "agent_id": "..." } ] }
```

`agent_id` omitted when equal to `member_id` or empty. Callers that today append the hint after an error keep: short English reason + `\n` + this JSON string.

### Tool descriptions

Update descriptions for tools that consume these encoders (`list_teammates`, `list_tasks`, `claim_task`, `read_messages`, `wait_for_message`) so agents expect JSON and know machine/cwd fields on roster members. Expand `claim_task` **and** `wait_for_message` descriptions with the post-claim / auto-claim loop (`update_task` → `wait_for_message` again).

### Key naming

Use **snake_case** JSON keys (as in the shapes above) for consistency with existing MCP argument names (`task_id`, etc.).

### Breaking change

Intentional. Any agent or test that scraped prose lines must switch to JSON. Update unit tests that assert format strings.

### Testing

- Unit: each encoder — nonempty + empty fixtures; `jsonDecode` round-trip.
- Unit: member JSON includes machine fields for local/ssh fixtures; omits when `machineId` empty.
- Unit: `encodeTaskAssignment` has no `ASSIGNED TASK` prose; equals full task object.
- Existing MCP handler tests updated to parse JSON.

---

## Implementation notes

| Area | Prefer |
|------|--------|
| Grouping logic | Pure Dart helper next to members panel or under `utils/` with a concrete name (e.g. `members_machine_groups.dart`) — not a vague `helpers` |
| Labels | Existing workspace folder target label/icon helpers |
| JSON | `dart:convert` `jsonEncode`; build `Map<String, Object?>` with conditional puts |
| Machine install | Follow list-teammates-machine design; format layer only reads profile fields |

## Out of scope follow-ups

- JSON-ify remaining TeamBus tools outside `TeammateBusToolFormat`.
- `same_machine` relative to caller on roster rows.
- Collapsible machine sections / counts in headers.
