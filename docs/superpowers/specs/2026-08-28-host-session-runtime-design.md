# Host Session Runtime — Design

**Date:** 2026-08-28
**Status:** Draft (awaiting review)
**Supersedes:** GUI-owned PTY (`ChatCubit` / `TerminalSession` as session owner), Android spawning CLIs through `SshPtyTransport`, file-poll “sync” between devices, owner/follower takeover.

Related: [SSH QR pairing](2026-08-20-ssh-qr-pairing-design.md) (SSH remains the pipe), [Agent runtime event plane](2026-08-25-agent-runtime-event-plane-design.md) (this process *is* that plane), [Persistent compose drafts](2026-08-25-persistent-compose-drafts-design.md) (drafts move onto the host).

## Problem

TeamPilot already has a single **home / control-plane machine** (`HomeTargetStore`). Workspaces, `session.json`, CLI transcripts, TeamBus mail, and automations live under that machine’s `<teampilotRoot>`.

What it does *not* have is a single **live process** that owns those sessions. Each GUI (desktop local PTY, Android SSH PTY) is its own owner. Consequences:

- A second GUI cannot see Running, cannot share one agent turn, and will spawn a second CLI on the same session runtime.
- Chat “sync” is an accident of reading the same JSONL over SFTP, with no list watch and ~2s poll.
- TeamBus, agent-status, prompt delivery, and automations die when that GUI dies.
- Phone-first vs desktop-first are different bugs instead of one model.

This is not a distributed-data problem. The data is already in one place. The missing piece is a **session control plane** independent of which window is open.

## Decisions (locked)

These are product choices, not backlog items.

1. **One Runtime process per home target.** All GUIs are peer clients. There is no owner/follower and no PTY takeover.
2. **Sessions outlive GUIs.** Closing the last client does not stop CLIs. Stop is an explicit action from any client (and automations).
3. **Any client may submit** into a live seat. `SubmitPrompt` is RPC to the Runtime, never a local `writeToPty`.
4. **Transcripts stay the durable chat truth.** The Runtime tails them and pushes canonical `AiMessage` deltas. Clients do not parse CLI formats and do not poll SFTP for history.
5. **No second chat store, no CRDT, no cloud bubble sync.** SSH (LAN / extra / relay) is the only remote pipe.
6. **No compatibility shims.** GUI does not spawn PTY. Android does not SSH-exec the CLI. `ChatCubit` does not hold `TerminalSession`. Pairing offer carries Runtime reachability; old offers are invalid.
7. **Event plane lives in the Runtime process**, not in a GUI isolate. [Agent runtime event plane](2026-08-25-agent-runtime-event-plane-design.md) is not a parallel design — it is this process’s interior.
8. **File IDE, Git, and workspace folders** keep using the home `Filesystem` (local or SFTP). They are not remoted as a second protocol. Only session/agent control is RPC.

## Goals

1. Phone-first and desktop-first are the same: connect to the home Runtime, see the same workspaces, Running strip, and live chat, send from either.
2. N clients (desktop, Android, later iOS or a headless operator) against one home, without double-spawn.
3. Mixed teams, mailbox, board, agent attention, and prompt-delivery correctness survive GUI restart and device switch.
4. New CLIs remain a Runtime `CliToolDefinition` + capabilities; GUI only renders `AiMessage` and seat chrome.
5. A headless work machine (SSH home with no desktop GUI) is a supported shape: install Runtime there, any GUI is remote.

## Non-goals

- TeamPilot-hosted cloud relay or accounts (self-hosted relay from pairing stays).
- Attaching to an orphan TTY after Runtime crash (resume the CLI with native ids; do not depend on tmux).
- Syncing two different home targets into one UI (one home at a time, as today).
- Replacing OpenSSH; replacing CLI transcript formats.
- Shipping an iOS client in this work (protocol must not block it).

## Product shape

```
Desktop GUI ── loopback ──┐
Android GUI ── SSH LocalForward to loopback ─┤
Future GUI  ── same ─────────────────────────┘
                                             ▼
                               teampilot-runtime  (home target)
                                 PTY broker, launch, TeamBus,
                                 event plane, history tailer,
                                 automations
                                             ▼
                               CLI processes on that machine
                               (and SSH-placed member machines
                                still launched *by* this Runtime)
```

The **home target** is the machine that already owns `<teampilotRoot>`. Runtime always runs there:

| Home | Where Runtime runs | How the GUI reaches it |
|------|--------------------|------------------------|
| Desktop local | Same OS user | Unix socket / named pipe |
| WSL | Inside the distro | Desktop GUI talks to the WSL loopback Runtime |
| SSH (Android, or desktop remote home) | Remote host | SSH LocalForward → `127.0.0.1` Runtime |
| Termux-as-home | The phone | Local socket on device (no cross-desktop sync unless that phone *is* the home) |

