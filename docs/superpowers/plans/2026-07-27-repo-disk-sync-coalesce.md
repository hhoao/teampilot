# Repo Disk Sync Coalesce Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make skill/plugin repo disk syncs race-safe via process-wide coalesce, stop trusting empty-SHA skill snapshots, and surface real git stderr.

**Architecture:** `AsyncKeyedCoalescer` + process-wide `RepoDiskSyncCoalescer` keyed by `$cacheRoot|$repoKey` (force shares the same key). Skill cache adds trust checks (non-empty SHA, layout, optional required paths). Shared `gitProcessStderrSnippet` for skill + plugin. Bootstrap injects shared `SkillRepoDiskCacheService` into `SkillAcquisitionEngine`.

**Tech Stack:** Dart/Flutter, existing `SkillFetchService` / `PluginRepoGitService`, `AppStorage` FS, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-27-repo-disk-sync-coalesce-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/utils/async_keyed_coalescer.dart` | Generic same-key Future coalesce |
| `client/lib/utils/repo_disk_sync_coalescer.dart` | Process-wide instance + `syncKey(cacheRoot, repoKey)` |
| `client/lib/utils/git_process_stderr.dart` | Progress-aware stderr snippet |
| `client/lib/services/skill/skill_repo_disk_cache_service.dart` | Coalesce + trust + `requiredRelativePaths` |
| `client/lib/services/skill/skill_repo_git_service.dart` | Use shared stderr helper |
| `client/lib/services/plugin/plugin_repo_disk_cache_service.dart` | Replace static `_syncInflight` |
| `client/lib/services/plugin/plugin_repo_git_service.dart` | Use shared stderr helper |
| `client/lib/app/app_shell.dart` | `repoCache: skillRepoCache` on acquisition engine |
| `client/lib/cubits/skill_cubit.dart` | Fallback engine gets `_repo.repoCache` |
| Tests under `client/test/utils/` and `client/test/services/skill/` (+ plugin coalesce case) |

---

### Task 1: `AsyncKeyedCoalescer`

**Files:**
- Create: `client/lib/utils/async_keyed_coalescer.dart`
- Create: `client/test/utils/async_keyed_coalescer_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/async_keyed_coalescer.dart';

