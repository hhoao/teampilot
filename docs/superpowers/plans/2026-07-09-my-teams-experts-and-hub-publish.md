# My Teams / My Experts + Hub Publish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add sidebar **我的团队** / **我的专家** ownership pages, a single local-expert write path with create UI, remove member-settings save-as-template and deprecated roster APIs, and ship fork-based Hub publish via GitHub REST.

**Architecture:** Local `TeamProfile` and `member-hub/local-templates` are the templates. Hubs stay discovery/clone. All local expert writes go through `LocalExpertWriter`. Publish uses an injectable `GithubRegistryPublisher` (fork → branch → contents API → upstream PR). Bundle deps reverse-map from Skill/Plugin/McpServer provenance fields; non-portable ids block the wizard.

**Tech Stack:** Flutter / `flutter_bloc`, existing hub pages, `FlutterSecureKeyValueStore`, GitHub REST (`api.github.com`), l10n ARB en/zh.

**Spec:** [docs/superpowers/specs/2026-07-09-my-teams-experts-and-hub-publish-design.md](../specs/2026-07-09-my-teams-experts-and-hub-publish-design.md)

**Plan decisions (spec open points):**
- Publish transport: injectable GitHub HTTP API (not `gh` CLI)
- Expert Hub keeps the existing “local / My templates” filter chip (no link-only change)
- Provenance: reverse-lookup from installed `Skill` / `Plugin` / `McpServer` model fields; no new provenance index unless a field is missing (then block as non-portable)

---

## File map (target)

| File | Responsibility |
|------|----------------|
| `client/lib/pages/home_workspace/home_workspace_global_section.dart` | `HomeGlobalView.myTeams` / `myExperts` + switch arms |
| `client/lib/pages/home_workspace/home_workspace_sidebar.dart` | Nav rows above Team Hub |
| `client/lib/pages/home_workspace/home_workspace_route.dart` | Optional `?team=` / `?member=` helpers for my-* views |
| `client/lib/pages/my_teams/my_teams_page.dart` | List / open / new / delete / upload entry |
| `client/lib/pages/my_experts/my_experts_page.dart` | Local expert list + CRUD + upload entry |
| `client/lib/pages/expert_hub/expert_editor_dialog.dart` | Shared create/edit form |
| `client/lib/services/expert_hub/local_expert_writer.dart` | Sole local-expert persistence API |
| `client/lib/services/ai/team_draft_roster_mapper.dart` | Call writer instead of store directly |
| `client/lib/pages/team_config/team_config_member_section.dart` | Delete save-as-template |
| `client/lib/cubits/launch_profile_cubit.dart` | Delete `addMember` / `addMemberToTeam` |
| `client/lib/services/hub_publish/hub_publish_credentials_store.dart` | Secure GitHub token |
| `client/lib/services/hub_publish/hub_publish_record_store.dart` | Local PR badges |
| `client/lib/services/hub_publish/bundle_provenance_lookup.dart` | skill/plugin/mcp id → `*DependencyRef` |
| `client/lib/services/hub_publish/team_profile_publish_mapper.dart` | `TeamProfile` → `DiscoverableTeam` |
| `client/lib/services/hub_publish/github_registry_publisher.dart` | Fork / commit / PR port + HTTP impl |
| `client/lib/pages/hub_publish/hub_publish_wizard.dart` | Shared wizard UI |
| `client/lib/l10n/app_en.arb` + `app_zh.arb` | Nav, pages, wizard, remove obsolete keys |

---

