# Personal Identity Bundles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse "team" and "personal" into one first-class concept — a sealed `WorkspaceIdentity` (`PersonalIdentity` | `TeamIdentity`) that is a named, reusable, directory-agnostic config bundle, so simple mode gains multi-instance reusable skills/plugins/MCP/extensions like teams, minus the roster.

**Architecture:** Clean-break refactor (no migration, no compat shims, no legacy paths). A sealed `WorkspaceIdentity` base holds `id`/`kind`/`display`/`icon`/`ConfigBundle`. `PersonalIdentity` adds per-tool tiering + agent config (absorbing today's `ProjectProfile`); `TeamConfig` is **renamed** to `TeamIdentity` and adapted to the base. One `IdentityRepository` and one `IdentityCubit` replace `TeamRepository`/`TeamCubit`; `ProjectProfile*` is deleted. Storage unifies to `identities/{id}` + `identities-runtime/{id}` (rename of `teams/` + `teams-runtime/`), and `RuntimeLayout` is re-keyed from `teamId` to `identityId`. `LaunchIdentity` becomes a bare `identityId`; `AppProject` gains `defaultIdentityId`. On a fresh store, one Default `PersonalIdentity` is auto-provisioned.

**Tech Stack:** Flutter / Dart, `flutter_bloc` cubits, `equatable`, JSON file storage via `AppStorage`/`Filesystem`, `flutter_test` + `setUpTestAppStorage()`/`tearDownTestAppStorage()` (`client/test/support/post_frame_test_harness.dart`).

**Spec:** [docs/superpowers/specs/2026-06-18-personal-identity-bundles-design.md](../specs/2026-06-18-personal-identity-bundles-design.md)

---

## Working agreement

- All commands run from `client/`.
- Work on a feature branch (not `main`): `git switch -c feat/personal-identity-bundles`.
- After each stage: `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` must be green before starting the next stage. The tree may not compile *between* tasks inside a stage; it **must** compile at each stage boundary.
- Commit after each task (messages end with the `Co-Authored-By` trailer per repo convention; omitted below for brevity).
- Reference reads before editing: the file being modified must be read in-session first.

## File structure

**Create**
- `client/lib/models/identity_kind.dart` — `IdentityKind { personal, team }`.
- `client/lib/models/config_bundle.dart` — `ConfigBundle { skillIds, pluginIds, mcpServerIds }`.
- `client/lib/models/workspace_identity.dart` — `sealed class WorkspaceIdentity`.
- `client/lib/models/personal_identity.dart` — `PersonalIdentity` (absorbs `ProjectProfile` fields + per-tool tiering).
- `client/lib/repositories/identity_repository.dart` — replaces `team_repository.dart`.
- `client/lib/cubits/identity_cubit.dart` — replaces `team_cubit.dart`.
- `client/lib/services/storage/identity_provisioner.dart` — first-run Default personal identity.
- Test files mirroring each (see tasks).

**Modify**
- `client/lib/models/team_config.dart` — rename `TeamConfig` → `TeamIdentity`, implement `WorkspaceIdentity`.
- `client/lib/models/launch_identity.dart` — reduce to a bare `identityId`.
- `client/lib/models/app_project.dart` — add `defaultIdentityId`.
- `client/lib/services/storage/app_storage.dart` — `teamsDir` → `identitiesDir`.
- `client/lib/services/storage/workspace_layout.dart` — drop `profileFile`; docstring.
- `client/lib/services/storage/runtime_layout.dart` — `teamId` params → `identityId`; `teams-runtime` → `identities-runtime`.
- `client/lib/services/storage/storage_resolver.dart` — `teamsUiDir` → `identitiesUiDir` (verify field name).
- `client/lib/services/plugin/team_plugin_linker_service.dart` → rename file/class to `identity_plugin_linker_service.dart` / `IdentityPluginLinkerService`.
- `client/lib/services/mcp/team_mcp_linker_service.dart` → `identity_mcp_linker_service.dart` / `IdentityMcpLinkerService`.
- `client/lib/services/session/session_lifecycle_service.dart` — resolve by `identityId`; drop `projectProfileRepository` dep.
- `client/lib/router/app_router.dart` — decode `?as=<identityId>`.
- `client/lib/pages/home_workspace/home_workspace_launch_project_dialog.dart` — list all identities.
- `client/lib/pages/home_workspace/project/project_config_section.dart` — kind-driven sections.
- `client/lib/pages/home_workspace/project/home_workspace_project_config_workspace.dart` — bind to identity.
- `client/lib/app/app_shell.dart` — DI swap.
- l10n: `client/lib/l10n/app_en.arb`, `app_zh.arb` — "Workspaces" label.

**Delete**
- `client/lib/models/project_profile.dart`
- `client/lib/repositories/project_profile_repository.dart`
- `client/lib/cubits/project_profile_cubit.dart`
- `client/lib/services/plugin/project_plugin_linker_service.dart` (folded into identity linker) — *verify no other consumers first.*

---

## Stage 1 — Sealed model foundation

Goal: introduce `IdentityKind`, `ConfigBundle`, `WorkspaceIdentity`, `PersonalIdentity`, and rename `TeamConfig` → `TeamIdentity` implementing the base. Stage compiles when all references to `TeamConfig` are updated to `TeamIdentity`.

### Task 1.1: `IdentityKind` enum

**Files:**
- Create: `client/lib/models/identity_kind.dart`
- Test: `client/test/models/identity_kind_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/identity_kind.dart';

void main() {
  test('decode parses known values and defaults to personal', () {
    expect(IdentityKind.decode('team'), IdentityKind.team);
    expect(IdentityKind.decode('personal'), IdentityKind.personal);
    expect(IdentityKind.decode('  TEAM '), IdentityKind.team);
    expect(IdentityKind.decode(null), IdentityKind.personal);
    expect(IdentityKind.decode('garbage'), IdentityKind.personal);
  });

  test('value round-trips', () {
    for (final k in IdentityKind.values) {
      expect(IdentityKind.decode(k.value), k);
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/identity_kind_test.dart`
Expected: FAIL — `identity_kind.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
/// Discriminator for [WorkspaceIdentity]: a solo personal setup or a team.
enum IdentityKind {
  personal('personal'),
  team('team');

  const IdentityKind(this.value);

  final String value;

  static IdentityKind decode(Object? raw) {
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    for (final kind in IdentityKind.values) {
      if (kind.value == normalized) return kind;
    }
    return IdentityKind.personal;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/identity_kind_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/identity_kind.dart test/models/identity_kind_test.dart
git commit -m "feat(identity): add IdentityKind enum"
```

### Task 1.2: `ConfigBundle`

**Files:**
- Create: `client/lib/models/config_bundle.dart`
- Test: `client/test/models/config_bundle_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';

void main() {
  test('json round-trip preserves id lists', () {
    const bundle = ConfigBundle(
      skillIds: ['a', 'b'],
      pluginIds: ['p'],
      mcpServerIds: ['m'],
    );
    final restored = ConfigBundle.fromJson(bundle.toJson());
    expect(restored, bundle);
  });

  test('fromJson tolerates missing keys and trims/filters', () {
    final b = ConfigBundle.fromJson({'skillIds': [' x ', '']});
    expect(b.skillIds, ['x']);
    expect(b.pluginIds, isEmpty);
    expect(b.mcpServerIds, isEmpty);
  });

  test('toJson omits empty lists', () {
    expect(const ConfigBundle().toJson(), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/config_bundle_test.dart`
Expected: FAIL — `config_bundle.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:flutter/foundation.dart';

/// The shared skills/plugins/mcp enable-lists carried by every
/// [WorkspaceIdentity]. Extensions are tracked separately in
/// ExtensionRepository, keyed by identity id.
@immutable
class ConfigBundle {
  const ConfigBundle({
    this.skillIds = const [],
    this.pluginIds = const [],
    this.mcpServerIds = const [],
  });

  factory ConfigBundle.fromJson(Map<String, Object?> json) => ConfigBundle(
        skillIds: _decodeIds(json['skillIds']),
        pluginIds: _decodeIds(json['pluginIds']),
        mcpServerIds: _decodeIds(json['mcpServerIds']),
      );

  final List<String> skillIds;
  final List<String> pluginIds;
  final List<String> mcpServerIds;

  static List<String> _decodeIds(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  ConfigBundle copyWith({
    List<String>? skillIds,
    List<String>? pluginIds,
    List<String>? mcpServerIds,
  }) =>
      ConfigBundle(
        skillIds: skillIds ?? this.skillIds,
        pluginIds: pluginIds ?? this.pluginIds,
        mcpServerIds: mcpServerIds ?? this.mcpServerIds,
      );

  Map<String, Object?> toJson() => {
        if (skillIds.isNotEmpty) 'skillIds': skillIds,
        if (pluginIds.isNotEmpty) 'pluginIds': pluginIds,
        if (mcpServerIds.isNotEmpty) 'mcpServerIds': mcpServerIds,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfigBundle &&
          listEquals(skillIds, other.skillIds) &&
          listEquals(pluginIds, other.pluginIds) &&
          listEquals(mcpServerIds, other.mcpServerIds);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(skillIds),
        Object.hashAll(pluginIds),
        Object.hashAll(mcpServerIds),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/config_bundle_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/config_bundle.dart test/models/config_bundle_test.dart
git commit -m "feat(identity): add ConfigBundle"
```

### Task 1.3: `WorkspaceIdentity` sealed base

**Files:**
- Create: `client/lib/models/workspace_identity.dart`

- [ ] **Step 1: Write the implementation** (no test yet — pure interface, exercised by subtype tests)

```dart
import 'config_bundle.dart';
import 'identity_kind.dart';
import 'project_icon_ref.dart';

/// A named, reusable launch identity. A directory ([AppProject]) is *where*
/// work happens; a [WorkspaceIdentity] is *who/how* — the CLI config bundle a
/// session launches with. Sealed: exactly [PersonalIdentity] or `TeamIdentity`.
sealed class WorkspaceIdentity {
  String get id;
  IdentityKind get kind;
  String get display;
  ProjectIconRef get icon;
  ConfigBundle get bundle;
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/models/workspace_identity.dart`
Expected: No errors (references to `PersonalIdentity`/`TeamIdentity` in the doc comment are comments only).

- [ ] **Step 3: Commit**

```bash
git add lib/models/workspace_identity.dart
git commit -m "feat(identity): add sealed WorkspaceIdentity base"
```

### Task 1.4: `PersonalIdentity` (absorbs `ProjectProfile`)

`ProjectAgentConfig` lives in `project_profile.dart` today; move it to its own file so it survives the later deletion of `project_profile.dart`.

**Files:**
- Create: `client/lib/models/project_agent_config.dart` (moved from `project_profile.dart`)
- Create: `client/lib/models/personal_identity.dart`
- Test: `client/test/models/personal_identity_test.dart`

- [ ] **Step 1: Move `ProjectAgentConfig`**

Cut the entire `ProjectAgentConfig` class (lines 5–80 of `client/lib/models/project_profile.dart`) into a new file `client/lib/models/project_agent_config.dart` with header:

```dart
import 'package:flutter/foundation.dart';

import 'team_config.dart'; // for TeamMemberConfig.decodeDangerouslySkipPermissions
```

(Leave `project_profile.dart` importing the new file until it is deleted in Stage 3.)

- [ ] **Step 2: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/identity_kind.dart';
import 'package:teampilot/models/personal_identity.dart';
import 'package:teampilot/models/project_agent_config.dart';

void main() {
  test('kind is always personal', () {
    expect(const PersonalIdentity(id: 'x', display: 'X').kind,
        IdentityKind.personal);
  });

  test('json round-trip preserves bundle, tiering and agent', () {
    const identity = PersonalIdentity(
      id: 'coding',
      display: 'Coding',
      bundle: ConfigBundle(skillIds: ['s1'], mcpServerIds: ['m1']),
      providerIdsByTool: {'claude': 'anthropic'},
      modelsByTool: {'claude': 'opus'},
      effortsByTool: {'claude': 'high'},
      agent: ProjectAgentConfig(prompt: 'hi'),
      activePresetId: 'preset-1',
    );
    final restored = PersonalIdentity.fromJson(identity.toJson());
    expect(restored, identity);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/models/personal_identity_test.dart`
Expected: FAIL — `personal_identity.dart` not found.

- [ ] **Step 4: Write minimal implementation**

```dart
import 'package:flutter/foundation.dart';

import 'config_bundle.dart';
import 'identity_kind.dart';
import 'project_agent_config.dart';
import 'project_icon_ref.dart';
import 'workspace_identity.dart';

/// A solo (no-roster) launch identity. Owns a [ConfigBundle] plus single-agent
/// per-tool tiering and an agent config. Replaces the per-directory
/// `ProjectProfile`.
@immutable
class PersonalIdentity implements WorkspaceIdentity {
  const PersonalIdentity({
    required this.id,
    required this.display,
    this.icon = ProjectIconRef.auto,
    this.bundle = const ConfigBundle(),
    this.providerIdsByTool = const {},
    this.modelsByTool = const {},
    this.effortsByTool = const {},
    this.agent = const ProjectAgentConfig(),
    this.activePresetId,
    this.createdAt = 0,
    this.sortOrder = 0,
  });

  factory PersonalIdentity.fromJson(Map<String, Object?> json) {
    final rawAgent = json['agent'];
    return PersonalIdentity(
      id: (json['id'] as String? ?? '').trim(),
      display: json['display'] as String? ?? '',
      icon: ProjectIconRef.fromJson(json['icon']),
      bundle: ConfigBundle.fromJson(
        json['bundle'] is Map
            ? Map<String, Object?>.from(json['bundle'] as Map)
            : json,
      ),
      providerIdsByTool: _decodeStringMap(json['providerIdsByTool']),
      modelsByTool: _decodeStringMap(json['modelsByTool']),
      effortsByTool: _decodeStringMap(json['effortsByTool']),
      agent: rawAgent is Map
          ? ProjectAgentConfig.fromJson(Map<String, Object?>.from(rawAgent))
          : const ProjectAgentConfig(),
      activePresetId: _nullableTrimmed(json['activePresetId']),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  final String id;
  @override
  final String display;
  @override
  final ProjectIconRef icon;
  @override
  final ConfigBundle bundle;

  final Map<String, String> providerIdsByTool;
  final Map<String, String> modelsByTool;
  final Map<String, String> effortsByTool;
  final ProjectAgentConfig agent;
  final String? activePresetId;
  final int createdAt;
  final int sortOrder;

  @override
  IdentityKind get kind => IdentityKind.personal;

  static Map<String, String> _decodeStringMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final key = k?.toString().trim() ?? '';
      final value = v?.toString().trim() ?? '';
      if (key.isNotEmpty && value.isNotEmpty) out[key] = value;
    });
    return Map.unmodifiable(out);
  }

  static String? _nullableTrimmed(Object? raw) {
    final s = raw?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  PersonalIdentity copyWith({
    String? display,
    ProjectIconRef? icon,
    ConfigBundle? bundle,
    Map<String, String>? providerIdsByTool,
    Map<String, String>? modelsByTool,
    Map<String, String>? effortsByTool,
    ProjectAgentConfig? agent,
    String? activePresetId,
    int? createdAt,
    int? sortOrder,
  }) =>
      PersonalIdentity(
        id: id,
        display: display ?? this.display,
        icon: icon ?? this.icon,
        bundle: bundle ?? this.bundle,
        providerIdsByTool: providerIdsByTool ?? this.providerIdsByTool,
        modelsByTool: modelsByTool ?? this.modelsByTool,
        effortsByTool: effortsByTool ?? this.effortsByTool,
        agent: agent ?? this.agent,
        activePresetId: activePresetId ?? this.activePresetId,
        createdAt: createdAt ?? this.createdAt,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.value,
        'display': display,
        if (icon.toJson() case final iconJson?) 'icon': iconJson,
        'bundle': bundle.toJson(),
        if (providerIdsByTool.isNotEmpty) 'providerIdsByTool': providerIdsByTool,
        if (modelsByTool.isNotEmpty) 'modelsByTool': modelsByTool,
        if (effortsByTool.isNotEmpty) 'effortsByTool': effortsByTool,
        'agent': agent.toJson(),
        if (activePresetId != null && activePresetId!.isNotEmpty)
          'activePresetId': activePresetId,
        if (createdAt > 0) 'createdAt': createdAt,
        if (sortOrder > 0) 'sortOrder': sortOrder,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonalIdentity &&
          id == other.id &&
          display == other.display &&
          icon == other.icon &&
          bundle == other.bundle &&
          mapEquals(providerIdsByTool, other.providerIdsByTool) &&
          mapEquals(modelsByTool, other.modelsByTool) &&
          mapEquals(effortsByTool, other.effortsByTool) &&
          agent == other.agent &&
          activePresetId == other.activePresetId &&
          createdAt == other.createdAt &&
          sortOrder == other.sortOrder;

  @override
  int get hashCode => Object.hash(
        id,
        display,
        icon,
        bundle,
        Object.hashAll(providerIdsByTool.entries.map((e) => '${e.key}=${e.value}')),
        Object.hashAll(modelsByTool.entries.map((e) => '${e.key}=${e.value}')),
        Object.hashAll(effortsByTool.entries.map((e) => '${e.key}=${e.value}')),
        agent,
        activePresetId,
        createdAt,
        sortOrder,
      );
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/models/personal_identity_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/models/project_agent_config.dart lib/models/personal_identity.dart test/models/personal_identity_test.dart
git commit -m "feat(identity): add PersonalIdentity + extract ProjectAgentConfig"
```

### Task 1.5: Rename `TeamConfig` → `TeamIdentity`, implement `WorkspaceIdentity`

**Files:**
- Modify: `client/lib/models/team_config.dart`
- Modify (sweep): every file referencing `TeamConfig`.

- [ ] **Step 1: Read `team_config.dart` fully** to see all `TeamConfig` self-references (constructors, `copyWith`, `fromJson`, statics).

- [ ] **Step 2: Rename the class and add the interface**

In `team_config.dart`:
- Rename `class TeamConfig` → `class TeamIdentity implements WorkspaceIdentity` and update all internal `TeamConfig`/`TeamConfig.` references (constructor return types, `copyWith` return, `fromJson` factory, static helpers stay as-is but are now `TeamIdentity.decodeSkillIds`, etc.).
- Add imports: `import 'config_bundle.dart';`, `import 'identity_kind.dart';`, `import 'project_icon_ref.dart';`, `import 'workspace_identity.dart';`.
- Add the interface members:

```dart
  @override
  IdentityKind get kind => IdentityKind.team;

  @override
  String get display => name;

  @override
  ProjectIconRef get icon => ProjectIconRef.auto;

  @override
  ConfigBundle get bundle => ConfigBundle(
        skillIds: skillIds,
        pluginIds: pluginIds,
        mcpServerIds: mcpServerIds,
      );
```

> Note: `id` already exists on `TeamConfig` (the slug). It satisfies `WorkspaceIdentity.id`.

- [ ] **Step 3: Sweep all references** `TeamConfig` → `TeamIdentity` across `lib/` and `test/`.

Run to enumerate: `rg -l '\bTeamConfig\b' lib test`
Apply the rename in each (IDE rename-symbol or `sed -i 's/\bTeamConfig\b/TeamIdentity/g'` per file). Also rename the static-helper call sites in `project_profile.dart` (`TeamConfig.decodeSkillIds` → `TeamIdentity.decodeSkillIds`) — these vanish in Stage 3 but must compile now.

- [ ] **Step 4: Analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No errors. (`TeamMode`, `TeamMemberConfig` keep their names — only `TeamConfig` is renamed.)

- [ ] **Step 5: Run the suite**

Run: `flutter test --exclude-tags integration`
Expected: PASS (behavior unchanged; pure rename + additive interface).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(identity): rename TeamConfig to TeamIdentity implementing WorkspaceIdentity"
```

### Task 1.6: Stage 1 gate

- [ ] Run `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`. Both green. The model layer now has the sealed hierarchy; storage/state still personal-via-ProjectProfile (changed next).

---

## Stage 2 — Storage & runtime re-key

Goal: rename `teams/`→`identities/` and `teams-runtime/`→`identities-runtime/`, re-key `RuntimeLayout` from `teamId` to `identityId`, and rename the linker services. Behavior preserved for teams; sets up the shared substrate for personal identities.

### Task 2.1: `AppStorage.teamsDir` → `identitiesDir`

**Files:**
- Modify: `client/lib/services/storage/app_storage.dart:40`
- Modify (sweep): consumers of `teamsDir`.

- [ ] **Step 1:** Read `app_storage.dart` around lines 30–110.
- [ ] **Step 2:** Rename `String get teamsDir => _ctx.join(basePath, 'teams');` to `String get identitiesDir => _ctx.join(basePath, 'identities');` and update the docstring referencing the teams layout.
- [ ] **Step 3:** Sweep: `rg -l 'teamsDir' lib test` → rename `teamsDir` → `identitiesDir` in each (notably `team_repository.dart`, `storage_resolver.dart`).
- [ ] **Step 4:** Inspect `storage_resolver.dart` for a `teamsUiDir` snapshot field; rename it to `identitiesUiDir` and update the join target to `identities`.

Run: `rg -n 'teamsUiDir|teamsDir' lib`
Expected after edits: no matches.

- [ ] **Step 5:** `flutter analyze --no-fatal-infos --no-fatal-warnings` — no errors.
- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(storage): rename teams dir to identities"
```

### Task 2.2: `RuntimeLayout` re-key to `identityId`

**Files:**
- Modify: `client/lib/services/storage/runtime_layout.dart`
- Test: `client/test/services/storage/runtime_layout_identity_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('identity runtime paths key by identity id under identities-runtime', () {
    final layout = RuntimeLayout(teampilotRoot: '/root');
    expect(layout.identitiesRuntimeDir, '/root/identities-runtime');
    expect(layout.identityRuntimeDir('coding'),
        '/root/identities-runtime/coding');
    expect(layout.identityToolDir('coding', 'claude'),
        '/root/identities-runtime/coding/claude');
    expect(layout.identitySessionCounterFile('coding'),
        '/root/identities-runtime/coding/session-counter.json');
  });
}
```

> Note: `RuntimeLayout` defaults `fs` to `AppStorage.fs`; path getters use the path context only. If the constructor touches `AppStorage` lazily, wrap with `setUpTestAppStorage()`/`tearDownTestAppStorage()` (see existing storage tests). Confirm during Step 2.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/storage/runtime_layout_identity_test.dart`
Expected: FAIL — `identitiesRuntimeDir` undefined.

- [ ] **Step 3: Rename in `runtime_layout.dart`** (these exact members):

| Old | New |
|-----|-----|
| `teamsRuntimeDir` | `identitiesRuntimeDir` (join `'identities-runtime'`) |
| `teamRuntimeDir(teamId)` | `identityRuntimeDir(identityId)` |
| `teamToolDir(teamId, tool)` | `identityToolDir(identityId, tool)` |
| `teamSessionCounterFile(teamId)` | `identitySessionCounterFile(identityId)` |
| `teamPluginsDir(teamId)` | `identityPluginsDir(identityId)` |
| `teamMcpDir(teamId)` | `identityMcpDir(identityId)` |
| `teamMcpServersFile(teamId)` | `identityMcpServersFile(identityId)` |
| `ensureTeamInheritsApp(teamId, tool)` | `ensureIdentityInheritsApp(identityId, tool)` |
| `_ensureTeamInheritsAppUnlocked` | `_ensureIdentityInheritsAppUnlocked` |
| `ensureSessionRuntimeInheritsTeam(...teamId...)` | `ensureSessionRuntimeInheritsIdentity(...identityId...)` |
| `provisionSessionPluginsFromTeam(...teamId...)` | `provisionSessionPluginsFromIdentity(...identityId...)` |
| `_teamInheritLocks`, `_teamInheritLockKey` | `_identityInheritLocks`, `_identityInheritLockKey` |
| `transcriptSearchRoots(..., teamId, ...)` | param `identityId` (keep optional) |

Update all internal references accordingly. The `projectConfig*` and `sessionRuntime*` methods are unchanged (directory-keyed, not identity-keyed).

- [ ] **Step 4:** Sweep callers: `rg -l 'teamRuntimeDir|teamToolDir|teamSessionCounterFile|teamPluginsDir|teamMcpDir|teamMcpServersFile|ensureTeamInheritsApp|ensureSessionRuntimeInheritsTeam|provisionSessionPluginsFromTeam' lib test` → update each call site to the new name (param value is still the team id where a team is involved).

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/services/storage/runtime_layout_identity_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS + no errors.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(storage): re-key RuntimeLayout from teamId to identityId"
```

### Task 2.3: Rename linker services to identity-keyed

**Files:**
- Rename: `team_plugin_linker_service.dart` → `identity_plugin_linker_service.dart` (`TeamPluginLinkerService` → `IdentityPluginLinkerService`)
- Rename: `team_mcp_linker_service.dart` → `identity_mcp_linker_service.dart` (`TeamMcpLinkerService` → `IdentityMcpLinkerService`)

- [ ] **Step 1:** Read both linker files; note their public method signatures (e.g. `syncForTeam(...)`).
- [ ] **Step 2:** `git mv` each file to the new name; rename the class; rename any `*Team*` method (e.g. `syncForTeam` → `syncForIdentity`) and `teamId` params → `identityId`. Internally they call the renamed `RuntimeLayout` methods from Task 2.2.
- [ ] **Step 3:** Sweep references: `rg -l 'TeamPluginLinkerService|TeamMcpLinkerService|team_plugin_linker_service|team_mcp_linker_service' lib test` → update imports + usages (notably `app_shell.dart`, `team_cubit.dart`).
- [ ] **Step 4:** `flutter analyze --no-fatal-infos --no-fatal-warnings` — no errors.
- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(identity): rename team linker services to identity linkers"
```

### Task 2.4: Stage 2 gate

- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` — green.

---

## Stage 3 — Repository & state unification

Goal: `IdentityRepository` (stores both kinds under `identities/{id}/identity.json`) replaces `TeamRepository`; `IdentityCubit` replaces `TeamCubit`; `ProjectProfile*` deleted; personal config reads/writes go through identities.

> This is the largest stage. `TeamCubit` is heavily wired in `app_shell.dart` (lines 447–504) and referenced by `SkillCubit`/`PluginCubit`/`McpCubit` callbacks. Read `team_cubit.dart` fully before starting.

### Task 3.1: `IdentityRepository`

Model storage as **one JSON file per identity** at `identities/{id}/identity.json`, `kind` discriminating. This replaces the team repo's flat `<name>.json` scheme (clean break: filename is now the id dir, not the display name).

**Files:**
- Create: `client/lib/repositories/identity_repository.dart`
- Test: `client/test/repositories/identity_repository_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/personal_identity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_identity.dart';
import 'package:teampilot/repositories/identity_repository.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late Directory tmp;
  late IdentityRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('identity_repo_');
    repo = IdentityRepository(rootDir: tmp.path);
  });
  tearDown(() => tmp.delete(recursive: true));

  test('saves and loads both kinds', () async {
    await repo.save(const PersonalIdentity(
      id: 'coding',
      display: 'Coding',
      bundle: ConfigBundle(skillIds: ['s']),
    ));
    await repo.save(const TeamIdentity(id: 'squad', name: 'Squad'));

    final all = await repo.loadAll();
    expect(all.map((e) => e.id).toSet(), {'coding', 'squad'});
    expect(all.whereType<PersonalIdentity>().single.bundle.skillIds, ['s']);
    expect(all.whereType<TeamIdentity>().single.display, 'Squad');
  });

  test('delete removes the identity dir', () async {
    await repo.save(const PersonalIdentity(id: 'coding', display: 'Coding'));
    await repo.delete('coding');
    expect(await repo.loadAll(), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/identity_repository_test.dart`
Expected: FAIL — `identity_repository.dart` not found.

- [ ] **Step 3: Implement** (adapted from `TeamRepository`, but per-id directory + kind dispatch)

```dart
import 'dart:convert';

import '../models/identity_kind.dart';
import '../models/personal_identity.dart';
import '../models/team_config.dart';
import '../models/workspace_identity.dart';
import '../services/io/filesystem.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/storage_resolver.dart';

/// Persists [WorkspaceIdentity] records (both kinds) at
/// `identities/{id}/identity.json`.
class IdentityRepository {
  IdentityRepository({
    String? rootDir,
    StorageRoots? storageRoots,
    SessionLifecycleService? lifecycleService,
  })  : _rootDirOverride = rootDir,
        _storageRoots = storageRoots,
        _lifecycleService = lifecycleService;

  final String? _rootDirOverride;
  final StorageRoots? _storageRoots;
  final SessionLifecycleService? _lifecycleService;

  Future<({String dir, Filesystem fs})> _paths() async {
    if (_storageRoots != null) {
      final snap = await _storageRoots.resolve();
      return (dir: snap.identitiesUiDir, fs: snap.fs);
    }
    return (
      dir: _rootDirOverride ?? AppPathsBootstrapper.current.identitiesDir,
      fs: AppStorage.fs,
    );
  }

  String _identityFile(Filesystem fs, String dir, String id) =>
      fs.pathContext.join(dir, id.trim(), 'identity.json');

  Future<List<WorkspaceIdentity>> loadAll() async {
    final paths = await _paths();
    final out = <WorkspaceIdentity>[];
    try {
      final entries = await paths.fs.listDir(paths.dir);
      for (final entry in entries) {
        if (!entry.isDirectory) continue;
        final file = _identityFile(paths.fs, paths.dir, entry.name);
        final content = await paths.fs.readString(file);
        if (content == null || content.isEmpty) continue;
        try {
          final decoded = jsonDecode(content);
          if (decoded is! Map) continue;
          out.add(_decode(Map<String, Object?>.from(decoded)));
        } on FormatException {
          continue;
        }
      }
    } on Object {
      return const [];
    }
    out.sort((a, b) => a.display.toLowerCase().compareTo(b.display.toLowerCase()));
    return List.unmodifiable(out);
  }

  WorkspaceIdentity _decode(Map<String, Object?> json) {
    return switch (IdentityKind.decode(json['kind'])) {
      IdentityKind.personal => PersonalIdentity.fromJson(json),
      IdentityKind.team => TeamIdentity.fromJson(json),
    };
  }

  Future<void> save(WorkspaceIdentity identity) async {
    final id = identity.id.trim();
    if (id.isEmpty) return;
    final paths = await _paths();
    final dir = paths.fs.pathContext.join(paths.dir, id);
    await paths.fs.ensureDir(dir);
    final json = switch (identity) {
      PersonalIdentity p => p.toJson(),
      TeamIdentity t => t.toJson(),
    };
    await paths.fs.atomicWrite(
      _identityFile(paths.fs, paths.dir, id),
      const JsonEncoder.withIndent('  ').convert(json),
    );
  }

  Future<void> delete(String id, {bool destroyCliState = true}) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    if (destroyCliState) {
      await _lifecycleService?.destroyCliToolState(trimmed);
    }
    final paths = await _paths();
    try {
      await paths.fs.removeRecursive(
        paths.fs.pathContext.join(paths.dir, trimmed),
      );
    } on Object {
      // best effort
    }
  }
}
```

> Verify `TeamIdentity.toJson` includes `'kind'` so `_decode` routes correctly. If `TeamIdentity.toJson` does not yet emit `kind`, add `'kind': kind.value` to its `toJson` (Task 1.5 follow-up) and a matching round-trip assertion.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/identity_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Add `kind` to `TeamIdentity.toJson`** if missing, and assert in `team_config` test that `TeamIdentity.fromJson(t.toJson()).kind == IdentityKind.team`.

- [ ] **Step 6: Commit**

```bash
git add lib/repositories/identity_repository.dart test/repositories/identity_repository_test.dart lib/models/team_config.dart
git commit -m "feat(identity): add IdentityRepository for both kinds"
```

### Task 3.2: `IdentityProvisioner` (first-run Default personal)

**Files:**
- Create: `client/lib/services/storage/identity_provisioner.dart`
- Test: `client/test/services/storage/identity_provisioner_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/identity_kind.dart';
import 'package:teampilot/repositories/identity_repository.dart';
import 'package:teampilot/services/storage/identity_provisioner.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('provisions exactly one default personal identity on empty store', () async {
    final tmp = await Directory.systemTemp.createTemp('identity_prov_');
    final repo = IdentityRepository(rootDir: tmp.path);
    final provisioner = IdentityProvisioner(repository: repo);

    final first = await provisioner.ensureDefaultPersonal();
    final again = await provisioner.ensureDefaultPersonal();

    expect(first.id, IdentityProvisioner.defaultPersonalId);
    expect(first.kind, IdentityKind.personal);
    expect(again.id, first.id);
    final all = await repo.loadAll();
    expect(all.where((e) => e.kind == IdentityKind.personal).length, 1);
    await tmp.delete(recursive: true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/storage/identity_provisioner_test.dart`
Expected: FAIL — `identity_provisioner.dart` not found.

- [ ] **Step 3: Implement**

```dart
import '../../models/personal_identity.dart';
import '../../models/workspace_identity.dart';
import '../../repositories/identity_repository.dart';

/// Ensures a fresh store always has at least one personal identity, so the
/// simple/open-with path always has a target. Initialization, not migration.
class IdentityProvisioner {
  IdentityProvisioner({required IdentityRepository repository})
      : _repository = repository;

  static const defaultPersonalId = 'personal-default';

  final IdentityRepository _repository;

  Future<PersonalIdentity> ensureDefaultPersonal() async {
    final all = await _repository.loadAll();
    final existing = all
        .whereType<PersonalIdentity>()
        .where((p) => p.id == defaultPersonalId)
        .firstOrNull;
    if (existing != null) return existing;

    final defaultIdentity = PersonalIdentity(
      id: defaultPersonalId,
      display: 'Personal',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _repository.save(defaultIdentity);
    return defaultIdentity;
  }
}
```

> `firstOrNull` comes from `package:collection`; if not already imported elsewhere, add `import 'package:collection/collection.dart';`. Confirm it is in `pubspec.yaml` (it is a common transitive dep — `rg 'collection:' pubspec.yaml`; add if absent). The "Personal" display string is user-facing — route it through l10n at the call site in `app_shell` if localization is required, or keep a fixed neutral default.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/storage/identity_provisioner_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/storage/identity_provisioner.dart test/services/storage/identity_provisioner_test.dart
git commit -m "feat(identity): add first-run Default personal provisioning"
```

### Task 3.3: `IdentityCubit` (replaces `TeamCubit`)

This is a mechanical-but-large adaptation. Keep `TeamCubit`'s team behavior intact; add personal CRUD; back it by `IdentityRepository`.

**Files:**
- Create: `client/lib/cubits/identity_cubit.dart` (start by `git mv lib/cubits/team_cubit.dart lib/cubits/identity_cubit.dart`)
- Test: extend existing team cubit tests; add `client/test/cubits/identity_cubit_personal_test.dart`

- [ ] **Step 1:** Read `team_cubit.dart` fully. Inventory: state shape, `repository` type (`TeamRepository`), the methods referenced as callbacks elsewhere (`removeSkillFromAllTeams`, `removePluginFromAllTeams`, `syncTeamsUsingPlugin`, `removeMcpFromAllTeams`).

- [ ] **Step 2:** `git mv` to `identity_cubit.dart`; rename `TeamCubit` → `IdentityCubit`, `TeamState`/`TeamCubitState` (whatever it is) → `IdentityState`. Swap the `TeamRepository repository` field/param to `IdentityRepository`. The team list in state becomes `List<WorkspaceIdentity>`; add convenience getters `teams` (filter `whereType<TeamIdentity>()`) and `personals` (filter `whereType<PersonalIdentity>()`) so existing team-only call sites keep working.

- [ ] **Step 3:** Add personal CRUD methods mirroring team ones:

```dart
  Future<void> savePersonal(PersonalIdentity identity) async {
    await _repository.save(identity);
    await _reload();
    // relink bundle for personal id (skills/plugins/mcp), same path teams use
  }

  Future<void> deletePersonal(String id) async {
    if (personals.length <= 1) return; // never delete the only personal
    await _repository.delete(id);
    await _reload();
  }
```

(Adapt `_reload`/state-emit to the cubit's existing pattern discovered in Step 1.)

- [ ] **Step 4:** Update callback method names that say "Teams" but now must also prune personal bundles, OR keep them team-scoped and add personal equivalents. Minimum: keep signatures so `SkillCubit`/`PluginCubit`/`McpCubit` wiring in `app_shell` still resolves (rename only the type, not the method names, unless extending behavior).

- [ ] **Step 5:** Write `identity_cubit_personal_test.dart` covering: save personal → appears in `personals`; deleting the only personal is a no-op; deleting when >1 removes it. Use `IdentityRepository(rootDir: tmp.path)` and the `setUpTestAppStorage` harness as in Task 3.1.

- [ ] **Step 6:** Sweep `rg -l '\bTeamCubit\b|team_cubit' lib test` → update imports/types (`app_shell.dart`, pages, tests).

- [ ] **Step 7:** `flutter analyze` + run the cubit tests. Green.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(identity): replace TeamCubit with IdentityCubit (both kinds)"
```

### Task 3.4: Delete `ProjectProfile*`, repoint `SessionLifecycleService`

**Files:**
- Delete: `project_profile.dart`, `project_profile_repository.dart`, `project_profile_cubit.dart`
- Modify: `session_lifecycle_service.dart`, `app_shell.dart`

- [ ] **Step 1:** Read `session_lifecycle_service.dart` — find where `projectProfileRepository` is used and where personal vs team launch config is assembled (search `projectProfile`, `isPersonal`, `teamId`).

- [ ] **Step 2:** Replace the personal-config source: instead of loading a `ProjectProfile` by `projectId`, the lifecycle resolves a `WorkspaceIdentity` by `identityId` (passed from the launch plan — see Stage 4) and links its `ConfigBundle` under `identities-runtime/{identityId}`. Remove the `projectProfileRepository` constructor param.

- [ ] **Step 3:** Remove `ProjectProfileCubit`/`ProjectProfileRepository` wiring from `app_shell.dart` (lines 415, 438, 494–498) and the fields/params at 156–157, 261–262. Provide `IdentityCubit` + `IdentityProvisioner` instead; call `ensureDefaultPersonal()` during bootstrap.

- [ ] **Step 4:** `git rm` the three files. Fix every remaining import (`rg -l 'project_profile' lib test`).

- [ ] **Step 5:** `flutter analyze --no-fatal-infos --no-fatal-warnings` — resolve all breakages.

- [ ] **Step 6:** `flutter test --exclude-tags integration` — fix/relocate tests that referenced `ProjectProfile`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(identity): delete ProjectProfile, source personal config from identities"
```

### Task 3.5: Stage 3 gate

- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` — green. Personal config now lives on identities; teams unchanged behaviorally.

---

## Stage 4 — Launch identity & routing

Goal: `LaunchIdentity` becomes a bare `identityId`; `AppProject` remembers `defaultIdentityId`; the router and launch path resolve by id.

### Task 4.1: `LaunchIdentity` = bare id

**Files:**
- Modify: `client/lib/models/launch_identity.dart`
- Test: `client/test/models/launch_identity_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_identity.dart';

void main() {
  test('encode/decode a bare identity id', () {
    const li = LaunchIdentity('coding');
    expect(li.encode(), 'coding');
    expect(LaunchIdentity.decode('coding'), li);
  });

  test('decode trims and rejects empty', () {
    expect(LaunchIdentity.decode('  squad '), const LaunchIdentity('squad'));
    expect(LaunchIdentity.decode(''), isNull);
    expect(LaunchIdentity.decode(null), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/launch_identity_test.dart`
Expected: FAIL — old `LaunchIdentity` has no unnamed `(String)` constructor / `personal` semantics.

- [ ] **Step 3: Rewrite `launch_identity.dart`**

```dart
import 'package:flutter/foundation.dart';

/// Which identity a directory is opened against. Encoded on the project route
/// as `?as=<identityId>`. Kind is resolved from the loaded identity record.
@immutable
class LaunchIdentity {
  const LaunchIdentity(this.identityId);

  final String identityId;

  String encode() => identityId;

  static LaunchIdentity? decode(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    return LaunchIdentity(value);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchIdentity &&
          runtimeType == other.runtimeType &&
          identityId == other.identityId;

  @override
  int get hashCode => identityId.hashCode;

  @override
  String toString() => 'LaunchIdentity($identityId)';
}
```

- [ ] **Step 4:** Run test — PASS.

- [ ] **Step 5:** Sweep usages from the known list (`rg -n 'LaunchIdentity' lib`): `app_router.dart:140`, `home_workspace_launch_project_dialog.dart`, `home_workspace_shell.dart`, `home_workspace_project_page.dart`, `home_workspace_projects_tab.dart`. Replace `LaunchIdentity.personal` / `LaunchIdentity.team(id)` / `.isPersonal` / `.teamId` usages — see Task 4.3 for the dialog, Task 4.2 for the page/shell plumbing.

- [ ] **Step 6: Commit** (compile may still break in UI until 4.2/4.3 — acceptable mid-stage)

```bash
git add lib/models/launch_identity.dart test/models/launch_identity_test.dart
git commit -m "feat(identity): LaunchIdentity is a bare identity id"
```

### Task 4.2: `AppProject.defaultIdentityId` + launch resolution

**Files:**
- Modify: `client/lib/models/app_project.dart`
- Modify: `client/lib/services/session/session_lifecycle_service.dart` (launch plan), `home_workspace_project_page.dart`, `home_workspace_shell.dart`
- Test: `client/test/models/app_project_test.dart` (create or extend)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_project.dart';

void main() {
  test('defaultIdentityId round-trips and defaults empty', () {
    const p = AppProject(
      projectId: 'p1',
      primaryPath: '/tmp/p1',
      createdAt: 1,
      defaultIdentityId: 'coding',
    );
    final restored = AppProject.fromJson(p.toJson());
    expect(restored.defaultIdentityId, 'coding');
    expect(
      AppProject.fromJson({'projectId': 'x', 'primaryPath': '/x'})
          .defaultIdentityId,
      '',
    );
  });
}
```

- [ ] **Step 2:** Run — FAIL (`defaultIdentityId` not a member).

- [ ] **Step 3:** Add `this.defaultIdentityId = ''` to the `AppProject` constructor, the field, `fromJson` (`json['defaultIdentityId'] as String? ?? ''`), `toJson` (`if (defaultIdentityId.isNotEmpty) 'defaultIdentityId': defaultIdentityId`), `copyWith`, `==`, `hashCode` — mirroring the existing `display` field handling at `app_project.dart:31/42/72/85/100/112`.

- [ ] **Step 4:** Run test — PASS.

- [ ] **Step 5:** In the launch path (where `LaunchProjectChoice.remember` is honored — find via `rg -n 'remember' lib/pages/home_workspace`), persist `project.copyWith(defaultIdentityId: choice.identity.identityId)` when `remember` is true. When opening a project, preselect `LaunchIdentity(project.defaultIdentityId)` if non-empty, else `LaunchIdentity(IdentityProvisioner.defaultPersonalId)`.

- [ ] **Step 6:** In `SessionLifecycleService.prepareLaunch` (and its callers in `home_workspace_project_page.dart`), pass the resolved `identityId`; look the identity up via `IdentityCubit`/`IdentityRepository`, branch on `identity.kind` for roster vs solo. Remove any remaining `teamId == ''` personal detection.

- [ ] **Step 7:** `flutter analyze` — resolve breakages from 4.1's sweep.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(identity): remember per-directory identity and resolve launch by id"
```

### Task 4.3: Router decode

**Files:**
- Modify: `client/lib/router/app_router.dart:140`

- [ ] **Step 1:** Read `app_router.dart` around lines 120–160. The decode is already `LaunchIdentity.decode(query['as'])` — confirm downstream consumers (`home_workspace_project_page`) now receive a `LaunchIdentity?` with an `identityId` and no longer call `.isPersonal`/`.teamId`.
- [ ] **Step 2:** Update those consumers to resolve kind from the identity record (`context.read<IdentityCubit>().byId(identityId)`), adding a `byId` helper to `IdentityCubit` if absent.
- [ ] **Step 3:** `flutter analyze` — no errors.
- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(router): resolve launch identity by id"
```

### Task 4.4: Stage 4 gate

- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` — green.

---

## Stage 5 — Config UI & home surface

Goal: one kind-driven config surface; rename the "My Teams" nav to "Workspaces" with a kind badge; open-with lists every identity.

### Task 5.1: Kind-driven config sections

**Files:**
- Modify: `client/lib/pages/home_workspace/project/project_config_section.dart`
- Test: `client/test/pages/home_workspace/project_config_section_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/identity_kind.dart';
import 'package:teampilot/pages/home_workspace/project/project_config_section.dart';

void main() {
  test('personal shows full bundle surface without members', () {
    final s = ProjectConfigSection.forKind(IdentityKind.personal);
    expect(s, isNot(contains(ProjectConfigSection.members)));
    expect(s, contains(ProjectConfigSection.skills));
    expect(s, contains(ProjectConfigSection.mcp));
  });

  test('team adds members', () {
    final s = ProjectConfigSection.forKind(IdentityKind.team);
    expect(s, contains(ProjectConfigSection.members));
  });
}
```

- [ ] **Step 2:** Run — FAIL (`members` value and `forKind` absent).

- [ ] **Step 3:** Edit the enum (`project_config_section.dart`): add a `members` value; replace `personalSections`/`teamSections` with:

```dart
  static const _bundleSections = [
    settings, agent, skills, plugins, mcp, extensions,
  ];

  static List<ProjectConfigSection> forKind(IdentityKind kind) =>
      kind == IdentityKind.team
          ? [...{_bundleSections.first}, members, ..._bundleSections.skip(1)]
          : _bundleSections;
```

(Adjust ordering to taste; ensure `members` has `routeSegment`/`title`/`icon` cases and an l10n string `homeWorkspaceProjectMembers`.)

- [ ] **Step 4:** Run test — PASS.

- [ ] **Step 5:** Sweep `rg -ln 'personalSections|teamSections' lib` and update call sites to `forKind(identity.kind)`.

- [ ] **Step 6:** Add l10n keys `homeWorkspaceProjectMembers` to `app_en.arb` + `app_zh.arb`; `flutter pub get` to regenerate; re-run `dart run tool/gen_warmup_glyphs.dart` per AGENTS.md.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(identity): kind-driven config sections with Members for teams"
```

### Task 5.2: Config workspace binds to identity

**Files:**
- Modify: `client/lib/pages/home_workspace/project/home_workspace_project_config_workspace.dart`

- [ ] **Step 1:** Read the file; find where it reads `ProjectProfileCubit` / `personalSections` / team config.
- [ ] **Step 2:** Swap reads to `IdentityCubit.byId(identityId)`; drive sections via `ProjectConfigSection.forKind(identity.kind)`; route bundle edits (skills/plugins/mcp/extensions/agent/provider tiering) through `IdentityCubit.savePersonal(...)` for personal or existing team-config mutators for team.
- [ ] **Step 3:** `flutter analyze` — no errors; run any widget tests for this page.
- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(identity): config workspace driven by WorkspaceIdentity"
```

### Task 5.3: Open-with dialog lists all identities

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_launch_project_dialog.dart`

- [ ] **Step 1:** Replace `LaunchProjectTeamOption` with a kind-aware option:

```dart
class LaunchProjectIdentityOption {
  const LaunchProjectIdentityOption({
    required this.id,
    required this.name,
    required this.isTeam,
  });
  final String id;
  final String name;
  final bool isTeam;
}
```

- [ ] **Step 2:** Change the dialog param `List<LaunchProjectTeamOption> teams` → `List<LaunchProjectIdentityOption> identities`; render one `ListTile` per identity with `Icons.person_outline_rounded` (personal) / `Icons.groups_2_outlined` (team) as the kind badge; `selected: _selected == LaunchIdentity(opt.id)`; `onTap: () => _choose(LaunchIdentity(opt.id))`. Drop the hardcoded "Simple mode" tile.
- [ ] **Step 3:** Default `_selected`: `widget.preselected ?? LaunchIdentity(IdentityProvisioner.defaultPersonalId)`.
- [ ] **Step 4:** Update the caller (the projects tab / shell that builds `teams:`) to pass all identities from `IdentityCubit` (personals first, then teams), and to map the result's `identityId`.
- [ ] **Step 5:** `flutter analyze` + widget test for the dialog if present.
- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(identity): open-with lists every workspace identity"
```

### Task 5.4: Rename "My Teams" nav → "Workspaces"

**Files:**
- Modify: l10n `app_en.arb`, `app_zh.arb`; the nav/section widget rendering the team library label.

- [ ] **Step 1:** `rg -n 'homeWorkspaceTeams|My Teams|我的团队|团队库' lib/l10n lib/pages` to find the label key + usage.
- [ ] **Step 2:** Add/rename l10n: English "Workspaces", Chinese "工作区". Point the nav widget at the new key; in the list, render a per-row kind badge (person vs groups icon) so personal and team rows read distinctly.
- [ ] **Step 3:** `flutter pub get`; `dart run tool/gen_warmup_glyphs.dart`.
- [ ] **Step 4:** `flutter analyze` + the full suite.
- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(identity): rename home Teams surface to Workspaces"
```

### Task 5.5: Stage 5 gate + golden-path manual checks

- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` — green.
- [ ] Manual (document results per AGENTS.md):
  1. Fresh store → open a directory → launches against auto-provisioned Default personal identity, no setup prompt.
  2. New personal setup → add a skill + MCP server → launch a directory → skill/MCP present in the agent runtime under `identities-runtime/{id}`.
  3. Open a second directory with the same personal identity → same skills/MCP apply.
  4. Create a team + a personal identity → both appear as peers in "Workspaces" + open-with; launching each lands in the right config surface (Members only for team).

---

## Self-review notes (spec coverage)

- Sealed model / ConfigBundle / kind split → Stage 1.
- Unified `identities/` + `identities-runtime/`, identity-keyed runtime, renamed linkers → Stage 2.
- `IdentityRepository`/`IdentityCubit`, delete `ProjectProfile*`, first-run Default → Stage 3.
- `LaunchIdentity` bare id, `defaultIdentityId`, launch resolution, router → Stage 4.
- Kind-driven config UI, open-with list, "Workspaces" rename + kind badge → Stage 5.
- Error handling (deleted-id fallback, undeletable sole personal) → Tasks 3.3 (`deletePersonal` guard) and 4.2 (preselect fallback). **Add** an explicit test in Task 4.2 that launching with a dangling `defaultIdentityId` falls back to the Default personal identity.
- Extensions re-key from `teamId` → `identityId`: handled wherever `effectiveEnabledIds(teamId)` is called (`app_shell.dart:424–435`, `team_cubit`'s `extensionMcpContributor`). During Stage 3/4, confirm these now pass `identityId`; the `ExtensionRepository` method names can stay but their argument is the identity id.

## Risks / watch-items

- `TeamCubit` is broadly wired (`app_shell.dart`) and exposes callbacks to `SkillCubit`/`PluginCubit`/`McpCubit`. Task 3.3 must preserve those method names/signatures or update all four call sites together.
- `SessionLifecycleService.prepareLaunch` body was not read line-by-line while writing this plan; Task 3.4/4.2 begin with a mandatory read of it before editing.
- Verify `project_plugin_linker_service.dart` has no consumers beyond `ProjectProfileCubit` before deleting; if a session-launch path uses it, fold that into the identity plugin linker instead.
