# Skill Acquisition Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a declarative `SkillAcquireSpec` + `SkillAcquisitionEngine` so skill install supports `git-dir` (default, today’s behavior) and HTTPS `script` acquire, with primary `Skill.id == expectedLocalId`.

**Architecture:** Parallel to `ExtensionAcquisitionEngine` (do not merge). Optional `acquire` on `SkillDependencyRef` / `DiscoverableSkill`; missing acquire ≡ `git-dir`. `SkillCubit.installTeamDependency` / `installFromDiscovery` route through the engine. Script installs run an injectable `curl|sh` runner, then register skills under `skills/installed/` with the dep’s `expectedLocalId`.

**Tech Stack:** Flutter/Dart, `flutter_test`, existing `SkillInstallService` / `CliInstallerCommand`, fake FS via `setUpTestAppStorage` patterns.

**Spec:** `docs/superpowers/specs/2026-07-23-skill-acquisition-engine-design.md`

**Model constraint:** Use only Grok 4.5 (`cursor-grok-4.5-high`) for any implementation/review subagents.

---

## File map

| File | Responsibility |
|------|----------------|
| Create: `client/lib/models/skill_acquire_spec.dart` | `SkillAcquireSpec` parse/serialize (`kind`, `package`, `alternatives`, optional `primaryDirectory`) |
| Modify: `client/lib/models/discoverable_team.dart` | `SkillDependencyRef`: optional `id`, `acquire`; `expectedLocalId` rules; carry acquire in `toDiscoverableSkill()` |
| Modify: `client/lib/models/skill.dart` | `DiscoverableSkill`: optional `acquire`, optional `id`; soften required git fields to empty-string defaults for script-only rows |
| Create: `client/lib/services/skill/skill_acquisition_engine.dart` | Kind dispatch, URL safety, host gate, script runner, post-script registration |
| Modify: `client/lib/services/skill/skill_install_service.dart` | Small helpers if needed for “register dir under explicit id” (prefer keep engine-owned upsert via existing `manifest.upsertSkill` / installLocal patterns) |
| Modify: `client/lib/cubits/skill_cubit.dart` | Route `installTeamDependency` / `installFromDiscovery` through engine |
| Modify: `client/lib/app/app_shell.dart` | Wire engine into `SkillCubit` (or lazy-construct inside cubit with injectables) |
| Create: `client/test/models/skill_acquire_spec_test.dart` | Spec parse + expectedLocalId |
| Create: `client/test/services/skill/skill_acquisition_engine_test.dart` | Engine unit tests (fake runner + FS) |
| Modify: existing skill/dep tests if JSON round-trips break | Keep green |

---

### Task 1: `SkillAcquireSpec` + `expectedLocalId` for script deps

**Files:**
- Create: `client/lib/models/skill_acquire_spec.dart`
- Modify: `client/lib/models/discoverable_team.dart` (`SkillDependencyRef`)
- Modify: `client/lib/models/skill.dart` (`DiscoverableSkill`)
- Test: `client/test/models/skill_acquire_spec_test.dart`

- [ ] **Step 1: Write failing tests for acquire parse + expectedLocalId**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/skill_acquire_spec.dart';

