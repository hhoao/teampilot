# Mixed Team ACP Session Design

## Goal

Let **mixed TeamBus members** opt into terminal-less ACP chat per seat,
without replacing PTY mixed teams, native Claude teams, or personal ACP.

Personal ACP stays a session kind (`AppSession.acp` + `isAcpChatSession`).
Team ACP is a **seat transport**: each mixed member is independently ACP or
PTY. One team may mix both. Collaboration stays the existing TeamBus MCP
protocol.

Decisions locked with the user (2026-10-12):

- Approach A: mixed TeamBus + per-member ACP. Not native `--team-name`.
- Same team may mix ACP and PTY members. A single seat must not run both.
- `AppSession.acp` remains personal-only. Team sessions always persist
  `acp: false`.
- Seat fact is `SessionMemberBinding.acp`. Omit when false.
- Existing Claude / Codex settings switches also seed **new** mixed
  members of that CLI. Preference keys do not change. Existing team
  sessions stay PTY.
- Gemini mixed members on a local desktop target are ACP (same as
  personal Gemini).
- Desktop local only (`RuntimeKind.local`). Android, SSH, WSL, Termux,
  and native teams stay PTY.
- First-wave CLIs: Claude, Codex, Gemini, Cursor, and OpenCode (each
  declares `AcpCapability`). FlashskyAI stays PTY.
  OpenCode mixed seats: docs/superpowers/specs/2026-10-13-opencode-acp-session-design.md.
- Protocol stack stays vendored `acpd` + `AcpProcessTransport`.
- Do not fall back to PTY when ACP attach fails for that seat.
- Do not rewrite TeamBus. Wire idle / wake onto the existing launcher.

## Why this shape

ACP today is a session-level shortcut that skips roster, TeamBus, and the
PTY shell (`SessionConnectExecutor` returns after `attachAcpRuntime`).
That is correct for simple chat and wrong for a team.

Mixed teams already spawn one process per member and talk over teammate-bus
MCP. ACP is another stdio process per member. Native Claude teams are one
CLI process with `--team-name`; adapters do not speak that, so they stay
out of this phase.

```
Personal ACP:  isAcpChatSession → attachAcpRuntime → skip TeamBus/PTY
Mixed ACP:     resolveMember → installTeamBus → prepareTeamConnect
               → attachMemberAcp (or PTY connect) → fan-out
```

## Layering

| Piece | Owner |
|-------|--------|
| `services/acp/*` | `openSession` gains `mcpServers` (default `[]`). No other protocol change. |
| `SessionMemberBinding.acp` | Seat fact. JSON omit-when-false. Include in `==` / `hashCode`. |
| `isAcpChatSession` | Unchanged: `session.isSimple && session.acp`. |
| `isAcpChatSeat` | New, next to `isAcpChatSession` in `chat/session/chat_tab.dart`. |
| `resolveLaunchAcp` | Personal Claude/Codex desktop gate, unchanged. |
| Seat ACP resolver | New helper beside `claude_acp_launch_switch.dart`: mixed + local + capable CLI + not Android. |
| `ChatTab.memberAcpRuntimes` | `Map<String, AcpChatRuntimeCubit>` parallel to `memberShells`. |
| `ChatTab.acpRuntime` | Alias: personal uses `sessionId` as the sole key. |
| `AcpChatRuntimeCubit.seatMemberId` | Personal default `'acp'`; team passes the roster member id. |
| `MemberLauncher` / materializer | ACP `wake` / `retryDelivery` → `sendPrompt`; PTY unchanged. |
| Settings copy | Same preference keys; arb text covers new mixed members. |

No `if (cli == …)` at the executor. Capability + binding + runtime kind
decide the branch.

`SessionLaunchService` is already past the services size limit (~1088
lines). Do not add `attachMemberAcpRuntime` there. Extract personal
`attachAcpRuntime` and the new member attach into
`launch/connect/acp_runtime_attach.dart` (or the existing
`acp_launch_environment.dart` if it stays one concern). The service
implements the port by delegating.

