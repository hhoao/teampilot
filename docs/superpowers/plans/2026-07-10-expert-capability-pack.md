# Expert Capability Pack & Launch Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every expert a full capability pack (persona + skills/plugins/MCP), merge session config as `team > expert > workspace`, and delete `PersonalProfile` so Simple is unteamed launch — no backward compatibility.

**Architecture:** One resolve path (`ExpertCapabilityResolver` → `ExpertCapabilityPack`) feeds one merge (`LayeredConfigBundle.merge`) into one per-seat `SessionRuntimePlan` consumed by prepare/connect. Simple skips `identities-runtime/`; Team keeps team identity runtime. Install deps only into the app global library. Do not confuse `SessionRuntimePlan` with existing PTY `LaunchPlan` in `shell_launch_spec.dart`.

**Tech Stack:** Flutter / Dart, `flutter_bloc`, existing Skill/Plugin/Mcp cubit installers, Expert Hub catalog, `ConfigBundle`, session lifecycle.

**Spec:** [docs/superpowers/specs/2026-07-10-expert-capability-pack-design.md](../specs/2026-07-10-expert-capability-pack-design.md)

**Constraints:** No migration of on-disk `PersonalProfile` / `personal-default` automations. No compatibility shims. Prefer deleting parallel personal APIs over wrapping them.

---

## File map (target)

| File | Responsibility |
|------|----------------|
| `client/lib/services/launch/layered_config_bundle.dart` | `merge(team > expert > workspace)` — union + precedence |
| `client/lib/services/launch/session_runtime_plan.dart` | Per-seat launch input (bundle + member + keys); **not** PTY `LaunchPlan` |
| `client/lib/services/expert_hub/expert_capability_pack.dart` | Resolved pack: `member` + `bundle` |
| `client/lib/services/expert_hub/expert_capability_resolver.dart` | `preflight` / `resolve`; wraps materializer; installs to app global library |
| `client/lib/models/discoverable_member.dart` | Add `pluginDeps` / `mcpDeps` |
| `client/lib/services/expert_hub/builtin_member_templates.dart` | Add `teampilot/builtin/default` |
| `client/lib/services/expert_hub/member_roster_service.dart` | Preflight all three dep kinds on add-to-team |
| `client/lib/services/session/session_lifecycle_service.dart` | Consume `SessionRuntimePlan`; delete personal branches / `_teamWithProjectBundle` |
| `client/lib/services/cli/registry/config_profile/*` | Delete standalone/personal scopes; Simple = team=null path |
| Delete `client/lib/models/personal_profile.dart` | Gone |
| Automations | Scope key `simple` instead of `personal-default` |
| Landing / home UI | Drop `personalProfileId` and personal identity panes |

---

### Task 1: `LayeredConfigBundle.merge`

**Files:**
- Create: `client/lib/services/launch/layered_config_bundle.dart`
- Create: `client/test/services/launch/layered_config_bundle_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/services/launch/layered_config_bundle.dart';

void main() {
  test('union with precedence team > expert > workspace', () {
    const workspace = ConfigBundle(
      skillIds: ['ws-a', 'shared'],
      pluginIds: ['ws-p'],
      mcpServerIds: ['ws-m'],
    );
    const expert = ConfigBundle(
      skillIds: ['ex-b', 'shared'],
      pluginIds: ['ex-p'],
      mcpServerIds: const [],
    );
    const team = ConfigBundle(
      skillIds: ['team-c', 'shared'],
      pluginIds: const [],
      mcpServerIds: ['team-m'],
    );

    final merged = LayeredConfigBundle.merge(
      team: team,
      expert: expert,
      workspace: workspace,
    );

    // shared kept once; team occurrence wins (appears in team position policy —
    // assert set equality + that shared is present once)
    expect(merged.skillIds.toSet(), {'ws-a', 'ex-b', 'team-c', 'shared'});
    expect(merged.skillIds.where((id) => id == 'shared').length, 1);
    expect(merged.pluginIds.toSet(), {'ws-p', 'ex-p'});
    expect(merged.mcpServerIds.toSet(), {'ws-m', 'team-m'});
  });

  test('null team/expert still returns workspace base', () {
    const workspace = ConfigBundle(skillIds: ['only']);
    final merged = LayeredConfigBundle.merge(workspace: workspace);
    expect(merged.skillIds, ['only']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/launch/layered_config_bundle_test.dart`