void main() {
  test('SkillAcquireSpec parses kind package alternatives primaryDirectory', () {
    final s = SkillAcquireSpec.fromJson({
      'kind': 'script',
      'package': 'https://example.com/install.sh',
      'alternatives': ['script:https://example.com/alt.sh'],
      'primaryDirectory': 'gstack-office-hours',
    });
    expect(s.kind, 'script');
    expect(s.package, 'https://example.com/install.sh');
    expect(s.alternatives, ['script:https://example.com/alt.sh']);
    expect(s.primaryDirectory, 'gstack-office-hours');
  });

  test('script dep expectedLocalId prefers explicit id', () {
    final ref = SkillDependencyRef(
      name: 'gstack',
      id: 'script:custom/gstack',
      acquire: const SkillAcquireSpec(
        kind: 'script',
        package: 'https://example.com/install.sh',
      ),
      repoOwner: '',
      repoName: '',
      repoBranch: 'main',
      directory: '',
    );
    expect(ref.expectedLocalId, 'script:custom/gstack');
  });

  test('script dep expectedLocalId derives from URL host/basename', () {
    final ref = SkillDependencyRef(
      name: 'gstack',
      acquire: const SkillAcquireSpec(
        kind: 'script',
        package: 'https://cdn.example.com/path/install-gstack.sh?x=1',
      ),
      repoOwner: '',
      repoName: '',
      repoBranch: 'main',
      directory: '',
    );
    expect(ref.expectedLocalId, 'script:cdn.example.com/install-gstack.sh');
  });

  test('git-dir dep without acquire keeps owner/name:basename id', () {
    const ref = SkillDependencyRef(
      repoOwner: 'obra',
      repoName: 'superpowers',
      repoBranch: 'main',
      directory: 'skills/brainstorming',
      name: 'Brainstorming',
    );
    expect(ref.expectedLocalId, 'obra/superpowers:brainstorming');
    expect(ref.resolvedAcquire.kind, 'git-dir');
  });
}
```

- [ ] **Step 2: Run test — expect FAIL (types missing)**

Run: `cd client && flutter test test/models/skill_acquire_spec_test.dart --reporter compact`  
Expected: FAIL (library/type not found)

- [ ] **Step 3: Implement models**

`SkillAcquireSpec` (`client/lib/models/skill_acquire_spec.dart`):

```dart
class SkillAcquireSpec {
  const SkillAcquireSpec({
    required this.kind,
    this.package,
    this.alternatives = const [],
    this.primaryDirectory,
  });

  final String kind;
  final String? package;
  final List<String> alternatives;
  final String? primaryDirectory;

  factory SkillAcquireSpec.fromJson(Map<String, Object?> json) { /* mirror ExtensionAcquireSpec */ }

  Map<String, Object?> toJson() => {
    'kind': kind,
    if (package != null) 'package': package,
    if (alternatives.isNotEmpty) 'alternatives': alternatives,
    if (primaryDirectory != null && primaryDirectory!.isNotEmpty)
      'primaryDirectory': primaryDirectory,
  };
}
```

`SkillDependencyRef` changes:
- Add optional `String? id`, `SkillAcquireSpec? acquire`
- Add getter `SkillAcquireSpec get resolvedAcquire => acquire ?? const SkillAcquireSpec(kind: 'git-dir');`
- Update `expectedLocalId`:
  - If `resolvedAcquire.kind == 'script'`: use `id` if non-empty, else parse `package` URL → `script:<host>/<path-basename>` (strip query/fragment)
  - Else existing `owner/name:basename(directory)`
- Update `fromJson` / `toJson` / `==` / `hashCode`
- `toDiscoverableSkill()`: set `key: expectedLocalId`, pass `acquire`, `id`; allow empty repo/directory for script

`DiscoverableSkill` changes:
- Add optional `SkillAcquireSpec? acquire`, `String? id`
- Keep `repoOwner`/`repoName`/`directory` as `String` but allow `''` for script-only; do not break existing required JSON that always has them
- `fromJson`: parse optional acquire/id; default missing strings to `''`

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/models/skill_acquire_spec_test.dart --reporter compact`  
Expected: All tests passed

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/skill_acquire_spec.dart \
  client/lib/models/discoverable_team.dart \
  client/lib/models/skill.dart \
  client/test/models/skill_acquire_spec_test.dart
git commit -m "$(cat <<'EOF'
feat(skills): add SkillAcquireSpec and script expectedLocalId

