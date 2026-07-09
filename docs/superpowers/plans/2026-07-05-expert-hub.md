# Expert Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expert Hub discovery + **reference-only team rosters** (`TeamProfile.roster[]` of `expertKey`s). Teams are collections of experts; persona text lives in the catalog and is **materialized at connect** — no embedded copies, no `ExpertSessionOverlay`, no migration.

**Architecture:** See design spec § *Teams as expert collections* and § *Code to remove*. This plan’s task steps predate the 2026-07-09 revision — **rewrite tasks** against `TeamRosterSlot` / `MemberRosterService` / `materializeRosterSlot` before implementation.

**Tech Stack:** Flutter / `flutter_bloc`, existing `AppStorage` paths, JSON registry on GitHub (`hhoao/teampilot/member-hub`), l10n ARB en/zh.

**Spec:** [docs/superpowers/specs/2026-07-05-expert-hub-design.md](../specs/2026-07-05-expert-hub-design.md)

---

## File map (target)

| File | Responsibility |
|------|----------------|
| `client/lib/models/team_roster_slot.dart` | Persisted roster slot (`expertKey` + overrides) |
| `client/lib/models/discoverable_member.dart` | Catalog expert |
| `client/lib/services/expert_hub/expert_member_materializer.dart` | `materializeRosterSlot` → runtime `TeamMemberConfig` |
| `client/lib/services/expert_hub/member_roster_service.dart` | Add expert reference to team (replaces clone service) |
| `client/lib/models/team_config.dart` | `TeamProfile.roster` (drop embedded `members` persistence) |
| `client/lib/models/discoverable_team.dart` | `DiscoverableTeam.roster` (drop embedded `members`) |
| `client/lib/models/app_session.dart` | Optional `expertKey` only |
| `client/lib/services/expert_hub/builtin_member_templates.dart` | Built-in `DiscoverableMember` list |
| `client/lib/services/expert_hub/expert_hub_source.dart` | `ExpertHubRegistry`, `ExpertHubSource` interface |
| `client/lib/services/expert_hub/git_registry_expert_hub_source.dart` | Git fetch + cache (mirror team hub) |
| `client/lib/services/expert_hub/composite_expert_hub_source.dart` | Merge builtin + registry + local + template key index |
| `client/lib/services/expert_hub/expert_hub_favorites_store.dart` | favorites.json |
| `client/lib/services/expert_hub/expert_hub_recent_store.dart` | recent.json (landing picker) |
| `client/lib/services/expert_hub/local_member_template_store.dart` | local-templates/*.json CRUD |
| `client/lib/services/expert_hub/expert_member_resolver.dart` | Resolve `expertKey` → `DiscoverableMember` |
| `client/lib/cubits/expert_hub_cubit.dart` | State + filters (mirror TeamHubCubit) |
| `client/lib/pages/expert_hub/*` | Page, body, cards, detail, feedback, picker sheet |
| `client/lib/models/landing_launch_context.dart` | `expertKey` field |
| `client/lib/cubits/launch_profile_cubit.dart` | `addRosterSlotToTeam(teamId, TeamRosterSlot)` |
| `client/lib/cubits/team/team_roster_editor.dart` | Roster CRUD (slots, not inline prompts) |

---

### Task 1: `DiscoverableMember` model

**Files:**
- Create: `client/lib/models/discoverable_member.dart`
- Create: `client/test/models/discoverable_member_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// client/test/models/discoverable_member_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';

void main() {
  test('round-trips JSON with nested member fields', () {
    const m = DiscoverableMember(
      key: 'teampilot/builtin/developer',
      name: 'Developer',
      description: 'Implements features',
      category: 'Development',
      source: ExpertMemberSource.builtin,
      member: DiscoverableTeamMember(
        name: 'developer',
        prompt: 'You implement code.',
        playbook: 'Use TDD.',
        capabilities: {'implementation'},
      ),
    );
    final decoded = DiscoverableMember.fromJson(m.toJson());
    expect(decoded, m);
  });

  test('toMemberConfig assigns slug id and joinedAt', () {
    const m = DiscoverableMember(
      key: 'local/abc',
      name: 'PM',
      description: '',
      category: 'Business',
      source: ExpertMemberSource.local,
      member: DiscoverableTeamMember(name: 'Product Manager', prompt: 'Plan.'),
    );
    final cfg = m.toMemberConfig(joinedAt: 1);
    expect(cfg.id, isNotEmpty);
    expect(cfg.prompt, 'Plan.');
    expect(cfg.joinedAt, 1);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client && flutter test test/models/discoverable_member_test.dart`
Expected: FAIL — library not found

- [ ] **Step 3: Implement model**

```dart
// client/lib/models/discoverable_member.dart
import 'package:flutter/foundation.dart';
import '../utils/team_member_naming.dart';
import 'discoverable_team.dart';
import 'team_config.dart';

enum ExpertMemberSource { builtin, registry, teamExtract, local }

@immutable
class DiscoverableMember {
  const DiscoverableMember({
    required this.key,
    required this.name,
    required this.description,
    required this.category,
    required this.source,
    required this.member,
    this.author,
    this.updatedAt = 0,
    this.tags = const {},
    this.skillDeps = const [],
    this.originTeamKey,
  });

  final String key;
  final String name;
  final String description;
  final String category;
  final String? author;
  final int updatedAt;
  final Set<String> tags;
  final DiscoverableTeamMember member;
  final List<SkillDependencyRef> skillDeps;
  final ExpertMemberSource source;
  final String? originTeamKey;

  factory DiscoverableMember.fromJson(Map<String, Object?> json) { /* mirror DiscoverableTeam factory style */ }

  Map<String, Object?> toJson() => { /* ... */ };

  TeamMemberConfig toMemberConfig({required int joinedAt, String? idOverride}) {
    final base = member.toMemberConfig(joinedAt: joinedAt);
    if (idOverride == null) return base;
    return base.copyWith(id: idOverride, name: name.trim().isNotEmpty ? name : base.name);
  }
}
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit** `feat: add DiscoverableMember model`

