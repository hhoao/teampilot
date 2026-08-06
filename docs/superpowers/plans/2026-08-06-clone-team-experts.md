# Clone Team — Shadow-Clone Missing Experts into My Experts — Implementation Plan (rev. 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a TeamHub team is cloned, roster-referenced experts that are not already cloned locally are cloned into My Experts under their **catalog key**, and resolution **shadows** the catalog entry — team rosters stay unchanged and the team becomes self-contained. No backward compatibility with the initial uuid-clone layout beyond a one-time cleanup.

**Architecture:** `LocalExpertStore` (replaces `LocalMemberTemplateStore`) stores clones under `member-hub/local-templates/{key}.json` (nested, key = catalog key) and user-created experts under `local/{uuid}.json`. `ExpertMemberResolver.resolveMember` checks the store for **any** key first (shadow); `CompositeExpertHubSource.fetchMembers` dedups so a local clone shadows the catalog entry in listings. `ExpertCloneService` is a stateless singleton (O(1) dedup by key existence). `TeamCloneService` takes a plain `ExpertSlotCloner` (tear-off), roster unchanged, counts clones / records `DependencyKind.expert` failures. `DiscoverableMember` drops `catalogKey`, gains `ExpertMemberSource.clone` + `clonedAt`. A one-time `migrateLegacyLayout()` purges old uuid clones (files carrying `catalogKey`) and relocates legacy user-created files into `local/`.

**Tech Stack:** Dart / Flutter, flutter_bloc cubits, `LocalExpertStore` (Filesystem: `listDirRecursive`, `ensureDir`, `readString`), generated l10n.

## Global Constraints

- Layering: services in `client/lib/services/…`; models in `client/lib/models/…`; UI in `client/lib/pages/…`; wiring in `client/lib/app/app_shell.dart`.
- l10n: edit `app_en.arb` / `app_zh.arb` only; regenerate with `cd client && flutter gen-l10n`.
- Tests: constructor injection / `InMemoryFilesystem` (`client/test/support/in_memory_filesystem.dart`); no network.
- Final gate: `flutter analyze --no-fatal-infos --no-fatal-warnings` must show **0 non-`third_party/fastforge` errors** (that vendored dir is pre-existing noise) + `flutter test --exclude-tags integration`.
- Design spec: `docs/superpowers/specs/2026-08-06-clone-team-experts-design.md`.

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `client/lib/models/discoverable_member.dart` | Modify | Drop `catalogKey`; add `ExpertMemberSource.clone` + `clonedAt`; pure `copyWith` |
| `client/test/models/discoverable_member_test.dart` | Modify | Clone source / `clonedAt` round-trip; copyWith |
| `client/lib/services/expert_hub/local_expert_store.dart` | **Rename from** `local_member_template_store.dart` | Nested store, `getByKey` any key, `save` user-custom → `local/`, `putClone`, recursive `loadAll`, `migrateLegacyLayout` |
| `client/test/services/expert_hub/local_expert_store_test.dart` | **Rename from** `local_member_template_store_test.dart` | Store behaviors |
| `client/lib/services/expert_hub/expert_member_resolver.dart` | Modify | Shadow: local store first for any key |
| `client/lib/services/expert_hub/composite_expert_hub_source.dart` | Modify | Dedup: local shadows catalog/builtin/teamExtract by key |
| `client/test/services/expert_hub/composite_expert_hub_source_test.dart` | Modify | Shadow dedup |
| `client/lib/services/expert_hub/expert_clone_service.dart` | Modify | Stateless, O(1) dedup, `putClone`, `source: clone`, `clonedAt` |
| `client/test/services/expert_hub/expert_clone_service_test.dart` | Modify | Shadow clone / reuse / builtin / failure |
| `client/lib/services/team/team_clone_service.dart` | Modify | `expertCloner` plain function (no factory); no repoint |
| `client/test/services/team/team_clone_service_test.dart` | Modify | No repoint, counts, failure |
| `client/lib/app/app_shell.dart` | Modify | Singleton store + clone service; `migrateLegacyLayout()`; tear-off |
| `client/lib/pages/expert_hub/expert_hub_cards.dart` | Modify | `ExpertMemberSource.clone` source label |
| `client/lib/cubits/expert_hub_cubit.dart` | Modify | `localOnly` includes `clone` |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | Modify | `expertHubSourceClone` |