### Task 1: Navigation — `myTeams` / `myExperts` shells

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_global_section.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_sidebar.dart`
- Create: `client/lib/pages/my_teams/my_teams_page.dart`
- Create: `client/lib/pages/my_experts/my_experts_page.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/home_workspace/home_global_view_test.dart`

- [ ] **Step 1: Write failing route tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_global_section.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_route.dart';

void main() {
  test('fromSegment resolves myTeams and myExperts', () {
    expect(HomeGlobalView.fromSegment('myTeams'), HomeGlobalView.myTeams);
    expect(HomeGlobalView.fromSegment('myExperts'), HomeGlobalView.myExperts);
  });

  test('home deep link parses global myTeams', () {
    expect(
      HomeWorkspaceRoute.homeGlobalView('/home-v2?global=myTeams'),
      HomeGlobalView.myTeams,
    );
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client && flutter test test/pages/home_workspace/home_global_view_test.dart`  
Expected: FAIL — enum values missing

- [ ] **Step 3: Implement shells**

1. Add to `HomeGlobalView`: `myTeams`, `myExperts` (place before `teamHub` in the enum for readability).
2. Switch arms:

```dart
HomeGlobalView.myTeams => const MyTeamsPage(),
HomeGlobalView.myExperts => const MyExpertsPage(),
```

3. Sidebar hub block order:

```
我的团队
我的专家
────────
Team Hub
Expert Hub
────────
Skills / …
```

4. Placeholder pages: `WorkspaceHubTitleBar` + empty body (or short “coming soon” text using new l10n). Prefer empty list scaffolding so later tasks fill in.
5. ARB keys: `myTeamsNav`, `myTeamsTitle`, `myTeamsSubtitle`, `myExpertsNav`, `myExpertsTitle`, `myExpertsSubtitle` (en + zh). Run Flutter l10n codegen as this repo normally does after ARB edits.
6. Deep-link helpers (v1): add `HomeWorkspaceRoute.myTeamsTeamId` / `myExpertsMemberKey` mirroring `teamHubTeamKey` / `expertHubMemberKey` (`?team=` / `?member=` when global is myTeams/myExperts). Wire pages to honor them in Task 2/4; if unused in UI yet, still add parsers + unit tests in this task.

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/pages/home_workspace/home_global_view_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/home_workspace_global_section.dart \
  client/lib/pages/home_workspace/home_workspace_sidebar.dart \
  client/lib/pages/my_teams/my_teams_page.dart \
  client/lib/pages/my_experts/my_experts_page.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations*.dart \
  client/test/pages/home_workspace/home_global_view_test.dart
git commit -m "feat: add My Teams and My Experts sidebar shells"
```

---

### Task 2: My Teams list — open / new / delete

**Files:**
- Modify: `client/lib/pages/my_teams/my_teams_page.dart`
- Test: `client/test/pages/my_teams/my_teams_page_test.dart`

- [ ] **Step 1: Write failing widget test**

Pump `MyTeamsPage` with a `LaunchProfileCubit` that has two `TeamProfile`s. Expect both names visible; tap delete on one and verify `deleteSelected` / delete path is invoked (use a fake cubit or spy). Also expect a New Team control that can call `showHomeNewTeamDialog` (or a testable callback).

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client && flutter test test/pages/my_teams/my_teams_page_test.dart`  
Expected: FAIL — page still placeholder

- [ ] **Step 3: Implement**