Cross-device sync **is** “several GUIs bound to the same home”, not a special mobile feature.

## Components

### `teampilot-runtime`

A headless entry of the same Dart package (`teampilot --runtime`), not a second language. It loads `AppPaths` / `AppStorage` for the home root and owns:

| Unit | Responsibility |
|------|----------------|
| `RuntimeListener` | Loopback socket; device auth; multiplexed WS/JSON sessions. |
| `RuntimeSessionDirectory` | Workspace/session catalog; push upsert/delete. |
| `PtyBroker` | One master PTY per seat; spawn via existing launch pipeline; stdin inject; optional output subscribe. |
| `HistoryPublisher` | Locate + incremental tail via `AiHistoryCapability`; emit `AiMessage` deltas + page cursors. |
| `AgentEventGateway` | Existing event-plane HTTP ingress, now in-process here. |
| `PromptDeliveryCoordinator` | Sole writer of automated user input (event-plane spec). |
| `TabTeamBusCoordinator` equivalent | One TeamBus per mixed session; MCP gateway loopback. |
| `AutomationScheduler` | Lives here so rules fire with no GUI. |
| `RuntimeSupervisor` | User-service install, pid file, crash restart, orphan CLI reconciliation. |

It does **not** own: SSH profile catalog on the phone, window layout, or the Connect QR widget. It **does** own host-side Connect (sshd probe, `authorized_keys`, relay client, pairing HTTP) so pairing is host infrastructure. Desktop GUI is only the QR / policy surface talking to local Runtime.

### GUI (`teampilot`)

Flutter workbench. On startup:

1. Resolve home target (unchanged).
2. `RuntimeSupervisor.ensure` (local spawn or SSH `systemctl --user start` / exec advertised `runtimeCommand`).
3. Open `RuntimeClient` (local socket or SSH tunnel).
4. Bind `AppStorage` home as today for files/Git/IDE.
5. Drive chat/sidebar from `RuntimeClient` projections, not from a local PTY registry.

`ChatCubit` becomes a projection + command sender: open tab, select member, submit, stop, pin, rename. It must not import `TerminalSession`.

Android Connect: pairing still produces an `SshProfile` and binds home to the host `appDataRoot`. After SSH is up, the phone **only** forwards to Runtime. It must not call `SessionLaunchService` against `SshPtyTransport`.

### Pairing offer (breaking)

Extend the pairing JSON (new `v`, old `v: 1` rejected):

```json
{
  "v": 2,
  "hostId": "…",
  "username": "alice",
  "appDataRoot": "/home/alice/.local/share/com.hhoa.teampilot",
  "runtime": {
    "port": 43100,
    "socketName": "teampilot-runtime",
    "command": "/usr/bin/teampilot --runtime"
  },
  "endpoints": []
}
```

`runtime.port` is the loopback port the SSH forward targets (or a Unix socket path forwarded with `StreamLocal`). The phone never exposes that port on a public interface.

## Protocol

JSON messages, length-prefixed, over a single multiplexed connection. `protocolVersion = 1`. Unknown methods/events are errors, not ignored (clients and Runtime ship together from this cut).

### Auth

Runtime binds `127.0.0.1` (and WSL equivalent) only. Network attackers need a local foothold.

- Local GUI: same uid + a runtime-local token file under `<teampilotRoot>/runtime/auth`.
- Remote GUI: SSH authentication is the gate; after tunnel, the same token file is readable via the home filesystem, or pairing writes a `runtimeGrant` next to `relayGrant` in `SshCredentialStore`. Prefer the token file on the home root so all clients share one secret rotated by Runtime.

Reject connections that cannot present the current token.

### RPCs (commands)

| Method | Role |
|--------|------|
| `hello` | Version, client id, device label. |
| `watchCatalog` | Stream workspace + session list. |
| `watchSession` | History pages + live deltas + seat presence + attention. |
| `createSession` / `deleteSession` / `patchSession` | Catalog mutations. |
| `startSeats` / `stopSession` / `stopSeat` | PTY lifecycle. Explicit stop. |
| `submitPrompt` | Body + member + attachments; returns `deliveryId`. |
| `interruptSeat` / `answerQuestion` / `exitPlan` | Existing chrome, now RPC. |
| `subscribePty` | Optional raw output for the terminal pane. |
| `putDraft` / `clearDraft` | Host-persisted compose draft for a seat. |

Idempotency: `submitPrompt` carries a client `deliveryId`. Runtime dedupes. This is the same id the event-plane coordinator already requires.