---

### Task R1: `DiscoverableMember` — drop `catalogKey`, add `clone` source + `clonedAt`

**Files:** `client/lib/models/discoverable_member.dart`, `client/test/models/discoverable_member_test.dart`

**Interfaces:**
- Produces: `ExpertMemberSource.clone`, `DiscoverableMember.clonedAt` (`int?`), `DiscoverableMember.copyWith` (pure `??`, no `update*` flags).

- [ ] **Step 1: Write failing tests**

In `discoverable_member_test.dart`, replace the `catalogKey` tests with:

```dart
  test('clone source and clonedAt round-trip through JSON', () {
    final m = DiscoverableMember(
      key: 'acme/experts/pm',
      name: 'Product Manager',
      description: 'Plans.',
      category: 'Business',
      source: ExpertMemberSource.clone,
      member: const DiscoverableTeamMember(name: 'pm'),
      originTeamKey: 'acme/teams/squad',
      clonedAt: 1723000000000,
    );
    final decoded = DiscoverableMember.fromJson(m.toJson());
    expect(decoded, m);
    expect(decoded.source, ExpertMemberSource.clone);
    expect(decoded.clonedAt, 1723000000000);
  });

  test('copyWith overrides source, originTeamKey and clonedAt', () {
    const m = DiscoverableMember(
      key: 'acme/experts/pm',
      name: 'PM',
      description: '',
      category: 'Business',
      source: ExpertMemberSource.registry,
      member: DiscoverableTeamMember(name: 'pm'),
    );
    final updated = m.copyWith(
      source: ExpertMemberSource.clone,
      originTeamKey: 'acme/teams/squad',
      clonedAt: 1723000000000,
    );
    expect(updated.source, ExpertMemberSource.clone);
    expect(updated.originTeamKey, 'acme/teams/squad');
    expect(updated.clonedAt, 1723000000000);
    expect(updated.key, 'acme/experts/pm');
  });
```

- [ ] **Step 2: Run to verify fail**

Run: `cd client && flutter test test/models/discoverable_member_test.dart`
Expected: FAIL — `clonedAt` not defined, `ExpertMemberSource.clone` not defined; `catalogKey` tests still reference removed field.

- [ ] **Step 3: Implement**

