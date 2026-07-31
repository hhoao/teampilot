# Android SSH home disconnect soft-fail design

**Date:** 2026-07-31  
**Status:** Approved for planning  
**Problem:** On Android, when the persisted home is remote `ssh:…` and that host is unreachable at cold start, `ensureHome` / `_resolveSsh` throws. `TeamPilotBootstrap` shows a hard error page. The only fallback button is Windows WSL → native storage. The user cannot retry, switch to Termux, pick another SSH profile, or return to the work-environment chooser — the app is stuck. Termux home already soft-fails with path cache + in-shell banner; remote SSH does not.

**Builds on:**  
[2026-07-31-android-termux-home-design.md](./2026-07-31-android-termux-home-design.md) (disconnected strategy, gate vs liveness),  
[2026-07-29-android-ssh-startup-list-design.md](./2026-07-29-android-ssh-startup-list-design.md) (Connect → bind home).

## Goal

Treat **remote SSH home disconnect** like Termux: once home is bound, connection liveness must not block entry to the main shell. Soft-fail with cached remote paths, show a recoverable banner (reconnect), keep the work-environment selector available, and keep a bootstrap safety net only when soft-fail is impossible (no cache).

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Soft-fail vs hard gate | Soft-fail into main shell when path cache exists; never auto-fall home to `local` on connect failure |
| Path cache storage | Persist `lastHome` + `lastAppDataRoot` on the **device-local** SSH profile record (same fields/shape as `TermuxConfig`) |
| Connection UI truth | Reuse `SshConnectionCubit` / storage-pool status; do **not** invent a second SSH connection cubit |
| Banner | Non-blocking strip when home is `ssh:…` and the home profile is not connected; Reconnect + rely on existing work-environment selector for switch |
| Bootstrap safety net | If resolve still hard-fails (no usable cache), Android error page: **Retry** + **Choose work environment** (persist `local` home → rebuild → StartupGate chooser) |
| Desktop | Unchanged (no Android-only escape required; WSL fallback stays as today) |
| Profile connection change | Existing `HomeSshProfileImpact.homeConnectionChanged` reinstall path remains; stale cache is overwritten on next successful resolve |

## Invariants

1. **Bind ≠ liveness.** StartupGate only answers “is Android home bound to Termux or SSH?” A down remote host must not re-open the chooser or trap bootstrap forever when cache exists.
2. **Never silent unbind.** Connect / resolve failure must not call `select(local)` automatically. Unbind only via explicit user action (chooser / clear / safety-net button).
3. **Control plane stays device-local.** Path cache lives on the SSH profile catalog (device-local), not under remote `AppStorage` home.
4. **One reconnect path.** Banner Reconnect and profile Connect both go through `SshConnectionCubit.connect` / coordinator `userConnect` (same pool as today).
5. **Parity with Termux soft-fail.** Cached-path `RuntimeContext` uses lazy SFTP (`RemoteFileStore`); first I/O may fail until reconnect. Index bootstrap already soft-fails remote reads — keep that.

## Design

### 1. Path cache on SSH profiles

Extend device-local `SshProfile` (or an adjacent optional side-fields map if schema hygiene prefers) with:

- `lastHome: String?`
- `lastAppDataRoot: String?`

| Event | Behavior |
|-------|----------|
| Successful `_resolveSsh` / path resolve | Persist both fields on that profile |
| Soft-fail cold start | Read cache for home profile id; build context without eager `pathResolver.resolve` / `sftpFor` |
| Successful reconnect / reinstall | Refresh cache from live resolve |
| Profile deleted / missing | Existing `homeProfileMissing` → switch home (unchanged) |

Generalize resolver flag naming if needed: Termux’s `termuxPathsFromCache` may become a shared `pathsFromCache` (or keep Termux-specific flag and add `sshPathsFromCache` — prefer **one** `pathsFromCache` on `RuntimeContext` to avoid parallel bools). Soft-fail applies to **remote SSH kind** the same way Termux already does for termux kind.

### 2. Resolver / ensureHome