void main() {
  test('same key runs work once and shares result', () async {
    final c = AsyncKeyedCoalescer();
    var runs = 0;
    Future<int> work() async {
      runs++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return 7;
    }

    final results = await Future.wait([
      c.run('a', work),
      c.run('a', work),
      c.run('a', work),
    ]);
    expect(results, [7, 7, 7]);
    expect(runs, 1);
  });

  test('different keys run independently', () async {
    final c = AsyncKeyedCoalescer();
    var runs = 0;
    Future<String> work(String id) async {
      runs++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return id;
    }

    final results = await Future.wait([
      c.run('x', () => work('x')),
      c.run('y', () => work('y')),
    ]);
    expect(results.toSet(), {'x', 'y'});
    expect(runs, 2);
  });

  test('after completion same key can run again', () async {
    final c = AsyncKeyedCoalescer();
    var runs = 0;
    await c.run('a', () async {
      runs++;
      return 1;
    });
    await c.run('a', () async {
      runs++;
      return 2;
    });
    expect(runs, 2);
  });

  test('shared failure propagates to all waiters', () async {
    final c = AsyncKeyedCoalescer();
    var runs = 0;
    Future<void> boom() async {
      runs++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      throw StateError('nope');
    }

    final f1 = c.run('a', boom);
    final f2 = c.run('a', boom);
    await expectLater(f1, throwsA(isA<StateError>()));
    await expectLater(f2, throwsA(isA<StateError>()));
    expect(runs, 1);
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL** (library missing)

```bash
cd client && flutter test test/utils/async_keyed_coalescer_test.dart
```

- [ ] **Step 3: Implement**

```dart
/// Coalesces concurrent async work by [key]: waiters share one [Future].
class AsyncKeyedCoalescer {
  final _inflight = <String, Future<dynamic>>{};

  Future<T> run<T>(String key, Future<T> Function() work) {
    final existing = _inflight[key];
    if (existing != null) return existing as Future<T>;

    final future = work();
    _inflight[key] = future;
    future.whenComplete(() {
      if (identical(_inflight[key], future)) {
        _inflight.remove(key);
      }
    });
    return future;
  }
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/utils/async_keyed_coalescer_test.dart
```

- [ ] **Step 5: Commit** (when user asks, or per executing-plans policy)

```bash
git add client/lib/utils/async_keyed_coalescer.dart client/test/utils/async_keyed_coalescer_test.dart
git commit -m "feat(utils): add AsyncKeyedCoalescer for same-key Future merge"
```

---

### Task 2: `RepoDiskSyncCoalescer` + `gitProcessStderrSnippet`

**Files:**
- Create: `client/lib/utils/repo_disk_sync_coalescer.dart`
- Create: `client/lib/utils/git_process_stderr.dart`
- Create: `client/test/utils/git_process_stderr_test.dart`

- [ ] **Step 1: Write stderr failing tests**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/git_process_stderr.dart';

void main() {
  test('skips cloning-into progress and keeps real error', () {
    final r = ProcessResult(1, 128, '', '''
正克隆到 '/tmp/foo'...
fatal: destination path '/tmp/foo' already exists and is not an empty directory.
''');
    final s = gitProcessStderrSnippet(r);
    expect(s, contains('fatal:'));
    expect(s.contains('正克隆到'), isFalse);
  });

  test('english Cloning into is skipped', () {
    final r = ProcessResult(
      1,
      128,
      '',
      "Cloning into '/tmp/x'...\nfatal: unable to access 'https://example.com/': Failed\n",
    );
    expect(gitProcessStderrSnippet(r), contains('fatal:'));
  });

  test('empty stderr uses exit code', () {
    expect(
      gitProcessStderrSnippet(ProcessResult(1, 1, '', '')),
      'exit 1',
    );
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/utils/git_process_stderr_test.dart
```

- [ ] **Step 3: Implement helpers**

`git_process_stderr.dart`:

```dart
import 'dart:io';

/// Compact stderr for git failures; skips clone progress lines.
String gitProcessStderrSnippet(
  ProcessResult result, {
  int maxLines = 3,
  int maxChars = 400,
}) {
  final err = result.stderr?.toString().trim() ?? '';
  if (err.isEmpty) return 'exit ${result.exitCode}';
  final useful = err
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .where((l) => !_isCloneProgressLine(l))
      .take(maxLines)
      .toList();
  final text = useful.isEmpty ? err.split('\n').first.trim() : useful.join('\n');
  return text.length > maxChars ? '${text.substring(0, maxChars)}…' : text;
}

bool _isCloneProgressLine(String line) {
  final lower = line.toLowerCase();
  return lower.startsWith('cloning into ') || line.startsWith('正克隆到');
}
```

`repo_disk_sync_coalescer.dart`:

```dart
import 'async_keyed_coalescer.dart';

/// Process-wide coalesce for skill/plugin repo disk sync.
class RepoDiskSyncCoalescer {
  RepoDiskSyncCoalescer._();
  static final instance = AsyncKeyedCoalescer();

  static String syncKey(String cacheRoot, String repoKey) =>
      '$cacheRoot|$repoKey';
}
```

- [ ] **Step 4: Tests PASS** for stderr

```bash
cd client && flutter test test/utils/git_process_stderr_test.dart
```

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(utils): repo disk sync coalescer + git stderr snippet"
```

---

### Task 3: Skill cache trust + coalesce

**Files:**
- Modify: `client/lib/services/skill/skill_repo_disk_cache_service.dart`
- Create: `client/test/services/skill/skill_repo_disk_cache_service_test.dart`

**Constructor change:** accept optional `AsyncKeyedCoalescer? coalescer` (default `RepoDiskSyncCoalescer.instance`) and existing `SkillFetchService? fetch`.

**Trust:** replace “`_hasSnapshot` + remote null → reuse” with trusted check:

```dart
Future<bool> _isTrustedSnapshot({
  required String dirPath,
  required SkillRepoCacheMeta meta,
  required String configuredBranch,
  List<String> requiredRelativePaths = const [],
}) async {
  if (meta.configuredBranch != configuredBranch) return false;
  if (meta.commitSha.trim().isEmpty) return false;
  if (!await _hasSnapshot(dirPath)) return false;
  for (final rel in requiredRelativePaths) {
    final trimmed = rel.trim();
    if (trimmed.isEmpty) continue;
    final p = _fs.pathContext.join(dirPath, 'files', trimmed);
    if (!(await _fs.stat(p)).exists) return false;
  }
  return true;
}
```

**`ensureSynced` shape:**

```dart
Future<SkillRepoSyncResult> ensureSynced(
  SkillRepo repo, {
  bool force = false,
  List<String> requiredRelativePaths = const [],
}) {
  final key = RepoDiskSyncCoalescer.syncKey(_cacheRoot, repoKey(repo));
  return _coalescer.run(
    key,
    () => _ensureSyncedOnce(
      repo,
      force: force,
      requiredRelativePaths: requiredRelativePaths,
    ),
  );
}
```

Move current body into `_ensureSyncedOnce`. Concrete edits inside that method:

1. Early freshness: require `meta != null` and `await _isTrustedSnapshot(...)` (not bare `_hasSnapshot`).
2. `remoteSha == null` reuse branch: only when trusted (same helper).
3. Catch fallback: reuse disk only when trusted; otherwise rethrow.
4. After `_writeSnapshot`, if `commitSha.trim().isEmpty` → `appLogger.w('[SkillRepoCache] synced ${repo.fullName} with empty commitSha')`.

- [ ] **Step 1: Write failing tests** (use `setUpTestAppStorage` / `tearDownTestAppStorage`)

Fake fetch subclass:

```dart
class _CountingFetch extends SkillFetchService {
  int downloads = 0;
  String? remoteSha;
  String commitShaOnDownload = 'abc123';

  @override
  Future<String?> fetchBranchCommitSha(
    String owner,
    String name,
    String branch,
  ) async => remoteSha;

  @override
  Future<({Map<String, Uint8List> entries, String branch, String commitSha})>
  downloadRepoEntries(
    SkillRepo repo, {
    Filesystem? fs,
    String? persistentGitPath,
  }) async {
    downloads++;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return (
      entries: {
        'demo/SKILL.md': Uint8List.fromList(
          utf8.encode('---\nname: demo\ndescription: d\n---\n'),
        ),
      },
      branch: repo.branch,
      commitSha: commitShaOnDownload,
    );
  }
}
```

Cases:

1. Empty `commitSha` in meta + `remoteSha == null` → must call download (not trust).
2. Non-empty SHA + snapshot + `remoteSha == null` → no download.
3. Two `SkillRepoDiskCacheService` instances sharing one `AsyncKeyedCoalescer` → parallel `ensureSynced` → `downloads == 1`.
4. `requiredRelativePaths: ['bin']` missing under `files/` → untrusted → download.

- [ ] **Step 2: Run — expect FAIL** on trust/coalesce behavior

```bash
cd client && flutter test test/services/skill/skill_repo_disk_cache_service_test.dart
```

- [ ] **Step 3: Implement service changes**

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "fix(skills): coalesce repo sync and distrust empty-SHA snapshots"
```

---

### Task 4: Wire stderr into skill + plugin git services

**Files:**
- Modify: `client/lib/services/skill/skill_repo_git_service.dart` — replace `_stderrSnippet` body with `gitProcessStderrSnippet(result)` (or delete method and call helper at throw sites)
- Modify: `client/lib/services/plugin/plugin_repo_git_service.dart` — same
- Extend: `client/test/services/skill/skill_repo_git_service_test.dart` with one clone-failure message assertion if easy; otherwise rely on `git_process_stderr_test.dart`

- [ ] **Step 1:** Optional thin test that syncCheckout failure message contains `fatal:` when runner returns progress+fatal stderr
- [ ] **Step 2:** Implement replacements
- [ ] **Step 3:** `flutter test test/utils/git_process_stderr_test.dart test/services/skill/skill_repo_git_service_test.dart`
- [ ] **Step 4: Commit**

```bash
git commit -m "fix(git): surface real clone errors beyond Cloning into"
```

---

### Task 5: Plugin cache uses process-wide coalescer

**Files:**
- Modify: `client/lib/services/plugin/plugin_repo_disk_cache_service.dart`
- Extend: `client/test/services/plugin/plugin_repo_disk_cache_service_test.dart` (or new file)

Remove:

```dart
static final Map<String, Future<String>> _syncInflight = {};
```

In `syncMarketplace`:

```dart
final root = await _cacheRoot();
final key = RepoDiskSyncCoalescer.syncKey(root, repoKey(m));
return (_coalescer ?? RepoDiskSyncCoalescer.instance).run(
  key,
  () => _syncMarketplaceOnce(m, force: force),
);
```

Add constructor `AsyncKeyedCoalescer? coalescer`.

- [ ] **Step 1: Failing test** — use `setUpTestAppStorage` / `tearDownTestAppStorage`; two service instances, shared coalescer, mocked git that counts `syncCheckout`; parallel `syncMarketplace` → count 1  
  (Inject `PluginRepoGitService` with fake runner / subclass if needed.)
- [ ] **Step 2: Implement migration**
- [ ] **Step 3: Tests PASS**
- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(plugins): use process-wide RepoDiskSyncCoalescer"
```

---

### Task 6: DI hygiene — shared skill repo cache

**Files:**
- Modify: `client/lib/app/app_shell.dart` — pass `repoCache: skillRepoCache` into `SkillAcquisitionEngine(...)`
- Modify: `client/lib/cubits/skill_cubit.dart` — fallback `SkillAcquisitionEngine` should pass `repoCache: _repo.repoCache`
- Confirm: `SkillAcquisitionEngine` already has `repoCache` ctor param (it does)

- [ ] **Step 1:** Grep for `SkillAcquisitionEngine(` — every production construction must pass `repoCache` when a shared cache exists
- [ ] **Step 2:** Apply app_shell + SkillCubit fixes
- [ ] **Step 3:** `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` on touched files
- [ ] **Step 4: Commit**

```bash
git commit -m "fix(skills): inject shared SkillRepoDiskCacheService into acquisition engine"
```

---

### Task 7: Verification

- [ ] **Step 1: Run focused suites**

```bash
cd client && flutter test \
  test/utils/async_keyed_coalescer_test.dart \
  test/utils/git_process_stderr_test.dart \
  test/services/skill/skill_repo_disk_cache_service_test.dart \
  test/services/skill/skill_repo_git_service_test.dart \
  test/services/plugin/plugin_repo_disk_cache_service_test.dart \
  test/services/skill/skill_acquisition_engine_test.dart
```

- [ ] **Step 2: Broader check**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

- [ ] **Step 3:** Manually note: existing corrupt `garrytan__gstack` with empty SHA will re-download on next expert select (no manual wipe required for that class)

---

## Out of scope (do not implement in this plan)

- Pack/acquire coalesce by `packId`
- Plugin empty-SHA trust alignment
- Wiring `requiredRelativePaths: ['bin']` from gstack recipe
- Changing `skill-packs/gstack/pack.json`