---

### Task 2: Storage paths + favorites/recent stores

**Files:**
- Modify: `client/lib/services/storage/app_storage.dart`
- Create: `client/lib/services/expert_hub/expert_hub_favorites_store.dart`
- Create: `client/lib/services/expert_hub/expert_hub_recent_store.dart`
- Create: `client/test/services/expert_hub/expert_hub_favorites_store_test.dart`

- [ ] **Step 1: Add paths** (mirror `teamHubFavoritesJson`):

```dart
// app_storage.dart — add alongside teamHub* helpers
static String memberHubDirForTeampilotRoot(String root) =>
    p.join(root, 'member-hub');
static String memberHubFavoritesJsonForTeampilotRoot(String root) =>
    p.join(memberHubDirForTeampilotRoot(root), 'favorites.json');
static String memberHubRecentJsonForTeampilotRoot(String root) =>
    p.join(memberHubDirForTeampilotRoot(root), 'recent.json');
static String memberHubLocalTemplatesDirForTeampilotRoot(String root) =>
    p.join(memberHubDirForTeampilotRoot(root), 'local-templates');
static String memberHubCacheDirForTeampilotRoot(String root) =>
    p.join(memberHubDirForTeampilotRoot(root), 'cache');
```

- [ ] **Step 2: Copy `TeamHubFavoritesStore` → `ExpertHubFavoritesStore`** using `AppStorage.paths.memberHubFavoritesJson`

- [ ] **Step 3: Implement `ExpertHubRecentStore`** — `touch(key)` prepends key, caps at 10 unique keys

- [ ] **Step 4: Test favorites toggle** with `MemoryFilesystem` (see `client/test/services/team_hub/` pattern)

- [ ] **Step 5: Commit** `feat: member-hub storage paths and favorites store`

---

### Task 3: Builtin templates + composite source

**Files:**
- Create: `client/lib/services/expert_hub/builtin_member_templates.dart`
- Create: `client/lib/services/expert_hub/team_member_index_source.dart`
- Create: `client/lib/services/expert_hub/composite_expert_hub_source.dart`
- Create: `client/test/services/expert_hub/composite_expert_hub_source_test.dart`

