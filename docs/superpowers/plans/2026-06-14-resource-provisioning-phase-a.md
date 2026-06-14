# Resource Provisioning Phase A — Core + Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make enabled skills take effect identically in personal, native, and mixed session modes by replacing push/staging provisioning with a declarative, launch-time, idempotent materializer — built on a reusable core that plugins and MCP will later adopt.

**Architecture:** A pure `ResourceResolver` maps a `ResourceScope` (personal | team) to the effective set of enabled resources read from the user's stored enable lists (`ProjectProfile.skillIds` / `TeamConfig.skillIds`) against the installed catalog. A `ResourceMaterializer` idempotently reconciles one resource kind into the leaf CONFIG_DIR by symlinking (junction → symlink → copy fallback) straight to the global library, removing stale entries. A thin per-CLI `ResourceCapability` declares supported kinds and their on-disk subdir/representation. `ResourceProvisioningService` ties resolve→materialize and is the single launch entry point, replacing the per-mode `provision*FromTeam`/`provision*FromProject` methods.

**Tech Stack:** Dart / Flutter, `flutter_bloc`, the project's `Filesystem` abstraction (`AppStorage.fs`), the `CliToolRegistry` capability system, `package:test` + `flutter_test`.

**Scope (this plan):** Core abstractions + **skills only**, end-to-end across all three modes, plus removal of the old skills provisioning path. **Out of scope (follow-on plans):** plugins (per-CLI manifest mirroring via `CliPluginRegistryService`) and MCP (JSON merge + extension contributions + teammate-bus injection). They reuse this plan's core unchanged.

**Conventions reminder:** Run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` before claiming done. Diagnostics → `appLogger`; user-facing strings → l10n. State via cubits only. No raw paths in UI; all IO via `Filesystem`. Commit after every passing task.

---

## File Structure

**Create:**
- `client/lib/services/resource/resource_kind.dart` — `ResourceKind` enum, `ResourceRef`, `EffectiveResourceSet`, `ResourceCatalog`.
- `client/lib/services/resource/resource_scope.dart` — sealed `ResourceScope` (`PersonalResourceScope`, `TeamResourceScope`).
- `client/lib/services/resource/resource_resolver.dart` — pure scope→effective-set resolver.
- `client/lib/services/resource/link_strategy.dart` — symlink→copy link helper.
- `client/lib/services/resource/resource_materializer.dart` — idempotent per-kind reconcile.
- `client/lib/services/resource/resource_provisioning_service.dart` — resolve→materialize orchestration + `ResourceProvisionResult`.
- `client/lib/services/cli/registry/capabilities/resource_capability.dart` — `ResourceCapability` interface + `ResourceRepresentation` enum.
- `client/lib/services/cli/registry/resources/default_resource_capability.dart` — shared default impl (subdir = kind name; skills only).
- `client/lib/services/cli/registry/resources/opencode_resource_capability.dart` — opencode override (skills subdir = `skill`).
- Test files mirroring each under `client/test/services/resource/` and `client/test/services/cli/registry/`.

**Modify:**
- The five launch-supported tool definitions in `client/lib/services/cli/registry/tools/` — add the `resource` capability field + list entry.
- `client/lib/services/provider/config_profile_service.dart` — inject a skills-catalog loader; replace skill provisioning in `ensureStandaloneSessionProfile` and `ensureSessionProfile` with `ResourceProvisioningService`.
- `client/lib/services/cli/cli_data_layout.dart` — delete `provisionStandaloneSessionSkillsFromProject`, `provisionMemberSkillsFromTeam`, and the skills-linking part of `ensureMemberInheritsTeam` / `ensureStandaloneSessionInheritsProject` (keep agents inheritance).
- `client/lib/cubits/project_profile_cubit.dart` — drop `_syncSkills` (persist `skillIds` only).
- `client/lib/cubits/team/team_resource_sync_service.dart` — drop `syncSkills` skill-linking.
- Delete `client/lib/services/skill/project_skill_linker_service.dart` and the skill portion of `team_skill_linker_service.dart` (and their tests) once nothing references them.

---

## Task 0: Reproduce the bug (root-cause TDD anchor)

Per the spec, confirm the mechanism with evidence before redesigning. This test asserts the END state we want; it should FAIL today (skills not present in the personal leaf CONFIG_DIR after launch prep).

**Files:**
- Test: `client/test/services/provider/personal_skill_provisioning_repro_test.dart`

- [ ] **Step 1: Write the failing characterization test**

```dart
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('personal launch prep links enabled skill into leaf CONFIG_DIR', () async {
    final fs = AppStorage.fs;
    final root = AppStorage.paths.basePath;
    final layout = CliDataLayout(teampilotRoot: root, fs: fs);

    // Install one skill into the global library.
    final skillsRoot = AppPaths.skillsDirForTeampilotRoot(root);
    final srcDir = fs.pathContext.join(skillsRoot, 'demo-skill');
    await fs.ensureDir(srcDir);
    await fs.writeString(
      fs.pathContext.join(srcDir, 'SKILL.md'),
      '# demo',
    );

    final service = ConfigProfileService(
      basePath: root,
      fs: fs,
      layout: layout,
      loadInstalledSkills: () async => [
        Skill(
          id: 'demo',
          name: 'Demo',
          description: 'd',
          directory: 'demo-skill',
          installedAt: 0,
          updatedAt: 0,
        ),
      ],
    );

    const profile = ProjectProfile(
      projectId: 'p1',
      cli: CliTool.flashskyai,
      skillIds: ['demo'],
    );

    await service.prepareProjectLaunch(
      projectId: 'p1',
      sessionId: 's1',
      profile: profile,
    );

    final leafSkillsDir = fs.pathContext.join(
      layout.standaloneProjectSessionToolDir('p1', 's1', 'flashskyai'),
      'skills',
    );
    final entries = await fs.listDir(leafSkillsDir);
    expect(
      entries.map((e) => e.name),
      contains('demo-skill'),
      reason: 'enabled skill must be materialized into the leaf CONFIG_DIR',
    );
  });
}
```

- [ ] **Step 2: Run it — expect FAIL**

Run: `cd client && flutter test test/services/provider/personal_skill_provisioning_repro_test.dart`
Expected: FAIL. Likely a compile error first (`loadInstalledSkills` not yet a `ConfigProfileService` param) — that itself proves the launch path has no installed-catalog input today, which is the root cause. Note the failure in the commit body.

- [ ] **Step 3: Commit the red test**

```bash
git add client/test/services/provider/personal_skill_provisioning_repro_test.dart
git commit -m "test: red repro for skills not effective in personal mode

