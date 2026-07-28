# Team Landing Hub Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In team-mode landing, replace the flat local-team chip menu with recent teams + 「浏览全部团队」, opening a Team Hub–style picker that resolves (reuse-or-clone) to a local `teamId` for launch.

**Architecture:** Keep `TeamHubCubit` (discovery) and `LaunchProfileCubit` (launch identities) separate. Add `TeamProfile.hubSourceKey` provenance, `TeamLandingRecentStore`, pure chip/catalog helpers, and `TeamLandingSelection` use-case for resolve. Landing UI only wires browse → picker → `selectTeam`.

**Tech Stack:** Flutter / `flutter_bloc`; `TpDialog` / `TpActionMenuSpec` from `shared_ui`; existing `TeamCloneService` / `TeamHubCubit`; `flutter_test` + `InMemoryFilesystem`.

**Spec:** `docs/superpowers/specs/2026-07-28-team-landing-hub-picker-design.md`

## Global Constraints

- Product shape mirrors expert landing: recent ≤5 + browse-all → picker → confirm selects for launch.
- No clear/empty action on the team chip (team mode requires a team).
- Do **not** synthesize local `TeamProfile` into `TeamHubCubit` / `DiscoverableTeam`.
- Clone-or-reuse only via `hubSourceKey` (no name matching, no backfill of old clones).
- Multi-match earliest rule: `(createdAt asc, sortOrder asc, id asc)`.
- Recent path: `team-hub/recent.json` via `AppPaths.teamHubRecentJson`.
- Partial clone dep failures still succeed; toast via `teamHubCloneToastMessage`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` (or at least all new/changed test files listed in tasks).

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/team_config.dart` | `TeamProfile.hubSourceKey` field, JSON, `copyWith`, equality |
| `client/lib/services/team/team_clone_service.dart` | Pass `hubSourceKey: team.key` into `createTeam` |
| `client/lib/cubits/launch_profile_cubit.dart` | `addClonedTeam(..., hubSourceKey:)` persists provenance |
| `client/lib/app/app_shell.dart` | Wire `hubSourceKey` through `TeamCloneService.createTeam` lambda |
| `client/lib/services/storage/app_storage.dart` | `teamHubRecentJson` path helpers |
| `client/lib/services/team/team_landing_recent_store.dart` | Persist ordered local team ids |
| `client/lib/services/team/team_landing_selection.dart` | resolve local/hub → `teamId` (+ optional `CloneResult`) |
| `client/lib/pages/team_hub/team_landing_chip_menu.dart` | Pure chip menu specs |
| `client/lib/pages/team_hub/team_landing_catalog.dart` | `TeamLandingEntry` + filter/build helpers |
| `client/lib/pages/team_hub/team_landing_picker_sheet.dart` | Picker dialog |
| `client/lib/pages/team_hub/team_hub_detail_overlay.dart` | `pickerMode` + Confirm CTA |
| `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart` | Wire chip + picker |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | browse / confirm / already-added strings |
| Tests under `client/test/...` mirroring paths above | TDD coverage |

---

### Task 1: `TeamProfile.hubSourceKey`

**Files:**
- Modify: `client/lib/models/team_config.dart`
- Modify: `client/test/models/team_config_test.dart`

**Interfaces:**
- Consumes: existing `TeamProfile` ctor / JSON
- Produces:
  - `final String? hubSourceKey` on `TeamProfile`
  - `copyWith({String? hubSourceKey, bool updateHubSourceKey = false})`
  - JSON key `'hubSourceKey'` when non-empty; missing/empty decodes to `null`

- [ ] **Step 1: Write the failing test**

Append to `client/test/models/team_config_test.dart`:

```dart
test('round trips hubSourceKey and defaults missing to null', () {
  const team = TeamProfile(
    id: 'team-1',
    name: 'hello',
    hubSourceKey: 'owner/repo/slug',
  );
  final decoded = TeamProfile.fromJson(team.toJson());
  expect(decoded.hubSourceKey, 'owner/repo/slug');
  expect(decoded, team);

  final legacy = TeamProfile.fromJson({'id': 't', 'name': 'T'});
  expect(legacy.hubSourceKey, isNull);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/team_config_test.dart --name hubSourceKey`
Expected: FAIL (no named param / field)

- [ ] **Step 3: Implement `hubSourceKey`**

