# Remote toolchain locate + path wiring (Git / Node)

**Date:** 2026-08-03  
**Status:** Approved for planning  
**Scope:** Remote work-plane Locate for Git and Node; persist into existing `SessionPreferences.toolchainPaths`; make `GitCommandRunner` and CLI installer actually honor those paths.

## Problem

1. Settings UI offers Locate for toolchain Git/Node, but remote work planes hard-reject with `cliExecutablePathLocateRemoteUnsupported`.
2. `ToolchainExecutableDiscovery` only implements local discovery (`locateLocal` / `locateLocalTool`).
3. Even when a path is stored in `toolchainPaths`, `GitService` / `GitCommandRunner` always use PATH / `CliToolLocator` and ignore the preference. Node’s preference is similarly unused by `CliInstallerService` npm/node lookup.

Remote source control already runs `git` over SSH via `RemoteGitCommandRunner`, and remote CLI Locate already exists (`RemoteCliLocator` + `DefaultRemoteCliLocator`). Toolchain is the missing parallel.

## Goals

1. **Remote Locate** for Git and Node on SSH/Termux work planes (same UX as CLI Locate).
2. **Persist** results into existing global `SessionPreferences.toolchainPaths` (`git` / `node` keys).
3. **Wire Git:** configured non-empty `toolchainPaths['git']` is the executable used by local / WSL / SSH runners; empty falls back to today’s auto-discovery.
4. **Wire Node:** configured non-empty `toolchainPaths['node']` is preferred when `CliInstallerService` resolves node/npm (path itself and/or its directory for sibling `npm`); empty keeps today’s probes.
5. **Tests** covering discovery, settings-row remote locate, git runner executable selection, and installer override preference.

## Non-goals

- Per-SSH-target toolchain path storage (no new `cliPathOverrides`-style map for git/node).
- Changing startup to auto-scan remote toolchains (`locateLocal()` at boot stays local-only).
- Remote Browse (file picker remains local `FilePicker`; users may still type a remote absolute path).
- Remote Install for Git/Node (Install buttons stay local / existing behavior).
- Reworking Skill/Plugin git fetch services (`SkillRepoGitService` / `PluginRepoGitService`) unless they already share the same runner path helper—out of scope unless a one-line reuse is free.
- Unifying git/node into `CliToolRegistry` as pseudo-CLIs.

## Approach

**Mirror CLI Locate + inject executable overrides (Option A from design discussion).**

Reuse `DefaultRemoteCliLocator(executableName)` for remote probes instead of inventing a second SSH PATH scanner. Keep storage on existing `toolchainPaths`. Inject resolved git executable into command runners; inject preferred node path into installer locate.

## Architecture

### 1. Discovery

Extend `ToolchainExecutableDiscovery`:

```dart
Future<String?> locateRemoteTool({
  required String toolId,
  required SshCommandRunner run,
});
```

Mapping:

| `toolId` | Remote probe |
|----------|----------------|
| `SessionPreferences.toolchainGit` | `DefaultRemoteCliLocator('git')` |
| `SessionPreferences.toolchainNode` | `DefaultRemoteCliLocator('node')` |
| other | `null` |

Local APIs unchanged.

### 2. Settings row

`ToolchainPathSettingsRow._locate`:

- Remove the early `isRemoteWorkPlane` → unsupported toast branch.
- Resolve path:
  - **Remote:** `_remoteSshProfile` + `SshClientFactory.clientForStorage` + `locateRemoteTool` (same helper pattern as `CliExecutablePathSettingsRow`).
  - **Local:** existing `locateLocalTool` / `locateOverride`.
- On success: `setToolchainPath` + success toast; on empty/error: failure toast.

Share or duplicate the small `_remoteSshProfile` helper (prefer extract to a tiny shared function if both rows already need it; otherwise copy once with a comment—YAGNI on a new file unless duplication is ugly).

### 3. Git executable wiring

`gitCommandRunnerForContext(RuntimeContext ctx, {String? gitExecutable})` (or equivalent) passes an optional absolute/bare executable into:

