# SSH plane close policy + storage-only home banner

**Date:** 2026-08-03  
**Status:** Approved (chat)  
**Scope:** Separate durable SSH **work-home** (storage pool) health from per-seat **member** PTY planes so session switch / intentional member teardown no longer false-alarms Android “远程 SSH 工作环境已断开”.

## Problem

Android home is an SSH profile. Switching chat sessions closes the previous seat’s `SshMemberSession` with `SshTransportCloseReason.memberSessionClosed`.

Today `SshProfileConnectionCoordinator._onTransportClosed` treats **every** transport close as profile-down (`markDown` + coalesce reconnect). `SshHomeDisconnectedBanner` shows whenever host UI status is not `connected` (including `reconnecting`).

Result: normal session switch flashes “work home disconnected” even when the storage pool is still live.

## Goals

- Intentional member-plane closes do **not** mark durable home down or schedule storage reconnect.
- True network blips that drop storage (and often member) still coalesce into one disconnect/reconnect wave.
- Home-disconnected banner / reconnect CTA reflect **storage pool presence only**.
- Close handling is driven by an explicit, unit-tested policy table (extensible for future planes such as ephemeral exec).

## Non-goals

- Changing MaxSessions / pooling topology beyond close policy.
- Auto-reconnecting individual member PTYs without storage recovery (existing `sessionReconnectSignals` after durable recover stays).
- Termux-specific banner (separate widget); same storage-plane principle may apply later.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Architecture | Explicit `SshTransportClosePolicy` + coordinator consumes it; banner/cubit storage-only |
| Durable truth | `SshClientFactory.hasLiveStorageClient(profileId)` |
| Member intentional close | No `markDown`, no storage reconnect schedule |
| Member unexpected close (`remotePeerClosed` / `transportError`) | Still affects durable home (coalesce with storage blips) |
| Expected local storage closes (`userDisconnect`, invalidate, …) | `markDown`; reconnect suppressed by existing latch / skip rules |
| Banner | Visible only when home is SSH **and** storage pool is not live; connecting may disable button |
| Cubit `reconnecting` | Only when storage is **not** live and monitor/reconnect is in flight |

## Design

### 1. `SshTransportClosePolicy`

Pure function over `SshTransportClosed` (and optionally raw errors mapped into that shape):

```dart
class SshTransportCloseDecision {
  final bool affectsDurableHome;      // markDown + enqueue storage reconnect wave
  final bool emitDisconnectNotification;
  final bool scheduleStorageReconnect; // false when latch / non-retryable / expected local
}
```

Policy matrix:

| Input | `affectsDurableHome` | Notes |
|-------|----------------------|-------|
| `plane=member` + `memberSessionClosed` | false | Session switch / seat dispose |
| `plane=member` + other `isExpectedLocalSshTransportClose` | false | Defensive |
| `plane=member` + `remotePeerClosed` / `transportError` | true | Network blip |
| `plane=storage` + expected local (userDisconnect, …) | true markDown; reconnect via latch rules | Existing behavior |
| `plane=storage` + unexpected | true | Durable home down |

Keepalive failures remain storage-path only (unchanged).

### 2. Coordinator

`_onTransportClosed(profileId, error, stack)`:

1. Normalize to `SshTransportClosed` when possible.
2. Ask policy.
3. If `!affectsDurableHome`: optional info log; return (no coalesce timer for durable wave).
4. Else: existing `_enqueueDisconnect` / reconnect path.

`onDisconnect` logging in `app_shell` already distinguishes expected local closes; policy reduces false waves reaching that path for member intentional closes.

### 3. Cubit + banner

**`SshConnectionCubit._resolveStatus`:**

- If `hasLiveStorageClient` → `connected` (ignore monitor `reconnecting` caused by stale member-only downs; monitor should no longer mark down for those).
- If not live and monitor/`_connectingIds` say reconnecting/connecting → those statuses.
- Else disconnected / last failure.

**`SshHomeDisconnectedBanner`:**

- Still gated on SSH home mode + home `sshProfileId`.
- Show strip iff `!factory.hasLiveStorageClient` **or** (equivalently) cubit status is not `connected` **and** not merely a member-plane ghost — safest: show when status ∈ `{disconnected, error, authFailed}` **or** (`connecting`/`reconnecting` **and** storage not live). After cubit fix, `status != connected` while storage live should not happen; banner may still assert `!live` as defense in depth.

### 4. Tests

Coordinator:

- Close member with `memberSessionClosed` while storage live → monitor stays healthy / not down; no reconnect create; pool still live.
- Unexpected member close → durable wave (markDown); coalesce with storage close still one notification.
- Existing latch / hostkey / coalesce tests remain green.

Cubit:

- After member intentional close signal path, host stays `connected` if pool live.
- Storage close → not connected / reconnecting as today.

Banner widgets:

- Hidden while storage live even if cubit were briefly non-connected (defense) — prefer testing via real cubit+factory after member close.
- Shown when pool absent; reconnect CTA still works.

## File map

| File | Role |
|------|------|
| `client/lib/services/ssh/ssh_transport_close_policy.dart` | New policy |
| `client/test/services/ssh/ssh_transport_close_policy_test.dart` | Matrix unit tests |
| `client/lib/services/ssh/ssh_profile_connection_coordinator.dart` | Consume policy |
| `client/lib/cubits/ssh_connection_cubit.dart` | Storage-live wins over reconnecting |
| `client/lib/widgets/ssh/ssh_home_disconnected_banner.dart` | Storage-live gate |
| Coordinator / cubit / banner tests | Extend coverage |

## Risks

- Unexpected member-only drops without storage drop: policy still marks durable home down so session-plane reconnect can run after storage probe — acceptable; may briefly show banner if storage also dies under MaxSessions pressure (real outage).
- Stale monitors previously marked down by member closes: after fix, new closes won’t; no migration required.

## Related

- `docs/superpowers/specs/2026-07-24-ssh-status-bar-indicator-design.md` — durable truth = storage pool
- `client/lib/services/ssh/ssh_member_session.dart` — `memberSessionClosed`
- `client/lib/widgets/ssh/ssh_home_disconnected_banner.dart`