In `TeamProfile`:
1. Add ctor param `this.hubSourceKey` (nullable, default null) and field `final String? hubSourceKey`.
2. In `fromJson`, decode:
   ```dart
   hubSourceKey: () {
     final raw = json['hubSourceKey'] as String?;
     final trimmed = raw?.trim() ?? '';
     return trimmed.isEmpty ? null : trimmed;
   }(),
   ```
3. In `toJson`: `if (hubSourceKey != null && hubSourceKey!.isNotEmpty) 'hubSourceKey': hubSourceKey,`
4. In `copyWith`, add `String? hubSourceKey, bool updateHubSourceKey = false` and assign `hubSourceKey: updateHubSourceKey ? hubSourceKey : this.hubSourceKey`.
5. Include `hubSourceKey` in `==` and `hashCode`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/team_config_test.dart --name hubSourceKey`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/team_config.dart client/test/models/team_config_test.dart
git commit -m "$(cat <<'EOF'
feat(team): add TeamProfile.hubSourceKey provenance

EOF
)"
```

---

### Task 2: Clone path writes `hubSourceKey`

**Files:**
- Modify: `client/lib/services/team/team_clone_service.dart` (`ClonedTeamCreator`, `clone`)
- Modify: `client/lib/cubits/launch_profile_cubit.dart` (`addClonedTeam`)
- Modify: `client/lib/app/app_shell.dart` (createTeam lambda)
- Create: `client/test/services/team/team_clone_hub_source_key_test.dart`
- Reference: existing clone tests if any under `client/test/services/team/`

**Interfaces:**
- Consumes: Task 1 `TeamProfile.hubSourceKey`
- Produces:
  - `ClonedTeamCreator` gains `String? hubSourceKey`
  - `TeamCloneService.clone` passes `hubSourceKey: team.key`
  - `LaunchProfileCubit.addClonedTeam({..., String? hubSourceKey})` sets it on the new profile

- [ ] **Step 1: Write the failing test**

Create `client/test/services/team/team_clone_hub_source_key_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/services/team/team_clone_service.dart';

void main() {
  test('clone passes DiscoverableTeam.key as hubSourceKey to createTeam', () async {
    String? seenHubSourceKey;
    final service = TeamCloneService(
      installSkill: (_) async => null,
      installPlugin: (_) async => null,
      installMcp: (_) async => null,
      createTeam: ({
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
        seenHubSourceKey = hubSourceKey;
        return 'local-1';
      },
    );

    const team = DiscoverableTeam(
      key: 'owner/repo/demo',
      name: 'Demo',
      description: '',
      category: 'general',
      updatedAt: 1,
    );

    final result = await service.clone(team);
    expect(result.teamId, 'local-1');
    expect(seenHubSourceKey, 'owner/repo/demo');
  });
}
```