Expected: FAIL (library not found)

- [ ] **Step 3: Implement merge**

```dart
import '../../models/config_bundle.dart';

abstract final class LayeredConfigBundle {
  LayeredConfigBundle._();

  /// Union with precedence: [team] > [expert] > [workspace].
  static ConfigBundle merge({
    ConfigBundle? team,
    ConfigBundle? expert,
    required ConfigBundle workspace,
  }) {
    return ConfigBundle(
      skillIds: _mergeIds(workspace.skillIds, expert?.skillIds, team?.skillIds),
      pluginIds: _mergeIds(
        workspace.pluginIds,
        expert?.pluginIds,
        team?.pluginIds,
      ),
      mcpServerIds: _mergeIds(
        workspace.mcpServerIds,
        expert?.mcpServerIds,
        team?.mcpServerIds,
      ),
    );
  }

  static List<String> _mergeIds(
    List<String> workspace,
    List<String>? expert,
    List<String>? team,
  ) {
    final seen = <String>{};
    final out = <String>[];
    void addAll(Iterable<String>? ids) {
      if (ids == null) return;
      for (final raw in ids) {
        final id = raw.trim();
        if (id.isEmpty || seen.contains(id)) continue;
        seen.add(id);
        out.add(id);
      }
    }

    // Higher layers first so first-seen wins = precedence.
    addAll(team);
    addAll(expert);
    addAll(workspace);
    return List.unmodifiable(out);
  }
}
```

Note: first-seen from team→expert→workspace implements “higher wins” while keeping stable order of the winning layer.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/launch/layered_config_bundle_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/launch/layered_config_bundle.dart \
  client/test/services/launch/layered_config_bundle_test.dart
git commit -m "feat: add LayeredConfigBundle merge (team > expert > workspace)"
```

---

### Task 2: Extend `DiscoverableMember` with plugin/MCP deps

**Files:**
- Modify: `client/lib/models/discoverable_member.dart`
- Modify: `client/test/models/discoverable_member_test.dart` (create if missing)

- [ ] **Step 1: Write failing tests for round-trip of pluginDeps/mcpDeps**

```dart
test('round-trips pluginDeps and mcpDeps', () {
  final m = DiscoverableMember(
    key: 'local/x',
    name: 'X',
    description: '',
    category: 'Dev',
    source: ExpertMemberSource.local,
    member: const DiscoverableTeamMember(name: 'x', prompt: 'p'),
    skillDeps: const [],
    pluginDeps: [
      PluginDependencyRef(
        marketplaceOwner: 'o',
        marketplaceName: 'n',
        marketplaceBranch: 'main',
        pluginName: 'plug',
      ),
    ],
    mcpDeps: [
      McpDependencyRef(name: 'srv', command: 'npx', args: ['-y', 'pkg']),
    ],
  );
  expect(DiscoverableMember.fromJson(m.toJson()), m);
});
```

(Adjust `PluginDependencyRef` / `McpDependencyRef` constructors to match `discoverable_team.dart` exactly.)

- [ ] **Step 2: Run test — expect FAIL on missing fields**

- [ ] **Step 3: Add fields to model** — mirror `DiscoverableTeam` JSON keys `pluginDeps` / `mcpDeps`; default `const []`; include in `==` / `hashCode` / `toJson` / `fromJson`.

- [ ] **Step 4: Run test — PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: add pluginDeps and mcpDeps to DiscoverableMember"
```

---

### Task 3: Builtin default expert `teampilot/builtin/default`

**Files:**
- Modify: `client/lib/services/expert_hub/builtin_member_templates.dart`
- Modify: `client/test/services/expert_hub/expert_member_resolver_test.dart` (or new test)

- [ ] **Step 1: Failing test** — `ExpertMemberResolver.resolveMember(key: 'teampilot/builtin/default')` returns non-null with empty deps and a neutral prompt.

- [ ] **Step 2: Add `_builtinMember(slug: 'default', ...)`** at the start of `builtinExpertMembers()`:

```dart
_builtinMember(
  slug: 'default',
  name: 'Default',
  description: 'Neutral unteamed agent for Simple launch when no expert is selected.',
  category: 'Workflow',
  prompt:
      'You are a helpful coding agent in TeamPilot. Follow the user\'s '
      'instructions carefully. Prefer reading the repo before editing.',
),
```

