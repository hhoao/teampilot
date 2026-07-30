# Android Termux home design

**Date:** 2026-07-31  
**Status:** Approved for planning  
**Problem:** TeamPilot on Android has no local Linux work plane. Today the app always requires an SSH home (`ConnectionMode.ssh` / `androidNeedsSshHome`). That blocks on-device agent sessions, shell, and Git unless a remote host is available. Roxum IDE’s “built-in Termux” pattern shows a practical backend: treat Termux’s OpenSSH (`localhost:8022`) as the on-device Linux machine via `dartssh2`, without embedding Termux in the APK.

**Builds on:**  
[2026-07-30-work-target-literal-local-design.md](./2026-07-30-work-target-literal-local-design.md),  
[2026-07-30-default-workspace-ssh-path-design.md](./2026-07-30-default-workspace-ssh-path-design.md),  
[2026-07-29-android-ssh-startup-list-design.md](./2026-07-29-android-ssh-startup-list-design.md),  
device-local control plane for SSH profiles / `targets.json`.

## Goal

On Android, make **Termux a first-class work home** peer to remote SSH: one home = one machine for file tree, Git, workspace shell, and CLI agent sessions. Cold start offers Termux **or** remote SSH; neither is mandatory if the other is connected.

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Product role | Peer home/backend (files + shell + agents), not shell-only or agent-only |
| Cold start | Termux and remote SSH are peer options; UI may soft-recommend Termux for on-device |
| Modeling | First-class `RuntimeKind.termux` / id `termux:default`; transport reuses loopback SSH/SFTP |
| Default workspace path | `$HOME/TeamPilot` on the Termux host; `termux-setup-storage` in setup; optional later migrate to shared storage |
| CLI install | Detect + one-click / copy-command install via CLI registry; no silent full install on Connect |
| Placement | `termux:` is a real target id; v1 UI only sells Termux-as-home (no cross-home mix) |
| Integration style | Thin Termux home adapter over existing SSH stack (not bundled Linux userspace; not a tagged ordinary SSH profile) |

## Invariants

1. **One home = one machine.** When home is `termux:…`, workspace folders, session launch, workspace shell, and Git for that home work plane resolve to the Termux RuntimeContext — never device-native `File.existsSync` / local PTY for CLI binaries on that plane.
2. **`local` stays device-native only.** `WorkTargetCanonicalizer` treats home=`termux:` like SSH/WSL: bare `local` canonicalizes to `termux:default`.
3. **Control plane stays device-local.** SSH profile catalog, Termux key material / connection config, and home selection must not ride `AppStorage` home after Termux Connect (same failure mode already fixed for remote SSH).
4. **Product vs transport.** FS may be `SftpFilesystem` so `StorageBackendMode` reports `ssh`; UI and policy branch on `target.kind == termux`, not by inventing a third storage mode in v1.
5. **Termux remains a separate app.** TeamPilot owns keys, guided setup, connection pool, and home bind — not Termux’s process lifecycle.

## Design

### 1. Architecture and core model

```text
RuntimeKind: local | wsl | ssh | termux
RuntimeTarget id: termux:default   (v1 singleton)

HomeTargetController.select('termux:default')
  → RuntimeContextResolver(kind: termux)
  → SSH to 127.0.0.1:8022 (device-local key)
  → SftpFilesystem + RuntimeLayout (POSIX app-data on Termux)
  → SshPtyTransport for sessions / workspace shell
```

| Piece | Behavior |
|-------|----------|
| `RuntimeKind.termux` | New enum value; `runtimeKindOfId` recognizes `termux:` prefix |
| `RuntimeTarget.termux()` | Factory + registry entry; Android-only in pickers |
| Resolver | Loopback SSH client (default host `127.0.0.1`, port `8022`); reuse remote path / app-data resolution patterns used for SSH homes |
| `StorageBackendMode` | Remains `ssh` when FS is SFTP; prefer `target.kind` for Termux-specific UX |
| PTY | Reuse `SshPtyTransport` |
| Work targets | `defaultFolderTargetId(termux home) == 'termux:default'`; resolve bare `local` → home |
| v1 placement UI | Do not expose pinning folders/members to Termux while home is remote (id space reserved) |

**Out of this section:** embedding Linux; disguising Termux as a normal `ssh:` profile; restoring Android device-native work PTY.

### 2. Cold start / StartupGate / setup UX

**Gate predicate (Android):** allow main shell when either:

- home is already bound to `termux:…` (persisted after a successful first-time setup Connect / `select('termux:default')`) — **connection liveness is not part of the gate**; or  
- home is `ssh:…` with existing Connect semantics (unchanged peer path).

Otherwise show a **work environment chooser** (not SSH-list-only):

**Gate vs connection:** StartupGate only answers “has the user chosen and bound a work home?” Once `termux:default` is the persisted home, a down sshd must **not** return the user to the chooser. Disconnected / reconnect-failed states are handled in-shell (banner, blocked launch) per §3.

1. **On-device · Termux** → Termux setup / Connect flow  
2. **Remote · SSH** → existing `SshProfilesPage` → Connect → `select('ssh:$id')`

`requiresSshProfileSetup` applies only when the user is on the remote path and has no profiles. Lack of SSH profiles must not block users who choose Termux.

**Termux setup flow (guided, Roxum-like):**