- `LocalGitCommandRunner` — if `gitExecutable` non-empty, use it and skip `CliToolLocator`; else current locate cache.
- `WslGitCommandRunner` — if set, run that path/name inside WSL; else `'git'`.
- `RemoteGitCommandRunner` — if set, run that path/name over SSH; else `'git'`. Availability probe should prefer the configured path when present (`test -x` / `command -v` on that path) so a bad override fails clearly.

Prefer threading the override through **`GitService.forContext` / `gitCommandRunnerForContext`** so every caller (source-control `GitRepoStore`, worktree create/remove, etc.) picks it up—not only the panel.

Resolver source (from `app_shell` or a thin shared callback):

```dart
String? resolveGitExecutable(/* RuntimeContext optional */) =>
  sessionPreferencesCubit.toolchainPath(SessionPreferences.toolchainGit);
  // empty → null → runner auto-discover
```

(Mode-agnostic: the stored path means “path for the current work plane,” matching today’s settings copy.)

**Cache note:** `GitRepoStore` LRU-caches `GitCubit`s by `targetId:root`. Preference changes after cubit creation need either (a) accept stale executable until cubit eviction/rebuild (match typical CLI path UX), or (b) invalidate/rebuild on toolchain git path change. Default for this iteration: **(a)** unless a one-line refresh hook is already easy.

### 4. Node executable wiring

`CliInstallerService` (and any thin host helper it uses for `_locateRemoteNpm` / local node/npm):

1. If `toolchainPaths['node']` (injected via constructor/callback, not a hard cubit dependency) is non-empty:
   - Prefer that path when a **node** binary is required.
   - For **npm**: try `dirname(node)/npm` (and Windows `npm.cmd` if applicable) before existing `command -v npm` / login-shell / Termux probes.
2. If unset or sibling npm missing → existing locate behavior.

`CliInstallerService` is constructed at multiple call sites (settings row, onboarding `cli_step`, remote preflight install, etc.), not as an `app_shell` singleton. Pass  
`() => sessionPreferencesCubit.toolchainPath(SessionPreferences.toolchainNode)`  
(or an equivalent preferred-path getter) into **each** construction site that should honor the preference.

### 5. Error / empty behavior

| Case | Behavior |
|------|----------|
| Remote locate, no SSH profile | Failure toast; path unchanged |
| Probe finds nothing | Failure toast |
| Configured git path missing on host | Git ops fail with existing `GitException` / exit 127 style errors |
| Empty preference | Auto-discover (unchanged) |

## Data flow

```
Locate (local)  → ToolchainExecutableDiscovery.locateLocalTool
Locate (remote) → SSH client → DefaultRemoteCliLocator → locateRemoteTool
                    ↓
         SessionPreferences.toolchainPaths[git|node]
                    ↓
    ┌───────────────┴────────────────┐
    ↓                                ↓
GitRepoStore → GitCommandRunner    CliInstallerService node/npm locate
(source control panel)             (CLI install / bootstrap)
```

## Testing

| Area | Cases |
|------|--------|
| `ToolchainExecutableDiscovery` | `locateRemoteTool` git/node success; unknown id → null; empty stdout → null |
| `ToolchainPathSettingsRow` | Remote Locate no longer shows unsupported; writes path via override/SSH seam; missing profile fails |
| `GitCommandRunner` | Configured executable used in `runInDirectory`; empty uses fallback |
| `CliInstallerService` (or unit of locate helper) | Preferred node path wins; sibling npm preferred; falls back when unset |

Reuse existing fakes (`SshCommandRunner`, process runner injection, `locateOverride` test seam).

## Implementation notes

- Do not put git/node into `CliToolRegistry`.
- Keep `cliExecutablePathLocateRemoteUnsupported` string for any remaining callers; toolchain stops using it.
- Prefer small diffs in `git_command_runner.dart`, `toolchain_executable_discovery.dart`, `toolchain_path_settings_row.dart`, `git_repo_store.dart` / `app_shell.dart`, `cli_installer_service.dart`.
- Follow TDD: failing tests first per behavior above.

## Success criteria

- Remote work plane: Locate fills Git and Node paths when present on the host.
- All `GitService.forContext` / runner-backed git ops use the configured Git path on local/WSL/SSH when set.
- CLI installer prefers configured Node (and sibling npm) when set.
- Empty preferences preserve previous auto-discovery behavior.
- Unit/widget tests above pass under `flutter test --exclude-tags integration`.