- [ ] **Step 3: Export constant** for callers:

```dart
const kBuiltinDefaultExpertKey = '$kBuiltinTeamHubKeyPrefix/default';
// or top-level in builtin_member_templates.dart / expert_member_resolver.dart
```

Use `kBuiltinTeamHubKeyPrefix` from `builtin_team_templates.dart` so the key is exactly `teampilot/builtin/default`.

- [ ] **Step 4: Tests PASS + commit**

```bash
git commit -m "feat: add builtin default expert for Simple launch"
```

---

### Task 4: `ExpertCapabilityPack` + `ExpertCapabilityResolver`

**Files:**
- Create: `client/lib/services/expert_hub/expert_capability_pack.dart`
- Create: `client/lib/services/expert_hub/expert_capability_resolver.dart`
- Create: `client/test/services/expert_hub/expert_capability_resolver_test.dart`
- Modify: `client/lib/services/expert_hub/member_roster_service.dart` (later task wires plugins/MCP; this task focuses on resolver API)

- [ ] **Step 1: Failing tests**

Cover:
1. Resolve member with no deps → empty `ConfigBundle`, non-empty persona `member`
2. Missing skill dep → installer called; id appears in `bundle.skillIds`
3. Installer returns null → soft-fail; persona still present; failure listed
4. Unknown key → hard fail / null (match chosen API)

Inject installers via constructor (same typedefs as `TeamCloneService`):

```dart
typedef SkillDepInstaller = Future<String?> Function(SkillDependencyRef dep);
typedef PluginDepInstaller = Future<String?> Function(PluginDependencyRef dep);
typedef McpDepInstaller = Future<String?> Function(McpDependencyRef dep);
```

- [ ] **Step 2: Implement**

```dart
class ExpertCapabilityPack {
  const ExpertCapabilityPack({
    required this.member,
    required this.bundle,
    this.failedDeps = const [],
  });
  final TeamMemberConfig member;
  final ConfigBundle bundle;
  final List<DependencyFailure> failedDeps; // reuse team_clone_service type or extract
}

class ExpertCapabilityResolver {
  ExpertCapabilityResolver({
    required this.installSkill,
    required this.installPlugin,
    required this.installMcp,
  });
  // preflight(expertKey) / resolve(DiscoverableMember, {overrides, team?})
  // 1) ExpertMemberResolver.resolveMember
  // 2) install each dep into app global library via injectors
  // 3) ExpertMemberMaterializer for member
  // NEVER write project-config or TeamProfile.bundle
}
```

Reuse `DependencyFailure` / `DependencyKind` from `team_clone_service.dart` (extract to a small shared file if import cycles appear).

- [ ] **Step 3: Wire installers in `app_shell.dart`** next to `MemberRosterService` (SkillCubit/PluginCubit/McpCubit `installTeamDependency`).

- [ ] **Step 4: Tests PASS + commit**

```bash
git commit -m "feat: resolve expert capability packs with global dep install"
```

---

### Task 5: `SessionRuntimePlan` builder

**Files:**
- Create: `client/lib/services/launch/session_runtime_plan.dart`
- Create: `client/lib/services/launch/session_runtime_plan_builder.dart`
- Create: `client/test/services/launch/session_runtime_plan_builder_test.dart`

**Naming:** Do **not** name this `LaunchPlan` or `SessionLaunchPlan` if it collides in imports — spec used `SessionLaunchPlan`; codebase name is **`SessionRuntimePlan`** to avoid clash with `shell_launch_spec.dart` `LaunchPlan`.

- [ ] **Step 1: Failing tests**

```dart
test('simple plan merges expert over workspace', () async {
  // fake resolver returns pack with skillIds: [ex]
  // workspace bundle skillIds: [ws]
  // builder.buildSimple(...) → runtimeBundle.skillIds first-seen ex then ws
  // expertKey == selected or kBuiltinDefaultExpertKey
});

test('team plan merges team > expert > workspace per seat', () async {
  // team bundle [t], expert [e], workspace [w]
});
```

- [ ] **Step 2: Implement types**