In `discoverable_member.dart`:
- `enum ExpertMemberSource` — add `clone('clone')` after `local('local')`.
- Add field after `originTeamKey`: `final int? clonedAt;` with constructor param `this.clonedAt,`.
- Remove `catalogKey` field + constructor param.
- `fromJson`: replace `catalogKey: json['catalogKey'] as String?,` with `clonedAt: (json['clonedAt'] as num?)?.toInt(),`.
- `toJson`: replace the `catalogKey` line with `if (clonedAt != null && clonedAt! > 0) 'clonedAt': clonedAt,`.
- `forLocale`: replace `catalogKey: catalogKey,` with `clonedAt: clonedAt,`.
- `==`: replace `catalogKey == other.catalogKey &&` with `clonedAt == other.clonedAt &&`.
- `hashCode`: replace `catalogKey,` with `clonedAt,`.
- `copyWith`: remove `updateOriginTeamKey` / `updateCatalogKey`; add `int? clonedAt`; pure `??` body.

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
    int? clonedAt,
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
      originTeamKey: originTeamKey ?? this.originTeamKey,
      clonedAt: clonedAt ?? this.clonedAt,
      i18n: i18n ?? this.i18n,
    );
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd client && flutter test test/models/discoverable_member_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/discoverable_member.dart client/test/models/discoverable_member_test.dart
git commit -m "refactor(expert): drop catalogKey, add clone source + clonedAt"
```

---

### Task R2: `LocalExpertStore` (rename + nested store + clone API + legacy migration)

**Files:**
- `client/lib/services/expert_hub/local_member_template_store.dart` → rename → `local_expert_store.dart`
- `client/test/services/expert_hub/local_member_template_store_test.dart` → rename → `local_expert_store_test.dart`

**Interfaces:**
- Consumes: `DiscoverableMember.copyWith`, `ExpertMemberSource` (R1).
- Produces:
  - `class LocalExpertStore { Future<DiscoverableMember> save(DiscoverableMember m); Future<DiscoverableMember> putClone(DiscoverableMember m); Future<DiscoverableMember?> getByKey(String key); Future<List<DiscoverableMember>> loadAll(); Future<void> delete(String key); Future<void> migrateLegacyLayout(); }`
  - `static bool isLocalKey(String key)` (kept; `local/` prefix = user-created).

- [ ] **Step 1: Rename the file + class (compile-fix sweep)**

```bash
cd client && git mv lib/services/expert_hub/local_member_template_store.dart lib/services/expert_hub/local_expert_store.dart
git mv test/services/expert_hub/local_member_template_store_test.dart test/services/expert_hub/local_expert_store_test.dart
```
In both files, rename `LocalMemberTemplateStore` → `LocalExpertStore`. Fix the three `lib` importers (`composite_expert_hub_source.dart`, `expert_member_resolver.dart`, `expert_clone_service.dart`) and their tests to import `local_expert_store.dart`. Re-run the store test to keep it green before behavior changes.

- [ ] **Step 2: Write failing tests (nested / any-key / putClone / migrate)**

In `local_expert_store_test.dart`, add:

```dart
  test('putClone stores under the catalog key (nested path)', () async {
    final saved = await store.putClone(
      _sampleMember().copyWith(
        key: 'acme/experts/pm',
        source: ExpertMemberSource.clone,
        originTeamKey: 'acme/teams/squad',
        clonedAt: 1723000000000,
      ),
    );
    expect(saved.key, 'acme/experts/pm');
    final loaded = await store.getByKey('acme/experts/pm');
    expect(loaded, isNotNull);
    expect(loaded!.source, ExpertMemberSource.clone);
    expect(loaded.originTeamKey, 'acme/teams/squad');
  });

  test('getByKey reads any key (shadow lookup)', () async {
    await store.putClone(_sampleMember().copyWith(key: 'acme/experts/pm'));
    expect(await store.getByKey('acme/experts/pm'), isNotNull);
  });

  test('save keeps user-custom keys under the local/ namespace', () async {
    final saved = await store.save(_sampleMember());
    expect(saved.key, 'local/test-uuid');
    expect(await store.getByKey('local/test-uuid'), isNotNull);
  });

  test('loadAll reads nested clone files', () async {
    await store.putClone(_sampleMember().copyWith(key: 'acme/experts/pm'));
    await store.save(_sampleMember());
    final loaded = await store.loadAll();
    expect(loaded.map((m) => m.key), containsAll(['acme/experts/pm', 'local/test-uuid']));
  });

  test('migrateLegacyLayout purges old clones and keeps user-custom', () async {
    final ctx = fs.pathContext;
    final dir = AppPaths('/tp').memberHubLocalTemplatesDir;
    // old flat files at root
    await fs.writeString(
      ctx.join(dir, 'old-clone.json'),
      jsonEncode(_sampleMember().copyWith(catalogKey: 'acme/experts/pm').toJson()),
    );
    await fs.writeString(
      ctx.join(dir, 'old-custom.json'),
      jsonEncode(_sampleMember().copyWith(key: 'local/old-custom').toJson()),
    );
    await store.migrateLegacyLayout();
    expect(fs.fileExists(ctx.join(dir, 'old-clone.json')), isFalse);
    expect(await store.getByKey('local/old-custom'), isNotNull);
  });
