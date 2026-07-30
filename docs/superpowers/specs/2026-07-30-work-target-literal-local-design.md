# Work target literal `local` design

**Date:** 2026-07-30  
**Status:** Approved for planning  
**Problem:** On Android (SSH home), workspace folders default to `targetId=local`. Remote CLI discovery finds `/root/.local/bin/claude` on the SSH host and stores it in preferences, but session launch treats `local` as device-native PTY and runs `File.existsSync` on the phone → `claude executable not found`. Desktop remote workspaces work because folders use `ssh:<profileId>`.

## Goal

Make every work-plane `targetId` mean exactly one machine. `local` means **device-native** FS/PTY only. When home is SSH (Android), folders and launch targets must use `ssh:<profileId>` — never overload `local` as “the home machine.”

No long-lived backward-compat shims. Dirty `local` + SSH-home data is canonicalized at resolve time to `home.id` (one-shot normalize), not kept as an alias API forever.

## Invariants

1. `WorkspaceFolder.targetId == 'local'` **iff** the work plane runs on the device-native filesystem and local PTY.
2. When `home.kind == RuntimeKind.ssh`, agent session launch targets, workspace-folder defaults, and workspace-terminal specs for that home work plane **must not** stay as bare `local` after resolution — they resolve to `home`.
3. Process placement (session CLI, workspace shell, remote CLI readiness, off-home provision) decides transport from the **resolved** `RuntimeTarget.kind`, not from `Platform.isAndroid` guesses.

## Design

### `WorkTargetCanonicalizer` (pure, single choke point)

New module under `client/lib/services/storage/` (or `models/` if kept dependency-free — prefer `services/storage/` next to home/target code):

```dart
abstract final class WorkTargetCanonicalizer {
  /// Default folder target when creating / bootstrapping workspaces.
  /// local home → `local`; ssh home → `home.id`; wsl home → `home.id`.
  static String defaultFolderTargetId(RuntimeTarget home);

  /// Resolve a persisted folder / member target id for execution + FS.
  /// If [targetId] is `local` and [home] is non-local, return [home]
  /// (normalize dirty Android / SSH-home data). Otherwise parse id normally.
  static RuntimeTarget resolve(String targetId, {required RuntimeTarget home});
}
```

Callers must not re-implement “if Android then SSH” for work targets.

### Write path

All places that mint `WorkspaceFolder` with an implicit default must stamp `defaultFolderTargetId(home)`:

- Home / create workspace dialogs (`_targetId` initial value)
- `DefaultWorkspaceService.ensureDefault`
- `WorkspaceCreateDirectoryPicker` / folders editors when adding a row without an explicit picker value (initial selection = home default)
- Ad-hoc `WorkspaceFolder(path: …)` in session launch helpers — pass the session’s resolved folder target or home default, never bare `local` on SSH home

Persist honest `ssh:…` ids on Android going forward.

### Read / launch path

| Call site | Change |
|-----------|--------|
| `SessionLifecycleService._runtimeTargetFromId` / `launchWorkTarget` | Resolve via `WorkTargetCanonicalizer.resolve(..., home: homeTarget)` |
| `ChatSessionShellFactory` / `_shellForLaunch` | Receives already-resolved SSH target → `validateLaunch: false`, remote transport |
| `defaultSessionSpecFor` | Needs `home` (or pre-resolved target id); SSH-home “local” folders → `WorkspaceTerminalWorkspaceTargetSpec(home.id)`, **not** `WorkspaceTerminalLocalSpec` |
| `WorkspaceShellConnector` | Specs that resolve to SSH open SSH PTY (already true for `WorkspaceTerminalWorkspaceTargetSpec`) |
| `WorkspaceProvisionCoordinator.isOffHome` | Compare resolved member target id to home id (SSH home + on-home folder → not off-home) |
| `remote_cli_requirements` / readiness | Use resolved targets so SSH-home workplanes are treated as remote |

Wire `homeTarget` into `SessionLifecycleService` (callback or injected `RuntimeTarget Function()`) so launch resolution does not depend on a stale snapshot.

### Converge Android storage special-case

Today `RuntimeContextResolver` uses `Platform.isAndroid \|\| target.kind == ssh` so even `local` targets open SFTP. After honest targets:

- Work-plane resolve uses the concrete target kind.
- Home binding remains an SSH `RuntimeTarget` on Android (`HomeTargetStore` / gate).
- Remove or narrow the Android `\|\|` so **`local` means native** again. Android must not bind home as `local`; if something still requests `local` on Android for work FS, canonicalizer has already remapped to home before resolve.

Do **not** leave “Android always SSH regardless of target id” as the permanent work-plane rule.

**Implementation order:** wire `WorkTargetCanonicalizer` at every resolve / launch entry first; only then remove the Android `||` in `RuntimeContextResolver`, so there is no window where `local` means native FS while callers still pass bare `local` under SSH home.

### Call-site audit (required for success criterion 3)

Plan must grep and fix every independent `_runtimeTargetFromId` / bare `localTargetId` process-placement path, including at least:

- `SessionLifecycleService` / `resolveWorkContextForTargetId`
- `RunTargetResolver`
- `workspace_shell_connector` / `defaultSessionSpecFor`
- `remote_cli_requirements` (`sshTargetForProjectFolder` returning null on `local`)
- session launch ad-hoc `WorkspaceFolder(path: …)` without target

`ChatSessionShellFactory` already sets `validateLaunch: false` for SSH work targets — upstream resolve is the main fix; factory needs regression tests more than logic changes.

### Out of scope

- Changing SSH profile UX / startup gate (already covered elsewhere)
- Migrating PC desktop remote folders (already `ssh:*`)
- Rewriting all historical workspace JSON on disk in a batch job (resolve-time canonicalize is enough; optional eager rewrite on workspace load is allowed but not required)

## Error / edge cases

- SSH home with empty/missing profile id: fail at shell factory / SSH open with existing profile-missing errors; do not fall back to local PTY.
- WSL home on Windows: `defaultFolderTargetId` returns `wsl:…`; `local` + WSL home canonicalizes to home the same way as SSH (literal `local` = native Windows, not WSL).
- Mixed workspaces: per-folder ids remain authoritative after resolve; only bare `local` is rewritten when home is non-local.

## Testing

- Unit: `WorkTargetCanonicalizer` — local home + local; SSH home + local → home; SSH home + `ssh:other` unchanged; WSL home + local → home.
- Unit: `launchWorkTarget` / lifecycle with injected SSH home and folder `local` → SSH kind.
- Unit: `ChatSessionShellFactory` with resolved SSH workTarget → `validateLaunch == false`, `usesRemoteTransport`.
- Unit: `defaultSessionSpecFor` with SSH home + local folder id → workspace-target spec, not local shell spec.
- Unit: create-default / default folder target id under SSH home is `ssh:…`.

## Success criteria

- Android + SSH home + existing or new workspace can start Claude (or other CLI) over SSH without local `File.existsSync` rejecting `/root/.local/bin/claude`.
- Workspace bottom shell on that work plane opens remote shell, not a phone-local PTY.
- No remaining call path that treats folder `local` as device-native when home is SSH.
