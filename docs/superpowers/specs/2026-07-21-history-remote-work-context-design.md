# History remote work-context: design

## Problem

History (`AiHistoryLoader` / live refresh) always reads transcripts via
`AppStorage` (control-plane home FS + layout). Launch writes member transcripts
on the seat’s **work-plane** machine (`SessionLifecycleService` →
`launchWorkContext` / `memberTargets`).

On mixed (member-remote) and project-remote workspaces, remote seats therefore
show empty History even when the PTY session has a full transcript on the SSH
host.

## Goal

History locate / parse / live softReload for a seat use the **same work-plane
`RuntimeContext`** launch would use for that seat — on-demand over the existing
SSH/SFTP (or WSL) `Filesystem`, with the existing in-memory `cacheToken` cache.

## Non-goals

- Full transcript tree mirror from remote → local `AppStorage`
- Disk snapshot of parsed messages / raw bytes for offline History (optional
  later)
- Changing adapter parse formats or pagination windows
- Making History answer CLI permission prompts

## Approach

**On-demand work-plane read + memory cache (no full mirror).**

```
SessionHistoryReview / AiHistoryCubit
  → AiHistoryLoader.load / resolveWatchMeta
       → async launchWorkContext(WorkspaceLaunchContext, memberId?)
       → SessionHistoryContextBuilder(
            fs / layout / appDataRoot from that RuntimeContext)
       → locate + parse (or cache hit on cacheToken)
  → AiHistoryLiveRefreshController watches/polls on the same seat FS
```

`RuntimeContextRegistry` already caches work-plane contexts (and SSH clients)
per target id. WSL work targets use the same registry path. Expensive work
remains “read + parse when token changes,” same as local History live continue.

Target resolution contract already covered by
`SessionLifecycleService.debugResolveWorkContext` /
`member_work_target_test.dart` — History must call the same helpers, not
reimplement target math.

## Behavior

| Seat | Filesystem / layout |
|------|---------------------|
| Local member / simple on local workspace | Unchanged (home or local work target) |
| Member pinned to `ssh:…` (mixed) | That target’s work context |
| Project-remote (all folders one SSH) | That workspace target’s work context |
| Simple / personal on remote topology | Workspace session target, not home |
| WSL work target | Same registry `forTarget` path as SSH |

**Folder catalog / cwd:** History must resolve
`workingDirectory` / bucket via `WorkspaceLaunchContext.folderCatalog`
(merged workspace + session folders), same as
`lifecycle.memberWorkDirs` — not `session.folders` alone. Today
`SessionHistoryReview` often passes `session.folders` only; callers must supply
workspace from `ChatCubit` state (fallback:
`Workspace(workspaceId, folders: session.folders)`), matching artifact transfer.

### Cache (required in v1)

Keep `AiHistoryLoader`’s existing memory cache keyed by
`sessionId + memberId` with `cacheToken` (mtime / locate hint):

- softReload / live poll: prefer cheap `stat` / token probe on the seat FS
- full read + parse only when token misses or changes
- remote poll interval: keep or slightly lengthen the non-`FsWatcher` path
  already used when the FS lacks watchers (SFTP)

Do **not** add a control-plane transcript sync in v1.

### Disconnect / errors

If work-context resolve or remote IO fails:

- Initial load → existing History `error` / empty path (surface a clear failure;
  do **not** silently fall back to scanning empty home/local roots for that
  remote seat)
- softReload → keep last good messages + `softReloadError` (existing cubit
  behavior)

When `RuntimeContextRegistry.dispose` / SSH drop evicts a work target, call
`AiHistoryLoader.invalidate` for affected seats so memory cache cannot serve
stale hits against a dead context.

**Who hooks evict:** bootstrap wires registry `onEvict` (or the existing SSH
disconnect path that already calls `dispose`) to invalidate. Prefer
`invalidate(sessionId: …)` without member when mapping `targetId` → seats is
ambiguous, or invalidate all open History seats pinned to that `targetId` via
`ChatCubit` session snapshots (`memberTargets` / folder targets). Exact
session enumeration can be “open tabs only” in v1.

## Wiring changes (sketch)

1. **`AiHistoryLoader`** — `_resolveSeat` becomes async end-to-end (`load` /
   `resolveWatchMeta` already async). Stop using a single global
   `fs` / `layout` / `appDataRoot` as the only source. Inject:

   ```dart
   Future<RuntimeContext> Function(
     WorkspaceLaunchContext ctx, {
     String? memberId,
   }) resolveWorkContext;
   ```

   Implemented as `lifecycle.launchWorkContext(ctx, memberId: memberId)`.
   Resolve once per load/watch-meta (registry cache makes this cheap). Build
   `SessionHistoryContext` from that context’s `filesystem`, `layout`,
   `appDataRoot`.

2. **Call path** — `AiHistoryCubit.load` / `softReload` / `resolveWatchMeta`
   accept or build the same `WorkspaceLaunchContext` (workspace from
   `ChatCubit` + session). `SessionHistoryReview` is the primary caller and
   must pass that ctx (and `workingDirectory` from `memberWorkDirs` /
   `folderCatalog`), not session folders alone.

3. **Bootstrap (`app_shell`)** — wire the injector to
   `SessionLifecycleService.launchWorkContext`. Do not duplicate
   `_workTargetForMember` / folder-target math in the loader. Wire
   evict → `AiHistoryLoader.invalidate` as above.

4. **`AiHistoryLiveRefreshController` / `SessionHistoryReview`** —
   `fs:` must not be `() => AppStorage.fs`. After async seat resolve on attach,
   **cache** the seat `Filesystem` (or full `RuntimeContext`) on the controller
   before `_attachSignal` (which calls `_fs()` synchronously). On seat change,
   stop/recreate the controller (already done) so FS switches with the member.

5. **Tests** — loader unit tests with a fake resolver returning distinct
   in-memory FS per target; assert remote seat reads remote roots and does not
   touch home FS; assert invalidate-on-evict clears cache. Prefer reusing
   lifecycle member-target contract tests rather than re-testing target math.
   Review host smoke: live refresh uses cached seat FS after resolve.

## Performance notes

- Context open: amortized by `RuntimeContextRegistry` target cache
- Steady state while History visible + PTY running: token poll / watch on seat
  FS; parse only on change
- Switching members: one resolve + locate; memory cache still per seat key

## Out of scope follow-ups

- Local disk snapshot of last successful parse for offline remote History
- Cross-machine artifact service reuse for History blobs
- Pushing remote mtime into a home-side index without file bodies

## Success criteria

- Mixed workspace, remote member: History shows that member’s transcript when
  SSH work context is available
- Project-remote: History matches launch machine transcripts
- Local-only seats: behavior and cache semantics unchanged
- No new background sync of remote transcript trees into `AppStorage`