```

Note: the migrate test needs `dart:convert` for `jsonEncode` and an in-memory `fs.fileExists` helper (add it if missing).

- [ ] **Step 3: Run to verify fail**

Run: `cd client && flutter test test/services/expert_hub/local_expert_store_test.dart`
Expected: FAIL — `putClone`/`migrateLegacyLayout`/any-key `getByKey` not implemented; nested reads miss.

- [ ] **Step 4: Implement**

In `local_expert_store.dart`:
- Path helpers: `String _pathForKey(String key) => ctx.join(_dir, '$key.json');`
- `save`: assign `local/{uuid}` when not `isLocalKey`; write to `_pathForKey(newKey)` with `ensureDir(ctx.dirname(...))`.
- `putClone`: write under `member.key` verbatim with `ensureDir` of parent; return member.
- `getByKey`: read `_pathForKey(key)` for **any** key (drop the `isLocalKey` guard); null on missing/invalid.
- `loadAll`: use `_fs.listDirRecursive(_dir)`; skip non-`.json`; parse each; skip unreadable.
- `delete`: remove `_pathForKey(key)` (best-effort); keep behavior.
- `migrateLegacyLayout`: non-recursive `_fs.listDir(_dir)`; for each root `.json`: read raw text; `jsonDecode`; if `json['catalogKey']` is a non-empty String → delete; else (legacy user-custom, key is `local/...`) → re-save via the new path (`putClone`-style write under the same key) and delete the old root file.

- [ ] **Step 5: Run to verify pass**

Run: `cd client && flutter test test/services/expert_hub/local_expert_store_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A client/lib/services/expert_hub/local_expert_store.dart client/lib/services/expert_hub/local_member_template_store.dart client/lib/services/expert_hub/composite_expert_hub_source.dart client/lib/services/expert_hub/expert_member_resolver.dart client/lib/services/expert_hub/expert_clone_service.dart client/test/services/expert_hub/local_expert_store_test.dart client/test/services/expert_hub/local_member_template_store_test.dart
git commit -m "refactor(expert): rename to LocalExpertStore with shadow clone storage"
```

---

### Task R3: Resolution shadow (resolver + hub source dedup)

**Files:**
- `client/lib/services/expert_hub/expert_member_resolver.dart`
- `client/lib/services/expert_hub/composite_expert_hub_source.dart`
- `client/test/services/expert_hub/composite_expert_hub_source_test.dart`

**Interfaces:**
- Consumes: `LocalExpertStore` (R2).
- Produces: `resolveMember` prefers local for any key; `fetchMembers` local shadows builtin/registry/teamExtract.

- [ ] **Step 1: Write failing tests**

In `composite_expert_hub_source_test.dart`, add:

```dart
  test('local clone shadows a registry entry with the same key', () async {
    final registryMember = DiscoverableMember(
      key: 'acme/experts/pm', name: 'Registry PM', description: '', category: 'c',
      source: ExpertMemberSource.registry, member: const DiscoverableTeamMember(name: 'pm'));
    await store.putClone(registryMember.copyWith(
      source: ExpertMemberSource.clone, name: 'Cloned PM'));
    final source = CompositeExpertHubSource(
      builtIns: const [], registry: _FakeExpertHubSource([registryMember]), localStore: store);
    final members = await source.fetchMembers();
    expect(members.map((m) => m.key), contains('acme/experts/pm'));
    expect(members.where((m) => m.key == 'acme/experts/pm'), hasLength(1));
    expect(members.firstWhere((m) => m.key == 'acme/experts/pm').name, 'Cloned PM');
  });
```

Add a resolver test in `expert_member_resolver_test.dart`:

```dart
  test('resolveMember prefers a local clone over the catalog', () async {
    await store.putClone(_catalogExpert().copyWith(source: ExpertMemberSource.clone));
    final resolved = await ExpertMemberResolver.resolveMember(
      key: 'acme/experts/pm', source: compositeSource, localStore: store);
    expect(resolved, isNotNull);
    expect(resolved!.source, ExpertMemberSource.clone);
  });
```

(Adjust to the existing test helpers in each file.)

- [ ] **Step 2: Run to verify fail**

Run: `cd client && flutter test test/services/expert_hub/composite_expert_hub_source_test.dart test/services/expert_hub/expert_member_resolver_test.dart`
Expected: FAIL — duplicate entries / registry wins.

- [ ] **Step 3: Implement**

`expert_member_resolver.dart` — replace the `isLocalKey` guard with any-key shadow:

```dart
    final store = localStore ?? LocalExpertStore();
    final local = await store.getByKey(trimmed);
    if (local != null) return local;
```

`composite_expert_hub_source.dart` `fetchMembers` — filter by local keys:

```dart
    final local = await _localStore.loadAll();
    final localKeys = local.map((m) => m.key).toSet();
    final builtinKeys = builtIns.map((m) => m.key).toSet();
    final builtins = _builtIns
        .where((m) => !localKeys.contains(m.key))
        .toList(growable: false);
    final registryOnly = registry
        .where((m) => !builtinKeys.contains(m.key) && !localKeys.contains(m.key))
        .toList(growable: false);
    final preferredHashes = {
      for (final m in [...builtins, ...registryOnly])
        memberContentHash(m.member),
    };
    final teamExtractOnly = teamExtract
        .where((m) =>
            !localKeys.contains(m.key) &&
            !preferredHashes.contains(memberContentHash(m.member)))
        .toList(growable: false);
    return [...builtins, ...registryOnly, ...teamExtractOnly, ...local];