Confirms root cause: the launch path (ConfigProfileService) has no
installed-skill catalog input, so personal/mixed leaf CONFIG_DIRs are
never populated from the enabled skillIds."
```

This test is wired green by Task 8.

---

## Task 1: Resource domain model

**Files:**
- Create: `client/lib/services/resource/resource_kind.dart`
- Test: `client/test/services/resource/resource_kind_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/resource/resource_kind.dart';

void main() {
  test('EffectiveResourceSet.of returns the kind list or empty', () {
    const ref = ResourceRef(
      id: 'demo',
      linkName: 'demo-skill',
      sourceDir: '/lib/skills/demo-skill',
    );
    const set = EffectiveResourceSet({
      ResourceKind.skill: [ref],
    });
    expect(set.of(ResourceKind.skill), [ref]);
    expect(set.of(ResourceKind.plugin), isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/resource/resource_kind_test.dart`
Expected: FAIL — `resource_kind.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
/// The three kinds of linkable resource a CLI session can consume.
enum ResourceKind { skill, plugin, mcp }

/// One enabled resource, resolved to its canonical on-disk source.
class ResourceRef {
  const ResourceRef({
    required this.id,
    required this.linkName,
    required this.sourceDir,
  });

  /// Catalog id (used for diagnostics / warnings).
  final String id;

  /// Basename to create under `<configDir>/<kindSubdir>/`.
  final String linkName;

  /// Absolute path to the canonical install to link to
  /// (e.g. `<teampilotRoot>/skills/installed/<dir>`).
  final String sourceDir;

  @override
  bool operator ==(Object other) =>
      other is ResourceRef &&
      other.id == id &&
      other.linkName == linkName &&
      other.sourceDir == sourceDir;

  @override
  int get hashCode => Object.hash(id, linkName, sourceDir);
}

/// Effective enabled resources for one launch scope, grouped by kind.
class EffectiveResourceSet {
  const EffectiveResourceSet(this.byKind);

  final Map<ResourceKind, List<ResourceRef>> byKind;

  List<ResourceRef> of(ResourceKind kind) => byKind[kind] ?? const [];
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/services/resource/resource_kind_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/resource/resource_kind.dart client/test/services/resource/resource_kind_test.dart
git commit -m "feat: add resource domain model (ResourceKind/Ref/EffectiveResourceSet)"
```

---

## Task 2: Resource scope + catalog

**Files:**
- Create: `client/lib/services/resource/resource_scope.dart`
- Test: covered indirectly by the resolver test in Task 3 (this task is pure data; commit with Task 3).

- [ ] **Step 1: Write the implementation**

```dart
import 'package:path/path.dart' as p;

import '../../models/project_profile.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';

/// Describes WHERE a launch is materializing resources to, and WHICH stored
/// enable lists are authoritative for it. Mode lives here and nowhere else.
sealed class ResourceScope {
  const ResourceScope();
}

/// Personal / simple mode: enable lists come from the project's [ProjectProfile].
class PersonalResourceScope extends ResourceScope {
  const PersonalResourceScope({required this.profile});
  final ProjectProfile profile;
}

/// Native or mixed team mode: enable lists come from [TeamConfig].
/// Members inherit the team set (there is no per-member skill list), so
/// [member] is carried only for future per-kind needs.
class TeamResourceScope extends ResourceScope {
  const TeamResourceScope({required this.team, this.member});
  final TeamConfig team;
  final TeamMemberConfig? member;
}

/// Installed catalogs + source roots needed to turn enabled ids into refs.
/// Skills only for now; plugin/mcp fields are added by their follow-on plans.
class ResourceCatalog {
  const ResourceCatalog({
    required this.skills,
    required this.skillsRoot,
    required this.pathContext,
  });

  final List<Skill> skills;
  final String skillsRoot;
  final p.Context pathContext;
}
```

- [ ] **Step 2: Verify it analyzes**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/resource/resource_scope.dart`
Expected: No errors (warnings about unused `member` are acceptable; it is part of the public API).

(Committed together with Task 3.)

---

## Task 3: ResourceResolver (pure, no IO)

**Files:**
- Create: `client/lib/services/resource/resource_resolver.dart`
- Test: `client/test/services/resource/resource_resolver_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/resource/resource_kind.dart';
import 'package:teampilot/services/resource/resource_resolver.dart';
import 'package:teampilot/services/resource/resource_scope.dart';

Skill _skill(String id, String dir) => Skill(
      id: id,
      name: id,
      description: '',
      directory: dir,
      installedAt: 0,
      updatedAt: 0,
    );

void main() {
  final catalog = ResourceCatalog(
    skills: [_skill('a', 'skill-a'), _skill('b', 'skill-b')],
    skillsRoot: '/root/skills/installed',
    pathContext: p.posix,
  );
  const resolver = ResourceResolver();

  test('personal scope resolves enabled skillIds to refs', () {
    const scope = PersonalResourceScope(
      profile: ProjectProfile(projectId: 'p', skillIds: ['a']),
    );
    final set = resolver.resolve(scope: scope, catalog: catalog);
    final refs = set.of(ResourceKind.skill);
    expect(refs.length, 1);
    expect(refs.single.linkName, 'skill-a');
    expect(refs.single.sourceDir, '/root/skills/installed/skill-a');
  });

  test('team scope resolves from team.skillIds; unknown ids are dropped', () {
    final scope = TeamResourceScope(
      team: const TeamConfig(id: 't', name: 'T', skillIds: ['b', 'missing']),
    );
    final set = resolver.resolve(scope: scope, catalog: catalog);
    expect(set.of(ResourceKind.skill).map((r) => r.linkName), ['skill-b']);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/resource/resource_resolver_test.dart`
Expected: FAIL — `resource_resolver.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'resource_kind.dart';
import 'resource_scope.dart';

/// Computes the effective enabled resource set for a scope, purely in memory.
/// No filesystem access — inheritance/selection is just reading the right
/// stored enable list and filtering against the installed catalog.
class ResourceResolver {
  const ResourceResolver();

  EffectiveResourceSet resolve({
    required ResourceScope scope,
    required ResourceCatalog catalog,
  }) {
    return EffectiveResourceSet({
      ResourceKind.skill: _skills(scope, catalog),
    });
  }

  List<ResourceRef> _skills(ResourceScope scope, ResourceCatalog catalog) {
    final ids = switch (scope) {
      PersonalResourceScope(:final profile) => profile.skillIds,
      TeamResourceScope(:final team) => team.skillIds,
    };
    if (ids.isEmpty) return const [];
    final byId = {for (final s in catalog.skills) s.id: s};
    final refs = <ResourceRef>[];
    for (final id in ids) {
      final skill = byId[id];
      if (skill == null) continue; // unknown / uninstalled — dropped
      refs.add(ResourceRef(
        id: skill.id,
        linkName: skill.directory,
        sourceDir: catalog.pathContext.join(catalog.skillsRoot, skill.directory),
      ));
    }
    return refs;
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/services/resource/resource_resolver_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/resource/resource_scope.dart client/lib/services/resource/resource_resolver.dart client/test/services/resource/resource_resolver_test.dart
git commit -m "feat: add ResourceScope and pure ResourceResolver (skills)"
```

---

## Task 4: LinkStrategy

**Files:**
- Create: `client/lib/services/resource/link_strategy.dart`
- Test: `client/test/services/resource/link_strategy_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/resource/link_strategy.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('link creates an accessible entry (symlink or copy fallback)', () async {
    final fs = AppStorage.fs;
    final tmp = await fs.createTempDir(prefix: 'link_test_');
    final src = fs.pathContext.join(tmp, 'src');
    final dst = fs.pathContext.join(tmp, 'dst');
    await fs.ensureDir(src);
    await fs.writeString(fs.pathContext.join(src, 'f.txt'), 'hello');

    final strategy = LinkStrategy(fs);
    await strategy.link(source: src, target: dst);

    final read = await fs.readString(fs.pathContext.join(dst, 'f.txt'));
    expect(read, 'hello');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/resource/link_strategy_test.dart`
Expected: FAIL — `link_strategy.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import '../io/filesystem.dart';

/// Centralized "make `target` point at `source`" strategy:
/// junction/symlink first (O(1)), copy as a fallback when the platform or
/// transport refuses symlinks (Windows without privilege, SFTP).
class LinkStrategy {
  const LinkStrategy(this._fs);

  final Filesystem _fs;

  /// Returns true if a symlink was created, false if it fell back to copy.
  Future<bool> link({
    required String source,
    required String target,
  }) async {
    final linked = await _fs.createSymlink(target: source, linkPath: target);
    if (linked) return true;
    await _fs.copyTree(source: source, destination: target);
    return false;
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/services/resource/link_strategy_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/resource/link_strategy.dart client/test/services/resource/link_strategy_test.dart
git commit -m "feat: add centralized LinkStrategy (symlink -> copy fallback)"
```

---

## Task 5: ResourceMaterializer (idempotent reconcile)

**Files:**
- Create: `client/lib/services/resource/resource_materializer.dart`
- Test: `client/test/services/resource/resource_materializer_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/resource/resource_kind.dart';
import 'package:teampilot/services/resource/resource_materializer.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('reconcile adds missing, removes stale, and is idempotent', () async {
    final fs = AppStorage.fs;
    final tmp = await fs.createTempDir(prefix: 'mat_test_');
    final srcA = fs.pathContext.join(tmp, 'srcA');
    final srcB = fs.pathContext.join(tmp, 'srcB');
    await fs.ensureDir(srcA);
    await fs.ensureDir(srcB);
    final kindDir = fs.pathContext.join(tmp, 'cfg', 'skills');

    final materializer = ResourceMaterializer(fs: fs);

    // 1. Add A.
    var result = await materializer.reconcile(
      kindDir: kindDir,
      desired: [ResourceRef(id: 'a', linkName: 'a', sourceDir: srcA)],
    );
    expect(result.errors, isEmpty);
    expect((await fs.listDir(kindDir)).map((e) => e.name), ['a']);

    // 2. Swap to B — A becomes stale and must be removed.
    await materializer.reconcile(
      kindDir: kindDir,
      desired: [ResourceRef(id: 'b', linkName: 'b', sourceDir: srcB)],
    );
    expect((await fs.listDir(kindDir)).map((e) => e.name), ['b']);

    // 3. Idempotent: same desired set => no errors, same content.
    final again = await materializer.reconcile(
      kindDir: kindDir,
      desired: [ResourceRef(id: 'b', linkName: 'b', sourceDir: srcB)],
    );
    expect(again.errors, isEmpty);
    expect((await fs.listDir(kindDir)).map((e) => e.name), ['b']);
  });

  test('reconcile records an error when source is missing', () async {
    final fs = AppStorage.fs;
    final tmp = await fs.createTempDir(prefix: 'mat_err_');
    final kindDir = fs.pathContext.join(tmp, 'skills');
    final result = await ResourceMaterializer(fs: fs).reconcile(
      kindDir: kindDir,
      desired: [
        ResourceRef(
          id: 'gone',
          linkName: 'gone',
          sourceDir: fs.pathContext.join(tmp, 'does-not-exist'),
        ),
      ],
    );
    expect(result.errors.single, contains('gone'));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/resource/resource_materializer_test.dart`
Expected: FAIL — `resource_materializer.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import '../../utils/logger.dart';
import '../io/filesystem.dart';
import 'link_strategy.dart';
import 'resource_kind.dart';

/// Result of reconciling one kind directory.
class MaterializeResult {
  const MaterializeResult({this.linked = const [], this.errors = const []});
  final List<String> linked;
  final List<String> errors;
}

/// The only component that touches disk. Reconciles `<kindDir>` so it contains
/// exactly the `desired` refs: removes stale entries, links missing ones, and
/// leaves correct symlinks untouched (idempotent).
class ResourceMaterializer {
  ResourceMaterializer({required Filesystem fs, LinkStrategy? linkStrategy})
      : _fs = fs,
        _link = linkStrategy ?? LinkStrategy(fs);

  final Filesystem _fs;
  final LinkStrategy _link;

  Future<MaterializeResult> reconcile({
    required String kindDir,
    required List<ResourceRef> desired,
  }) async {
    final path = _fs.pathContext;
    await _fs.ensureDir(kindDir);

    final existing = await _fs.listDir(kindDir);
    final desiredByName = {for (final r in desired) r.linkName: r};

    // Remove stale entries.
    for (final entry in existing) {
      if (!desiredByName.containsKey(entry.name)) {
        await _fs.removeRecursive(path.join(kindDir, entry.name));
      }
    }
    final existingNames = {
      for (final e in existing)
        if (desiredByName.containsKey(e.name)) e.name,
    };

    final linked = <String>[];
    final errors = <String>[];
    for (final ref in desired) {
      final target = path.join(kindDir, ref.linkName);
      final src = await _fs.stat(ref.sourceDir);
      if (!src.isDirectory) {
        errors.add('${ref.id}: source missing at ${ref.sourceDir}');
        continue;
      }
      if (existingNames.contains(ref.linkName)) {
        // Present already. Keep if a symlink points at the right source;
        // otherwise rebuild (stale target, or a prior copy that may be stale).
        final current = await _fs.readSymlinkTarget(target);
        if (current == ref.sourceDir) {
          linked.add(ref.linkName);
          continue;
        }
        await _fs.removeRecursive(target);
      }
      try {
        await _link.link(source: ref.sourceDir, target: target);
        linked.add(ref.linkName);
      } catch (e) {
        errors.add('${ref.id}: $e');
        appLogger.w('[resource] link failed for ${ref.id}: $e');
      }
    }
    return MaterializeResult(linked: linked, errors: errors);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/services/resource/resource_materializer_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/resource/resource_materializer.dart client/test/services/resource/resource_materializer_test.dart
git commit -m "feat: add idempotent ResourceMaterializer (reconcile one kind dir)"
```

---

## Task 6: ResourceCapability + per-CLI impls + registry wiring

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/resource_capability.dart`
- Create: `client/lib/services/cli/registry/resources/default_resource_capability.dart`
- Create: `client/lib/services/cli/registry/resources/opencode_resource_capability.dart`
- Modify: the five tool defs in `client/lib/services/cli/registry/tools/` (`flashskyai_cli_tool.dart`, `claude_cli_tool.dart`, `codex_cli_tool.dart`, `opencode_cli_tool.dart`, `cursor_cli_tool.dart`)
- Test: `client/test/services/cli/registry/resource_capability_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/resource_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/resource/resource_kind.dart';

void main() {
  test('every launchable CLI exposes a ResourceCapability supporting skills', () {
    final registry = CliToolRegistry.builtIn();
    for (final cli in CliTool.values) {
      final cap = registry.capability<ResourceCapability>(cli);
      expect(cap, isNotNull, reason: '$cli must expose ResourceCapability');
      expect(cap!.supportedKinds, contains(ResourceKind.skill));
    }
  });

  test('opencode uses "skill" subdir; others use "skills"', () {
    final registry = CliToolRegistry.builtIn();
    expect(
      registry.capability<ResourceCapability>(CliTool.opencode)!
          .subdirFor(ResourceKind.skill),
      'skill',
    );
    expect(
      registry.capability<ResourceCapability>(CliTool.flashskyai)!
          .subdirFor(ResourceKind.skill),
      'skills',
    );
  });
}
```

> Note: confirm `CliToolRegistry.builtIn()` is the correct constructor name from `cli_tool_registry.dart`; if the project builds the registry via `registerBuiltInCliTools(registry)`, adjust the test setup to that form.

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/resource_capability_test.dart`
Expected: FAIL — `resource_capability.dart` does not exist.

- [ ] **Step 3: Write the capability interface**

`client/lib/services/cli/registry/capabilities/resource_capability.dart`:

```dart
import '../../../resource/resource_kind.dart';
import '../cli_capability.dart';

/// How a resource kind is represented inside a CLI's CONFIG_DIR.
enum ResourceRepresentation { linkedDirectory, mergedJsonEntry }

/// Declares, per-CLI, which resource kinds it consumes and how they land in its
/// CONFIG_DIR. Contains NO provisioning logic — the shared materializer does the
/// work; this just describes the target shape.
abstract interface class ResourceCapability implements CliCapability {
  Set<ResourceKind> get supportedKinds;

  /// Subdirectory (relative to the CONFIG_DIR) where this kind's entries live,
  /// for `linkedDirectory` kinds (e.g. 'skills', 'plugins').
  String subdirFor(ResourceKind kind);

  ResourceRepresentation representationFor(ResourceKind kind);
}
```

- [ ] **Step 4: Write the default + opencode impls**

`client/lib/services/cli/registry/resources/default_resource_capability.dart`:

```dart
import '../../../resource/resource_kind.dart';
import '../capabilities/resource_capability.dart';

/// Default: skills land in a `skills/` directory. Plugin/MCP support is added
/// by their follow-on plans (extend [supportedKinds] then).
final class DefaultResourceCapability implements ResourceCapability {
  const DefaultResourceCapability();

  @override
  Set<ResourceKind> get supportedKinds => const {ResourceKind.skill};

  @override
  String subdirFor(ResourceKind kind) => switch (kind) {
        ResourceKind.skill => 'skills',
        ResourceKind.plugin => 'plugins',
        ResourceKind.mcp => 'mcp',
      };

  @override
  ResourceRepresentation representationFor(ResourceKind kind) => switch (kind) {
        ResourceKind.skill => ResourceRepresentation.linkedDirectory,
        ResourceKind.plugin => ResourceRepresentation.linkedDirectory,
        ResourceKind.mcp => ResourceRepresentation.mergedJsonEntry,
      };
}
```

`client/lib/services/cli/registry/resources/opencode_resource_capability.dart`:

```dart
import '../../../resource/resource_kind.dart';
import '../capabilities/resource_capability.dart';
import 'default_resource_capability.dart';

/// opencode names its skills directory `skill` (singular).
final class OpencodeResourceCapability implements ResourceCapability {
  const OpencodeResourceCapability();

  static const _base = DefaultResourceCapability();

  @override
  Set<ResourceKind> get supportedKinds => _base.supportedKinds;

  @override
  String subdirFor(ResourceKind kind) =>
      kind == ResourceKind.skill ? 'skill' : _base.subdirFor(kind);

  @override
  ResourceRepresentation representationFor(ResourceKind kind) =>
      _base.representationFor(kind);
}
```

- [ ] **Step 5: Wire into each tool definition**

For `flashskyai_cli_tool.dart`, `claude_cli_tool.dart`, `codex_cli_tool.dart`, `cursor_cli_tool.dart`: add to the constructor params, fields, and `capabilities` list. Example for `flashskyai_cli_tool.dart` (mirror the existing capability pattern exactly):

```dart
// in the const constructor parameter list:
    this.resource = const DefaultResourceCapability(),
// in the field declarations:
  final ResourceCapability resource;
// in the `Iterable<CliCapability> get capabilities => [ ... ]` list:
    resource,
```
Add the imports at the top of each file:
```dart
import '../capabilities/resource_capability.dart';
import '../resources/default_resource_capability.dart';
```
For `opencode_cli_tool.dart` use `const OpencodeResourceCapability()` as the default and import `../resources/opencode_resource_capability.dart` instead of the default impl.

- [ ] **Step 6: Run to verify it passes**

Run: `cd client && flutter test test/services/cli/registry/resource_capability_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/resource_capability.dart client/lib/services/cli/registry/resources/ client/lib/services/cli/registry/tools/ client/test/services/cli/registry/resource_capability_test.dart
git commit -m "feat: add per-CLI ResourceCapability and wire into tool registry"
```

---

## Task 7: ResourceProvisioningService

**Files:**
- Create: `client/lib/services/resource/resource_provisioning_service.dart`
- Test: `client/test/services/resource/resource_provisioning_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/resource/resource_provisioning_service.dart';
import 'package:teampilot/services/resource/resource_scope.dart';
import 'package:teampilot/services/resource/resource_kind.dart' show ResourceCatalog;
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('provisionForLaunch materializes skills into the leaf config dir',
      () async {
    final fs = AppStorage.fs;
    final tmp = await fs.createTempDir(prefix: 'prov_test_');
    final skillsRoot = fs.pathContext.join(tmp, 'skills', 'installed');
    final src = fs.pathContext.join(skillsRoot, 'demo-skill');
    await fs.ensureDir(src);
    final configDir = fs.pathContext.join(tmp, 'cfg', 'flashskyai');

    final service = ResourceProvisioningService(
      fs: fs,
      registry: CliToolRegistry.builtIn(),
    );

    await service.provisionForLaunch(
      scope: const PersonalResourceScope(
        profile: ProjectProfile(projectId: 'p', skillIds: ['demo']),
      ),
      cli: CliTool.flashskyai,
      configDir: configDir,
      catalog: ResourceCatalog(
        skills: [
          Skill(
            id: 'demo',
            name: 'Demo',
            description: '',
            directory: 'demo-skill',
            installedAt: 0,
            updatedAt: 0,
          ),
        ],
        skillsRoot: skillsRoot,
        pathContext: fs.pathContext,
      ),
    );

    final entries =
        await fs.listDir(fs.pathContext.join(configDir, 'skills'));
    expect(entries.map((e) => e.name), contains('demo-skill'));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/resource/resource_provisioning_service_test.dart`
Expected: FAIL — `resource_provisioning_service.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import '../cli/registry/capabilities/resource_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../io/filesystem.dart';
import '../../models/team_config.dart';
import 'resource_kind.dart';
import 'resource_materializer.dart';
import 'resource_resolver.dart';
import 'resource_scope.dart';

class ResourceProvisionResult {
  const ResourceProvisionResult({this.warnings = const []});
  final List<String> warnings;
}

/// Single launch-time entry point: resolve the effective resource set for a
/// scope, then materialize every linked-directory kind the CLI supports into
/// its leaf CONFIG_DIR. Same code for personal, native, and mixed modes.
class ResourceProvisioningService {
  ResourceProvisioningService({
    required Filesystem fs,
    required CliToolRegistry registry,
    ResourceResolver resolver = const ResourceResolver(),
    ResourceMaterializer? materializer,
  })  : _fs = fs,
        _registry = registry,
        _resolver = resolver,
        _materializer = materializer ?? ResourceMaterializer(fs: fs);

  final Filesystem _fs;
  final CliToolRegistry _registry;
  final ResourceResolver _resolver;
  final ResourceMaterializer _materializer;

  Future<ResourceProvisionResult> provisionForLaunch({
    required ResourceScope scope,
    required CliTool cli,
    required String configDir,
    required ResourceCatalog catalog,
  }) async {
    final cap = _registry.capability<ResourceCapability>(cli);
    if (cap == null) return const ResourceProvisionResult();

    final effective = _resolver.resolve(scope: scope, catalog: catalog);
    final warnings = <String>[];
    for (final kind in cap.supportedKinds) {
      if (cap.representationFor(kind) !=
          ResourceRepresentation.linkedDirectory) {
        continue; // mergedJsonEntry kinds (mcp) handled by their own plan
      }
      final kindDir =
          _fs.pathContext.join(configDir, cap.subdirFor(kind));
      final result = await _materializer.reconcile(
        kindDir: kindDir,
        desired: effective.of(kind),
      );
      warnings.addAll(result.errors);
    }
    return ResourceProvisionResult(warnings: warnings);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/services/resource/resource_provisioning_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/resource/resource_provisioning_service.dart client/test/services/resource/resource_provisioning_service_test.dart
git commit -m "feat: add ResourceProvisioningService (resolve -> materialize)"
```

---

## Task 8: Wire skills provisioning into the launch path (personal)

Make the Task 0 repro pass by routing personal launch prep through `ResourceProvisioningService`.

**Files:**
- Modify: `client/lib/services/provider/config_profile_service.dart`
- Test: re-run `client/test/services/provider/personal_skill_provisioning_repro_test.dart` (Task 0)

- [ ] **Step 1: Add a skills-catalog loader dependency**

In `config_profile_service.dart`, add a constructor parameter and field (mirror the existing `loadEnabledExtensionIds` callback style):

```dart
// add import:
import '../../models/skill.dart';
import '../resource/resource_kind.dart';
import '../resource/resource_provisioning_service.dart';
import '../resource/resource_scope.dart';
import '../storage/app_storage.dart';

// add constructor parameter:
    Future<List<Skill>> Function()? loadInstalledSkills,
// store it (alongside _cliRegistry):
       _loadInstalledSkills = loadInstalledSkills,
// field:
  final Future<List<Skill>> Function()? _loadInstalledSkills;
```

Add a private helper that builds the catalog from the loader (empty when no loader is injected — keeps existing callers working until they pass it):

```dart
Future<ResourceCatalog> _skillCatalog() async {
  final skills = await (_loadInstalledSkills?.call() ?? Future.value(const <Skill>[]));
  return ResourceCatalog(
    skills: skills,
    skillsRoot: AppPaths.skillsDirForTeampilotRoot(_infra.basePath),
    pathContext: _infra.fs.pathContext,
  );
}
```

> Confirm the accessor names on `_infra` for `basePath` and `fs` from `config_profile_infrastructure.dart`; if they are private, expose lightweight getters or use the `basePath`/`AppStorage.fs` already available in this class.

- [ ] **Step 2: Replace skill provisioning in `ensureStandaloneSessionProfile`**

In the `Future.wait([...])` at lines ~220-238, **remove** the `layout.provisionStandaloneSessionSkillsFromProject(...)` element (keep `ensureStandaloneSessionInheritsProject` for agents and the plugin provisioning element). After the `Future.wait`, add:

```dart
if (profile != null) {
  await ResourceProvisioningService(
    fs: fs,
    registry: _cliRegistry,
  ).provisionForLaunch(
    scope: PersonalResourceScope(profile: profile),
    cli: cli,
    configDir: layout.standaloneProjectSessionToolDir(
      trimmedProjectId,
      trimmedSessionId,
      cli.value,
    ),
    catalog: await _skillCatalog(),
  );
}
```

- [ ] **Step 3: Run the Task 0 repro — expect PASS**

Run: `cd client && flutter test test/services/provider/personal_skill_provisioning_repro_test.dart`
Expected: PASS — the enabled skill is now materialized into the personal leaf CONFIG_DIR directly from the global library, independent of any prior cubit sync.

- [ ] **Step 4: Run the full resource + provider suites**

Run: `cd client && flutter test test/services/resource test/services/provider`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/provider/config_profile_service.dart
git commit -m "fix: provision personal skills at launch via ResourceProvisioningService

Personal leaf CONFIG_DIR is now materialized from the enabled skillIds +
global library at launch, not copied from a UI-synced staging layer."
```

---

## Task 9: Wire skills provisioning into the launch path (team: native + mixed)

**Files:**
- Modify: `client/lib/services/provider/config_profile_service.dart`
- Test: `client/test/services/provider/team_skill_provisioning_test.dart`

- [ ] **Step 1: Write the failing test (covers native and mixed via sessionId scoping)**

```dart
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('team launch prep links enabled skill into member leaf CONFIG_DIR',
      () async {
    final fs = AppStorage.fs;
    final root = AppStorage.paths.basePath;
    final layout = CliDataLayout(teampilotRoot: root, fs: fs);

    final skillsRoot = AppPaths.skillsDirForTeampilotRoot(root);
    await fs.ensureDir(fs.pathContext.join(skillsRoot, 'demo-skill'));

    final service = ConfigProfileService(
      basePath: root,
      fs: fs,
      layout: layout,
      loadInstalledSkills: () async => [
        Skill(
          id: 'demo',
          name: 'Demo',
          description: '',
          directory: 'demo-skill',
          installedAt: 0,
          updatedAt: 0,
        ),
      ],
    );

    const team = TeamConfig(
      id: 't1',
      name: 'T1',
      cli: CliTool.flashskyai,
      skillIds: ['demo'],
    );

    await service.prepareTeamLaunch(
      teamId: 't1',
      runtimeTeamId: 't1-1',
      cli: CliTool.flashskyai,
      team: team,
    );

    final leafSkillsDir = fs.pathContext.join(
      layout.memberToolDir('t1', 't1-1', 'flashskyai'),
      'skills',
    );
    final entries = await fs.listDir(leafSkillsDir);
    expect(entries.map((e) => e.name), contains('demo-skill'));
  });
}
```

> The `sessionId` passed into `ensureSessionProfile` is already mode-scoped by the caller (native: runtimeTeamId; mixed: `mixedModeMemberScopeSessionId(...)`). Wiring at `ensureSessionProfile` therefore covers both native and mixed with one code path — confirm the exact `sessionId` value `prepareTeamLaunch` forwards and assert against the same `memberToolDir(...)` it produces.

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/provider/team_skill_provisioning_test.dart`
Expected: FAIL — team launch still relies on the old `provisionMemberSkillsFromTeam` staging path; member leaf skills dir is empty (team layer not populated in this test).

- [ ] **Step 3: Replace skill provisioning in `ensureSessionProfile`**

In the `Future.wait([...])` at lines ~139-156, **remove** the `layout.provisionMemberSkillsFromTeam(...)` element (keep `ensureMemberInheritsTeam` for agents and the plugin provisioning element). After the `Future.wait`, add:

```dart
if (team != null) {
  await ResourceProvisioningService(
    fs: fs,
    registry: _cliRegistry,
  ).provisionForLaunch(
    scope: TeamResourceScope(team: team),
    cli: cli,
    configDir: layout.memberToolDir(
      trimmedTeamId,
      trimmedSessionId,
      cli.value,
    ),
    catalog: await _skillCatalog(),
  );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/services/provider/team_skill_provisioning_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/provider/config_profile_service.dart client/test/services/provider/team_skill_provisioning_test.dart
git commit -m "fix: provision team (native+mixed) skills at launch via ResourceProvisioningService"
```

---

## Task 10: Cross-mode regression lock + injection wiring

Prove the three modes behave identically, and ensure the real app injects the skills loader (so the fix is live, not just test-only).

**Files:**
- Test: `client/test/services/provider/cross_mode_skill_parity_test.dart`
- Modify: wherever `ConfigProfileService(...)` is constructed for the running app (search `app_shell.dart` and any provisioner factory).

- [ ] **Step 1: Find the production construction site**

Run: `cd client && grep -rn "ConfigProfileService(" lib | grep -v test`
Expected: one or more construction sites (likely in `app_shell.dart` or a config-profile provisioner). Note each.

- [ ] **Step 2: Inject the installed-skills loader at each site**

Add `loadInstalledSkills: () => skillRepository.loadInstalled()` (use the project's actual skill repository accessor — confirm its method name; the same loader the cubits use). If a site has no access to a skill repository, thread it through following the existing `loadEnabledExtensionIds` injection pattern in that file.

- [ ] **Step 3: Write the cross-mode parity test**

```dart
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<Set<String>> namesIn(String dir) async {
    final fs = AppStorage.fs;
    final entries = await fs.listDir(dir);
    return entries.map((e) => e.name).toSet();
  }

  test('the same enabled skill lands identically in all three modes', () async {
    final fs = AppStorage.fs;
    final root = AppStorage.paths.basePath;
    final layout = CliDataLayout(teampilotRoot: root, fs: fs);
    await fs.ensureDir(
      fs.pathContext.join(AppPaths.skillsDirForTeampilotRoot(root), 'demo-skill'),
    );
    final service = ConfigProfileService(
      basePath: root,
      fs: fs,
      layout: layout,
      loadInstalledSkills: () async => [
        Skill(id: 'demo', name: 'Demo', description: '', directory: 'demo-skill', installedAt: 0, updatedAt: 0),
      ],
    );

    // personal
    await service.prepareProjectLaunch(
      projectId: 'p', sessionId: 's',
      profile: const ProjectProfile(projectId: 'p', cli: CliTool.flashskyai, skillIds: ['demo']),
    );
    // native team
    await service.prepareTeamLaunch(
      teamId: 'tn', runtimeTeamId: 'tn-1', cli: CliTool.flashskyai,
      team: const TeamConfig(id: 'tn', name: 'TN', cli: CliTool.flashskyai, skillIds: ['demo']),
    );
    // mixed team (mode-scoped sessionId comes from prepareTeamLaunch internals)
    await service.prepareTeamLaunch(
      teamId: 'tm', runtimeTeamId: 'tm-1', cli: CliTool.flashskyai,
      team: const TeamConfig(id: 'tm', name: 'TM', cli: CliTool.flashskyai, teamMode: TeamMode.mixed, skillIds: ['demo']),
    );

    final personal = await namesIn(fs.pathContext.join(
        layout.standaloneProjectSessionToolDir('p', 's', 'flashskyai'), 'skills'));
    final native = await namesIn(fs.pathContext.join(
        layout.memberToolDir('tn', 'tn-1', 'flashskyai'), 'skills'));

    expect(personal, contains('demo-skill'));
    expect(native, contains('demo-skill'));
    expect(personal, native); // identical behavior across modes
  });
}
```

> For the mixed assertion, compute the mixed member leaf dir using the same scoping helper `prepareTeamLaunch` uses (`mixedModeMemberScopeSessionId`) and assert it also contains `demo-skill`. Confirm the helper's signature when wiring.

- [ ] **Step 4: Run it — expect PASS**

Run: `cd client && flutter test test/services/provider/cross_mode_skill_parity_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/app/app_shell.dart client/test/services/provider/cross_mode_skill_parity_test.dart
git commit -m "test: lock cross-mode skill parity; inject installed-skills loader in app"
```

---

## Task 11: Remove the dead skills-staging path

Now that launch is the source of truth, delete the old skill staging so the architecture has one way to do this.

**Files:**
- Modify: `client/lib/services/cli/cli_data_layout.dart` (delete `provisionStandaloneSessionSkillsFromProject`, `provisionMemberSkillsFromTeam`, `standaloneProjectSkillsDir`, `teamSkillsDir`, and the skills-copy portion of `ensureMemberInheritsTeam` / `ensureStandaloneSessionInheritsProject` — keep agents inheritance).
- Modify: `client/lib/cubits/project_profile_cubit.dart` (delete `_syncSkills` and its calls; `setSkillIds` only persists).
- Modify: `client/lib/cubits/team/team_resource_sync_service.dart` (delete `syncSkills` skill-linking body / calls).
- Delete: `client/lib/services/skill/project_skill_linker_service.dart` and the skill-linking in `team_skill_linker_service.dart`; delete their tests.

- [ ] **Step 1: Delete the layout methods**

Remove the four methods/fields listed above from `cli_data_layout.dart`. Keep all agents/plugins/mcp methods intact.

- [ ] **Step 2: Remove cubit sync calls**

In `project_profile_cubit.dart`, change `setSkillIds` to:

```dart
Future<void> setSkillIds(List<String> skillIds) async {
  final profile = state.profile;
  if (profile == null) return;
  await _persist(profile.copyWith(skillIds: List<String>.unmodifiable(skillIds)));
}
```
Delete `_syncSkills` and its now-unused `_skillLinker` field/import. In `team_resource_sync_service.dart`, delete the skill-linking inside `syncSkills` (and remove `_skillLinker` for skills if unused elsewhere).

- [ ] **Step 3: Delete the dead linker + tests**

```bash
git rm client/lib/services/skill/project_skill_linker_service.dart
git rm client/test/services/skill/project_skill_linker_service_test.dart
```
Remove skill-specific code paths from `team_skill_linker_service.dart` if it only handled skills; otherwise leave non-skill code.

- [ ] **Step 4: Fix the fallout, then analyze + full test**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Resolve every reference to the removed symbols (imports, constructor wiring in `app_shell.dart`, etc.).

Run: `cd client && flutter test --exclude-tags integration`
Then: `cd client && flutter test test/services/resource test/services/provider`
Expected: PASS (no references to removed staging methods remain).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: delete dead skills-staging path (launch is now source of truth)"
```

---

## Task 12: Final verification

- [ ] **Step 1: Full gate**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: analyze clean; all non-integration tests PASS.

- [ ] **Step 2: Integration tests for the new provisioning**

Run: `cd client && flutter test test/services/provider/personal_skill_provisioning_repro_test.dart test/services/provider/team_skill_provisioning_test.dart test/services/provider/cross_mode_skill_parity_test.dart`
Expected: PASS.

- [ ] **Step 3: Manual golden-path check (document result)**

Launch the app; in a personal project enable a skill, open a session, and confirm the CLI sees the skill (e.g. it appears in the agent's skill list). Repeat in a mixed team. Record the outcome in the PR description (CI cannot cover PTY launch).

---

## Self-Review Notes (carried into execution)

- **Spec coverage:** Core (resolver/materializer/capability/service) = Tasks 1-7; launch source-of-truth across 3 modes = Tasks 8-10; eliminate intermediate layer / dead path = Task 11; error handling (missing source → warning, link→copy fallback) = Tasks 4-5; testing strategy incl. cross-mode parity + root-cause TDD anchor = Tasks 0, 10. **Deferred by scope decision:** plugins + MCP get their own plans reusing this core (capability's `supportedKinds` extends to `plugin`/`mcp`, and `mergedJsonEntry` handling is added to `ResourceProvisioningService` then). Directory-model "choice B" (links straight to the global library) is realized in Tasks 8-9 + 11; the team/project staging dirs for plugins/mcp remain until those plans run.
- **Names to confirm during execution (verify, don't assume):** `CliToolRegistry.builtIn()` vs `registerBuiltInCliTools`; `_infra.basePath`/`_infra.fs` accessor visibility in `ConfigProfileInfrastructure`; the skill repository's installed-loader method name; `mixedModeMemberScopeSessionId` signature; exact `sessionId` `prepareTeamLaunch` forwards to `ensureSessionProfile`.
- **Type consistency:** `ResourceRef(id,linkName,sourceDir)`, `EffectiveResourceSet(Map).of(kind)`, `ResourceMaterializer.reconcile({kindDir,desired})→MaterializeResult{linked,errors}`, `ResourceCapability.{supportedKinds,subdirFor,representationFor}`, `ResourceProvisioningService.provisionForLaunch({scope,cli,configDir,catalog})→ResourceProvisionResult{warnings}` — used consistently across Tasks 1-10.