- `BlocBuilder<LaunchProfileCubit, …>` listing `state.teams` (exclude personal if present in same list — only `TeamProfile`).
- Row shows: name, roster length, `cli` / `teamMode`, `createdAt`.
- **Open:** `selectTeam(id)` then clear `HomeGlobalView` so the home shell shows the team config pane — same sequence as sidebar `onSelectIdentity` in `home_workspace_page.dart` (do not invent a separate `/team-config` jump unless that is already the desktop path for the current platform).
- **New:** `showHomeNewTeamDialog(context, cubit)`.
- **Delete:** reuse confirmation pattern from `TeamConfigDangerZone` / existing delete dialogs; call the same delete API (`deleteSelected` after select, or extract a `deleteTeam(id)` if cleaner — prefer one clear cubit method without leaving deprecated wrappers).
- **Upload:** hide until Task 9 to avoid dead UI.
- Honor `HomeWorkspaceRoute.myTeamsTeamId` when present (scroll/highlight or auto-open that team).

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/pages/my_teams/my_teams_page_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/my_teams/ client/test/pages/my_teams/
git commit -m "feat: wire My Teams list to local TeamProfiles"
```

---

### Task 3: `LocalExpertWriter` + AI mapper refactor

**Files:**
- Create: `client/lib/services/expert_hub/local_expert_writer.dart`
- Modify: `client/lib/services/ai/team_draft_roster_mapper.dart`
- Test: `client/test/services/expert_hub/local_expert_writer_test.dart`
- Modify: `client/test/services/ai/team_draft_roster_mapper_test.dart` (create if missing)

- [ ] **Step 1: Write failing writer tests**

```dart
test('save assigns local key and round-trips', () async {
  final fs = InMemoryFilesystem();
  final store = LocalMemberTemplateStore(fs: fs, dirOverride: '/t');
  final writer = LocalExpertWriter(store: store);
  final saved = await writer.save(DiscoverableMember(
    key: '',
    name: 'Arch',
    member: DiscoverableTeamMember(name: 'Arch', prompt: 'p'),
  ));
  expect(LocalMemberTemplateStore.isLocalKey(saved.key), isTrue);
  expect(await writer.loadAll(), [saved]);
});

test('delete removes template', () async {
  // save then delete; loadAll empty
});
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client && flutter test test/services/expert_hub/local_expert_writer_test.dart`  
Expected: FAIL — class missing

- [ ] **Step 3: Implement writer + refactor AI**

```dart
class LocalExpertWriter {
  LocalExpertWriter({LocalMemberTemplateStore? store})
    : _store = store ?? LocalMemberTemplateStore();

  final LocalMemberTemplateStore _store;

  Future<DiscoverableMember> save(DiscoverableMember member) =>
      _store.save(member);

  Future<List<DiscoverableMember>> loadAll() => _store.loadAll();

  Future<DiscoverableMember?> getByKey(String key) => _store.getByKey(key);

  Future<void> delete(String key) => _store.delete(key);
}
```

Change `rosterSlotsFromTeamDraft` to take `LocalExpertWriter? writer` (default construct) and call `writer.save(...)` — **do not** call `LocalMemberTemplateStore` from the mapper anymore.

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/services/expert_hub/local_expert_writer_test.dart test/services/ai/`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/expert_hub/local_expert_writer.dart \
  client/lib/services/ai/team_draft_roster_mapper.dart \
  client/test/services/expert_hub/local_expert_writer_test.dart
git commit -m "feat: add LocalExpertWriter as sole local-expert API"
```

---

### Task 4: Shared expert editor + My Experts CRUD + Expert Hub「新建」

**Files:**
- Create: `client/lib/pages/expert_hub/expert_editor_dialog.dart`
- Modify: `client/lib/pages/my_experts/my_experts_page.dart`
- Modify: `client/lib/pages/expert_hub/expert_hub_body.dart` (toolbar CTA)
- Modify: `client/lib/pages/expert_hub/expert_hub_page.dart` (wire create if needed)
- Modify: l10n ARBs
- Test: `client/test/pages/my_experts/my_experts_page_test.dart`
- Test: `client/test/pages/expert_hub/expert_editor_dialog_test.dart`

- [ ] **Step 1: Write failing tests**

- Editor: submit name+prompt → returns `DiscoverableMember` / calls writer.
- My Experts: empty state + create adds a card; edit updates; delete of unreferenced expert removes it.
- Delete referenced: given a `TeamProfile` roster with `expertKey`, delete shows error and keeps file.

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement**

**Editor fields (v1):** name, description, category, prompt, playbook, optional tags. Persist via `LocalExpertWriter.save`. On success: `ExpertHubCubit.load(forceRefresh: true)`.

**My Experts page:**
- List `writer.loadAll()` (refresh on resume / after mutations).
- CTA opens editor (create).
- Row overflow: edit / delete / add-to-team (reuse `showExpertTeamPickerDialog` + `ExpertHubCubit.addToTeam` path) / upload (hide until Task 7).
- Delete gate: scan `LaunchProfileCubit` teams’ `roster` for matching `expertKey`; if any, toast/dialog with l10n and abort.

**Expert Hub:** add trailing `TextButton`/`FilledButton.tonal` in `ExpertHubBody` toolbar Row labeled `expertHubCreate` → same editor → refresh cubit.

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/pages/my_experts/ test/pages/expert_hub/expert_editor_dialog_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/expert_hub/expert_editor_dialog.dart \
  client/lib/pages/my_experts/ client/lib/pages/expert_hub/expert_hub_body.dart \
  client/lib/l10n/ client/test/pages/my_experts/ client/test/pages/expert_hub/
git commit -m "feat: add expert editor and My Experts CRUD"
```