1. Install Termux (links only: Play / F-Droid / GitHub — no bundled APK)  
2. Generate device-local ed25519 under native app data (e.g. `<nativeAppData>/.termux/ssh/`)  
3. Copyable steps: `pkg install openssh` → authorize pubkey → `termux-setup-storage` → start `sshd` → `whoami`  
4. Persist username + fixed loopback endpoint  
5. Connect → `HomeTargetController.select('termux:default')` → seed Default workspace → clear gate  

Top-bar selector upgrades from SSH-only to **work environment** (Termux + SSH profiles). Users may switch homes later like desktop WSL/SSH.

### 3. Connection lifecycle

`TermuxConnection` (config + runtime) states: unconfigured → configured disconnected → connected → degraded.

| Event | Behavior |
|-------|----------|
| Connect OK | Open/reuse SSH pool; bind home; resolve `$HOME` / app-data |
| Cold start, last home Termux | Auto-reconnect; on failure **keep home** and enter main shell with disconnected banner (gate already satisfied by persisted home — see §2) |
| Mid-session sshd down | Mark disconnected; existing SSH PTY failure path; non-blocking banner + Reconnect; optional deep-link / copy `sshd` |
| Disconnect | Tear down pool; keep keys/username; home may stay `termux:` |
| Clear setup | Remove config/keys; if home was Termux → return to environment chooser |

Session launch / shell / Git / SFTP require connected Termux. After reconnect, do **not** auto-resume sessions blindly (align with remote SSH). Home switches rebind RuntimeContext like today’s SSH home switch — no merged workspace catalogs across homes.

Health checks: short TCP + auth on Connect/Reconnect/explicit check; no aggressive background polling; no TeamPilot-owned background start of Termux/sshd.

### 4. Paths, shared storage, CLI

**Paths**

- Default workspace: `$HOME/TeamPilot` via home filesystem (`DefaultWorkspaceService` treats `termux` like ssh/wsl).  
- Folder `targetId`: `termux:default`.  
- App data / sessions / cli-defaults: on Termux teampilot root (same layout shape as SSH home).  
- Control plane: device-local only.

**Shared storage**

- Setup still runs `termux-setup-storage`.  
- Default folder stays private `$HOME/TeamPilot`.  
- Settings: optional migrate Default (or chosen folder) to e.g. `~/storage/shared/TeamPilot`, updating folder path; best-effort move with rollback of path on failure.  
- If storage not set up, migration shows the missing step instead of half-writing.

**CLI**

- Discover executables on the Termux RuntimeContext (remote/`which` paths) — never device-native existence checks for that plane.  
- Install via registry installer capabilities: one-click or copy official command; run in Termux login-shell environment.  
- Connect does not silently install all CLIs; onboarding/landing may surface missing tools.  
- New CLIs extend registry installers only.

### 5. Error handling

| Failure | User-facing recovery |
|---------|----------------------|
| Termux not installed | Install links; do not claim connected |
| Port 8022 refused | “Start sshd in Termux” + copyable `sshd` + retry |
| Auth failure | Re-run authorized_keys or reset key; keep username |
| Bad username | Validate `u0_a…`-style; point to `whoami` |
| SFTP/PTY drop | Banner + Reconnect; no silent session resume |
| CLI missing | One-click / copy install, not phone-local path errors |
| Migrate without storage | Complete `termux-setup-storage` first |

User errors → l10n; diagnostics → `AppLogger`.

## Testing

Prefer unit/widget tests with mocks; do not require a physical Termux for CI.

- `RuntimeKind.termux` / id parsing / `RuntimeTarget.termux()`  
- `WorkTargetCanonicalizer` with termux home  
- `DefaultWorkspaceService` seeds `$HOME/TeamPilot` + `termux:default`  
- StartupGate: chooser when unbound; pass for persisted termux home (even if reconnect mocked as failed) or ssh home; Termux path not blocked by empty SSH catalog  
- Connect helper selects `termux:default` only on success  
- Disconnect / Clear setup: disconnect keeps home; clear setup returns to chooser when home was Termux  
- Resolver builds SFTP context for termux (mocked); CLI validation skips native `File.existsSync` for that target  
- Regression: Android SSH Connect home + device-local control plane unchanged  

Manual / device: install Termux → setup → Connect → open Default → launch one CLI after install/detect.

## Success criteria

1. Android can cold-start with **only** Termux (no remote profile) into the main shell and Default workspace at Termux `$HOME/TeamPilot`.  
2. Under Termux home, at least one supported CLI session can start after detect or one-click install.  
3. Remote SSH home remains a peer path with today’s behavior.  
4. Control plane (SSH catalog, Termux keys, home selection) stays device-local across Termux Connect.  
5. After Termux home is persisted, disconnect / failed reconnect shows recoverable in-shell UI and does **not** re-open the work-environment chooser (StartupGate thrash).

## Non-goals (v1)

- Bundling/embedding Termux or a full Linux userspace  
- Cross-home mix UI (remote home + pin work to Termux)  
- Automatically starting Termux/sshd in the background  
- Silent full CLI install on Connect  
- Default workspace on shared storage  
- iOS  
- Adding `StorageBackendMode.termux` (use `target.kind` instead)

## Reference: Roxum pattern

Roxum does not embed Termux. It generates keys, guides OpenSSH + `authorized_keys` + `termux-setup-storage`, and connects with `dartssh2` to `ssh://<u0_a…>@localhost:8022`. TeamPilot adopts that transport UX but maps it onto RuntimeTarget / home / WorkTarget / device-local control plane instead of a one-off editor backend flag.
