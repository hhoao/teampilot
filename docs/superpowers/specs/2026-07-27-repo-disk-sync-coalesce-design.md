# Repo Disk Sync Coalesce + Skill Cache Trust

## Goal

Stop concurrent skill/plugin repo syncs from corrupting on-disk caches, and stop
TeamPilot from treating incomplete skill repo snapshots as trustworthy when
GitHub is unreachable or rate-limited.

Triggered by `garrytan/gstack` install failures: parallel landing preflight +
session connect raced on `SkillRepoDiskCacheService.ensureSynced`, left a
partial `files/` tree (missing `bin/` and many skill dirs), then trusted that
snapshot because remote commit SHA lookup returned HTTP 403.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Scope | Shared coalesce primitive for skill + plugin; skill cache trust policy; git stderr diagnostics |
| Concurrency | **Inflight coalesce by key** (share one `Future`), not merely serialize with `LockPool` |
| Coalesce scope | **Process-wide**, keyed by `$cacheRoot\|$repoKey` — not per service instance |
| Force | **Same coalesce key** as non-force (aligned with today’s plugin map). First caller’s `force` flag defines the in-flight work; a later `force=true` that joins a non-force run accepts that result (caller may invoke force again). Distinct `\|force` keys are **rejected** — they would allow parallel writers on one disk tree |
| Skill trust | Reuse disk only when snapshot is **trusted** (non-empty `commitSha` + layout checks + optional required paths) |
| Plugin trust | Keep existing “checkout exists → use on remote miss” behavior this round; migrate only coalesce |
| DI hygiene | Wire shared `SkillRepoDiskCacheService` into `SkillAcquisitionEngine` at bootstrap (defense in depth; coalesce remains authoritative) |
| Pack/acquire coalesce | **Out of scope** (option C deferred); same-repo double sync is covered by cache-level coalesce |
| Git stderr | Improve **both** skill and plugin `_stderrSnippet` (same progress-line bug) |
| User cache wipe | Not required in code; untrusted snapshots will re-download on next sync |

## Problem

1. `SkillRepoDiskCacheService.ensureSynced` has no per-repo concurrency control.
2. Concurrent `_writeSnapshot` / git `source/` checkouts share paths → torn
   `files/` with a full `skills.json` (discovery from in-memory entries ≠ what
   survived on disk after a race).
3. `_hasSnapshot` only checks `skills.json` file + `files/` directory.
4. When `fetchBranchCommitSha` returns null (API 403 / network), code trusts any
   snapshot — including empty `commitSha` and incomplete trees.
5. `SkillRepoGitService._stderrSnippet` keeps the first stderr line, often just
   `Cloning into…` / `正克隆到…`, hiding the real git error.
6. Plugin cache already has a local `_syncInflight` map; skill does not — two
   divergent patterns.

## Architecture

```
AsyncKeyedCoalescer (process-wide)
  ├─ SkillRepoDiskCacheService.ensureSynced($cacheRoot|$repoKey)
  └─ PluginRepoDiskCacheService.syncMarketplace($cacheRoot|$repoKey)

SkillRepoDiskCacheService
  ├─ isTrustedSnapshot(meta, dir, requiredRelativePaths?)
  ├─ freshness: trusted + remoteSha match → reuse
  ├─ trusted + remoteSha null → reuse
  └─ else download; on failure reuse only if trusted
```

### `AsyncKeyedCoalescer`

New: `client/lib/utils/async_keyed_coalescer.dart`

```dart
class AsyncKeyedCoalescer {
  Future<T> run<T>(String key, Future<T> Function() work);
}
```

Semantics:

- Same `key` with in-flight work → await the existing `Future` (no re-entry).
- On completion (success or failure), remove the entry iff `identical` to the
  stored future (same pattern as plugin `_syncInflight` today).
- Different keys do not block each other.
- Coalesce key is `$cacheRoot|$repoKey` only — **do not** append `|force`.
  Parallel force + non-force must not write the same tree; joining the in-flight
  future preserves mutual exclusion (same as plugin’s static map today).

**Why process-wide:** Today `app_shell` shares one `SkillRepoDiskCacheService`
across `SkillRepository` / `SkillInstallService`, but `SkillAcquisitionEngine`
defaults to `SkillRepoDiskCacheService()` when `repoCache` is omitted — a second
instance writing the same disk tree. Plugin already used a **static**
`_syncInflight` for the same reason. Per-instance coalesce would miss the
landing/session race and would **regress** plugin cross-instance behavior.

**Ownership:**

- Provide a shared process-wide coalescer for repo-disk sync, e.g.
  `RepoDiskSyncCoalescer.instance` (thin wrapper around `AsyncKeyedCoalescer`)
  or a library-private static used by both cache services.
- Coalesce key **must** include the cache root path plus repo key
  (`'$cacheRoot|$repoKey'`) so skill vs plugin roots never collide and tests
  with different temp roots stay isolated.
- Unit tests construct a **fresh** `AsyncKeyedCoalescer()` for isolation.
- Production cache services use the process-wide instance, but accept an optional
  `AsyncKeyedCoalescer? coalescer` constructor override for tests that assert
  cross-instance coalesce without touching the global singleton.