## Session model

### `AppSession.acp`

Unchanged. Team create still forces `false`
(`trimmedTeam.isEmpty && (acp || cli == gemini)`).

### `SessionMemberBinding.acp`

- Type: `bool`, default `false`.
- JSON: omit when false; write `"acp": true` when true.
- Missing key → `false` (every existing team session stays PTY).
- Create stamps it; reconnect trusts the binding, not the preference.

Stamped `true` only when **all** of:

1. Team mode is mixed (native never stamps true).
2. Member CLI has `AcpCapability` (Claude, Codex, Gemini).
3. Member target `runtimeKindOfId` is `RuntimeKind.local`.
4. Not Android.
5. Claude / Codex: the existing personal-ACP preference is on. Gemini:
   always (no preference).

WSL, SSH, and Termux fail (3) and stay PTY.

### `isAcpChatSeat`

```
bool isAcpChatSeat(AppSession session, String memberId) =>
    !session.isSimple &&
    (session.bindingFor(memberId)?.acp ?? false);
```

`isAcpChatSeat` is binding-only (plus “not simple”). Connect-time
**defense** is a separate gate in the executor (do not persist a rewrite
this phase): even if the binding says true, take PTY when the team is
not mixed, the member target is not local, the platform is Android, or
the CLI has no `AcpCapability`.

### Preference vs binding

| Store | Role |
|-------|------|
| `claudePersonalAcpDefault` / `codexPersonalAcpDefault` | Default for **new** personal sessions **and** **new** mixed local members of that CLI. |
| `AppSession.acp` | Personal session fact only. |
| `SessionMemberBinding.acp` | Mixed seat fact. Reconnect / open-existing uses it. |

Changing a preference does not rewrite existing sessions or bindings.
No new preference key. No team-compose ACP toggle this phase.

## Launch

### Executor

Keep the personal shortcut:

```
if (isAcpChatSession(session)) attachAcpRuntime; return;
```

After `resolveMember` + `installTeamRuntime` (TeamBus up):

```
if (seat is ACP after connect-time defense)
  attachMemberAcpRuntime
  onResult(..., ConnectShellResult.attached)  // fan-out remaining members
  return
else
  existing PTY connect
```

Personal ACP still skips `onResult` (no teammates). Mixed ACP **must**
call `onResult` with `attached` so `shouldFanOutRemainingMembers` runs.
ACP attach is not a shell, but a successful start is still `attached`.
A failed ACP attach matches failed PTY: `onResult` is not treated as
`attached`, so fan-out does **not** auto-start siblings. The user can
still connect other members by hand.

Deferred (`connectShell == false`) mixed ACP seats still install TeamBus
and skip process spawn, same as deferred PTY.

### `attachMemberAcpRuntime`

Same spawn / handshake as personal `attachAcpRuntime`, except:

- Env comes from `prepareTeamConnect` (not `prepareSimpleConnect`).
- Cubit is stored at `tab.memberAcpRuntimes[member.id]`.
- `seatMemberId` is the roster id.
- Transcript path is per member (below).
- `session/new` `mcpServers` is the extra MCP list from that team
  staging (teammate-bus, plus catalog if it is already in extra MCP).
  Personal continues to pass `[]`.

Claude / Codex still consume teammate-bus from isolated `CONFIG_DIR`
written by team staging. Gemini (no config MCP) depends on `mcpServers`.
Tests must fail if a mixed ACP seat opens with an empty list.

### Transcript

| Kind | Path under `sessions/<id>/runtime/` |
|------|--------------------------------------|
| Personal | `acp-transcript.jsonl` (unchanged) |
| Mixed member | `acp-transcript-<rosterMemberId>.jsonl` |

Roster ids are already slug-shaped (`team-lead`, `builder-0`). Do not
share one file across members. Document format stays the v1 message
snapshot from the history spec
(`docs/superpowers/specs/2026-10-10-acp-history-message-document-design.md`).

### Tab runtime