```text
_resolveSsh(profile):
  try live path resolve + sftp warm
  on failure:
    if lastHome + lastAppDataRoot usable → RuntimeContext(cache, pathsFromCache: true)
    else rethrow
```

Registry / shell: after successful live resolve for SSH home, write cache back to the profile store (mirror Termux `lastHome` persistence in `app_shell` / cubit after Connect).

Cold start with SSH home + dead host + cache → `ensureHome` succeeds → shell builds → index soft-fail → main UI.

### 3. In-shell disconnected UX

When `ConnectionModeService.isSshMode` and the home profile’s `SshConnectionCubit` status is not `connected` (and not mid-connecting, or show connecting state on the button):

- Show **`SshHomeDisconnectedBanner`** (peer of `TermuxDisconnectedBanner`) in the same shell slot.
- Message: remote work home unreachable (l10n).
- Primary action: **Reconnect** → `SshConnectionCubit.connect(homeProfileId)`.
- Switching home: existing `AndroidWorkEnvironmentSelector` (Termux / other SSH / manage profiles). No second “switch” control required on the banner unless space is trivial — selector is the authority.

Optional cold-start: once shell is up, attempt one reconnect for the home profile (align with TermuxCubit reconnect-after-provide). Failure leaves banner visible.

Session launch / shell / Git already fail or gate when transport is down; do not auto-resume sessions after reconnect.

### 4. Bootstrap hard-fail safety net

Only when soft-fail cannot run (no cache, or non-recoverable install error before UI):

`TeamPilotBootstrap` error page on **Android** (and any platform where home kind is `ssh` if desired — **ship Android first**):

| Action | Behavior |
|--------|----------|
| Retry | Re-run `_start()` without changing home |
| Choose work environment | `HomeTargetStore.save(local)` → `_start()` → unbound → `StartupGate` chooser |

Windows WSL → native storage button remains as today (`_canFallbackToNativeStorage`).

Do **not** rely on this page as the primary disconnect UX once cache exists.

### 5. Error handling matrix

| Failure | User-facing recovery |
|---------|----------------------|
| Cold start, SSH down, cache hit | Enter shell + banner + Reconnect / selector |
| Cold start, SSH down, no cache | Error page: Retry + Choose work environment |
| Mid-session drop | Existing pool/coordinator + banner; selector available |
| Auth / host key failure | Cubit `authFailed` / `error` detail; Reconnect after user fixes profile |
| Switch to another SSH while down | Existing `HomeTargetController.select`; live resolve or soft-fail for target profile cache |

User errors → l10n; diagnostics → `AppLogger`.

## Testing

Prefer unit/widget tests with mocks; no live remote host required in CI.

- Resolver: SSH kind + failing live resolve + cache → context with `pathsFromCache`; without cache → throws  
- Profile persistence: successful resolve writes `lastHome` / `lastAppDataRoot`  
- Banner: visible when SSH home + not connected; Reconnect invokes cubit connect  
- Bootstrap error UI (widget or extracted helper): Android SSH hard-fail exposes Retry + Choose work environment; choosing environment persists `local`  
- Regression: Termux soft-fail / banner / clear-setup → chooser unchanged  
- Regression: Connect success still binds `ssh:$id` and clears StartupGate  

## Success criteria

1. After at least one successful SSH home resolve, killing the remote host and cold-starting Android enters the main shell (not a dead-end error page).  
2. User can Reconnect from the banner or switch Termux / another SSH via the work-environment selector.  
3. First-time / no-cache hard failure still offers Choose work environment so the user is never stuck without an exit.  
4. Termux disconnect soft-fail and device-local control plane remain unchanged.  
5. Desktop WSL fallback behavior unchanged.

## Non-goals (v1)

- Soft-fail without any prior successful path resolve (impossible without inventing paths)  
- Auto-falling home to `local` on every disconnect  
- Aggressive background SSH health polling  
- iOS-specific UX  
- Changing desktop SSH optional-home semantics beyond shared resolver cache helpers if reused

## Out of scope follow-ups

- Richer mid-switch progress UI when `HomeTargetController.select('ssh:…')` is in flight  
- Unifying Termux + SSH banners into one “remote home disconnected” widget (nice-to-have after parity ships)
