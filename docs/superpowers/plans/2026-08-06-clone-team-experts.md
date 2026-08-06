# Clone Team — Clone Missing Experts into My Experts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a TeamHub team is cloned, any roster-referenced expert that is not already present locally is cloned into My Experts, and the team's roster repoints to the local copy so the team is self-contained.

**Architecture:** `TeamCloneService.clone` gains a per-run `ExpertSlotCloner` (produced by an injected `expertClonerFactory`). The cloner resolves each roster `expertKey` via the expert hub source, saves a local copy through `LocalMemberTemplateStore` (recording `catalogKey` provenance for cross-clone dedup), and returns the key the slot should reference. `DiscoverableMember` gains an optional `catalogKey` field; `CloneResult`/summary and the clone toast report cloned-expert counts and non-blocking expert failures.

**Tech Stack:** Dart / Flutter, flutter_bloc cubits, `LocalMemberTemplateStore` (disk under `member-hub/local-templates/`), generated l10n (`flutter gen-l10n`).

## Global Constraints

- Layering: services in `client/lib/services/…`; models in `client/lib/models/…`; UI in `client/lib/pages/…`; wiring in `client/lib/app/app_shell.dart`.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` **only**; regenerate generated files with `cd client && flutter gen-l10n`.
- No `print`; diagnostics go through `AppLogger`.
- Tests: constructor injection / `InMemoryFilesystem` (`client/test/support/in_memory_filesystem.dart`); no network.
- Final gate: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.
- Design spec: `docs/superpowers/specs/2026-08-06-clone-team-experts-design.md`.

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `client/lib/models/discoverable_member.dart` | Modify | Add `catalogKey` provenance field + real `copyWith` |
| `client/test/models/discoverable_member_test.dart` | Modify | Tests for `catalogKey` round-trip / `forLocale` / `copyWith` |
| `client/lib/services/expert_hub/local_member_template_store.dart` | Modify | `save` preserves `catalogKey` |
| `client/test/services/expert_hub/local_member_template_store_test.dart` | Modify | Test `catalogKey` persistence; drop redundant test-local `copyWith` extension |
| `client/lib/services/expert_hub/expert_clone_service.dart` | Create | `ExpertCloneOutcome` + `ExpertCloneService` (resolve → save → repoint key) |
| `client/test/services/expert_hub/expert_clone_service_test.dart` | Create | Unit tests with fake `ExpertHubSource` + in-memory store |
| `client/lib/services/team/team_clone_service.dart` | Modify | `expertClonerFactory`, per-slot repoint, `DependencyKind.expert`, summary expert keys |
| `client/test/services/team/team_clone_service_test.dart` | Modify | Add cloner factory to existing tests + new repoint/failure tests |
| `client/lib/app/app_shell.dart` | Modify | Move `compositeExpertHubSource` earlier; wire `expertClonerFactory` |
| `client/lib/pages/team_hub/team_hub_clone_feedback.dart` | Modify | Toast copy includes expert count |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | Modify | Add `expertCount` placeholder to clone strings |
| `client/test/pages/team_hub/team_hub_clone_feedback_test.dart` | Modify | Update expected strings; add expert-count test |

---

### Task 1: `DiscoverableMember.catalogKey` + real `copyWith`

**Files:**
- Modify: `client/lib/models/discoverable_member.dart`
- Test: `client/test/models/discoverable_member_test.dart`

**Interfaces:**
- Produces: `DiscoverableMember.catalogKey` (`String?`), `DiscoverableMember.copyWith({String? key, String? name, String? description, String? category, String? author, int? updatedAt, Set<String>? tags, DiscoverableTeamMember? member, List<SkillDependencyRef>? skillDeps, List<PluginDependencyRef>? pluginDeps, List<McpDependencyRef>? mcpDeps, ExpertMemberSource? source, String? originTeamKey, bool updateOriginTeamKey = false, String? catalogKey, bool updateCatalogKey = false, Map<String, DiscoverableMemberLocaleText>? i18n})`.

- [ ] **Step 1: Write the failing test**

Add to `client/test/models/discoverable_member_test.dart`:

```dart
  test('catalogKey round-trips through JSON', () {
    final m = DiscoverableMember(
      key: 'teampilot/builtin/developer',
      name: 'Developer',
      description: 'Implements features',
      category: 'Development',
      source: ExpertMemberSource.local,
      member: const DiscoverableTeamMember(name: 'developer'),
      catalogKey: 'acme/experts/developer',
      originTeamKey: 'acme/teams/squad',
    );
    final decoded = DiscoverableMember.fromJson(m.toJson());
    expect(decoded, m);
    expect(decoded.catalogKey, 'acme/experts/developer');
  });

  test('copyWith updates catalogKey and originTeamKey', () {
    const m = DiscoverableMember(
      key: 'local/abc',
      name: 'PM',
      description: '',
      category: 'Business',
      source: ExpertMemberSource.local,
      member: DiscoverableTeamMember(name: 'pm'),
    );
    final updated = m.copyWith(
      catalogKey: 'acme/experts/pm',
      originTeamKey: 'acme/teams/squad',
    );
    expect(updated.catalogKey, 'acme/experts/pm');
    expect(updated.originTeamKey, 'acme/teams/squad');
    expect(updated.key, 'local/abc');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/discoverable_member_test.dart`
Expected: FAIL — `catalogKey` is not a field on `DiscoverableMember` (compile error) and `copyWith` is not defined.

- [ ] **Step 3: Implement the field and `copyWith`**

In `client/lib/models/discoverable_member.dart`:

Add constructor param after `this.originTeamKey,`:

```dart
    this.originTeamKey,
    this.catalogKey,
    this.i18n = const {},
  });
