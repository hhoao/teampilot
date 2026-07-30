# Default workspace SSH/WSL path design

**Date:** 2026-07-30  
**Status:** Approved for planning  
**Problem:** First-launch `DefaultWorkspaceService` always seeds folder path as device-native `<Documents>/TeamPilot`. On Android (SSH home) the folder `targetId` is correctly `ssh:<profileId>`, but the path is still a phone Documents path that does not exist on the remote host. Sessions then `cd` into a missing remote directory.

## Goal

When home is non-local (SSH or WSL), the built-in Default workspace folder path must live on that home machine: `$HOME/TeamPilot`. Local home keeps `<Documents>/TeamPilot`.

## Invariants

1. Folder `targetId` continues to use `WorkTargetCanonicalizer.defaultFolderTargetId(home)` (unchanged).
2. Folder `path` must be resolvable on the machine identified by that `targetId`.
3. Local home: path = `DefaultWorkspaceDirectory.resolveDefaultWorkspacePath()` (`<Documents>/TeamPilot`).
4. SSH/WSL home: path = posix-join of bound home context home directory + `TeamPilot` (i.e. `$HOME/TeamPilot` on that host), created via the home filesystem (`AppStorage.fs`), not via `dart:io` `Directory`.
5. No automatic rewrite of already-seeded workspaces with a wrong device path (out of scope). New seed / lookup uses the corrected path only.

## Design

### `DefaultWorkspaceService.resolvePrimaryPath`

Accept optional `RuntimeTarget? home` (default: treat as local / current callers that omit it behave as today only when home is local).

```dart
static Future<String> resolvePrimaryPath({RuntimeTarget? home}) async {
  final resolved = home ?? RuntimeTarget.local();
  if (resolved.kind == RuntimeKind.local) {
    return DefaultWorkspaceDirectory.resolveDefaultWorkspacePath();
  }
  // SSH / WSL: path on the home work plane
  final path = AppPaths.pathContextForDataRoot(AppStorage.home)
      .join(AppStorage.home, 'TeamPilot');
  await AppStorage.fs.ensureDir(path);
  return path;
}
```

### Call sites

| Site | Change |
|------|--------|
| `ensureDefault` / `seed` | Pass `home` into `resolvePrimaryPath(home: …)` for both create and lookup |
| `OnboardingGate` | Pass current home target when resolving primary path for post-onboarding navigation |

Bootstrap already passes `home` into `ensureDefault`; wire the same value through path resolution.

### Out of scope

- Migrating existing Default workspaces that already store a device Documents path under SSH home
- Changing create-workspace dialog defaults beyond seed (user picks a path there)
- Desktop SSH as optional home (same code path applies if home is SSH)

## Testing

- Existing local seed test unchanged (Documents/TeamPilot + `local` targetId).
- New test: with `AppStorage` bound to a remote-style home (`home: '/home/user'`, non-local filesystem ok) and `ensureDefault(..., home: RuntimeTarget.ssh('p1'))`, assert folder path is `/home/user/TeamPilot` and `targetId` is `ssh:p1`.
- Idempotency still holds when looking up by the corrected primary path.

## Success criteria

1. Android first launch after SSH home bind seeds Default at remote `$HOME/TeamPilot` with `ssh:…` targetId.
2. Desktop local home behavior unchanged.
3. Onboarding navigates to the seeded Default workspace when home is SSH.