```

- [ ] **Step 4: Run to verify pass**

Run: `cd client && flutter test test/services/expert_hub/composite_expert_hub_source_test.dart test/services/expert_hub/expert_member_resolver_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/expert_hub/expert_member_resolver.dart client/lib/services/expert_hub/composite_expert_hub_source.dart client/test/services/expert_hub/composite_expert_hub_source_test.dart client/test/services/expert_hub/expert_member_resolver_test.dart
git commit -m "feat(expert): shadow local clones over catalog in resolution"
```

---

### Task R4: `ExpertCloneService` — stateless singleton

**Files:** `client/lib/services/expert_hub/expert_clone_service.dart`, `client/test/services/expert_hub/expert_clone_service_test.dart`

**Interfaces:**
- Consumes: `LocalExpertStore` (R2), shadow resolver (R3), `ExpertMemberSource.clone`, `clonedAt` (R1).
- Produces: `class ExpertCloneOutcome { const ExpertCloneOutcome({required this.cloned}); final bool cloned; }`; `ExpertCloneService.clone({required String expertKey, String? originTeamKey}) → Future<ExpertCloneOutcome?>` (null = failure).

- [ ] **Step 1: Rewrite tests**

Rewrite `expert_clone_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_clone_service.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/local_expert_store.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeExpertHubSource implements ExpertHubSource {
  _FakeExpertHubSource(this.members);
  final List<DiscoverableMember> members;
  @override
  Future<List<DiscoverableMember>> fetchMembers({bool forceRefresh = false}) async => members;
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
      member: const DiscoverableTeamMember(name: 'pm', responsibilities: 'You are a PM.'),
    );

void main() {
  late InMemoryFilesystem fs;
  late LocalExpertStore store;
  late ExpertCloneService service;

  setUp(() {
    fs = InMemoryFilesystem();
    store = LocalExpertStore(
      fs: fs,
      dirOverride: AppPaths('/tp').memberHubLocalTemplatesDir,
      uuidFactory: () => 'test-uuid',
    );
    final source = CompositeExpertHubSource(
      builtIns: const [],
      registry: _FakeExpertHubSource([_catalogExpert()]),
      localStore: store,
    );
    service = ExpertCloneService(source: source, store: store);
  });

  test('clones a catalog expert under its key with provenance', () async {
    final out = await service.clone(expertKey: 'acme/experts/pm', originTeamKey: 'acme/teams/squad');
    expect(out, isNotNull);
    expect(out!.cloned, isTrue);
    final saved = await store.getByKey('acme/experts/pm');
    expect(saved, isNotNull);
    expect(saved!.source, ExpertMemberSource.clone);
    expect(saved.originTeamKey, 'acme/teams/squad');
    expect(saved.clonedAt, greaterThan(0));
  });

  test('reuses an existing clone (O(1) dedup, no duplicate file)', () async {
    await service.clone(expertKey: 'acme/experts/pm');
    final second = await service.clone(expertKey: 'acme/experts/pm');
    expect(second, isNotNull);
    expect(second!.cloned, isFalse);
    expect(await store.loadAll(), hasLength(1));
  });

  test('built-in expert is kept, not cloned', () async {
    final out = await service.clone(expertKey: 'teampilot/builtin/team-lead');
    expect(out, isNotNull);
    expect(out!.cloned, isFalse);
    expect(await store.loadAll(), isEmpty);
  });

  test('unresolvable key is a failure', () async {
    expect(await service.clone(expertKey: 'acme/experts/nope'), isNull);
  });

  test('empty key is a failure', () async {
    expect(await service.clone(expertKey: '  '), isNull);
  });
}
```

- [ ] **Step 2: Run to verify fail**

Run: `cd client && flutter test test/services/expert_hub/expert_clone_service_test.dart`
Expected: FAIL — service still has per-run memo / `ExpertCloneOutcome.key` mismatch.

- [ ] **Step 3: Implement**

Rewrite `expert_clone_service.dart`:

```dart
import '../../models/discoverable_member.dart';
import 'composite_expert_hub_source.dart';
import 'expert_member_resolver.dart';
import 'local_expert_store.dart';