EOF
)"
```

---

### Task 2: `SkillAcquisitionEngine` — git-dir + script (TDD)

**Files:**
- Create: `client/lib/services/skill/skill_acquisition_engine.dart`
- Create: `client/test/services/skill/skill_acquisition_engine_test.dart`
- Possibly small helper on `SkillInstallService` to upsert a skill for an on-disk dir under an explicit id

- [ ] **Step 1: Write failing engine tests**

Mirror `extension_acquisition_engine_test.dart` style. Cover:

1. `git-dir` calls install delegate once and returns that skill’s id  
2. `script` with unsafe URL never calls runner, `success == false`  
3. `script` with safe URL: runner called with `sh` + curl pipeline; plant one new dir under skills root with `SKILL.md`; result skill id == `expectedLocalId`  
4. unknown kind fails without runner  
5. `script` exit 0 but no new `SKILL.md` → failure  
6. alternatives: primary fails, alternative script succeeds  
7. unsupported host: runner never called  

Use `setUpTestAppStorage` / `tearDownTestAppStorage` from `client/test/support/post_frame_test_harness.dart` for FS. Snapshot skill dir names **before** runner, then in fake runner create `skills/installed/foo/SKILL.md`, then assert primary registration.

Sketch:

```dart
test('script rejects unsafe URL before runner', () async {
  var ran = false;
  final engine = SkillAcquisitionEngine(
    runner: (_) async {
      ran = true;
      return const CliInstallerCommandResult(exitCode: 0);
    },
    isLocalAcquireSupported: () => true,
    installGitDir: (_) async => throw StateError('unused'),
  );
  final result = await engine.install(
    SkillDependencyRef(
      name: 'x',
      acquire: const SkillAcquireSpec(
        kind: 'script',
        package: 'https://evil.example.com/a.sh; rm -rf /',
      ),
      repoOwner: '',
      repoName: '',
      repoBranch: 'main',
      directory: '',
    ),
  );
  expect(ran, isFalse);
  expect(result.success, isFalse);
});
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `cd client && flutter test test/services/skill/skill_acquisition_engine_test.dart --reporter compact`  
Expected: FAIL (engine missing)

- [ ] **Step 3: Implement engine**

`SkillAcquisitionEngine` API sketch:

```dart
typedef SkillInstallRunner =
    Future<CliInstallerCommandResult> Function(CliInstallerCommand command);

typedef SkillGitDirInstaller =
    Future<Skill> Function(DiscoverableSkill discovery);

class SkillAcquireResult {
  const SkillAcquireResult({
    required this.success,
    this.message = '',
    this.skillId,
  });
  final bool success;
  final String message;
  final String? skillId;
}

class SkillAcquisitionEngine {
  SkillAcquisitionEngine({
    SkillInstallRunner? runner,
    required SkillGitDirInstaller installGitDir,
    bool Function()? isLocalAcquireSupported,
    // FS/manifest injectables for post-script registration
  });

  Future<SkillAcquireResult> install(SkillDependencyRef ref);
  Future<SkillAcquireResult> installDiscoverable(DiscoverableSkill d);
}
```

Behavior:
- Resolve acquire via `ref.resolvedAcquire` / discoverable acquire / default `git-dir`
- `git-dir` → `installGitDir(d)` → success with `skill.id`
- `script` → if `!isLocalAcquireSupported()` fail fast; validate URL (copy Extension regex); run sequential primary + alternatives; on success snapshot→scan `skills/installed/` for **new** dirs (present after, absent before) with `SKILL.md`; pick primary per spec (`primaryDirectory` → URL basename match → single new dir → else multi-match fail); upsert `Skill(id: expectedLocalId, directory: chosen, …)`; siblings may get `local:<dir>` via existing unmanaged import if desired (optional in v1 — primary id is required)
- unknown kind → fail

URL safety: duplicate `_isSafeScriptUrl` logic from `ExtensionAcquisitionEngine` (do not extract shared helper in v1 per YAGNI / locked decision).

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/services/skill/skill_acquisition_engine_test.dart --reporter compact`  
Expected: All tests passed

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/skill/skill_acquisition_engine.dart \
  client/test/services/skill/skill_acquisition_engine_test.dart \
  # plus any SkillInstallService helper touched
git commit -m "$(cat <<'EOF'
feat(skills): add SkillAcquisitionEngine for git-dir and script

EOF
)"
```

