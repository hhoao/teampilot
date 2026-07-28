# Skill Pack Dockerfile-like Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace author-facing `recipe`/`uses` step graphs with Dockerfile-like `install[]` instructions and a typed AST engine; hard-cut all legacy recipe APIs.

**Architecture:** Parse `install` into sealed `SkillPackInstruction` values; `SkillAcquisitionEngine` runs them in order (type dispatch). Packs, deps, and discoverable skills share the same AST; repo/`scriptUrl` fields only synthesize instructions. Session PATH/ENV still come from pack install records.

**Tech Stack:** Dart/Flutter, existing `SkillRepoDiskCacheService` / `SkillInstallService` / `SkillPackInstallStore`, AppStorage FS.

**Spec:** `docs/superpowers/specs/2026-07-28-skill-pack-dockerfile-install-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/skill_pack_instruction.dart` | Sealed instructions + `parseInstall` / path helpers |
| `client/lib/models/skill_pack.dart` | `id`/`name`/`description`/`labels`/`install`; drop recipe/skills/repo* |
| `client/lib/models/skill.dart` | `DiscoverableSkill`: `install` / `scriptUrl`; `resolvedInstall` |
| `client/lib/models/discoverable_team.dart` | `SkillDependencyRef`: same; drop `recipe` |
| **Delete** `client/lib/models/skill_install_recipe.dart` | Legacy recipe IR |
| `client/lib/services/skill/acquire/skill_acquire_context.dart` | syncRoot, workdir, shell, path/env exports; no `$PACK_*` |
| `client/lib/services/skill/acquire/skill_instruction_runner.dart` | Optional thin runner if engine grows too large |
| `client/lib/services/skill/skill_acquisition_engine.dart` | Execute instruction list; drop `uses` handler map |
| **Delete** `client/lib/services/skill/acquire/skill_step_handler.dart` | Old handler typedef |
| `client/lib/services/skill/skill_pack_registry.dart` | gstack `install` only |
| `client/lib/services/skill/skill_pack_install_store.dart` | Persist `syncRoot` instead of `packBin`; pathExports absolute |
| `skill-packs/gstack/pack.json` | Canonical new shape |
| `skill-packs/README.md` | Point at new spec |
| Tests under `client/test/models/` + `client/test/services/skill/` | Replace recipe tests |

**Windows `SHELL` default:** `['cmd', '/C']` when `Platform.isWindows`, else `['sh', '-c']`.

---

### Task 1: Instruction AST + parse tests

**Files:**
- Create: `client/lib/models/skill_pack_instruction.dart`
- Create: `client/test/models/skill_pack_instruction_test.dart`
- Later delete: `client/lib/models/skill_install_recipe.dart` (Task 7)

- [ ] **Step 1: Write failing parse tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill_pack_instruction.dart';

void main() {
  test('parses gstack-shaped install', () {
    final list = parseSkillPackInstall([
      {'FROM': 'garrytan/gstack@main'},
      {'SKILLS': '*'},
      {'RUN': './setup', 'optional': true},
      {'PATH': 'bin'},
    ]);
    expect(list, hasLength(4));
    expect(list[0], isA<FromInstruction>());
    final from = list[0] as FromInstruction;
    expect(from.owner, 'garrytan');
    expect(from.name, 'gstack');
    expect(from.branch, 'main');
    expect((list[1] as SkillsInstruction).includeAll, isTrue);
    expect((list[2] as RunInstruction).optional, isTrue);
    expect((list[3] as PathInstruction).entries, ['bin']);
  });

  test('SKILLS object include/exclude', () {
    final s = parseSkillPackInstall([
      {
        'SKILLS': {
          'include': ['*'],
          'exclude': ['qa'],
        },
      },
    ]).single as SkillsInstruction;
    expect(s.includeAll, isTrue);
    expect(s.exclude, ['qa']);
  });

  test('rejects dual keys and unknown keys', () {
    expect(
      () => parseSkillPackInstall([
        {'FROM': 'a/b', 'RUN': 'x'},
      ]),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parseSkillPackInstall([
        {'LINK': 'bin'},
      ]),
      throwsA(isA<FormatException>()),
    );
  });

  test('FROM defaults branch to main', () {
    final from =
        parseSkillPackInstall([
              {'FROM': 'owner/repo'},
            ]).single
            as FromInstruction;
    expect(from.branch, 'main');
  });
}
```

- [ ] **Step 2: Run test — expect FAIL** (library missing)

```bash
cd client && flutter test test/models/skill_pack_instruction_test.dart
```

- [ ] **Step 3: Implement sealed instructions + `parseSkillPackInstall`**

Implement in `skill_pack_instruction.dart`:

- Sealed hierarchy: `FromInstruction`, `ScriptInstruction`, `CopyInstruction`, `SkillsInstruction`, `ShellInstruction`, `RunInstruction`, `WorkdirInstruction`, `PathInstruction`, `EnvInstruction`
- `parseSkillPackInstall(List<Object?> raw)` — exactly one instruction key per map; `FormatException` with `install[$i] ...` messages
- `SkillsInstruction` fields (locked): `includeAll` (bool), `include` (`List<String>`),
  `exclude` (`List<String>`). When `includeAll`, `include` is empty; when whitelist,
  `includeAll == false` and `include` holds dir names.
- `FromInstruction.parseRef("owner/repo@branch")`
- Helpers: `resolveUnderRoot({required String root, required String relative})` rejecting absolute and `..` escape (pure functions, unit-testable)

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/models/skill_pack_instruction_test.dart
```