```

Add field after `originTeamKey`:

```dart
  final String? originTeamKey;

  /// Provenance: catalog key this local clone was saved from (cross-clone dedup).
  final String? catalogKey;
```

In `fromJson`, after the `originTeamKey` line:

```dart
      originTeamKey: json['originTeamKey'] as String?,
      catalogKey: json['catalogKey'] as String?,
```

In `toJson`, after the `originTeamKey` line:

```dart
    if (originTeamKey != null && originTeamKey!.isNotEmpty)
      'originTeamKey': originTeamKey,
    if (catalogKey != null && catalogKey!.isNotEmpty) 'catalogKey': catalogKey,
```

In `forLocale`, add after `originTeamKey: originTeamKey,`:

```dart
      catalogKey: catalogKey,
```

In `==`, add after `originTeamKey == other.originTeamKey &&`:

```dart
      catalogKey == other.catalogKey &&
```

In `hashCode`, add after `originTeamKey,`:

```dart
    originTeamKey,
    catalogKey,
```

Add a `copyWith` method right after the `forLocale` method (before `_overlayFor`):

```dart
  DiscoverableMember copyWith({
    String? key,
    String? name,
    String? description,
    String? category,
    String? author,
    int? updatedAt,
    Set<String>? tags,
    DiscoverableTeamMember? member,
    List<SkillDependencyRef>? skillDeps,
    List<PluginDependencyRef>? pluginDeps,
    List<McpDependencyRef>? mcpDeps,
    ExpertMemberSource? source,
    String? originTeamKey,
    bool updateOriginTeamKey = false,
    String? catalogKey,
    bool updateCatalogKey = false,
    Map<String, DiscoverableMemberLocaleText>? i18n,
  }) {
    return DiscoverableMember(
      key: key ?? this.key,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      author: author ?? this.author,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      member: member ?? this.member,
      skillDeps: skillDeps ?? this.skillDeps,
      pluginDeps: pluginDeps ?? this.pluginDeps,
      mcpDeps: mcpDeps ?? this.mcpDeps,
      source: source ?? this.source,
      originTeamKey: updateOriginTeamKey
          ? originTeamKey
          : (originTeamKey ?? this.originTeamKey),
      catalogKey: updateCatalogKey
          ? catalogKey
          : (catalogKey ?? this.catalogKey),
      i18n: i18n ?? this.i18n,
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/discoverable_member_test.dart`
Expected: PASS (all tests in the file).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/discoverable_member.dart client/test/models/discoverable_member_test.dart
git commit -m "feat(expert): add catalogKey provenance + copyWith to DiscoverableMember"
```

---

### Task 2: `LocalMemberTemplateStore.save` preserves `catalogKey`

**Files:**
- Modify: `client/lib/services/expert_hub/local_member_template_store.dart`
- Test: `client/test/services/expert_hub/local_member_template_store_test.dart`

**Interfaces:**
- Consumes: `DiscoverableMember.catalogKey`, `DiscoverableMember.copyWith` (from Task 1).
- Produces: `LocalMemberTemplateStore.save` keeps `catalogKey` on the persisted copy.

- [ ] **Step 1: Write the failing test**

Add to `client/test/services/expert_hub/local_member_template_store_test.dart`:

```dart
  test('save preserves catalogKey provenance', () async {
    final saved = await store.save(
      _sampleMember().copyWith(catalogKey: 'acme/experts/pm'),
    );

    expect(saved.catalogKey, 'acme/experts/pm');
    expect((await store.getByKey(saved.key))?.catalogKey, 'acme/experts/pm');
  });
```

Then remove the now-redundant test-local `copyWith` extension at the bottom of that file (lines 122-150, the `extension on DiscoverableMember { ... }` block). The model's real `copyWith` supersedes it.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/expert_hub/local_member_template_store_test.dart`
Expected: FAIL — `saved.catalogKey` is `null`.

- [ ] **Step 3: Implement**

In `client/lib/services/expert_hub/local_member_template_store.dart`, in `save`, add after `originTeamKey: member.originTeamKey,`:

```dart
      originTeamKey: member.originTeamKey,
      catalogKey: member.catalogKey,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/expert_hub/local_member_template_store_test.dart`
Expected: PASS (all tests in the file).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/expert_hub/local_member_template_store.dart client/test/services/expert_hub/local_member_template_store_test.dart
git commit -m "feat(expert): persist catalogKey provenance in LocalMemberTemplateStore"
```

---

### Task 3: `ExpertCloneService`

**Files:**
- Create: `client/lib/services/expert_hub/expert_clone_service.dart`
- Test: `client/test/services/expert_hub/expert_clone_service_test.dart`

**Interfaces:**
- Consumes: `CompositeExpertHubSource` (`withDefaults` factory or direct constructor with `ExpertHubSource? registry`), `LocalMemberTemplateStore`, `ExpertMemberResolver.resolveMember({required String? key, CompositeExpertHubSource? source, LocalMemberTemplateStore? localStore})`, `DiscoverableMember.copyWith`.
- Produces:
  - `class ExpertCloneOutcome { const ExpertCloneOutcome({required this.key, required this.cloned}); final String key; final bool cloned; }`
  - `class ExpertCloneService { ExpertCloneService({required CompositeExpertHubSource source, LocalMemberTemplateStore? localStore}); Future<ExpertCloneOutcome?> clone({required String expertKey, String? originTeamKey}); }` — returns `null` when the expert cannot be resolved; memoizes per instance (`Map<String,String> _memo`).

- [ ] **Step 1: Write the failing test**

Create `client/test/services/expert_hub/expert_clone_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_clone_service.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/local_member_template_store.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeExpertHubSource implements ExpertHubSource {
  _FakeExpertHubSource(this.members);
  final List<DiscoverableMember> members;
  @override
  Future<List<DiscoverableMember>> fetchMembers({bool forceRefresh = false}) async =>
      members;
  @override
  Future<List<String>> categories({bool forceRefresh = false}) async => const [];
}

DiscoverableMember _catalogExpert({String key = 'acme/experts/pm'}) =>
    DiscoverableMember(
      key: key,
      name: 'Product Manager',
      description: 'Plans.',
      category: 'Business',
      source: ExpertMemberSource.registry,
      member: const DiscoverableTeamMember(
        name: 'pm',
        responsibilities: 'You are a PM.',
      ),
    );

void main() {
  late InMemoryFilesystem fs;
  late LocalMemberTemplateStore store;
  late ExpertCloneService service;

  ExpertCloneService make({
    List<DiscoverableMember> catalog = const [],
  }) {
    final source = CompositeExpertHubSource(
      builtIns: const [],
      registry: _FakeExpertHubSource(catalog),
      localStore: store,
    );
    return ExpertCloneService(source: source, localStore: store);
  }

  setUp(() {
    fs = InMemoryFilesystem();
    store = LocalMemberTemplateStore(
      fs: fs,
      dirOverride: AppPaths('/tp').memberHubLocalTemplatesDir,
      uuidFactory: () => 'test-uuid',
    );
    service = make(catalog: [_catalogExpert()]);
  });

  test('catalog expert is cloned to a local key with provenance', () async {
    final out = await service.clone(
      expertKey: 'acme/experts/pm',
      originTeamKey: 'acme/teams/squad',
    );

    expect(out, isNotNull);
    expect(out!.cloned, isTrue);
    expect(out.key, 'local/test-uuid');

    final saved = await store.getByKey('local/test-uuid');
    expect(saved, isNotNull);
    expect(saved!.catalogKey, 'acme/experts/pm');
    expect(saved.originTeamKey, 'acme/teams/squad');
    expect(saved.name, 'Product Manager');
  });

  test('built-in expert is kept, not cloned', () async {
    final out = await service.clone(expertKey: 'teampilot/builtin/team-lead');

    expect(out, isNotNull);
    expect(out!.key, 'teampilot/builtin/team-lead');
    expect(out.cloned, isFalse);
    expect(await store.loadAll(), isEmpty);
  });

  test('existing local key is kept', () async {
    await store.save(_catalogExpert(key: 'local/existing'));

    final out = await service.clone(expertKey: 'local/existing');

    expect(out, isNotNull);
    expect(out!.key, 'local/existing');
    expect(out.cloned, isFalse);
  });

  test('dangling local key is a failure', () async {
    final out = await service.clone(expertKey: 'local/gone');
    expect(out, isNull);
  });

  test('unresolvable catalog key is a failure', () async {
    final out = await service.clone(expertKey: 'acme/experts/nope');
    expect(out, isNull);
  });

  test('reuses an existing local copy from the same catalogKey', () async {
    final first = await service.clone(expertKey: 'acme/experts/pm');
    expect(first!.key, 'local/test-uuid');

    // A fresh service (new run) sees the already-saved local copy.
    final second = make(catalog: [_catalogExpert()]).clone(
      expertKey: 'acme/experts/pm',
    );
    final out = await second;
    expect(out, isNotNull);
    expect(out!.key, 'local/test-uuid');
    expect(out.cloned, isFalse);
    expect(await store.loadAll(), hasLength(1));
  });

  test('same expert referenced twice in one run is cloned once', () async {
    final out1 = await service.clone(expertKey: 'acme/experts/pm');
    final out2 = await service.clone(expertKey: 'acme/experts/pm');

    expect(out1!.key, out2!.key);
    expect(await store.loadAll(), hasLength(1));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/expert_hub/expert_clone_service_test.dart`
Expected: FAIL — import `expert_clone_service.dart` cannot be resolved.

- [ ] **Step 3: Implement**

Create `client/lib/services/expert_hub/expert_clone_service.dart`:

```dart
import '../../models/discoverable_member.dart';
import 'composite_expert_hub_source.dart';
import 'expert_member_resolver.dart';
import 'local_member_template_store.dart';

/// Built-in catalog key prefix — always resolvable, never cloned.
const String kBuiltinExpertKeyPrefix = 'teampilot/builtin/';

/// Result of attempting to clone one expert for a team roster slot.
class ExpertCloneOutcome {
  const ExpertCloneOutcome({required this.key, required this.cloned});

  /// The key the roster slot should reference (kept or new local key).
  final String key;

  /// True when a new local copy was created in My Experts.
  final bool cloned;
}

/// Clones a catalog expert into My Experts when missing, so a cloned team is
/// self-contained. One instance per clone run (holds the run-scoped memo).
///
/// Returns the key the slot should reference, or `null` if the expert cannot
/// be resolved (caller reports a non-blocking failure).
class ExpertCloneService {
  ExpertCloneService({
    required CompositeExpertHubSource source,
    LocalMemberTemplateStore? localStore,
  }) : _source = source,
       _localStore = localStore ?? LocalMemberTemplateStore();

  final CompositeExpertHubSource _source;
  final LocalMemberTemplateStore _localStore;

  /// Run-scoped memo: catalog key -> cloned local key (one clone per expert).
  final Map<String, String> _memo = {};

  Future<ExpertCloneOutcome?> clone({
    required String expertKey,
    String? originTeamKey,
  }) async {
    final key = expertKey.trim();
    if (key.isEmpty) return null;

    if (LocalMemberTemplateStore.isLocalKey(key)) {
      final local = await _localStore.getByKey(key);
      if (local == null) return null; // dangling local key
      return ExpertCloneOutcome(key: key, cloned: false);
    }

    if (key.startsWith(kBuiltinExpertKeyPrefix)) {
      return ExpertCloneOutcome(key: key, cloned: false);
    }

    final memoized = _memo[key];
    if (memoized != null) {
      return ExpertCloneOutcome(key: memoized, cloned: true);
    }

    final existing = await _findLocalByCatalogKey(key);
    if (existing != null) {
      _memo[key] = existing.key;
      return ExpertCloneOutcome(key: existing.key, cloned: false);
    }

    final expert = await ExpertMemberResolver.resolveMember(
      key: key,
      source: _source,
      localStore: _localStore,
    );
    if (expert == null) return null;

    final saved = await _localStore.save(
      expert.copyWith(catalogKey: key, originTeamKey: originTeamKey),
    );
    _memo[key] = saved.key;
    return ExpertCloneOutcome(key: saved.key, cloned: true);
  }

  Future<DiscoverableMember?> _findLocalByCatalogKey(String catalogKey) async {
    final locals = await _localStore.loadAll();
    for (final member in locals) {
      if (member.catalogKey == catalogKey) return member;
    }
    return null;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/expert_hub/expert_clone_service_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/expert_hub/expert_clone_service.dart client/test/services/expert_hub/expert_clone_service_test.dart
git commit -m "feat(expert): add ExpertCloneService to clone missing experts"
```

---

### Task 4: `TeamCloneService` integration

**Files:**
- Modify: `client/lib/services/team/team_clone_service.dart`
- Test: `client/test/services/team/team_clone_service_test.dart`

**Interfaces:**
- Consumes: `ExpertCloneService` → `ExpertCloneOutcome`, `ExpertSlotCloner` (defined here).
- Produces:
  - `typedef ExpertSlotCloner = Future<ExpertCloneOutcome?> Function({required String expertKey, String? originTeamKey});`
  - `typedef ExpertSlotClonerFactory = ExpertSlotCloner Function();`
  - `TeamCloneService` constructor gains `required ExpertSlotClonerFactory expertClonerFactory`.
  - `DependencyKind` gains `expert` value.
  - `CloneDepInstallSummary` gains `expertKeys` (`List<String>`, default `const []`) / `expertCount`; `totalCount` includes it; `isEmpty` considers it.
  - `CloneResult.installed` carries cloned expert keys.

- [ ] **Step 1: Write the failing tests**

Update `client/test/services/team/team_clone_service_test.dart`:

Add `expertClonerFactory` to all three existing `TeamCloneService(...)` constructions (a keep-as-is cloner):

```dart
      expertClonerFactory: () => ({required expertKey, originTeamKey}) async =>
          ExpertCloneOutcome(key: expertKey, cloned: false),
```

Add new tests at the end of `main()`:

```dart
  test('repoints roster slots to cloned local expert keys', () async {
    TeamRosterSlot? createdSlot;
    final service = TeamCloneService(
      installSkill: (d) async => null,
      installPlugin: (d) async => null,
      installMcp: (d) async => null,
      expertClonerFactory: () =>
          ({required expertKey, originTeamKey}) async => expertKey ==
                  'catalog/pm'
              ? ExpertCloneOutcome(key: 'local/cloned-pm', cloned: true)
              : ExpertCloneOutcome(key: expertKey, cloned: false),
      createTeam:
          ({
            required name,
            required cli,
            required teamMode,
            required roster,
            required skillIds,
            required pluginIds,
            required mcpServerIds,
            required description,
            required extraArgs,
            String? hubSourceKey,
          }) async {
            createdSlot = roster.single;
            return 'squad';
          },
    );

    final result = await service.clone(
      const DiscoverableTeam(
        key: 'o/r/squad',
        name: 'Squad',
        description: 'd',
        category: 'AI',
        updatedAt: 1,
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
        roster: [TeamRosterSlot(id: 'pm', expertKey: 'catalog/pm')],
      ),
    );

    expect(createdSlot!.expertKey, 'local/cloned-pm');
    expect(result.installed.expertCount, 1);
    expect(result.installed.expertKeys, ['local/cloned-pm']);
    expect(result.failedDeps, isEmpty);
  });

  test('unresolvable expert is a non-blocking failure, key kept', () async {
    TeamRosterSlot? createdSlot;
    final service = TeamCloneService(
      installSkill: (d) async => null,
      installPlugin: (d) async => null,
      installMcp: (d) async => null,
      expertClonerFactory: () => ({required expertKey, originTeamKey}) async =>
          null,
      createTeam:
          ({
            required name,
            required cli,
            required teamMode,
            required roster,
            required skillIds,
            required pluginIds,
            required mcpServerIds,
            required description,
            required extraArgs,
            String? hubSourceKey,
          }) async {
            createdSlot = roster.single;
            return 'squad';
          },
    );

    final result = await service.clone(
      const DiscoverableTeam(
        key: 'o/r/squad',
        name: 'Squad',
        description: 'd',
        category: 'AI',
        updatedAt: 1,
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
        roster: [TeamRosterSlot(id: 'pm', expertKey: 'catalog/pm')],
      ),
    );

    expect(createdSlot!.expertKey, 'catalog/pm',
        reason: 'original key kept on failure');
    expect(result.failedDeps, hasLength(1));
    expect(result.failedDeps.single.kind, DependencyKind.expert);
    expect(result.failedDeps.single.name, 'catalog/pm');
    expect(result.installed.expertCount, 0);
  });
```

Note: `DiscoverableTeam` has no `copyWith`; the new tests construct the team inline with the custom roster.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/services/team/team_clone_service_test.dart`
Expected: FAIL — `expertClonerFactory` is not a named parameter of `TeamCloneService`; `DependencyKind.expert` does not exist; `CloneDepInstallSummary.expertCount` does not exist; import of `ExpertCloneOutcome` unresolved.

- [ ] **Step 3: Implement**

In `client/lib/services/team/team_clone_service.dart`:

Add import at the top:

```dart
import '../expert_hub/expert_clone_service.dart';
```

Add the typedefs after the `McpDepInstaller` typedef:

```dart
/// Clones one roster expert for a team clone; returns the key the slot should
/// reference (kept or new local key), or null on failure.
typedef ExpertSlotCloner = Future<ExpertCloneOutcome?> Function({
  required String expertKey,
  String? originTeamKey,
});

/// Produces a per-clone-run [ExpertSlotCloner] (run-scoped memoization).
typedef ExpertSlotClonerFactory = ExpertSlotCloner Function();
```

Add `expert` to `DependencyKind`:

```dart
enum DependencyKind { skill, plugin, mcp, expert }
```

Add `expertKeys` to `CloneDepInstallSummary`:

```dart
  const CloneDepInstallSummary({
    this.skillIds = const [],
    this.pluginIds = const [],
    this.mcpIds = const [],
    this.expertKeys = const [],
  });

  final List<String> skillIds;
  final List<String> pluginIds;
  final List<String> mcpIds;
  final List<String> expertKeys;

  int get skillCount => skillIds.length;
  int get pluginCount => pluginIds.length;
  int get mcpCount => mcpIds.length;
  int get expertCount => expertKeys.length;
  int get totalCount => skillCount + pluginCount + mcpCount + expertCount;
  bool get isEmpty => totalCount == 0;
```

Update `==` and `hashCode` to include `expertKeys`.

Add constructor param and field:

```dart
  TeamCloneService({
    required this.installSkill,
    required this.installPlugin,
    required this.installMcp,
    required this.expertClonerFactory,
    required this.createTeam,
  });

  final SkillDepInstaller installSkill;
  final PluginDepInstaller installPlugin;
  final McpDepInstaller installMcp;
  final ExpertSlotClonerFactory expertClonerFactory;
  final ClonedTeamCreator createTeam;
```

Replace the body of `clone()` — specifically, replace the `final now = ...` / roster-stamping block (`team_clone_service.dart:162-169`) and the `createTeam(...)` call's `roster:` argument — with:

```dart
    final cloner = expertClonerFactory();
    final now = DateTime.now().millisecondsSinceEpoch;
    final clonedExpertKeys = <String>[];
    final repointedRoster = <TeamRosterSlot>[];
    for (final slot in team.roster) {
      final key = slot.expertKey.trim();
      final base = slot.joinedAt == 0 ? slot.copyWith(joinedAt: now) : slot;
      if (key.isEmpty) {
        repointedRoster.add(base);
        continue;
      }
      final outcome = await cloner(expertKey: key, originTeamKey: team.key);
      if (outcome == null) {
        failed.add(DependencyFailure(DependencyKind.expert, key));
        repointedRoster.add(base);
      } else {
        if (outcome.cloned) clonedExpertKeys.add(outcome.key);
        repointedRoster.add(
          outcome.key == key ? base : base.copyWith(expertKey: outcome.key),
        );
      }
      progress('expert:$key');
    }

    final teamId = await createTeam(
      name: team.name,
      cli: team.cli,
      teamMode: team.teamMode,
      roster: repointedRoster,
      skillIds: skillIds,
      pluginIds: pluginIds,
      mcpServerIds: mcpIds,
      description: team.description,
      extraArgs: team.extraArgs,
      hubSourceKey: team.key,
    );
    if (teamId == null) {
      throw CloneException('team creation failed for "${team.name}"');
    }
    return CloneResult(
      teamId: teamId,
      installed: CloneDepInstallSummary(
        skillIds: skillIds,
        pluginIds: pluginIds,
        mcpIds: mcpIds,
        expertKeys: clonedExpertKeys,
      ),
      failedDeps: failed,
    );
```

Update the `total` computation at the top of `clone()` to include expert slots:

```dart
    final total =
        team.skillDeps.length +
        team.pluginDeps.length +
        team.mcpDeps.length +
        team.roster.where((s) => s.expertKey.trim().isNotEmpty).length;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/services/team/team_clone_service_test.dart`
Expected: PASS (all tests, including the 2 new ones).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team/team_clone_service.dart client/test/services/team/team_clone_service_test.dart
git commit -m "feat(clone): clone missing roster experts into My Experts during team clone"
```

---

### Task 5: Wire `expertClonerFactory` in `app_shell.dart`

**Files:**
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Consumes: `TeamCloneService` (Task 4), `ExpertCloneService` (Task 3), `CompositeExpertHubSource.withDefaults`.
- Produces: working wiring — no unit test (integration point); verified by `flutter analyze`.

- [ ] **Step 1: Move `compositeExpertHubSource` construction earlier**

In `client/lib/app/app_shell.dart`, the block currently around lines 1004-1008:

```dart
  final expertHubFavorites = ExpertHubFavoritesStore();
  final compositeExpertHubSource = CompositeExpertHubSource.withDefaults(
    registry: GitRegistryExpertHubSource(),
    teamIndex: teamHubSource.fetchTeams,
  );
```

Move **only the `compositeExpertHubSource` line** to just before the `TeamCloneService(` construction (before line 951), and keep `expertHubFavorites` where it is. The moved block becomes:

```dart
  final compositeExpertHubSource = CompositeExpertHubSource.withDefaults(
    registry: GitRegistryExpertHubSource(),
    teamIndex: teamHubSource.fetchTeams,
  );
```

So the order becomes: `teamHubSource` (947) → `compositeExpertHubSource` (new, before `teamCloneService`) → `teamCloneService` → … → `expertHubFavorites` (original location, still before `teamCubit.attachExpertHubSource(compositeExpertHubSource)`).

- [ ] **Step 2: Pass `expertClonerFactory` to `TeamCloneService`**

In the `TeamCloneService(` construction, after `installMcp: mcpCubit.installTeamDependency,`, add:

```dart
    expertClonerFactory: () {
      final cloner = ExpertCloneService(source: compositeExpertHubSource);
      return ({required expertKey, originTeamKey}) =>
          cloner.clone(expertKey: expertKey, originTeamKey: originTeamKey);
    },
```

Add the import at the top of the file (with the other expert_hub imports):

```dart
import '../services/expert_hub/expert_clone_service.dart';
```

- [ ] **Step 3: Verify it compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new errors/warnings (pre-existing ones allowed at this point).

- [ ] **Step 4: Commit**

```bash
git add client/lib/app/app_shell.dart
git commit -m "feat(clone): wire expert cloning into team clone service"
```

---

### Task 6: l10n + clone toast

**Files:**
- Modify: `client/lib/pages/team_hub/team_hub_clone_feedback.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/team_hub/team_hub_clone_feedback_test.dart`

**Interfaces:**
- Consumes: `CloneDepInstallSummary.expertCount` (Task 4).
- Produces: `l10n.teamHubCloneSuccessWithDeps(name, skillCount, pluginCount, mcpCount, expertCount)` and `l10n.teamHubClonePartial(name, skillCount, pluginCount, mcpCount, expertCount, failedCount, failedNames)`.

- [ ] **Step 1: Write the failing tests**

Update `client/test/pages/team_hub/team_hub_clone_feedback_test.dart`:

Update the expected string in "success with deps lists install counts":

```dart
    expect(
      msg,
      'Cloned "Squad". Installed 2 skills, 1 plugins, and 0 MCP servers, and cloned 0 experts.',
    );
```

Add a new test:

```dart
  test('success lists cloned expert count', () {
    final msg = teamHubCloneToastMessage(
      l10n,
      teamName: 'Squad',
      result: const CloneResult(
        teamId: 'id',
        installed: CloneDepInstallSummary(expertKeys: ['local/pm']),
        failedDeps: [],
      ),
    );
    expect(
      msg,
      'Cloned "Squad". Installed 0 skills, 0 plugins, and 0 MCP servers, and cloned 1 experts.',
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/team_hub/team_hub_clone_feedback_test.dart`
Expected: FAIL — `teamHubCloneSuccessWithDeps` still has 4 params / old string.

- [ ] **Step 3: Update the arb files**

In `client/lib/l10n/app_en.arb`, replace:

```json
  "teamHubCloneSuccessWithDeps": "Cloned \"{name}\". Installed {skillCount} skills, {pluginCount} plugins, and {mcpCount} MCP servers.",
  "@teamHubCloneSuccessWithDeps": {
    "placeholders": {
      "name": {},
      "skillCount": {"type": "int"},
      "pluginCount": {"type": "int"},
      "mcpCount": {"type": "int"}
    }
  },
```

with:

```json
  "teamHubCloneSuccessWithDeps": "Cloned \"{name}\". Installed {skillCount} skills, {pluginCount} plugins, and {mcpCount} MCP servers, and cloned {expertCount} experts.",
  "@teamHubCloneSuccessWithDeps": {
    "placeholders": {
      "name": {},
      "skillCount": {"type": "int"},
      "pluginCount": {"type": "int"},
      "mcpCount": {"type": "int"},
      "expertCount": {"type": "int"}
    }
  },
```

Replace `teamHubClonePartial` with:

```json
  "teamHubClonePartial": "Cloned \"{name}\". Installed {skillCount} skills, {pluginCount} plugins, {mcpCount} MCP servers, cloned {expertCount} experts. {failedCount} could not be installed: {failedNames}.",
  "@teamHubClonePartial": {
    "placeholders": {
      "name": {},
      "skillCount": {"type": "int"},
      "pluginCount": {"type": "int"},
      "mcpCount": {"type": "int"},
      "expertCount": {"type": "int"},
      "failedCount": {"type": "int"},
      "failedNames": {}
    }
  },
```

In `client/lib/l10n/app_zh.arb`, replace `teamHubCloneSuccessWithDeps` with:

```json
  "teamHubCloneSuccessWithDeps": "已克隆「{name}」。已安装 {skillCount} 个 Skill、{pluginCount} 个插件、{mcpCount} 个 MCP 服务,并克隆了 {expertCount} 个专家。",
  "@teamHubCloneSuccessWithDeps": {
    "placeholders": {
      "name": {},
      "skillCount": {"type": "int"},
      "pluginCount": {"type": "int"},
      "mcpCount": {"type": "int"},
      "expertCount": {"type": "int"}
    }
  },
```

Replace `teamHubClonePartial` with:

```json
  "teamHubClonePartial": "已克隆「{name}」。已安装 {skillCount} 个 Skill、{pluginCount} 个插件、{mcpCount} 个 MCP 服务,克隆了 {expertCount} 个专家;{failedCount} 个未能安装:{failedNames}。",
  "@teamHubClonePartial": {
    "placeholders": {
      "name": {},
      "skillCount": {"type": "int"},
      "pluginCount": {"type": "int"},
      "mcpCount": {"type": "int"},
      "expertCount": {"type": "int"},
      "failedCount": {"type": "int"},
      "failedNames": {}
    }
  },
```

- [ ] **Step 4: Regenerate l10n**

Run: `cd client && flutter gen-l10n`
Expected: `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart` regenerate with the new 5-param / 7-param methods.

- [ ] **Step 5: Update `teamHubCloneToastMessage`**

In `client/lib/pages/team_hub/team_hub_clone_feedback.dart`, pass `expertCount` in both branches:

```dart
    return l10n.teamHubCloneSuccessWithDeps(
      teamName,
      installed.skillCount,
      installed.pluginCount,
      installed.mcpCount,
      installed.expertCount,
    );
```

and:

```dart
  return l10n.teamHubClonePartial(
    teamName,
    installed.skillCount,
    installed.pluginCount,
    installed.mcpCount,
    installed.expertCount,
    result.failedDeps.length,
    failedNames,
  );
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd client && flutter test test/pages/team_hub/team_hub_clone_feedback_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/team_hub/team_hub_clone_feedback.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/test/pages/team_hub/team_hub_clone_feedback_test.dart
git commit -m "feat(team-hub): report cloned expert count in clone toast"
```

---

### Task 7: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze + full test suite**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: analyzer clean; all tests pass (including `team_clone_service_test.dart`, `expert_clone_service_test.dart`, `local_member_template_store_test.dart`, `discoverable_member_test.dart`, `team_hub_clone_feedback_test.dart`).

- [ ] **Step 2: Commit any stragglers**

```bash
git status --short
```
Expected: no unexpected modified files. If a regenerated l10n file or a pre-existing working-tree change to the same files is present, confirm it is intentional before committing.

---

## Self-Review Notes

- **Spec coverage:** model field (Task 1), store persistence (Task 2), clone service (Task 3), TeamCloneService integration + summary + `DependencyKind.expert` (Task 4), wiring (Task 5), toast/l10n (Task 6). Non-goals respected: no per-expert dep install at clone, no local-key-convention change (`local/{uuid}` preserved), no built-in cloning.
- **Type consistency:** `ExpertCloneOutcome`/`ExpertCloneService` defined in Task 3 are consumed by Task 4 (`expertClonerFactory` typedef) and Task 5 (wiring). `CloneDepInstallSummary.expertKeys` from Task 4 feeds Task 6 (`expertCount`). `DiscoverableMember.copyWith` from Task 1 is used by Task 3.
- **Placeholder scan:** every code step shows full code; no TBD.