```
memberShells:        memberId → TerminalSession
memberAcpRuntimes:   memberId → AcpChatRuntimeCubit
acpRuntime           getter/setter for the personal alias only
                     (key = session.sessionId)
```

Existing `tab.acpRuntime = cubit` personal assign writes the map via the
setter. Team UI passes `memberAcpRuntimes[selectedMemberId]` explicitly;
`acpRuntime` must not follow the selected member. Dispose every cubit in
`ChatTab.disposeBus`.

Selecting a member binds the chat view to that member's cubit or shell.
ACP seats hide the live-terminal toggle; PTY seats keep it.
Session-level `isAcpChatSession` chrome remains for personal only.

## Runtime / TeamBus

TeamBus protocol, mailbox JSONL, task board, and MCP tool names do not
change.

| Event | ACP seat | PTY seat |
|-------|----------|----------|
| User compose | `cubit.sendPrompt` | existing paste/submit |
| Turn end | cubit `idle` → `TeamBus.onMemberIdle(memberId)` (`fromPtyQuietWatch: false`) | existing hooks / quiet watch |
| `wake` / `retryDelivery` | `cubit.sendPrompt(notice)` | stdin inject |
| Handshake still running | queue prompt (existing cubit `_queuedPrompt`) | existing materialize wait |
| `ensureMemberInputReady` | return when cubit is `ready` or `idle` | existing composer wait |

`AcpChatRuntimeCubit` attention / permission holds use `seatMemberId`,
not the synthetic `'acp'`, so mixed cards and presence key the real
roster member.

ACP seats do not park on a PTY `wait_for_message`. They use teammate-bus
MCP the same way mixed Claude already does over MCP. Do not invent a
second doorbell protocol. Do not set `forceWaitBeforeStop` by injecting
PTY idle scripts into ACP.

ACP mixed seats have no `memberShells` entry. Add a coordination path
that reads cubit `inTurn` / `activity` / `idle` / `ended` and never
touches `shell.activityTracker`. PTY mixed coordination is unchanged.

## Idle reclaim and session resume

Hidden mixed ACP seats now participate in the Chrome-style idle reclaim
watch. When a background mixed seat is prompt-idle past the ACP threshold
(PTY threshold ×2), the watch discards it via `discardAcpSeat`: the cubit
is closed (persisting the transcript and the agent session id) and the
seat is recorded in `ChatTab.reclaimedMemberIds`. Personal ACP is reclaimed
too once its tab is not centre-active — see
[2026-10-22-personal-acp-idle-reclaim](../plans/2026-10-22-personal-acp-idle-reclaim.md);
it re-attaches on the next send, not on view (simple-PTY parity);
the selected seat, a launching seat, and a seat in `ended`
phase are protected, mirroring the PTY protection set. Restoration is lazy
and unchanged: the member-connect funnel re-attaches the seat
(`attachMemberAcpRuntime` re-creates the cubit because the discarded seat
was removed from `memberAcpRuntimes`), and `onConnectResult(attached)`
clears `reclaimedMemberIds`.

The agent session id (the ACP `session/new` response id) is persisted in a
per-seat sidecar (`acp-session-<rosterMemberId>.json`, or `acp-session.json`
for personal). On the next start the id is read back and reopened via
`session/load`; if the agent does not negotiate `session/load`, it falls
back to `session/resume`, then to a fresh `session/new`. Any load/resume
failure also falls back to `session/new` so a stale id never blocks launch.

## UI

- Settings: keep the Claude / Codex switches. Update label/description
  so they apply to new mixed local members as well as new personal
  sessions. Android still hidden/disabled.
- Team landing / team compose: no extra ACP control this phase.
- Chat center: selected member's cubit drives history + send + permission
  card (`acp_seat_message_sync` already seats on the cubit).
- Workbench terminal toggle: per selected seat, not per session.

## Failure policy