- [ ] **Step 5: Commit** (only if user asked to commit)

```bash
git add client/lib/models/skill_pack_instruction.dart client/test/models/skill_pack_instruction_test.dart
git commit -m "$(cat <<'EOF'
feat(skills): add Dockerfile-like install instruction AST

EOF
)"
```

---

### Task 2: SkillPack model + disk gstack pack

**Files:**
- Modify: `client/lib/models/skill_pack.dart`
- Modify: `skill-packs/gstack/pack.json`
- Modify: `client/lib/services/skill/skill_pack_registry.dart`
- Modify: `client/test/services/skill/skill_pack_registry_test.dart` (**both** tests)

**Compile note:** After this task, anything still importing `SkillPack.recipe` /
`skills` / `SkillInstallRecipe` will not analyze clean until Tasks 4–5 rewrite
the engine and deps. Do not leave shims; land Task 2+4+5 in one implementer
session (or one PR branch) before expecting `flutter analyze` green.

- [ ] **Step 1: Rewrite the entire registry test file**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill_pack.dart';
import 'package:teampilot/models/skill_pack_instruction.dart';
import 'package:teampilot/services/skill/skill_pack_registry.dart';

void main() {
  test('builtin gstack pack matches skill-packs/gstack/pack.json', () {
    final packJsonPath = File(
      '${Directory.current.path}/../skill-packs/gstack/pack.json',
    );
    expect(packJsonPath.existsSync(), isTrue, reason: packJsonPath.path);
    final disk = SkillPack.fromJson(
      (jsonDecode(packJsonPath.readAsStringSync()) as Map)
          .cast<String, Object?>(),
    );
    final builtin = kGstackSkillPack;
    expect(builtin.id, disk.id);
    expect(builtin.name, disk.name);
    expect(builtin.install, disk.install);
  });

  test('SkillPackRegistry resolves garrytan/gstack install shape', () {
    final pack = SkillPackRegistry().byId('garrytan/gstack');
    expect(pack, isNotNull);
    expect(pack!.install, isNotEmpty);
    expect(pack.install.first, isA<FromInstruction>());
    expect(
      pack.install.whereType<SkillsInstruction>(),
      isNotEmpty,
    );
    expect(pack.install.whereType<PathInstruction>(), isNotEmpty);
  });
}
```

- [ ] **Step 2: Rewrite `pack.json`**

```json
{
  "id": "garrytan/gstack",
  "name": "gstack",
  "install": [
    { "FROM": "garrytan/gstack@main" },
    { "SKILLS": "*" },
    { "RUN": "./setup", "optional": true },
    { "PATH": "bin" }
  ]
}
```

- [ ] **Step 3: Change `SkillPack`**

- Fields: `id`, `name`, `description?`, `labels`, `install`
- Remove: `repoOwner`, `repoName`, `repoBranch`, `recipe`, `skills`, `SkillPackEntry`, `_defaultPackRecipe`, `entryById`
- `fromJson` requires non-empty `install`; parse via `parseSkillPackInstall`
- Equality includes `install`

- [ ] **Step 4: Update `kGstackSkillPack` to mirror disk `install` only**

- [ ] **Step 5: Run**

```bash
cd client && flutter test test/services/skill/skill_pack_registry_test.dart
```

Expected: PASS (may need `--no-pub` if analyzer noise from other broken files; prefer running after Task 4 stubs if the test target pulls engine)

- [ ] **Step 6: Commit** (if requested)

---

### Task 3: Acquire context without `$` vars

**Files:**
- Rewrite: `client/lib/services/skill/acquire/skill_acquire_context.dart`
- Add tests in `client/test/services/skill/skill_acquire_context_test.dart` (create)

- [ ] **Step 1: Failing tests for workdir + path join**

```dart
test('resolveRelative stays under sync root', () {
  final ctx = SkillAcquireContext(overwrite: false, expectedSkillId: 'x')
    ..syncRoot = '/tmp/sync';
  expect(ctx.resolveRelative('bin'), '/tmp/sync/bin');
  expect(() => ctx.resolveRelative('/etc/passwd'), throwsA(isA<StateError>()));
  expect(() => ctx.resolveRelative('../outside'), throwsA(isA<StateError>()));
});