---

### Task 5: Remove save-as-template + deprecated cubit APIs

**Files:**
- Modify: `client/lib/pages/team_config/team_config_member_section.dart`
- Modify: `client/lib/cubits/launch_profile_cubit.dart`
- Modify: `client/lib/cubits/team/team_roster_editor.dart` (if `addMember` only serves deleted API)
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb` (remove `expertHubSaveAsTemplate`, `expertHubTemplateSaved` if unused)
- Modify tests that call `addMember` / `addMemberToTeam` (e.g. `widget_test.dart`) → use `addExpertToTeam` or test support helpers
- Test: `client/test/pages/team_config/team_member_config_form_test.dart` — assert menu has no save-template

- [ ] **Step 1: Write failing negative UI test**

```dart
expect(find.textContaining('Save as template'), findsNothing);
// or find by l10n key once generated — prefer Key if you add one before deletion
```

Better: before deleting, add `Key('member_save_as_template')` only in the failing test branch… Actually: search for the menu item by existing l10n string from `AppLocalizations`, then after removal the string may still exist until ARB cleanup. Prefer:

```dart
expect(find.byKey(const Key('member_overflow_save_template')), findsNothing);
```

Add that key in production only if the item still exists — for the negative test after deletion, `findsNothing` is enough without a key if you also assert overflow menu values don’t include save. Simplest: open overflow and expect no item with `expertHubSaveAsTemplate` **while the l10n key still exists**, then delete l10n in same task after UI gone.

- [ ] **Step 2: Run — expect FAIL** (item still present)

- [ ] **Step 3: Delete**

- Remove `_discoverableMemberForSave`, `_saveAsTemplate`, `save_template` menu item.
- Remove `LaunchProfileCubit.addMember` and `addMemberToTeam` entirely.
- Remove `TeamRosterEditor.addMember` if unused.
- Fix all call sites/tests.
- Remove unused ARB keys; regenerate l10n.

- [ ] **Step 4: Run focused tests — expect PASS**

Run: `cd client && flutter test test/pages/team_config/team_member_config_form_test.dart test/cubits/team_cubit_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/team_config/team_config_member_section.dart \
  client/lib/cubits/launch_profile_cubit.dart \
  client/lib/cubits/team/ client/lib/l10n/ client/test/