- [ ] **Step 1: Builtin list** — expand `TeamMemberPromptPreset.all` roles + add categories (Development, Business, Design, Writing, Data). Minimum 12 entries; reuse l10n preset text via `AppLocalizationsEn` in bootstrap or inline English for builtin keys.

- [ ] **Step 2: `TeamMemberIndexSource.indexFromTeams(List<DiscoverableTeam>)`** — for each member, emit `DiscoverableMember` with `key: '${team.key}#${slug}'`, `source: teamExtract`, `originTeamKey: team.key`, `category: team.category`.

- [ ] **Step 3: `CompositeExpertHubSource.fetchMembers`** merge order: builtin → registry → teamExtract → local; skip teamExtract when `contentHash(prompt+playbook)` matches an existing registry/builtin key.

```dart
String memberContentHash(DiscoverableTeamMember m) =>
    Object.hash(m.prompt, m.playbook).toString();
```

- [ ] **Step 4: Test** — two teams with same member name dedupes; local overrides nothing for same key prefix

- [ ] **Step 5: Commit** `feat: composite expert hub source`

---

### Task 4: Git registry source

**Files:**
- Create: `client/lib/services/expert_hub/expert_hub_source.dart`
- Create: `client/lib/services/expert_hub/git_registry_expert_hub_source.dart`
- Create: `client/test/services/expert_hub/git_registry_expert_hub_source_test.dart`

- [ ] **Step 1: Copy `GitRegistryTeamHubSource`** — replace `teams/` with `members/`, `team.json` → `member.json`, cache file `members.json`

```dart
const kDefaultExpertHubRegistry = ExpertHubRegistry(
  owner: 'teampilot',
  name: 'member-hub',
  branch: 'main',
);
```

- [ ] **Step 2: Test** with injected `RawContentFetcher` returning minimal `index.json` + one `member.json`

- [ ] **Step 3: Seed repo** — optional follow-up PR to `hhoao/teampilot/member-hub`; v1 works with builtin + team extract if registry empty

- [ ] **Step 4: Commit** `feat: git registry expert hub source`

---

### Task 5: Local template store

**Files:**
- Create: `client/lib/services/expert_hub/local_member_template_store.dart`
- Create: `client/test/services/expert_hub/local_member_template_store_test.dart`

- [ ] **Step 1: `save(DiscoverableMember)`** — assign `key: local/{uuid}` if missing, `source: local`, write JSON to `local-templates/{id}.json`

- [ ] **Step 2: `loadAll()`** — read directory, parse each file

- [ ] **Step 3: `delete(key)`** — remove file when key starts with `local/`

- [ ] **Step 4: Tests** with memory FS

- [ ] **Step 5: Commit** `feat: local member template store`

---

### Task 6: `MemberCloneService` + roster editor

**Files:**
- Create: `client/lib/services/expert_hub/member_clone_service.dart`
- Modify: `client/lib/cubits/team/team_roster_editor.dart`
- Modify: `client/lib/cubits/launch_profile_cubit.dart`
- Create: `client/test/services/expert_hub/member_clone_service_test.dart`

- [ ] **Step 1: Add `TeamRosterEditor.addMemberFromConfig`**

```dart
({TeamProfile team, TeamMemberConfig added}) addMemberFromConfig(
  TeamProfile team,
  TeamMemberConfig template,
) {
  final id = uniqueMemberSlug(team, template.id.isNotEmpty ? template.id : template.name);
  final names = team.members.map((m) => m.name).toSet();
  final display = uniqueDisplayName(
    template.name.trim().isEmpty ? id : template.name.trim(),
    names,
  );
  final added = template.copyWith(id: id, name: display, joinedAt: DateTime.now().millisecondsSinceEpoch);
  return (team: team.copyWith(members: [...team.members, added]), added: added);
}
```

- [ ] **Step 2: `LaunchProfileCubit.addMemberToTeam(String teamId, TeamMemberConfig member)`** — find team, call roster editor, `updateTeam` persist (mirror `updateMember` path)