### Events (push)

| Event | Role |
|-------|------|
| `catalog.upsert` / `catalog.delete` | Session/workspace rows. |
| `seat.presence` | `idle` / `working` / `waiting` / `stopped`, last heartbeat. |
| `history.snapshot` | Latest page + cursor (on `watchSession`). |
| `history.append` | Identity-preserving `AiMessage` add/merge (streaming assistant uses stable id). |
| `history.rewrite` | Compaction / invalidate tailer; client replaces from snapshot. |
| `history.page` | Older page response. |
| `delivery.updated` | Prompt delivery state machine. |
| `bus.mail` / `bus.task` / `bus.presence` | TeamBus projections. |
| `draft.updated` | LWW draft from any client. |
| `client.viewing` | Which devices have the session open (UX: “also on Pixel”). |

Subscribe with an opaque `resumeToken`. On reconnect: snapshot then replay. Clients must tolerate duplicate appends by message id.

## Data flow

### Session list

Runtime watches `<teampilotRoot>/workspace/…` (inotify locally). Every connected GUI receives catalog events. The sidebar never “hydrate once and freeze”. Running membership is `seat.presence != stopped` for any seat, not in-memory GUI tabs.

### Chat

```
CLI writes transcript
  → HistoryPublisher tail (existing incremental readers, in Runtime)
  → history.append (AiMessage)
  → all watchSession subscribers render
```

Paging older messages is RPC `readOlder` using the same CLI page readers, executed in Runtime, returned as `AiMessage` lists. Subagent attachments inflate in Runtime on demand (`inflateAttachment`).

GUI `AiHistorySeat` becomes a thin buffer over these events. `AiHistoryLiveRefreshController` and SFTP poll are deleted.

### Submit

```
GUI compose
  → submitPrompt
  → PromptDeliveryCoordinator
  → PtyBroker.write
  → CLI
  → transcript + hooks
  → history.append + delivery.updated
```

Two GUIs submitting on the same seat serialize in the coordinator (existing at-most-one unconfirmed delivery per seat). The other GUI sees the user bubble from `history.append`, not from optimistic local insert. Failed delivery keeps the host draft (see Drafts).

### Raw terminal

Optional. `subscribePty` streams bytes for flutter_alacritty. Resize is RPC. If nobody subscribes, the broker still runs the PTY (headless). History does not depend on this stream.

## Drafts and presence

Host path: `sessions/{sessionId}/drafts/{memberId}.json` with `{ text, rev, clientId, updatedAt }`.

- `putDraft` is last-write-wins by `rev` (client increments from last seen; Runtime rejects stale rev).
- Successful `submitPrompt` clears that seat draft.
- Landing (new chat) drafts stay workspace-scoped on the host: `workspace/workspaces/{id}/drafts/landing.json`.

Device-local-only draft cache is removed. Opening the same session on phone and desktop shows the same unsent text.

`client.viewing` is ephemeral (not durable). Used for chrome only.

## Lifecycle

### Install and start

First successful desktop home boot installs a user service (`systemd --user`, launchd, Windows logon task) that starts Runtime and restarts on crash. Pid + auth token under `<teampilotRoot>/runtime/`.

If the GUI finds no listener: start the service, wait, connect. Android: SSH exec `runtime.command` from the offer, then LocalForward.

### Last client disconnects

Runtime stays up. Seats keep their PTYs. Automations keep firing. The next GUI catch-up is snapshot + live events.

### Explicit stop

`stopSession` tears down PTYs, writes `stopped` presence, leaves `session.json` and transcripts. Resume later is `startSeats` with existing native ids (existing lifecycle resume paths, now only inside Runtime).

### Runtime crash

1. Supervisor restarts Runtime.
2. Reconcile: for each session with a recorded start, probe pid / native resume; seats that cannot be reattached go `interrupted` (visible on every GUI). No automatic re-paste (event-plane rule).
3. Clients reconnect, snapshot, continue.

Do not wrap CLIs in tmux. Resume is CLI `--resume` / pinned transcript, already modeled in `SessionLifecycleService`.

### Home switch

Switching `HomeTargetStore` disconnects `RuntimeClient`, binds files to the new home, ensures that home’s Runtime, watches its catalog. Two homes never share a Runtime.

## GUI mapping (replacement)

| Today | After |
|-------|--------|
| `TerminalSession.connect` in the GUI | `startSeats` / implicit start on first `submitPrompt` if policy says so |
| `openExistingSessionStartsTerminal` | Deleted. Opening a session is always `watchSession`. Start is explicit or first send. |
| History review vs live PTY as two modes | One session view: messages from Runtime; terminal pane is an optional subscriber |
| `AiHistoryLoader` in GUI | `HistoryPublisher` in Runtime |
| `TeammateBusMcpGateway` in GUI | Same class, Runtime process |
| `AutomationScheduler` in GUI | Runtime |
| Android `SshPtyTransport` for agents | SSH only for filesystem + Runtime tunnel |
| Sidebar running = local open tabs | Sidebar running = `seat.presence` |