```dart
enum SessionRuntimeMode { simple, team }

class SessionRuntimePlan {
  const SessionRuntimePlan({
    required this.mode,
    required this.workspaceId,
    required this.sessionId,
    required this.memberId,
    required this.expertKey,
    required this.runtimeBundle,
    required this.member,
    this.teamId,
    this.presetId,
  });
  final SessionRuntimeMode mode;
  final String workspaceId;
  final String sessionId;
  final String memberId;
  final String expertKey;
  final String? teamId;
  final String? presetId;
  final ConfigBundle runtimeBundle;
  final TeamMemberConfig member;
}
```

Builder loads workspace via `WorkspaceProjectConfigRepository`, resolves expert pack, calls `LayeredConfigBundle.merge`.

- [ ] **Step 3: Tests PASS + commit**

```bash
git commit -m "feat: add SessionRuntimePlan builder for per-seat launch"
```

---

### Task 6: Landing summon + deep link use full pack + default expert

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_compose_landing_pane.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_page.dart` — `?expert=` apply path
- Modify: `client/lib/services/expert_hub/expert_landing_deep_link.dart` (or wherever `applyExpertDeepLink` lives)
- Modify: `client/lib/models/landing_launch_context.dart` — stop requiring `personalProfileId` (full delete in Task 9)
- Test: `client/test/router/expert_landing_deep_link_test.dart` + landing/session action tests

- [ ] **Step 1: On expert chip select** — call `ExpertCapabilityResolver.preflight(key)`; toast failures; keep selection.

- [ ] **Step 2: On `?expert=` deep link** — force Simple mode, preselect `expertKey`, run the **same** `preflight` as chip select (spec: early install). Do not only set draft key.

- [ ] **Step 3: On submit** — `expertKey = draft.expertKey?.trim().isNotEmpty == true ? draft.expertKey! : kBuiltinDefaultExpertKey`; create session with that key; connect path (Task 7) builds/consumes `SessionRuntimePlan`.

- [ ] **Step 4: Tests** — chip select + deep link both invoke preflight; submit without expert uses default key.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: Landing summon and expert deep link preflight capability packs"
```

---

### Task 7: Lifecycle / connect consume `SessionRuntimePlan`

**Files (must-touch — full Simple/Team connect graph):**
- Modify: `client/lib/services/session/session_lifecycle_service.dart`
- Modify: `client/lib/services/launch/session_connect_orchestrator.dart` — replace `preparePersonalConnect` / team connect entry points so both build `SessionRuntimePlan` first
- Delete/replace: `client/lib/services/launch/personal_launch_context_resolver.dart`, `personal_launch_context.dart`
- Modify: `client/lib/services/launch/session_shell_connector.dart`
- Modify: `client/lib/services/launch/session_launch_pipeline.dart`
- Modify: `client/lib/services/launch/workspace_provision_coordinator.dart` (and `workspace_provisioner.dart` if it still takes `PersonalProfile`)
- Modify: `client/lib/services/provider/config_profile_service.dart`
- Modify: `client/lib/services/cli/registry/config_profile/config_profile_context.dart`
- Delete usages of `_teamWithProjectBundle`, `standaloneTeamFromPersonal` for bundle application
- Tests: rewrite `session_lifecycle_standalone_test.dart` → simple-mode; update connect/orchestrator tests; stop resolving experts via persona-only `ExpertMemberResolver` at connect without pack install/merge

- [ ] **Step 1: Replace personal connect entry**

Today Simple goes roughly: `preparePersonalConnect` → `PersonalLaunchContextResolver` → persona materialize → standalone provision.  
Target: **one** entry that:
1. Builds `SessionRuntimePlan` (simple or team seat) via `SessionRuntimePlanBuilder`
2. Passes that plan into lifecycle / shell connector / provision
3. Never takes `PersonalProfile`

Delete `PersonalLaunchContextResolver` once call sites are gone.

- [ ] **Step 2: `prepareLaunch` / shell context consume the plan**

1. `plan.runtimeBundle` = **only** skills/plugins/MCP id source for provision  
2. `plan.member` → `MemberRoleProvision`  
3. Simple (`SessionRuntimeMode.simple`): **skip** `identities-runtime/{id}/` — `cli-defaults` → workspace → session only  
4. Team: keep `identities-runtime/{teamId}/`