- [ ] **Step 3: `MemberCloneService.addToTeam`** — reuse `TeamCloneService` skill installers from `team_clone_service.dart`; return `MemberAddResult` `{memberId, installed, failedDeps}`

- [ ] **Step 4: Test** slug collision `developer` → `developer-2`

- [ ] **Step 5: Commit** `feat: member clone service and addMemberToTeam`

---

### Task 7: `ExpertHubCubit`

**Files:**
- Create: `client/lib/cubits/expert_hub_cubit.dart`
- Create: `client/test/cubits/expert_hub_cubit_test.dart`
- Modify: `client/lib/app/app_shell.dart`

- [ ] **Step 1: Mirror `TeamHubCubit`** — state fields: `allMembers`, `categories`, `favorites`, `installedDepIds`, `favoritesOnly`, `localOnly`, `teamExtractOnly`, `search`, `sort`, `status`, `addingKeys`

- [ ] **Step 2: `visibleMembers` getter** — apply search (name, description, tags), category, favorites, source filters

- [ ] **Step 3: Wire in `app_shell.dart`** next to `teamHubCubit` with same `loadInstalledDepIds` lambda

- [ ] **Step 4: BlocProvider** in widget tree (same place as `TeamHubCubit`)

- [ ] **Step 5: Cubit unit test** — filter favoritesOnly

- [ ] **Step 6: Commit** `feat: ExpertHubCubit`

---

### Task 8: Expert Hub UI (page, body, cards, detail)

**Files:**
- Create: `client/lib/pages/expert_hub/expert_hub_page.dart`
- Create: `client/lib/pages/expert_hub/expert_hub_body.dart`
- Create: `client/lib/pages/expert_hub/expert_hub_cards.dart`
- Create: `client/lib/pages/expert_hub/expert_hub_detail_overlay.dart`
- Create: `client/lib/pages/expert_hub/member_hub_add_feedback.dart`
- Create: `client/test/pages/expert_hub/expert_hub_body_test.dart`

- [ ] **Step 1: Copy `TeamHubPage` → `ExpertHubPage`** — swap types, wire `addToTeam` / `launchInWorkspace` callbacks

- [ ] **Step 2: `ExpertHubBody`** — copy `TeamHubBody`; add filter chips: **My templates** (`localOnly`), **From teams** (`teamExtractOnly`); debounce search 400ms (`Debounces.debounce('expert_hub_search', ...)`)

- [ ] **Step 3: `ExpertHubCard`** — reuse `TeamMonogram`, add `ExpertSourceBadge` chip (builtin/registry/local/team)

- [ ] **Step 4: `ExpertHubDetailOverlay`** — prompt/playbook `ExpansionTile`, capabilities `Wrap`, skill deps with installed badges; primary buttons: Add to team, Launch in workspace

- [ ] **Step 5: `member_hub_add_feedback.dart`** — copy `team_hub_clone_feedback.dart` message helpers

- [ ] **Step 6: Widget test** — empty favorites shows `EmptyStateBlock`

- [ ] **Step 7: Commit** `feat: expert hub UI pages`

---