Workbench files, editor, Git stay on `AppStorage` / `GitRepoStore` against the home `Filesystem`.

## Error handling

| Condition | Behavior |
|-----------|----------|
| Runtime down, GUI up | Blocking reconnect with start-service CTA; no local PTY fallback. |
| SSH drop (phone) | GUI reconnects tunnel; Runtime and CLIs unaffected. Chat resumes via `resumeToken` / snapshot. |
| Submit while seat `stopped` | Runtime starts seats then delivers, or rejects if the user had explicitly stopped and policy is “don’t auto-start” — **decision: first send auto-starts; explicit Stop stays stopped until the user starts or sends.** |
| Stale draft rev | GUI reloads host draft and does not clobber. |
| Protocol version mismatch | Fail hello; tell the user to update that client. |
| Duplicate GUI submit ids | Second is a no-op; first delivery stands. |
| Member on another machine (placement) | Runtime, not the phone, opens that SSH PTY. Phone never holds member transports. |

User-visible errors go through l10n; Runtime logs diagnostics with `AppLogger`.

## Extensibility

- **New GUI platform:** implement `RuntimeClient` + workbench. No launch stack.
- **New CLI:** Runtime registry only; history events remain `AiMessage`.
- **Headless operator / CI:** `teampilot --runtime` on a lab box; GUIs pair as SSH homes.
- **Official Connect:** still a relay byte-pipe to sshd; Runtime stays on loopback behind SSH.
- **More seats / mixed teams:** already session-scoped in Runtime; clients subscribe per session.

## Testing

Constructor-inject listener, filesystem, PTY broker, and clocks. No real sshd in unit tests.

Required:

1. Two `RuntimeClient` fakes watch one catalog; create on A appears on B without reload.
2. Start seat on A; B’s Running strip includes it; stop on B; A shows stopped.
3. Streamed assistant: append events merge on both clients with one message id.
4. Concurrent `submitPrompt` on one seat: coordinator serializes; at most one unconfirmed delivery.
5. Last client disconnect: broker still has PTY; reconnect snapshot includes new transcript lines.
6. Runtime restart: `submittedUnknown` restored; no automatic re-paste (event-plane cases 4–5).
7. Android path: client with only a tunnel factory never calls a PTY transport.
8. Draft LWW: stale rev rejected; other client sees `draft.updated`.
9. History rewrite event forces snapshot replace, not a corrupt tail merge.
10. Member placement SSH is opened by Runtime test doubles, not by the GUI client.

Widget/cubit tests: `ChatCubit` with a fake `RuntimeClient` has no `TerminalSession`.

## File map (target)

| Path | Role |
|------|------|
| `client/bin/teampilot_runtime.dart` (or `--runtime` in `main.dart`) | Headless entry. |
| `client/lib/services/runtime/` | Listener, auth token, supervisor, protocol codec, `RuntimeClient`. |
| `client/lib/services/runtime/history_publisher.dart` | Tail + `AiMessage` events. |
| Move into Runtime process | `session_lifecycle_service.dart`, `session_launch_service.dart` internals, `terminal_session.dart`, TeamBus gateway, `automation_scheduler.dart`, event-plane gateway. |
| `client/lib/cubits/chat_cubit.dart` | Projection + commands only. |
| `client/lib/pages/connect/` | QR talks to Runtime host-side Connect. |
| Pairing codec | `v: 2` + `runtime` object. |

Exact class splits stay under existing file-size limits; launch pipeline stays capability-based (no `if (cli == …)` in the protocol layer).

## Acceptance

A user starts a session on Android, puts the phone down, opens desktop TeamPilot on the same home, sees that session in Running, watches the current turn stream, types the next prompt, and the same CLI turn continues. They close the desktop app; the phone still sees the agent working. Stop from either device ends the PTYs. A third client added later is the same `RuntimeClient`, not a new sync mechanism.

## Spec self-review

- No TBD in behavior: last-client, first-send auto-start vs explicit stop, draft LWW, crash resume, pairing `v: 2` are decided.
- Event plane and this spec share one process; GUI is not a second owner of prompt delivery.
- Files/Git remain on home filesystem so IDE does not become an RPC rewrite.
- Scope is one control plane, not cloud sync; implementation can still be sliced (listener + catalog first, then PTY, then history push) without changing these contracts.