---

### Task 3: Wire `SkillCubit` + DI/host gate

**Files:**
- Modify: `client/lib/cubits/skill_cubit.dart`
- Modify: `client/lib/app/app_shell.dart` (construct engine with `installGitDir: (d, {overwrite}) => skillInstallService.installFromDiscovery(d, overwrite: overwrite)` and default local runner)
- Test: extend cubit test if one exists; else add focused test under `client/test/cubits/` or engine+cubit integration with fakes

- [ ] **Step 1: Write failing test — `installTeamDependency` with script ref returns `expectedLocalId`**

Also cover: when skill already installed (`expectedLocalId` present / install reports "already exists"), return `expectedLocalId` (not null).

Prefer injecting the engine into `SkillCubit` for testability.

- [ ] **Step 2: Run — expect FAIL / wrong path**

- [ ] **Step 3: Implement wiring**

- Inject `SkillAcquisitionEngine` into `SkillCubit`; **always** route install through the engine
- `installTeamDependency` (preserve soft-fail clone policy):
  1. busy id = `ref.expectedLocalId`
  2. If already installed → return that id immediately
  3. Else `engine.install(ref)`
  4. Success → `_emitInstalled()`; return `result.skillId`
  5. "already exists" (exception or result message) → `_emitInstalled()`; return `expectedLocalId`
  6. Other failures → log + return `null`
- `installFromDiscovery`: busy id = `d.key`; on engine failure set `state.errorMessage` from `result.message` (stderr/stdout summary); on success `_emitInstalled()`
- Discovery primary id alignment: `d.id` if non-empty, else `d.key`, else URL-derived `script:<host>/<basename>` (same rule as `SkillDependencyRef`)
- Forward `overwrite` on the `git-dir` delegate
- **Host gate:** injectable `isLocalAcquireSupported` on the engine. `app_shell` passes `true` for desktop/native local storage and `false` for SSH/non-local backends (same Phase 2 rule as Extension). Do not ship always-`true`.

- [ ] **Step 4: Run focused tests + analyze**

```bash
cd client && flutter test test/models/skill_acquire_spec_test.dart test/services/skill/skill_acquisition_engine_test.dart --reporter compact
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/models/skill_acquire_spec.dart lib/services/skill/skill_acquisition_engine.dart lib/cubits/skill_cubit.dart lib/models/discoverable_team.dart lib/models/skill.dart
```

Expected: tests pass; analyze clean for touched files

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/skill_cubit.dart client/lib/app/app_shell.dart \
  client/test/...
git commit -m "$(cat <<'EOF'
feat(skills): route skill install through SkillAcquisitionEngine

EOF
)"
```

---

### Task 4: Regression + docs touch

**Files:**
- Run broader skill/hub tests that construct `SkillDependencyRef` / `DiscoverableSkill`
- Modify: `docs/workspace-storage-layout.md` — one short note under skills that install may be `git-dir` or `script` acquire (optional, keep minimal)

- [ ] **Step 1: Run regression**

```bash
cd client && flutter test test/services/expert_hub/ test/services/hub_publish/expert_publish_mapper_test.dart test/services/skill/ --reporter compact
```

Fix any broken constructors (new optional params should be backward compatible).

- [ ] **Step 2: Commit if fixes/docs needed**

```bash
git commit -m "$(cat <<'EOF'
test(skills): keep dep install green after acquire wiring

EOF
)"
```

---

## Out of plan (do not implement)

- Production gstack install script URL / member-hub personas  
- `git-bundle` kind  
- Shared engine with Extensions  
- Free-form paste-URL UI  
- SSH remote acquire  

## Execution

After plan approval: **Subagent-Driven** with **Grok 4.5 only**, or inline in this session — ask the user.