| Failure | Behavior |
|---------|----------|
| Adapter missing, install failure, handshake failure | l10n on **that seat**; cubit `ended`. Do **not** fall back to PTY on the same connect. Binding stays `acp: true`; reconnect retries ACP. |
| Mid-session process exit | System message + `ended` on that seat only. Other members keep running. |
| One seat attach fails | Same as failed PTY: that seat `ended` / failed; siblings are **not** auto fan-out. Manual connect of other members still works. |
| SSH / Android / native / no `AcpCapability` | Never stamp `binding.acp`. Connect-time defense if a stale true appears. |
| Mixed ACP `mcpServers` empty when TeamBus extra MCP exists | Treat as attach failure (Gemini collaboration would be silent). |
| Tab close | Dispose all `memberAcpRuntimes`, then TeamBus. |

Personal sessions still forbid ACP+PTY on the same session. Teams mix
across members only.

## Out of scope

- Native Claude / FlashskyAI `--team-name` ACP
- `SshExecTransport` / Android / WSL / Termux ACP
- Cursor ACP (unshipped; later rides `AcpCapability` + binding)
- OpenCode / FlashskyAI ACP
- Replacing PTY mixed teams
- Per-member ACP toggle on team compose
- Rewriting existing team sessions when the preference changes
- Advertising `fs/*` / `terminal/*` client capabilities (stay false)
- Changing TeamBus wire protocol or mailbox format

## Testing

Constructor-injected fakes. Cubit / repository tests that need a home
plane use `setUpTestAppStorage()` / `tearDownTestAppStorage()`. Do not
invoke `flutter test` directly.

| Layer | Cases |
|-------|--------|
| Binding JSON | omit `acp` → false; `"acp": true` round-trip; `==` / `hashCode` include `acp`. |
| `AppSession` create | team `acp` still false when members have binding `acp` true. |
| `isAcpChatSeat` | mixed + binding true → true; simple session → false; missing/false binding → false. |
| Seat resolver (create stamp) | new mixed Claude/Codex follow preference; Gemini local mixed → true; native / Android / WSL / SSH / OpenCode → not stamped. |
| Connect-time defense | binding true + SSH target still opens PTY, does not rewrite the binding. |
| Executor | mixed ACP seat installs TeamBus, attaches ACP, does not open PTY, calls `onResult` so a second member fans out; mixed PTY sibling still shells; personal ACP shortcut unchanged. |
| `openSession` | personal `mcpServers` carries the app-owned servers (catalog / session SSH) composed for the seat; mixed list contains teammate-bus. Config-reading CLIs still get them from the staged config file. |
| Transcript | personal path unchanged; two mixed ACP members write two files. |
| Cubit | team `seatMemberId` is roster id; attention events use that id. |
| Launcher | ACP `wake` → `sendPrompt`; PTY `wake` → stdin. |
| Idle | cubit idle → `onMemberIdle(real memberId)` without `fromPtyQuietWatch`. |
| Materializer | ACP seat `ensureMemberInputReady` does not wait on a PTY composer. |
| UI | selected ACP member hides terminal toggle; selected PTY member shows it. |
| Regression | existing personal Gemini / Claude / Codex ACP tests stay green. |
| Failure | ACP attach error does not spawn PTY for that member; does not auto fan-out; sibling can still be connected manually. |

## Compatibility with prior ACP specs

- Gemini personal: `docs/superpowers/specs/2026-09-12-acp-gemini-session-design.md` — unchanged. Team roster was out of scope there; this spec fills it for mixed only.
- Claude personal: `docs/superpowers/specs/2026-10-09-claude-acp-session-design.md` — that spec said team never uses ACP. This spec supersedes it for **mixed** seats only. Do not edit the old spec in this phase.
- Codex personal: `docs/superpowers/specs/2026-10-12-codex-acp-session-design.md` — same supersede, no edit.
- Cursor personal (unshipped): `docs/superpowers/specs/2026-10-12-cursor-acp-session-design.md` — not implemented here.
- History document: `docs/superpowers/specs/2026-10-10-acp-history-message-document-design.md` — per-member filename only; v1 snapshot schema unchanged.