(Adjust `DiscoverableTeam` ctor fields if the real model requires more — match `client/lib/models/discoverable_team.dart`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/team/team_clone_hub_source_key_test.dart`
Expected: FAIL (typedef / createTeam arity)

- [ ] **Step 3: Minimal implementation**

1. Update `ClonedTeamCreator` in `team_clone_service.dart` to accept `String? hubSourceKey`.
2. In `clone`, pass `hubSourceKey: team.key` to `createTeam`.
3. Update `addClonedTeam` to take `String? hubSourceKey` and put it on the `TeamProfile(...)` before normalize/materialize.
4. Update `app_shell.dart` lambda to forward `hubSourceKey` into `teamCubit.addClonedTeam`.
5. Fix any other `ClonedTeamCreator` / `createTeam:` call sites the analyzer reports.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/team/team_clone_hub_source_key_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team/team_clone_service.dart \
  client/lib/cubits/launch_profile_cubit.dart \
  client/lib/app/app_shell.dart \
  client/test/services/team/team_clone_hub_source_key_test.dart
git commit -m "$(cat <<'EOF'
feat(team): persist hubSourceKey when cloning from Team Hub

EOF
)"
```

---

### Task 3: `TeamLandingRecentStore` + `AppPaths.teamHubRecentJson`

**Files:**
- Modify: `client/lib/services/storage/app_storage.dart`
- Create: `client/lib/services/team/team_landing_recent_store.dart`
- Create: `client/test/services/team/team_landing_recent_store_test.dart`
- Mirror: `client/lib/services/expert_hub/expert_hub_recent_store.dart`

**Interfaces:**
- Consumes: `AppStorage.fs`, `AppPaths`
- Produces:
  - `AppPaths.teamHubRecentJsonForTeampilotRoot` → `team-hub/recent.json`
  - `AppPaths.teamHubRecentJson` getter
  - `class TeamLandingRecentStore` with `static const maxEntries = 10`, `loadOrderedKeys()`, `touch(String teamId)`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/team/team_landing_recent_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late TeamLandingRecentStore store;

  setUp(() {
    fs = InMemoryFilesystem();
    final paths = AppPaths('/tp');
    store = TeamLandingRecentStore(
      fs: fs,
      pathOverride: paths.teamHubRecentJson,
    );
  });

  test('touch prepends teamId and dedupes', () async {
    await store.touch('team-a');
    await store.touch('team-b');
    expect(await store.loadOrderedKeys(), ['team-b', 'team-a']);
    await store.touch('team-a');
    expect(await store.loadOrderedKeys(), ['team-a', 'team-b']);
  });

  test('touch caps at maxEntries', () async {
    for (var i = 0; i < 12; i++) {
      await store.touch('team-$i');
    }
    final keys = await store.loadOrderedKeys();
    expect(keys.length, TeamLandingRecentStore.maxEntries);
    expect(keys.first, 'team-11');
    expect(keys, isNot(contains('team-0')));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/team/team_landing_recent_store_test.dart`
Expected: FAIL (missing type / path)

- [ ] **Step 3: Implement path + store**

1. In `app_storage.dart` next to `teamHubFavoritesJsonForTeampilotRoot`, add:
   ```dart
   static String teamHubRecentJsonForTeampilotRoot(String teampilotRoot) =>
       _pathUnderTeampilotRoot(teampilotRoot, 'team-hub/recent.json');
   ```
   and instance getter `teamHubRecentJson`.
2. Copy `ExpertHubRecentStore` to `TeamLandingRecentStore`, default path `AppStorage.paths.teamHubRecentJson`, same JSON shape `{'keys': [...]}`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/team/team_landing_recent_store_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/app_storage.dart \
  client/lib/services/team/team_landing_recent_store.dart \
  client/test/services/team/team_landing_recent_store_test.dart
git commit -m "$(cat <<'EOF'
feat(team): add TeamLandingRecentStore at team-hub/recent.json

EOF
)"
```

---

### Task 4: `TeamLandingSelection` resolve use-case

**Files:**
- Create: `client/lib/services/team/team_landing_selection.dart`
- Create: `client/test/services/team/team_landing_selection_test.dart`

**Interfaces:**
- Consumes: Task 1–3; `TeamCloneService.clone` (or `Future<CloneResult> Function(DiscoverableTeam)`)
- Produces:

```dart
class TeamLandingResolveSuccess {
  const TeamLandingResolveSuccess({
    required this.teamId,
    this.cloneResult,
  });
  final String teamId;
  /// Non-null only when a fresh hub clone ran.
  final CloneResult? cloneResult;
}

class TeamLandingSelectionException implements Exception {
  TeamLandingSelectionException(this.message);
  final String message;
}

class TeamLandingSelection {
  TeamLandingSelection({
    required Future<CloneResult> Function(DiscoverableTeam team) cloneTeam,
    required Future<void> Function(String teamId) touchRecent,
  });

  Future<TeamLandingResolveSuccess> resolveLocal({
    required String teamId,
    required List<TeamProfile> teams,
  });

  Future<TeamLandingResolveSuccess> resolveHub({
    required DiscoverableTeam team,
    required List<TeamProfile> teams,
  });
}

/// Shared earliest-match helper used by resolveHub and catalog mapping.
TeamProfile? earliestTeamWithHubSourceKey(
  List<TeamProfile> teams,
  String hubKey,
);
```

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/team_clone_service.dart';
import 'package:teampilot/services/team/team_landing_selection.dart';

DiscoverableTeam hub(String key) => DiscoverableTeam(
  key: key,
  name: 'Hub',
  description: '',
  category: 'general',
  updatedAt: 1,
);

void main() {
  test('resolveLocal returns id and touches recent', () async {
    final touched = <String>[];
    final selection = TeamLandingSelection(
      cloneTeam: (_) async => throw StateError('should not clone'),
      touchRecent: (id) async => touched.add(id),
    );
    final teams = [
      const TeamProfile(id: 'a', name: 'A'),
      const TeamProfile(id: 'b', name: 'B'),
    ];
    final ok = await selection.resolveLocal(teamId: 'b', teams: teams);
    expect(ok.teamId, 'b');
    expect(ok.cloneResult, isNull);
    expect(touched, ['b']);
  });

  test('resolveLocal throws when team missing', () async {
    final selection = TeamLandingSelection(
      cloneTeam: (_) async => throw StateError('no'),
      touchRecent: (_) async {},
    );
    expect(
      () => selection.resolveLocal(teamId: 'missing', teams: const []),
      throwsA(isA<TeamLandingSelectionException>()),
    );
  });

  test('resolveHub reuses earliest hubSourceKey match without cloning', () async {
    var clones = 0;
    final selection = TeamLandingSelection(
      cloneTeam: (_) async {
        clones++;
        return const CloneResult(
          teamId: 'new',
          installed: CloneDepInstallSummary(),
          failedDeps: [],
        );
      },
      touchRecent: (_) async {},
    );
    final teams = [
      const TeamProfile(
        id: 'newer',
        name: 'N',
        hubSourceKey: 'o/r/s',
        createdAt: 200,
        sortOrder: 0,
      ),
      const TeamProfile(
        id: 'older',
        name: 'O',
        hubSourceKey: 'o/r/s',
        createdAt: 100,
        sortOrder: 0,
      ),
    ];
    final ok = await selection.resolveHub(team: hub('o/r/s'), teams: teams);
    expect(ok.teamId, 'older');
    expect(ok.cloneResult, isNull);
    expect(clones, 0);
  });

  test('resolveHub clones when no match and touches new id', () async {
    final touched = <String>[];
    final selection = TeamLandingSelection(
      cloneTeam: (t) async => CloneResult(
        teamId: 'cloned-${t.key}',
        installed: const CloneDepInstallSummary(),
        failedDeps: const [],
      ),
      touchRecent: (id) async => touched.add(id),
    );
    final ok = await selection.resolveHub(
      team: hub('o/r/s'),
      teams: const [TeamProfile(id: 'other', name: 'X')],
    );
    expect(ok.teamId, 'cloned-o/r/s');
    expect(ok.cloneResult, isNotNull);
    expect(touched, ['cloned-o/r/s']);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/services/team/team_landing_selection_test.dart`
Expected: FAIL (library missing)

- [ ] **Step 3: Implement selection**

Implement `earliestTeamWithHubSourceKey` sort exactly as `(createdAt, sortOrder, id)`.
`resolveLocal`: trim id, find in `teams`, else throw; touch; return success.
`resolveHub`: if earliest match → touch + success; else `cloneTeam(team)` → touch `result.teamId` → success with `cloneResult`. Propagate `CloneException` as `TeamLandingSelectionException` or rethrow — picker will toast `teamHubCloneFailed`; prefer wrapping message for UI.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/services/team/team_landing_selection_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team/team_landing_selection.dart \
  client/test/services/team/team_landing_selection_test.dart
git commit -m "$(cat <<'EOF'
feat(team): add TeamLandingSelection resolve use-case

EOF
)"
```

---

### Task 5: Chip menu builder + l10n

**Files:**
- Create: `client/lib/pages/team_hub/team_landing_chip_menu.dart`
- Create: `client/test/pages/team_hub/team_landing_chip_menu_test.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Mirror: `client/lib/pages/expert_hub/expert_landing_chip_menu.dart`

**Interfaces:**
- Produces:

```dart
const kTeamLandingChipRecentLimit = 5;
enum TeamLandingChipAction { browseAll }

List<TpActionMenuSpec> buildTeamLandingChipMenuSpecs({
  required String browseAllLabel,
  required String? selectedTeamId,
  required List<({String id, String name})> recentTeams,
});
```

Menu order: recent items (≤5) → divider → browse all. **No** clear item. Empty recent still shows divider + browse all.

l10n keys:
- `teamHubBrowseAll`: EN `Browse all teams` / ZH `浏览全部团队`
- `teamHubConfirmSelection`: EN `Confirm` / ZH `确认`
- `teamHubAlreadyAdded`: EN `Already added` / ZH `已添加`

- [ ] **Step 1: Write the failing chip menu tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/team_hub/team_landing_chip_menu.dart';

void main() {
  group('buildTeamLandingChipMenuSpecs', () {
    test('orders recent, divider, browse all without clear', () {
      final specs = buildTeamLandingChipMenuSpecs(
        browseAllLabel: 'Browse all teams',
        selectedTeamId: 't1',
        recentTeams: const [
          (id: 't1', name: 'Alpha'),
          (id: 't2', name: 'Beta'),
        ],
      );
      expect(specs.map((s) => s.isDivider ? '|' : s.label).toList(), [
        'Alpha',
        'Beta',
        '|',
        'Browse all teams',
      ]);
      expect(specs.last.value, TeamLandingChipAction.browseAll);
      expect(specs.where((s) => s.value == 't1').single.selected, isTrue);
    });

    test('empty recent still exposes browse all', () {
      final specs = buildTeamLandingChipMenuSpecs(
        browseAllLabel: 'Browse all teams',
        selectedTeamId: null,
        recentTeams: const [],
      );
      expect(specs.map((s) => s.isDivider ? '|' : s.label).toList(), [
        '|',
        'Browse all teams',
      ]);
    });

    test('caps recent at kTeamLandingChipRecentLimit', () {
      final many = [for (var i = 0; i < 8; i++) (id: 't$i', name: 'T$i')];
      final specs = buildTeamLandingChipMenuSpecs(
        browseAllLabel: 'Browse all',
        selectedTeamId: 't1',
        recentTeams: many,
      );
      final recent = specs
          .where((s) => !s.isDivider && s.value is String)
          .map((s) => s.label)
          .toList();
      expect(recent, hasLength(kTeamLandingChipRecentLimit));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/pages/team_hub/team_landing_chip_menu_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement menu + ARB**

1. Implement `buildTeamLandingChipMenuSpecs` (icons: `Icons.groups_outlined` for teams, `Icons.travel_explore_outlined` for browse — match expert browse icon).
2. Add the three ARB keys near existing `teamHub*` strings in both `app_en.arb` and `app_zh.arb`.
3. Run `cd client && flutter gen-l10n` (or the project’s usual l10n generation if different — if analyze later complains about missing getters, generate).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/pages/team_hub/team_landing_chip_menu_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/team_hub/team_landing_chip_menu.dart \
  client/test/pages/team_hub/team_landing_chip_menu_test.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations*.dart
git commit -m "$(cat <<'EOF'
feat(team): add landing team chip menu and hub picker strings

EOF
)"
```

---

### Task 6: `TeamLandingEntry` catalog helpers

**Files:**
- Create: `client/lib/pages/team_hub/team_landing_catalog.dart`
- Create: `client/test/pages/team_hub/team_landing_catalog_test.dart`

**Interfaces:**

```dart
enum TeamLandingSourceFilter { all, mine, discovery }

sealed class TeamLandingEntry {
  String get name;
  String get description;
}

class TeamLandingLocalEntry extends TeamLandingEntry {
  TeamLandingLocalEntry(this.team);
  final TeamProfile team;
}

class TeamLandingHubEntry extends TeamLandingEntry {
  TeamLandingHubEntry(this.team, {this.localTeamId});
  final DiscoverableTeam team;
  final String? localTeamId; // set when hubSourceKey matched
}

class TeamLandingCatalogSections {
  const TeamLandingCatalogSections({
    required this.mine,
    required this.discovery,
  });
  final List<TeamLandingLocalEntry> mine;
  final List<TeamLandingHubEntry> discovery;
}

TeamLandingCatalogSections buildTeamLandingCatalog({
  required List<TeamProfile> localTeams,
  required List<DiscoverableTeam> hubTeams,
  required TeamLandingSourceFilter sourceFilter,
  required String searchQuery,
  required bool favoritesOnly,
  required Set<String> favoriteKeys,
  String? category, // null = all categories; discovery only
});
```

Rules from spec:
- Map each hub team’s `localTeamId` via `earliestTeamWithHubSourceKey(...)?.id`.
- Search: case-insensitive name/description on both sides.
- `sourceFilter.mine` → discovery empty; `discovery` → mine empty; `all` → both.
- `favoritesOnly` / `category` apply **only** to discovery rows.
- Default order inside sections: locals as provided (caller may sort by name); discovery as provided (caller uses hub sort).

- [ ] **Step 1: Write failing catalog tests** covering: already-added mapping, search, mine-only, discovery favorites filter, category filter does not drop mine when `all`.

- [ ] **Step 2: Run to verify fail**

Run: `cd client && flutter test test/pages/team_hub/team_landing_catalog_test.dart`

- [ ] **Step 3: Implement catalog**

Import `earliestTeamWithHubSourceKey` from `team_landing_selection.dart` (or move the helper to a tiny `team_hub_source_key.dart` if you want to avoid UI→service cycles — prefer keeping helper in `team_landing_selection.dart` and importing from catalog).

- [ ] **Step 4: Run to verify pass**

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/team_hub/team_landing_catalog.dart \
  client/test/pages/team_hub/team_landing_catalog_test.dart
git commit -m "$(cat <<'EOF'
feat(team): add TeamLandingEntry catalog filter helpers

EOF
)"
```

---

### Task 7: Picker dialog + detail `pickerMode`

**Files:**
- Modify: `client/lib/pages/team_hub/team_hub_detail_overlay.dart`
- Create: `client/lib/pages/team_hub/team_landing_picker_sheet.dart`
- Create: `client/test/pages/team_hub/team_landing_picker_dialog_test.dart`
- Mirror: `client/lib/pages/expert_hub/expert_landing_picker_sheet.dart`
- Reference: `client/lib/pages/team_hub/team_hub_body.dart`, `team_hub_cards.dart`, `team_hub_clone_feedback.dart`

**Interfaces:**
- Produces:
  - `Future<String?> showTeamLandingPickerSheet(BuildContext context, {String? selectedTeamId})`
  - `TeamHubDetailOverlay` gains `pickerMode` + `onConfirm` (and optional `alreadyAdded` badge text) analogous to `ExpertHubDetailOverlay`
  - On confirm: call `TeamLandingSelection`, pop `teamId` on success; toast errors / partial clone; keep dialog open on failure

- [ ] **Step 1: Write a focused widget test**

Pump a dialog with mocked/fake `TeamHubCubit` + `LaunchProfileCubit` (follow `client/test/pages/team_hub/team_hub_page_test.dart` patterns). Assert:
1. Title uses `teamHubTitle`.
2. Local section lists a known local team; tapping opens detail with Confirm.
3. Confirm pops the local `teamId`.

Keep the harness minimal — do not retest full hub registry networking.

- [ ] **Step 2: Run to verify fail**

Run: `cd client && flutter test test/pages/team_hub/team_landing_picker_dialog_test.dart`

- [ ] **Step 3: Implement**

1. Add `pickerMode` / `onConfirm` to `TeamHubDetailOverlay`: when `pickerMode`, primary button label = `teamHubConfirmSelection`; show `teamHubAlreadyAdded` chip when a `bool alreadyAdded` (or non-null local mapping) is true. Sidebar Team Hub page keeps default `pickerMode: false` (Clone button unchanged).
2. Build `TeamLandingPickerDialog`:
   - On init, `TeamHubCubit.load()` if empty.
   - Local filters for source (`all|mine|discovery`), plus reuse hub favorites/category/search state **or** hold picker-local filter state that feeds `buildTeamLandingCatalog` (prefer picker-local filter state so full-page hub is untouched).
   - Grid/list with section headers for mine vs discovery; cards open detail.
   - Local detail: simple overlay (name, description, roster count) + Confirm → `resolveLocal`.
   - Hub detail: `TeamHubDetailOverlay(pickerMode: true, ...)` → Confirm → `resolveHub` (uses cubit.clone under the hood via selection’s `cloneTeam: cubit.clone`).
   - Wire `TeamLandingSelection(cloneTeam: context.read<TeamHubCubit>().clone, touchRecent: TeamLandingRecentStore().touch)`.
   - After success with `cloneResult != null`, toast via `teamHubCloneToastMessage` / warning variant.
3. Export `showTeamLandingPickerSheet`.

- [ ] **Step 4: Run tests to verify pass**

Run: `cd client && flutter test test/pages/team_hub/team_landing_picker_dialog_test.dart test/pages/team_hub/team_hub_page_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/team_hub/team_hub_detail_overlay.dart \
  client/lib/pages/team_hub/team_landing_picker_sheet.dart \
  client/test/pages/team_hub/team_landing_picker_dialog_test.dart
git commit -m "$(cat <<'EOF'
feat(team): add Team Landing hub picker dialog

EOF
)"
```

---

### Task 8: Wire landing compose team chip

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`
- Optional test: extend an existing landing compose test if one covers team chip; otherwise create `client/test/pages/home_workspace/workspace/unbound_compose_team_chip_test.dart` with a **unit-level** assert that team-mode `_autoChipSpecs` path is replaced — prefer testing via extracted helpers already covered in Tasks 5–7 and a thin smoke widget test if harness cost is reasonable.

**Interfaces:**
- Consumes: Tasks 3–7
- Behavior changes in team mode:
  - `_autoChipSpecs` uses `buildTeamLandingChipMenuSpecs` with recent local teams (resolve names from `LaunchProfileCubit.state.teams`)
  - `onAutoChipSelected`: if `TeamLandingChipAction.browseAll` → `showTeamLandingPickerSheet`; on returned id → `_selectTeam` + `TeamLandingRecentStore.touch`
  - Selecting a recent id → `_selectTeam` + touch
  - Load recent keys in `initState` (mirror `_loadRecentExperts`)

- [ ] **Step 1: Write failing smoke test (optional but preferred)**

If harness is heavy, skip widget smoke and rely on helper tests + manual checklist; otherwise assert team-mode menu contains browse label from l10n.

- [ ] **Step 2: Implement landing wiring**

In `unbound_compose_body.dart`:
1. Import chip menu, recent store, picker sheet.
2. Add `_recentTeamIds` + load/touch helpers mirroring expert.
3. Replace team branch of `_autoChipSpecs` with `buildTeamLandingChipMenuSpecs`.
4. Update `onAutoChipSelected` team branch for browse vs id.
5. Keep chip label logic (`_autoChipLabel`) as-is (selected name or `selectTeam`).

- [ ] **Step 3: Run relevant tests**

```bash
cd client && flutter test \
  test/pages/team_hub/team_landing_chip_menu_test.dart \
  test/pages/team_hub/team_landing_catalog_test.dart \
  test/pages/team_hub/team_landing_picker_dialog_test.dart \
  test/services/team/team_landing_selection_test.dart \
  test/services/team/team_landing_recent_store_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/unbound_compose_body.dart \
  client/test/pages/home_workspace/workspace/unbound_compose_team_chip_test.dart
git commit -m "$(cat <<'EOF'
feat(landing): wire team chip to hub picker and recent store

EOF
)"
```

---

### Task 9: Full verification

**Files:** none new — verify only

- [ ] **Step 1: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors related to this change

- [ ] **Step 2: Tests**

Run: `cd client && flutter test --exclude-tags integration`
Expected: PASS (or fix failures introduced by `hubSourceKey` / `ClonedTeamCreator` signature)

- [ ] **Step 3: Manual checklist (document in commit message if useful)**

1. Team mode chip shows ≤5 recent + 浏览全部团队.
2. Browse opens picker with 我的团队 + 发现.
3. Confirm local team updates chip.
4. Confirm hub team clones once; second confirm reuses same local id.
5. Clone dep partial failure still selects team and shows warning toast.

- [ ] **Step 4: Final commit only if fixes were needed**

```bash
git add -u
git commit -m "$(cat <<'EOF'
fix(team): address landing hub picker verify fallout

EOF
)"
```

---

## Spec coverage self-check

| Spec requirement | Task |
|------------------|------|
| Recent ≤5 + browse all, no clear | 5, 8 |
| Picker My Teams + discovery, filters | 6, 7 |
| Confirm → resolve → selectTeam | 4, 7, 8 |
| Reuse by `hubSourceKey` / else clone | 1, 2, 4 |
| Earliest multi-match rule | 4 |
| `team-hub/recent.json` | 3 |
| Domain boundary (no TeamHub synthesis) | 4, 6, 7 |
| Partial clone toast | 7 |
| No backfill / no clear / no hub update | Global Constraints + Non-goals |

## Placeholder / type consistency self-check

- `hubSourceKey` naming consistent across model, clone, selection, catalog.
- `TeamLandingChipAction.browseAll` is the only chip action enum value.
- `showTeamLandingPickerSheet` returns `String?` local `teamId`.
- `ClonedTeamCreator` / `addClonedTeam` / `app_shell` all gain the same `hubSourceKey` parameter.