const String kBuiltinExpertKeyPrefix = 'teampilot/builtin/';

class ExpertCloneOutcome {
  const ExpertCloneOutcome({required this.cloned});
  final bool cloned;
}

class ExpertCloneService {
  ExpertCloneService({
    required CompositeExpertHubSource source,
    LocalExpertStore? store,
  }) : _source = source,
       _store = store ?? LocalExpertStore();

  final CompositeExpertHubSource _source;
  final LocalExpertStore _store;

  Future<ExpertCloneOutcome?> clone({
    required String expertKey,
    String? originTeamKey,
  }) async {
    final key = expertKey.trim();
    if (key.isEmpty) return null;

    if (key.startsWith(kBuiltinExpertKeyPrefix)) {
      return const ExpertCloneOutcome(cloned: false);
    }

    final existing = await _store.getByKey(key);
    if (existing != null) {
      return const ExpertCloneOutcome(cloned: false);
    }

    final expert = await ExpertMemberResolver.resolveMember(
      key: key,
      source: _source,
      localStore: _store,
    );
    if (expert == null) return null;

    await _store.putClone(
      expert.copyWith(
        source: ExpertMemberSource.clone,
        originTeamKey: originTeamKey,
        clonedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    return const ExpertCloneOutcome(cloned: true);
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd client && flutter test test/services/expert_hub/expert_clone_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/expert_hub/expert_clone_service.dart client/test/services/expert_hub/expert_clone_service_test.dart
git commit -m "refactor(expert): make ExpertCloneService stateless with O(1) dedup"
```

---

### Task R5: `TeamCloneService` — plain cloner, no repoint

**Files:** `client/lib/services/team/team_clone_service.dart`, `client/test/services/team/team_clone_service_test.dart`

**Interfaces:**
- Consumes: `ExpertCloneOutcome` (R4).
- Produces: `typedef ExpertSlotCloner = Future<ExpertCloneOutcome?> Function({required String expertKey, String? originTeamKey});`; `TeamCloneService({..., required ExpertSlotCloner expertCloner, ...})`.

- [ ] **Step 1: Update tests**

In `team_clone_service_test.dart`, replace all `expertClonerFactory:` with a direct cloner:

```dart
      expertCloner: ({required expertKey, originTeamKey}) async =>
          ExpertCloneOutcome(cloned: true),
```

Rewrite the "repoints roster slots" test to assert **no repoint** + counting:

```dart
  test('clones experts without repointing roster keys', () async {
    TeamRosterSlot? createdSlot;
    final service = TeamCloneService(
      installSkill: (d) async => null,
      installPlugin: (d) async => null,
      installMcp: (d) async => null,
      expertCloner: ({required expertKey, originTeamKey}) async =>
          ExpertCloneOutcome(cloned: true),
      createTeam: ({
        required name, required cli, required teamMode, required roster,
        required skillIds, required pluginIds, required mcpServerIds,
        required description, required extraArgs, String? hubSourceKey,
      }) async {
        createdSlot = roster.single;
        return 'squad';
      },
    );
    final result = await service.clone(const DiscoverableTeam(
      key: 'o/r/squad', name: 'Squad', description: 'd', category: 'AI',
      updatedAt: 1, cli: CliTool.claude, teamMode: TeamMode.mixed,
      roster: [TeamRosterSlot(id: 'pm', expertKey: 'catalog/pm')],
    ));
    expect(createdSlot!.expertKey, 'catalog/pm',
        reason: 'shadow model keeps the catalog key');
    expect(result.installed.expertCount, 1);
    expect(result.installed.expertKeys, ['catalog/pm']);
    expect(result.failedDeps, isEmpty);
  });
```

Keep the failure test (cloner returns null → `DependencyKind.expert` failure, slot unchanged).

- [ ] **Step 2: Run to verify fail**

Run: `cd client && flutter test test/services/team/team_clone_service_test.dart`
Expected: FAIL — `expertCloner` not a named param.

- [ ] **Step 3: Implement**

In `team_clone_service.dart`:
- `typedef ExpertSlotCloner` — keep.
- Remove `ExpertSlotClonerFactory` typedef and `expertClonerFactory`; add `required ExpertSlotCloner expertCloner` + field.
- In `clone()`: roster stays the stamped original; expert pass only records clones/failures (no repoint). Replace the repoint loop with:

```dart
    final now = DateTime.now().millisecondsSinceEpoch;
    final roster = team.roster
        .map((slot) => slot.joinedAt == 0 ? slot.copyWith(joinedAt: now) : slot)
        .toList(growable: false);

    final clonedExpertKeys = <String>[];
    for (final slot in team.roster) {
      final key = slot.expertKey.trim();
      if (key.isEmpty) continue;
      final outcome = await expertCloner(expertKey: key, originTeamKey: team.key);
      if (outcome == null) {
        failed.add(DependencyFailure(DependencyKind.expert, key));
      } else if (outcome.cloned) {
        clonedExpertKeys.add(key);
      }
      progress('expert:$key');
    }
```

`createTeam` receives `roster` (unchanged); summary keeps `expertKeys: clonedExpertKeys`.

- [ ] **Step 4: Run to verify pass**

Run: `cd client && flutter test test/services/team/team_clone_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team/team_clone_service.dart client/test/services/team/team_clone_service_test.dart
git commit -m "refactor(clone): plain expert cloner, roster unchanged under shadow model"
```

---

### Task R6: `app_shell.dart` wiring + one-time migration

**Files:** `client/lib/app/app_shell.dart`

- [ ] **Step 1: Implement**

Near the `compositeExpertHubSource` construction (already before `teamCloneService`):

```dart
  final localExpertStore = LocalExpertStore();
  await localExpertStore.migrateLegacyLayout();
  final expertCloneService = ExpertCloneService(
    source: compositeExpertHubSource,
    store: localExpertStore,
  );
```

Pass the tear-off:

```dart
    expertCloner: expertCloneService.clone,
```

Remove the old `expertClonerFactory: () { ... }` closure. Update the import `local_member_template_store.dart` → `local_expert_store.dart` (if present).

- [ ] **Step 2: Verify compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | grep -E "error •" | grep -v "third_party/fastforge"`
Expected: empty.

- [ ] **Step 3: Commit**

```bash
git add client/lib/app/app_shell.dart
git commit -m "feat(clone): wire shadow expert cloning + legacy migration in bootstrap"
```

---

### Task R7: clone source UI label + `localOnly` filter + l10n

**Files:**
- `client/lib/pages/expert_hub/expert_hub_cards.dart`
- `client/lib/cubits/expert_hub_cubit.dart`
- `client/lib/l10n/app_en.arb`, `app_zh.arb`
- regenerate `app_localizations*.dart`

- [ ] **Step 1: Add label + filter**

`expert_hub_cards.dart` source switch — add case:

```dart
      ExpertMemberSource.clone => l10n.expertHubSourceClone,
```

`expert_hub_cubit.dart` `localOnly` filter — include clones:

```dart
      base = base.where((m) =>
          m.source == ExpertMemberSource.local ||
          m.source == ExpertMemberSource.clone);
```

- [ ] **Step 2: arb + regen**

`app_en.arb` (after `expertHubSourceLocal`):
```json
  "expertHubSourceClone": "Cloned",
```
`app_zh.arb`:
```json
  "expertHubSourceClone": "克隆",
```
Run: `cd client && flutter gen-l10n`.

- [ ] **Step 3: Verify**

Run: `cd client && flutter test test/pages/expert_hub` and `flutter analyze ...` (non-fastforge).
Expected: PASS / 0 errors.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/expert_hub/expert_hub_cards.dart client/lib/cubits/expert_hub_cubit.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart
git commit -m "feat(expert-hub): show clone source label in expert hub"
```

---

### Task R8: Full verification

- [ ] **Step 1: Analyze + full suite**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | grep -E "error •" | grep -cv "third_party/fastforge"`
Expected: `0`.
Run: `cd client && flutter test --exclude-tags integration`
Expected: only the pre-existing `session_chat_view_draft_cache_test.dart` failures from the merged branch (unrelated); all clone/expert/store/resolver tests pass.

- [ ] **Step 2: Final commit of stragglers**

```bash
git status --short
```
Confirm only expected files remain modified; commit any stragglers with a clear message.