### Task 9: Global embed + pickers

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_global_section.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_sidebar.dart`
- Create: `client/lib/pages/expert_hub/expert_team_picker_dialog.dart`
- Create: `client/lib/pages/expert_hub/expert_workspace_picker_dialog.dart`

- [ ] **Step 1: Add `HomeGlobalView.expertHub`** enum value + switch case `ExpertHubPage()`

- [ ] **Step 2: Sidebar `_ShortcutRow`** under Team Hub with `l10n.expertHubNav`

- [ ] **Step 3: Team picker** — `AppDialog` listing `LaunchProfileCubit.state.teams`; on select call `cubit.addToTeam(member, teamId:)`

- [ ] **Step 4: Workspace picker** — list open workspaces from `ChatCubit` / home cache; on select:

```dart
context.go('/home-v2/workspace/$workspaceId?expert=${Uri.encodeComponent(member.key)}');
```

- [ ] **Step 5: Commit** `feat: expert hub global navigation and pickers`

---

### Task 10: Session overlay model + launch pipeline

**Files:**
- Create: `client/lib/models/expert_session_overlay.dart`
- Create: `client/lib/services/expert_hub/expert_member_overlay.dart`
- Modify: `client/lib/models/app_session.dart`
- Modify: `client/lib/cubits/chat/model/session_create_request.dart`
- Modify: `client/lib/services/launch/personal_launch_context_resolver.dart`
- Create: `client/test/services/expert_hub/expert_member_overlay_test.dart`

- [ ] **Step 1: `ExpertSessionOverlay`** — fields: `expertKey`, `displayName`, `prompt`, `playbook`

- [ ] **Step 2: `AppSession`** — add optional `expertKey`, `expertOverlay` (JSON map); include in `copyWith` / `fromJson` / `toJson`

- [ ] **Step 3: `applyExpertOverlay(TeamMemberConfig base, ExpertSessionOverlay? overlay)`**

```dart
TeamMemberConfig applyExpertOverlay(TeamMemberConfig base, ExpertSessionOverlay? overlay) {
  if (overlay == null) return base;
  final prompt = overlay.prompt.trim();
  final playbook = overlay.playbook.trim();
  return base.copyWith(
    name: overlay.displayName.trim().isNotEmpty ? overlay.displayName : base.name,
    prompt: prompt.isNotEmpty ? prompt : base.prompt,
    playbook: playbook.isNotEmpty ? playbook : base.playbook,
  );
}
```

- [ ] **Step 4: `PersonalLaunchContextResolver`** — after `standaloneMemberFromPersonal`, if `session.expertOverlay != null`, apply overlay

- [ ] **Step 5: `SessionCreateRequest.expertOverlay`** — pass through session create in `SessionLaunchService` / `session_repository.createSession`

- [ ] **Step 6: Test** overlay replaces prompt, preserves preset provider/model

- [ ] **Step 7: Commit** `feat: expert session overlay in personal launch`

---

### Task 11: Landing `expertKey` + compose chip

**Files:**
- Modify: `client/lib/models/landing_launch_context.dart`
- Modify: `client/lib/services/home_workspace/landing_prefs_store.dart`
- Modify: `client/lib/utils/landing_draft_resolver.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing_compose_card.dart`
- Create: `client/lib/pages/expert_hub/expert_landing_picker_sheet.dart`
- Create: `client/test/pages/expert_hub/expert_landing_picker_test.dart`

- [ ] **Step 1: Add `expertKey` to `LandingLaunchContext`, `LandingPrefs`, `persistLandingDraft` / `resolveLandingDraft`**

- [ ] **Step 2: Expert chip on compose card** — only when Simple mode; label from `ExpertMemberResolver.resolve(key)?.name ?? l10n.expertHubNoneSelected`

- [ ] **Step 3: `ExpertLandingPickerSheet`** — `ListView` of favorites + recent + search; footer TextButton → open Expert Hub global view

- [ ] **Step 4: Clear expert** menu item sets `expertKey: null`

- [ ] **Step 5: Widget test** — chip hidden in team mode

- [ ] **Step 6: Commit** `feat: landing expert chip and picker`

---

### Task 12: Landing submit + deep link

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`
- Modify: `client/lib/pages/chat_workbench.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_route.dart` (or router) for `?expert=` query
- Create: `client/lib/services/expert_hub/expert_member_resolver.dart`
- Create: `client/test/router/expert_landing_deep_link_test.dart`

- [ ] **Step 1: `ExpertMemberResolver`** — resolve order: local → memory cache (cubit) → builtin; inject `CompositeExpertHubSource` for full load

- [ ] **Step 2: `submitWorkspaceLandingMessage`** — add `String? expertKey`; resolve overlay; pass to `SessionCreateRequest`; call `ExpertHubRecentStore.touch`

- [ ] **Step 3: Parse `?expert=`** on workspace route — set landing cubit: `isPersonal: true`, `expertKey`; if team mode prefs, toast `l10n.expertHubIgnoredInTeamMode` and clear