test('WORKDIR affects resolveWorkdirRelative', () {
  final ctx = SkillAcquireContext(overwrite: false, expectedSkillId: 'x')
    ..syncRoot = '/tmp/sync'
    ..workdir = 'nested';
  expect(ctx.resolveWorkdirRelative('out.txt'), '/tmp/sync/nested/out.txt');
});
```

- [ ] **Step 2: Implement context**

- Keep: `overwrite`, `expectedSkillId`, `pack`, `syncRoot`, `installedSkillIds`, `pathExports`, `envExports`
- Add: `workdir` (relative segment or absolute under sync), `shell` (`List<String>`, default platform shell)
- Remove: `vars`, `resolve($TEMPLATE)`, `packRoot`, `packBin`, `applyExports(SkillInstallExports)`
- Add: `appendPathExports(Iterable<String> absPaths)`, `mergeEnv(Map<String,String>)`
- Path helpers as above; use `fs.pathContext` when available or `package:path`

- [ ] **Step 3: Tests PASS**

---

### Task 4: Engine executes instructions (core)

**Files:**
- Rewrite: `client/lib/services/skill/skill_acquisition_engine.dart`
- Delete: `client/lib/services/skill/acquire/skill_step_handler.dart` (when unused)
- Rewrite: `client/test/services/skill/skill_acquisition_engine_test.dart`

- [ ] **Step 1: Replace engine tests** (fake deps: repoCache, installGitDir/registerDirectory, runner, fs)

Cover at minimum:

1. `FROM` + `SKILLS: ["review"]` registers `{packId}:review` when `ctx.pack` set
2. `FROM` + `SKILLS: "*"` discovers dirs with `SKILL.md` under sync (inject list or fake FS)
3. `SKILLS` include/exclude
4. Single-dep expected id: pack null, `expectedSkillId: 'my-id'`, one dir → registers as `my-id`
5. `RUN` optional failure → success + PATH still applied
6. `SHELL` + string `RUN` → runner sees shell + `-c` + script
7. Exec `RUN: ["./setup"]` → runner sees `./setup` without shell
8. `PATH: "bin"` → `pathExports` contains `syncRoot/bin`
9. `COPY` then file exists at workdir destination
10. Reject install that uses workspace op before `FROM`

- [ ] **Step 2: Implement `runInstall(List<SkillPackInstruction> install, SkillAcquireContext ctx)`**

Dispatch:

| Instruction | Action |
|-------------|--------|
| `From` | `_repoCache.ensureSynced`; set `ctx.syncRoot`; reset workdir to sync root |
| `Script` | Existing script-run logic (HTTPS + register); set workspace if applicable; honor `optional` |
| `Copy` | `from` under sync root; `to` under workdir; copy file/dir via FS |
| `Skills` | Discover direct child dirs with `SKILL.md`; apply include/exclude; register each |
| `Shell` | set `ctx.shell` |
| `Run` | host gate; build command; on failure if optional → warn continue else fail |
| `Workdir` | set `ctx.workdir` relative under sync |
| `Path` | resolve each entry under **sync root** (spec: PATH relative sync); append abs paths |
| `Env` | merge into `ctx.envExports` (resolve relative values only if syncRoot set) |

Reuse existing `_installGitDir` / `_registerDirectory` / `_runner` / host gate.

Pack flow: `installPack` loads `pack.install`, sets `ctx.pack`, runs, writes
`SkillPackInstallStore` with `skillIds` from **`ctx.installedSkillIds`** (not a
static pack catalog), `pathExports`, `envExports`, `syncRoot`.

Dep with `packId`: run the whole pack `install`, then require
`ctx.installedSkillIds` contains `expectedSkillId` (bind); do not pre-check a
removed `pack.skills` list.

- [ ] **Step 3: Tests PASS**

```bash
cd client && flutter test test/services/skill/skill_acquisition_engine_test.dart
```

---

### Task 5: resolvedInstall sugar on deps / discoverable skills

**Files:**
- Modify: `client/lib/models/skill.dart` (`DiscoverableSkill`)
- Modify: `client/lib/models/discoverable_team.dart` (`SkillDependencyRef`)
- Rewrite: `client/test/models/skill_acquire_spec_test.dart` → rename to `skill_resolved_install_test.dart` if clearer
- Grep/fix any `recipe:` / `resolvedRecipe` call sites

- [ ] **Step 1: Failing tests**

```dart
test('repo fields synthesize FROM + SKILLS', () {
  final ref = SkillDependencyRef(
    id: 'owner/repo:dir',
    directory: 'dir',
    repoOwner: 'owner',
    repoName: 'repo',
    repoBranch: 'main',
  );
  final install = ref.resolvedInstall!;
  expect(install[0], isA<FromInstruction>());
  final skills = install[1] as SkillsInstruction;
  expect(skills.includeAll, isFalse);
  expect(skills.include, ['dir']);
});