- [ ] **Step 3: Delete `_teamWithProjectBundle` overwrite** — call sites use already-merged `plan.runtimeBundle`.

- [ ] **Step 4: Team connect loop** — for each roster seat, `buildTeamSeat(...)` → prepare/connect (**N plans**).

- [ ] **Step 5: Tests** — expert pack skills appear in provisioned bundle; merge order; Simple creates no `identities-runtime/personal-default`; deep-link/landing connect no longer persona-only.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: connect/prepare consume SessionRuntimePlan end-to-end"
```

---

### Task 8: MemberRosterService installs all expert deps

**Files:**
- Modify: `client/lib/services/expert_hub/member_roster_service.dart`
- Modify: `client/lib/app/app_shell.dart` (pass plugin/mcp installers)
- Modify: `client/test/services/expert_hub/member_roster_service_test.dart`

- [ ] **Step 1: Failing test** — expert with pluginDeps/mcpDeps calls those installers; still does **not** write ids into `TeamProfile.bundle`.

- [ ] **Step 2: Implement** — prefer calling `ExpertCapabilityResolver.preflight` instead of duplicating skill-only loop.

- [ ] **Step 3: PASS + commit**

```bash
git commit -m "feat: add-to-team preflights expert skill/plugin/MCP deps"
```

---

### Task 9: Delete `PersonalProfile` (identity model)

**Files (delete or gut):**
- Delete: `client/lib/models/personal_profile.dart`
- Modify: `client/lib/models/launch_profile_kind.dart` — remove `personal`; decode unknown → `team` or throw
- Modify: `client/lib/models/launch_profile.dart`, `launch_profile_index_store.dart`, `launch_profile_repository.dart`, `launch_profile_cubit.dart`, `launch_profile_state.dart`, `launch_profile_selectors.dart`
- Delete: `LaunchProfileProvisioner.ensureDefaultPersonal` / `defaultPersonalId` (prefer delete, no alias)
- Delete personal CRUD UI: `home_workspace_personal_*`, `home_personal_*`
- Modify: `default_workspace_service.dart`, onboarding, sidebar
- **Launch/connect must-touch (if still referencing PersonalProfile after Task 7):**  
  `session_create_request.dart`, `session_connect_request.dart`, `session_launch_pipeline.dart`, `session_provisional_builder.dart`, `session_shell_connector.dart`, `session_connect_orchestrator.dart`, `workspace_session_actions.dart`, `automation_dispatcher.dart`, `personal_launch_context*.dart` (delete)
- Delete tests listed in blast-radius map for personal identity

**Replace rules:**
- `LaunchProfile` = `TeamProfile` only
- Simple session: empty `sessionTeam` / empty `profileId`; `expertKey` + `presetId`; mode via `SessionRuntimeMode.simple` / empty `sessionTeam` (do not keep a parallel `isPersonal` identity concept — boolean flags may remain only as `sessionTeam.isEmpty` helpers)
- Remove `personalIdentityId` from `SessionCreateRequest` and call sites
- Landing: remove `personalProfileId` from `LandingLaunchContext` / prefs

- [ ] **Step 1: Delete model + fix compile errors in batches** (cubit → UI → session → tests). Prefer breaking the build and fixing over shims.

- [ ] **Step 2: `flutter analyze` until clean of PersonalProfile references**

Run: `cd client && rg -n "PersonalProfile|defaultPersonalId|LaunchProfileKind\\.personal" lib test`

Expected: no matches (except maybe changelog/docs)

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor: remove PersonalProfile; Simple is unteamed launch"
```

---

### Task 10: Delete standalone/personal config-profile path

**Files:**
- Modify: `client/lib/services/cli/registry/config_profile/config_profile_scope.dart` — remove `StandaloneLaunchProfileScope`
- Modify: `client/lib/services/provider/config_profile_service.dart` — remove `ensureStandalonePersonalProfile`, `prepareSessionLaunch` personal overloads
- Modify: per-CLI `*_config_profile_capability.dart` — remove standalone contribute branches; Simple uses shared session provision with `team == null`
- Delete/rewrite: `PersonalResourceScope` if only used for personal
- Rewrite tests: `standalone_config_profile_*`, `config_profile_service_standalone_test.dart`, `session_lifecycle_standalone_test.dart` → simple-mode equivalents