- [ ] **Step 4: Unknown key** — toast + clear expertKey

- [ ] **Step 5: Router test** — query param applied to draft

- [ ] **Step 6: Commit** `feat: expert deep link and landing submit overlay`

---

### Task 13: Team config + Team Hub cross-links

**Files:**
- Modify: `client/lib/pages/team_config/team_config_member_section.dart`
- Modify: `client/lib/pages/team_hub/team_hub_detail_overlay.dart`
- Modify: `client/lib/pages/expert_hub/expert_hub_detail_overlay.dart`

- [ ] **Step 1: Member form** — OutlinedButton "Add from Expert Hub" opens `ExpertLandingPickerSheet` in apply mode (fills `_promptCtl` / `_playbookCtl`)

- [ ] **Step 2: Overflow "Save as template"** — build `DiscoverableMember` from current form → `LocalMemberTemplateStore.save` → toast

- [ ] **Step 3: TeamHub detail** — each member row: `TextButton` "View in Expert Hub" if key exists in index (pass callback or `context.go` with query `?global=expertHub&member=` — add optional query on expert hub page to open detail)

- [ ] **Step 4: Expert detail** — "View origin team" navigates `HomeGlobalView.teamHub` with team key (hold pending team in cubit or URL param)

- [ ] **Step 5: Commit** `feat: team config and team hub expert cross-links`

---

### Task 14: l10n

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`

- [ ] **Step 1: Add keys** (minimum):

```
expertHubNav, expertHubTitle, expertHubSubtitle, expertHubSearchHint,
expertHubFavorites, expertHubMyTemplates, expertHubFromTeams,
expertHubAddToTeam, expertHubLaunchInWorkspace, expertHubNoneSelected,
expertHubBrowseAll, expertHubIgnoredInTeamMode, expertHubNotFound,
expertHubSaveAsTemplate, expertHubAddFromHub, expertHubSourceBuiltin,
expertHubSourceRegistry, expertHubSourceLocal, expertHubSourceTeamExtract,
expertHubViewOriginTeam, expertHubViewInHub
```

- [ ] **Step 2: Run** `cd client && flutter pub get` (regenerates localizations)

- [ ] **Step 3: Run** `dart run tool/gen_warmup_glyphs.dart`

- [ ] **Step 4: Commit** `feat: expert hub l10n`

---

### Task 15: Verification

- [ ] **Step 1: Run** `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

- [ ] **Step 2: Run** `cd client && flutter test --exclude-tags integration`

- [ ] **Step 3: Manual smoke**
  - Open Expert Hub from sidebar → browse builtin → favorite
  - Add to team → member appears in team config
  - Launch in workspace → landing shows expert chip → submit creates session with overlay
  - Workspace landing picker → summon without visiting global hub
  - Save member as local template → appears under My templates filter

- [ ] **Step 4: Commit** any fixups `fix: expert hub review feedback`

---

## Deferred — separate specs

| Phase | Scope |
|-------|--------|
| Share | Export/import `.teampilot-member.json`, share URL handler |
| Publish | `hhoao/teampilot/member-hub` PR docs + in-app publish wizard |

**In scope for Expert Hub refactor (this plan):** reference-only `TeamProfile.roster`, `TeamRosterSlot`, `materializeRosterSlot`, remove copy/overlay legacy — see design spec § *Delivery scope* and *Code to remove*.

---

## Plan self-review

| Spec requirement | Task |
|------------------|------|
| DiscoverableMember model | 1 |
| Composite sources (builtin/registry/team/local) | 3–5 |
| ExpertHub page (Team Hub shell) | 8–9 |
| Skills debounce / card chrome | 8 |
| Landing expert chip (compose modules) | 11 |
| Personal overlay | 10, 12 |
| Add to team | 6, 9 |
| Launch in workspace + deep link | 9, 12 |
| Local templates + favorites | 2, 5, 13 |
| Team Hub cross-links | 13 |
| l10n | 14 |
| Error handling | 10–12 (toast/clear paths) |
| Tests | each task |

No TBD placeholders in task steps. v1.5/v2 explicitly deferred.