test('scriptUrl synthesizes SCRIPT', () {
  final ref = SkillDependencyRef(
    id: 'script:example.com/x',
    scriptUrl: 'https://example.com/x',
    directory: 'skill-dir',
  );
  final script = ref.resolvedInstall!.single as ScriptInstruction;
  expect(script.url, 'https://example.com/x');
  expect(script.id, 'script:example.com/x');
  expect(script.primaryDirectory, 'skill-dir');
});

test('packId yields null resolvedInstall (engine loads pack)', () {
  final ref = SkillDependencyRef(
    id: 'garrytan/gstack:review',
    packId: 'garrytan/gstack',
    directory: 'review',
  );
  expect(ref.resolvedInstall, isNull);
});
```

- [ ] **Step 2: Implement**

- Remove `recipe` / `resolvedRecipe`
- Add optional `install` (`List<SkillPackInstruction>?`) and `scriptUrl`
- `resolvedInstall` per spec order (packId → null; else install; else repo sugar; else scriptUrl sugar)
- `fromJson`/`toJson`: accept `install` array; accept `scriptUrl`; if legacy
  `recipe` key is present → **throw** `FormatException` (hard cut, fail loud)
- Update `expectedLocalId` to not scan recipe steps; use `scriptUrl` helper for script ids

- [ ] **Step 3: Wire engine `ensureSkill` / dep install to `resolvedInstall` + pack registry**

- [ ] **Step 4: Tests PASS + fix compile errors across cubit tests**

---

### Task 6: Pack install store + session PATH/ENV

**Files:**
- Modify: `client/lib/services/skill/skill_pack_install_store.dart`
- Modify: `client/lib/services/session/session_lifecycle_service.dart` (both launch env sites ~562 and ~701)
- Add/extend store tests

- [ ] **Step 1:** Change `SkillPackInstallRecord`: add `syncRoot`; **remove `packBin`**. Update JSON read/write.
- [ ] **Step 2:** Add `envExportsForSkills(Iterable<String> skillIds)` mirroring `pathExportsForSkills` (merge maps; later pack wins on key collision, or first-wins — pick first-wins and document in store dartdoc).
- [ ] **Step 3:** In `session_lifecycle_service.dart`, after `prependPath`, also merge pack `envExports` into `launchEnv` (pack keys override only when non-empty; do not clobber unrelated env). Same at both call sites.
- [ ] **Step 4:** Tests:
  - Record round-trip with `syncRoot` + `envExports`
  - `pathExportsForSkills` / `envExportsForSkills` for overlapping skill ids
  - `prependPath` still puts pack paths first
- [ ] **Step 5:** Engine write path uses absolute `pathExports` from context; no `packBin`.

---

### Task 7: Delete legacy recipe + purge references

**Files:**
- Delete: `client/lib/models/skill_install_recipe.dart`
- Delete: `client/test/models/skill_install_recipe_test.dart`
- Delete: `client/lib/services/skill/acquire/skill_step_handler.dart` (if still present)
- Update: `skill-packs/README.md`
- Update: note at top of `docs/superpowers/specs/2026-07-24-skill-acquire-step-graph-design.md` — superseded by 2026-07-28 design for author protocol
- Grep entire repo for `SkillInstallRecipe`, `uses:`, `fs.materialize`, `register-pack`, `SkillPackEntry`, `resolvedRecipe`, `$PACK_BIN`

- [ ] **Step 1:** `rg` clean — zero hits on deleted symbols (except historical docs)
- [ ] **Step 2:**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/models/skill_pack_instruction_test.dart test/services/skill/skill_pack_registry_test.dart test/services/skill/skill_acquisition_engine_test.dart test/models/skill_acquire_spec_test.dart
```

- [ ] **Step 3:** Broader skill-related tests if any fail — fix until green

```bash
cd client && flutter test --exclude-tags integration
```

(If full suite too slow in agent session, run skill + cubit skill tests first, then full.)

- [ ] **Step 4:** Commit (if requested)

---

## Done when

- [ ] gstack `pack.json` is the short `install` form from the spec
- [ ] No `SkillInstallRecipe` / `uses` in code
- [ ] Engine tests cover SKILLS forms, optional RUN, SHELL, PATH, COPY, scriptUrl sugar
- [ ] Session still gets pack PATH **and** ENV exports
- [ ] README + superseded note on old step-graph spec

## Execution note

Prefer **subagent-driven-development** per task; do not start Task 7 until Tasks 1–6 compile and focused tests pass.