**DI hygiene (same PR):** Pass `repoCache: skillRepoCache` into
`SkillAcquisitionEngine` in `app_shell.dart` (and any `SkillCubit` fallback that
constructs an engine) so fetch clients are shared. Coalesce remains the
correctness guarantee if another default-constructed cache appears.

### Skill snapshot trust

Trusted when all hold:

1. `skills.json` is a file and `files/` is a directory.
2. `meta.commitSha` is non-empty.
3. `meta.configuredBranch == repo.branch`.
4. Every path in optional `requiredRelativePaths` exists under `files/`
   (file or directory). Default empty.

`ensureSynced` may accept `requiredRelativePaths` for pack/`git.sync` callers
that know they need e.g. `bin`. v1 may leave the parameter unused by acquire if
not yet wired; the trust API must support it for extensibility.

Empty `commitSha` after a successful write: log a warning; such snapshots must
**not** take the “remote unavailable → trust disk” branch.

**Observed gstack failure** had `commitSha: ""` — empty-SHA distrust is enough
to force re-download for that class of bad cache. A torn tree that somehow kept
a non-empty SHA while missing `bin/` is not guaranteed fixed in v1 unless
callers pass `requiredRelativePaths`; coalesce prevents new races of that form.

### Git stderr

Shared behavior for `SkillRepoGitService` and `PluginRepoGitService`
`_stderrSnippet` (extract a tiny shared helper if duplication is awkward):

- Prefer informative lines; skip progress-only lines matching cloning-into /
  `正克隆到`.
- Join up to ~3 remaining lines, cap ~400 characters.

### Plugin migration

Replace `static final Map<String, Future<String>> _syncInflight` with the
**process-wide** repo-disk coalescer (key: `$cacheRoot|$repoKey`, same for
force and non-force). Do not change remote-miss trust rules in this PR.

## Data flow (skill)

```
ensureSynced(repo, force?, requiredRelativePaths?)
  → coalescer.run(key)
    → if !force && trusted(meta, paths):
         remoteSha = fetch…
         match → SkillRepoSyncResult(updated: false)
         remote null → reuse (trusted only)
    → downloadRepoEntries + _writeSnapshot
    → on failure: if trusted → stale reuse else rethrow
```

## Error handling

| Case | Behavior |
|------|----------|
| Concurrent syncs | Single download/write; waiters share result |
| Download fails, trusted cache | Warn + return disk skills |
| Download fails, untrusted / missing | Rethrow / propagate to acquire |
| Git clone fails | Exception message includes real stderr snippet |
| API rate limit (403) | SHA null; trusted cache reusable; untrusted forces retry path |

## Testing

| Area | Cases |
|------|-------|
| `AsyncKeyedCoalescer` | Same key runs once; different keys concurrent; after settle can run again; errors shared |
| Trust helper | Empty SHA / missing files / missing required path → untrusted; good meta + paths → trusted |
| `ensureSynced` | Two parallel calls on **separate service instances** sharing one coalescer → one download; untrusted + remote null → attempts download |
| Plugin | Concurrent `syncMarketplace` on separate instances enters git sync once |
| `_stderrSnippet` | Progress line + real error → snippet contains real error (skill and/or shared helper) |

## Files

| Path | Change |
|------|--------|
| `client/lib/utils/async_keyed_coalescer.dart` | New |
| `client/lib/utils/repo_disk_sync_coalescer.dart` (or equiv.) | Process-wide instance + key helper |
| `client/test/utils/async_keyed_coalescer_test.dart` | New |
| `client/lib/services/skill/skill_repo_disk_cache_service.dart` | Coalesce + trust |
| `client/test/services/skill/skill_repo_disk_cache_service_test.dart` | New |
| `client/lib/utils/git_process_stderr.dart` (or equiv.) | Shared stderr snippet helper |
| `client/lib/services/skill/skill_repo_git_service.dart` | Use shared stderr helper |
| `client/lib/services/plugin/plugin_repo_git_service.dart` | Use shared stderr helper |
| `client/lib/services/plugin/plugin_repo_disk_cache_service.dart` | Use process-wide coalescer |
| `client/lib/app/app_shell.dart` | Inject `repoCache: skillRepoCache` into acquisition engine |
| `client/lib/services/skill/skill_acquisition_engine.dart` / cubit | Accept/pass shared cache where constructed |

## Non-goals / follow-ups

- Acquire/pack-level coalesce by `packId` (option C).
- Align plugin marketplace trust with skill empty-SHA / required-path rules.
- Wiring `requiredRelativePaths: ['bin']` from gstack `fs.materialize` / pack recipe (API ready, acquire optional later).
- Changing gstack `pack.json` recipe.
- Automatic deletion of existing corrupt user caches (empty-SHA → re-sync; other torn trees may need manual delete or force until required-paths are wired).

## Success criteria

- Parallel `ensureSynced` for the same disk repo key **across cache service instances** never interleaves `_writeSnapshot`.
- Snapshots with empty `commitSha` are not treated as offline-safe.
- Git failure logs (skill + plugin) include actionable stderr beyond “Cloning into…”.
- Plugin and skill share one process-wide coalesce implementation (no weaker than today’s plugin static map).
- Bootstrap injects the shared skill repo cache into `SkillAcquisitionEngine`.