git commit -m "refactor: remove save-as-template and deprecated addMember APIs"
```

---

### Task 6: Publish credentials + record stores

**Files:**
- Create: `client/lib/services/hub_publish/hub_publish_credentials_store.dart`
- Create: `client/lib/services/hub_publish/hub_publish_record_store.dart`
- Test: `client/test/services/hub_publish/hub_publish_credentials_store_test.dart`
- Test: `client/test/services/hub_publish/hub_publish_record_store_test.dart`

- [ ] **Step 1: Write failing tests**

Credentials (in-memory `SecureKeyValueStore`):

```dart
test('round-trips github token', () async {
  final store = HubPublishCredentialsStore(kv: InMemorySecureKeyValueStore());
  await store.saveToken('ghp_test');
  expect(await store.readToken(), 'ghp_test');
  await store.clearToken();
  expect(await store.readToken(), isNull);
});
```

Records (`InMemoryFilesystem`):

```dart
test('records publish badge fields', () async {
  final records = HubPublishRecordStore(fs: fs, pathOverride: '/p.json');
  await records.upsert(HubPublishRecord(
    kind: HubPublishKind.expert,
    registryFullName: 'flashskyai/member-hub',
    slug: 'arch',
    prUrl: 'https://github.com/flashskyai/member-hub/pull/1',
    publishedAtMs: 1,
  ));
  expect(records.find(kind: HubPublishKind.expert, slug: 'arch')?.prUrl, contains('/pull/1'));
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

- Credentials: mirror SSH store prefix style, e.g. `teampilot.hub_publish.v1.github_token`, wrap `SecureKeyValueStore`.
- Records: JSON file under app data, e.g. `hub-publish/records.json` via `AppStorage.paths` (add path getter next to team-hub/member-hub dirs).
- Token resolution for publish: credentials store first, else `readGithubTokenFromEnvironment()` as fallback for CI/dev (document in code comment).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/hub_publish/ client/lib/services/storage/app_storage.dart \
  client/test/services/hub_publish/
git commit -m "feat: add Hub publish credential and record stores"
```

---

### Task 7: Provenance lookup + team/expert publish mappers

**Files:**
- Create: `client/lib/services/hub_publish/bundle_provenance_lookup.dart`
- Create: `client/lib/services/hub_publish/team_profile_publish_mapper.dart`
- Create: `client/lib/services/hub_publish/expert_publish_mapper.dart` (sanitize local → registry JSON shape)
- Test: `client/test/services/hub_publish/bundle_provenance_lookup_test.dart`
- Test: `client/test/services/hub_publish/team_profile_publish_mapper_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
test('skill with repo fields maps to SkillDependencyRef', () {
  final lookup = BundleProvenanceLookup(
    skills: [Skill(id: 'o/r:dir', name: 'N', repoOwner: 'o', repoName: 'r',
      repoBranch: 'main', directory: 'skills/dir')],
    plugins: const [],
    mcps: const [],
  );
  final result = lookup.resolve(skillIds: ['o/r:dir'], pluginIds: [], mcpServerIds: []);
  expect(result.skillDeps.single.repoOwner, 'o');
  expect(result.nonPortableIds, isEmpty);
});

test('plugin with marketplace fields maps to PluginDependencyRef', () {
  final lookup = BundleProvenanceLookup(
    skills: const [],
    plugins: [
      Plugin(
        id: 'o/m/entry',
        name: 'P',
        marketplaceOwner: 'o',
        marketplaceName: 'm',
        marketplaceBranch: 'main',
        // entryName / marketplace fields as in Plugin model
      ),
    ],
    mcps: const [],
  );
  final result = lookup.resolve(
    skillIds: [],
    pluginIds: ['o/m/entry'],
    mcpServerIds: [],
  );
  expect(result.pluginDeps.single.marketplaceOwner, 'o');
  expect(result.nonPortableIds, isEmpty);
});

test('local-only skill is non-portable', () {
  final lookup = BundleProvenanceLookup(
    skills: [Skill(id: 'local-skill', name: 'L')], // no repoOwner
    plugins: const [],
    mcps: const [],
  );
  final result = lookup.resolve(skillIds: ['local-skill'], pluginIds: [], mcpServerIds: []);
  expect(result.nonPortableIds, contains('local-skill'));
});

test('MCP with command-only server map is portable after sanitize', () {
  final lookup = BundleProvenanceLookup(
    skills: const [],
    plugins: const [],
    mcps: [
      McpServer(
        id: 'demo',
        name: 'Demo',
        server: {
          'command': 'npx',
          'args': ['-y', 'demo-mcp'],
          'env': {'API_KEY': 'secret'},
        },
      ),
    ],
  );
  final result = lookup.resolve(skillIds: [], pluginIds: [], mcpServerIds: ['demo']);
  expect(result.mcpDeps.single.server.containsKey('env'), isFalse);
  expect(result.nonPortableIds, isEmpty);
});

test('MCP with empty server map is non-portable', () {
  final lookup = BundleProvenanceLookup(
    skills: const [],
    plugins: const [],
    mcps: [McpServer(id: 'empty', name: 'E', server: {})],
  );
  final result = lookup.resolve(skillIds: [], pluginIds: [], mcpServerIds: ['empty']);
  expect(result.nonPortableIds, contains('empty'));
});

test('mapper strips secrets and emits DiscoverableTeam', () {
  // TeamProfile with roster + portable skillIds → DiscoverableTeam
  // provider credential fields must not appear in toJson()
});

test('mapper fails closed when local expert keys remain', () {
  // unresolvedLocalExpertKeys non-empty → PublishGateResult.blocked
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

`BundleProvenanceLookup.resolve` → `{ skillDeps, pluginDeps, mcpDeps, nonPortableIds }`.

**Portability rules**

| Kind | Portable when | Emit | Non-portable when |
|------|---------------|------|-------------------|
| Skill | `repoOwner` + `repoName` + `directory` present | `SkillDependencyRef` | missing repo fields / unknown id |
| Plugin | `marketplaceOwner` + `marketplaceName` + `entryName` present | `PluginDependencyRef` | missing marketplace fields / unknown id |
| MCP | `server` map non-empty after sanitize | `McpDependencyRef(id, name, server: sanitized)` | empty server, unknown id, or sanitize leaves nothing usable |

**MCP sanitize (mandatory):** deep-copy `server` and **remove** secret-bearing keys before publish: `env`, `headers`, `Authorization`, token-like values, and any nested maps named `env`/`headers`. Keep structural launch fields (`command`, `args`, `url`, `type`, etc.). If after stripping the map is empty → non-portable (do not publish opaque stubs).

`TeamProfilePublishMapper.map({
  required TeamProfile team,
  required Map<String, String> expertKeyRemap, // local → published/builtin
  required BundleProvenanceLookup lookup,
})` → either `PublishReadyTeam(DiscoverableTeam)` or `PublishBlocked(reasons)`.

Rules:
- Apply `expertKeyRemap` to roster slots; any remaining `local/` key → blocked.
- Resolve bundle ids via lookup; any `nonPortableIds` → blocked.
- Emit only: name, description, category, author, updatedAt (now), cli, teamMode, extraArgs, roster, *Deps.
- Do **not** copy provider API keys, SSH, workspace paths, personal preset secrets.

`ExpertPublishMapper`: stamp registry-oriented fields; keep portable `skillDeps` (same skill portability rule); set source appropriately for JSON (registry consumers ignore local source when stamped by fetcher).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/hub_publish/ client/test/services/hub_publish/
git commit -m "feat: add publish mappers and bundle provenance lookup"
```

---

### Task 8: `GithubRegistryPublisher` (fork PR)

**Files:**
- Create: `client/lib/services/hub_publish/github_registry_publisher.dart`
- Create: `client/lib/services/hub_publish/hub_publish_service.dart`
- Test: `client/test/services/hub_publish/github_registry_publisher_test.dart`

- [ ] **Step 1: Write failing tests with fake HTTP**

Inject a `GithubApiClient` fake that records calls:

```dart
test('publish expert forks, commits member.json + index, opens PR', () async {
  final api = FakeGithubApi();
  final publisher = GithubRegistryPublisher(api: api);
  final result = await publisher.publishExpert(
    upstream: kDefaultExpertHubRegistry,
    slug: 'arch',
    memberJson: {...},
    token: 't',
  );
  expect(result.prUrl, isNotEmpty);
  expect(api.ensuredFork, isTrue);
  expect(api.writtenPaths, contains('members/arch/member.json'));
  expect(api.updatedIndex, isTrue);
  expect(api.openedPr, isTrue);
});

test('slug collision on upstream index fails before write', () async {
  // upstream index already lists slug → PublishException.slugCollision
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

Port interface:

```dart
abstract class GithubRegistryPublisher {
  Future<HubPublishResult> publishExpert({...});
  Future<HubPublishResult> publishTeam({...});
}
```

HTTP implementation (v1 algorithm):
1. `GET /repos/{upstream}` — default branch
2. `GET /repos/{upstream}/contents/index.json` — parse slugs; collision → error
3. `POST /repos/{upstream}/forks` (or GET user fork if exists)
4. Create branch on fork from upstream default SHA
5. Create/update `members|teams/<slug>/*.json` via Contents API on fork branch
6. Update fork `index.json` (add slug)
7. `POST /repos/{upstream}/pulls` head=`{user}:{branch}` base=default
8. Return PR HTML URL

Wire `HubPublishService` to: resolve token → map payload → publisher → `HubPublishRecordStore.upsert`.

Keep networking behind the injectable client so tests never hit the network.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/hub_publish/ client/test/services/hub_publish/
git commit -m "feat: add GitHub fork-based registry publisher"
```

---

### Task 9: Publish wizard UI (expert + team)

**Files:**
- Create: `client/lib/pages/hub_publish/hub_publish_wizard.dart`
- Modify: `client/lib/pages/my_experts/my_experts_page.dart` — Upload action
- Modify: `client/lib/pages/my_teams/my_teams_page.dart` — Upload action
- Modify: l10n ARBs
- Test: `client/test/pages/hub_publish/hub_publish_wizard_test.dart`

- [ ] **Step 1: Write failing wizard tests**

- Missing token → shows token field / error, cannot finish.
- Expert happy path with fake `HubPublishService` → success shows PR link.
- Team with `local/` roster expert and empty remap → blocked message; with remap picker selection → proceeds.
- Team with non-portable skill id → blocked list.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement wizard steps**

1. Auth (token from store or paste → save to credentials store)
2. Metadata (slug, name, description, category, author; tags if expert)
3. Gates (team only): local expert remap dropdowns; non-portable dep list
4. Confirm + publish → progress → PR URL + record badge

Reuse one wizard widget with `HubPublishKind.team|expert`.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/hub_publish/ client/lib/pages/my_experts/ \
  client/lib/pages/my_teams/ client/lib/l10n/ client/test/pages/hub_publish/
git commit -m "feat: add Hub publish wizard for teams and experts"
```

---

### Task 10: Badges, polish, full verification

**Files:**
- Modify: My Teams / My Experts list tiles to show publish badge from `HubPublishRecordStore`
- Modify: docs if storage layout needs `hub-publish/` noted (`docs/workspace-storage-layout.md`)
- Tests: any remaining gaps from spec §7

- [ ] **Step 1: Add badge unit/widget coverage**

- [ ] **Step 2: Implement badge UI + storage layout doc line**

- [ ] **Step 3: Spec §7 regression checks**

Run (or extend) existing coverage so these still pass:

- Team Hub clone path: `client/test/services/team/team_clone_service_test.dart` (or nearest clone test)
- Expert Hub add-to-team: `client/test/services/expert_hub/member_roster_service_test.dart` / home team tab add-member test
- Member settings has no save-as-template (Task 5 test)
- Deep links `myTeams` / `myExperts` (Task 1 test)

- [ ] **Step 4: Full verification**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

Expected: clean analyze (no new errors), all non-integration tests pass.

- [ ] **Step 5: Commit**

```bash
git add client/ docs/workspace-storage-layout.md
git commit -m "feat: show Hub publish badges and finalize My Teams/Experts"
```

---

## Execution notes

- Follow TDD per task; do not leave deprecated wrappers.
- Prefer constructor injection for stores/publisher in pages/cubits used by tests.
- After ARB changes, regenerate l10n and run `dart run tool/gen_warmup_glyphs.dart` if AGENTS.md requires it for new user-visible strings.
- Do not implement push-to-upstream or auto-rewrite of local `expertKey`s after publish.