- [ ] **Step 1: Replace personal prepare with SessionRuntimePlan-driven provision**

- [ ] **Step 2: Ensure Simple does not create `identities-runtime/personal-default`**

- [ ] **Step 3: Analyze + targeted tests PASS**

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor: unify CLI provision; drop standalone personal scopes"
```

---

### Task 11: Automations scope key `simple`

**Files:**
- Modify: `client/lib/models/automation_tab_scope.dart`
- Modify: `client/lib/services/automation/workspace_automation_profiles.dart`
- Modify: `client/lib/services/automation/automation_dispatcher.dart`
- Modify: `client/lib/services/automation/automation_scope_label.dart`
- Modify: automation editor / workspace automations UI
- Update automation tests/fixtures — stop using `personal-default`

- [ ] **Step 1: Fixed key** `simple` for Simple-mode automation files: `workspaces/{id}/automations/simple.json`

- [ ] **Step 2: Dispatcher** launches Simple sessions via `SessionRuntimePlan` / empty `sessionTeam` (no `personalIdentityId`)


- [ ] **Step 3: No migration** of old `personal-default.json` (orphaned; acceptable per spec)

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor: key Simple automations as simple instead of personal-default"
```

---

### Task 12: Expert Hub UI + publish for plugin/MCP deps

**Files:**
- Modify: `expert_hub_cards.dart`, `expert_hub_detail_overlay.dart` — show plugin/MCP counts
- Modify: `expert_editor_dialog.dart` — preserve/edit deps (minimum: preserve on save; better: pick from installed library like team publish provenance)
- Modify: `expert_publish_mapper.dart`, `hub_publish_wizard.dart` — mirror `TeamProfilePublishMapper` via `BundleProvenanceLookup`
- Tests: `expert_publish_mapper_test.dart`

- [ ] **Step 1: Failing publish test with pluginDeps/mcpDeps**

- [ ] **Step 2: Implement mapper + UI badges**

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: Expert Hub supports plugin and MCP dependency packs"
```

---

### Task 13: Docs + AGENTS.md + supersede note

**Files:**
- Modify: `docs/superpowers/specs/2026-07-05-expert-hub-design.md` — Personal summon section → link to 2026-07-10 spec
- Modify: `AGENTS.md` — Core concepts table: remove PersonalProfile as launch identity; document Simple = unteamed + expert pack; merge rule
- Modify: `docs/workspace-storage-layout.md` if it documents `identities-runtime` for personal
- Set status on `2026-07-10-expert-capability-pack-design.md` to Approved/Implemented-in-progress

- [ ] **Step 1: Update docs to match code**

- [ ] **Step 2: Commit**

```bash
git commit -m "docs: align AGENTS and Expert Hub specs with capability-pack launch"
```

---

### Task 14: Full verification

- [ ] **Step 1: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no errors

- [ ] **Step 2: Unit tests**

Run: `cd client && flutter test --exclude-tags integration`

Expected: PASS (fix or delete obsolete personal/standalone tests rather than skip)

- [ ] **Step 3: Grep guardrails**

```bash
cd client && rg -n "PersonalProfile|defaultPersonalId|StandaloneLaunchProfileScope|_teamWithProjectBundle|standaloneTeamFromPersonal" lib test
```

Expected: no matches

- [ ] **Step 4: Final commit if cleanup remained**

```bash
git commit -m "test: finish PersonalProfile removal and capability-pack verification"
```

---

## Execution notes

1. **Order matters:** Tasks 1–5 are foundation; 6–8 wire behavior; 9–11 delete personal identity (expect large diffs); 12–14 polish.
2. **TDD:** Each task starts with a failing test where behavior is new; deletion tasks use compile/grep as the red signal.
3. **No shims:** Do not leave `PersonalProfile` typedef aliases or `defaultPersonalId` fallbacks.
4. **PTY `LaunchPlan`:** Leave `shell_launch_spec.dart` alone except call-site wiring; `SessionRuntimePlan` is upstream of it.
5. **Extensions:** Out of scope for pack merge (not in `ConfigBundle`); do not fold into `pluginDeps`.

---

## Suggested execution

After plan approval:

1. **Subagent-Driven (recommended)** — fresh subagent per task + review between tasks  
2. **Inline Execution** — this session with executing-plans checkpoints  
