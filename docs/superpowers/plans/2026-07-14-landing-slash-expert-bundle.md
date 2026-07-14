# Landing Slash Expert Bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Simple-mode Landing `/` slash enable-lists include the active expert pack’s skill/plugin ids (default expert when none selected), matching launch merge layers.

**Architecture:** Replace `identityBundleForLanding` + `unionConfigBundles` with `slashBundleForLanding`, which uses `LayeredConfigBundle.merge` and sync expert dep ids via `ExpertMemberResolver` + `expectedLocalId`. Reuse existing `resolveLandingSessionExpertKey` for empty→default key; point `SessionRuntimePlanBuilder` at the same helper (no behavior change).

**Tech Stack:** Dart / Flutter, existing compose + expert hub + launch merge helpers.

**Spec:** `docs/superpowers/specs/2026-07-14-landing-slash-expert-bundle-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/compose/compose_landing_bundle.dart` | `slashBundleForLanding`; delete old helpers |
| `client/lib/services/launch/session_runtime_plan_builder.dart` | Call `resolveLandingSessionExpertKey` instead of private `_normalizeExpertKey` |
| `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart` | Wire hub state into new API |
| `client/lib/pages/chat/session_history_review.dart` | Same |
| `client/test/services/compose/compose_landing_bundle_test.dart` | New unit matrix |
| `client/test/services/compose/compose_trigger_query_test.dart` | Drop obsolete `unionConfigBundles` group |

---

### Task 1: Failing unit tests for `slashBundleForLanding`

**Files:**
- Create: `client/test/services/compose/compose_landing_bundle_test.dart`
- Modify: `client/test/services/compose/compose_trigger_query_test.dart` (remove `unionConfigBundles` group only)

- [ ] **Step 1: Add dedicated test file**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/compose/compose_landing_bundle.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/team_hub/builtin_team_templates.dart';

DiscoverableMember _member({
  required String key,
  List<SkillDependencyRef> skillDeps = const [],
  List<PluginDependencyRef> pluginDeps = const [],
}) {
  return DiscoverableMember(
    key: key,
    name: 'Test',
    description: '',
    category: 'Test',
    source: ExpertMemberSource.local,
    member: const DiscoverableTeamMember(name: 'test'),
    skillDeps: skillDeps,
    pluginDeps: pluginDeps,
  );
}

void main() {
  final skillA = superpowersSkillDep('using-superpowers', 'Using Superpowers');
  final skillB = superpowersSkillDep('brainstorming', 'Brainstorming');

  group('slashBundleForLanding', () {
    test('Simple + explicit expert merges expectedLocalIds with workspace', () {
      final expert = _member(
        key: 'local/architect',
        skillDeps: [skillB],
        pluginDeps: const [
          PluginDependencyRef(
            marketplaceOwner: 'o',
            marketplaceName: 'm',
            entryName: 'cmd',
            name: 'Cmd',
          ),
        ],
      );
      final hub = ExpertHubState(allMembers: [expert]);
      final bundle = slashBundleForLanding(
        draft: const LandingLaunchContext(
          isPersonal: true,
          expertKey: 'local/architect',
        ),
        workspace: const ConfigBundle(skillIds: ['ws-skill']),
        hubState: hub,
      );
      expect(bundle.skillIds, [skillB.expectedLocalId, 'ws-skill']);
      expect(bundle.pluginIds, ['o/m/cmd']);
    });

    test('Simple + empty expertKey uses default expert deps', () {
      final bundle = slashBundleForLanding(
        draft: const LandingLaunchContext(isPersonal: true),
        workspace: const ConfigBundle(),
        hubState: null,
      );
      final defaultMember = builtinExpertMembers()
          .firstWhere((m) => m.key == kBuiltinDefaultExpertKey);
      expect(
        bundle.skillIds,
        defaultMember.skillDeps.map((d) => d.expectedLocalId).toList(),
      );
    });

    test('Team mode uses team + workspace and ignores expertKey', () {
      const team = TeamProfile(
        id: 't1',
        name: 'Team',
        skillIds: ['team-skill'],
        pluginIds: ['team-plugin'],
      );
      final expert = _member(key: 'local/x', skillDeps: [skillA]);
      final bundle = slashBundleForLanding(
        draft: const LandingLaunchContext(
          isPersonal: false,
          teamId: 't1',
          expertKey: 'local/x',
        ),
        team: team,
        workspace: const ConfigBundle(skillIds: ['ws-skill']),
        hubState: ExpertHubState(allMembers: [expert]),
      );
      expect(bundle.skillIds, ['team-skill', 'ws-skill']);
      expect(bundle.pluginIds, ['team-plugin']);
    });

    test('unknown expert key yields workspace-only', () {
      final bundle = slashBundleForLanding(
        draft: const LandingLaunchContext(
          isPersonal: true,
          expertKey: 'missing/expert',
        ),
        workspace: const ConfigBundle(skillIds: ['ws-skill']),
        hubState: const ExpertHubState(),
      );
      expect(bundle.skillIds, ['ws-skill']);
      expect(bundle.pluginIds, isEmpty);
    });
  });
}
```

`PluginDependencyRef` in the first test must include required `marketplaceBranch: 'main'`. Import `superpowersSkillDep` from `builtin_team_templates.dart` (used by the skill helpers). Drop unused imports if analyze complains.

Do **not** use `ExpertHubState(members: …)` — the field is `allMembers`. Do **not** pass `updatedAt` to `TeamProfile`.

- [ ] **Step 2: Remove obsolete union tests**

In `compose_trigger_query_test.dart`, delete the entire `group('unionConfigBundles', …)` and unused `compose_landing_bundle.dart` import if nothing else needs it.

- [ ] **Step 3: Run tests — expect FAIL (API missing)**

```bash
cd client && flutter test test/services/compose/compose_landing_bundle_test.dart
```

Expected: compile/fail — `slashBundleForLanding` not defined (or similar).

- [ ] **Step 4: Commit**

```bash
git add client/test/services/compose/compose_landing_bundle_test.dart \
  client/test/services/compose/compose_trigger_query_test.dart
git commit -m "test: cover landing slash expert bundle merge"
```

---

### Task 2: Implement `slashBundleForLanding` + shared key normalize

**Files:**
- Modify: `client/lib/services/compose/compose_landing_bundle.dart`
- Modify: `client/lib/services/launch/session_runtime_plan_builder.dart`

- [ ] **Step 1: Replace compose_landing_bundle.dart**

```dart
import '../../cubits/expert_hub_cubit.dart';
import '../../models/config_bundle.dart';
import '../../models/discoverable_member.dart';
import '../../models/landing_launch_context.dart';
import '../../models/team_config.dart';
import '../expert_hub/expert_landing_preflight.dart';
import '../expert_hub/expert_member_resolver.dart';
import '../launch/layered_config_bundle.dart';

/// Slash enable-list for Landing / review compose.
///
/// Simple: [LayeredConfigBundle.merge] expert deps (empty key → default) +
/// workspace. Team: team config + workspace. Does not install deps.
ConfigBundle slashBundleForLanding({
  required LandingLaunchContext draft,
  TeamProfile? team,
  required ConfigBundle workspace,
  ExpertHubState? hubState,
}) {
  if (!draft.isPersonal) {
    final teamBundle = team == null
        ? const ConfigBundle()
        : ConfigBundle(
            skillIds: team.skillIds,
            pluginIds: team.pluginIds,
            mcpServerIds: team.mcpServerIds,
          );
    return LayeredConfigBundle.merge(team: teamBundle, workspace: workspace);
  }

  final key = resolveLandingSessionExpertKey(draft.expertKey);
  final member = ExpertMemberResolver.resolve(key: key, hubState: hubState);
  final expert = member == null
      ? const ConfigBundle()
      : _bundleFromExpertDeps(member);
  return LayeredConfigBundle.merge(expert: expert, workspace: workspace);
}

ConfigBundle _bundleFromExpertDeps(DiscoverableMember member) {
  return ConfigBundle(
    skillIds: [
      for (final d in member.skillDeps)
        if (d.expectedLocalId.trim().isNotEmpty) d.expectedLocalId,
    ],
    pluginIds: [
      for (final d in member.pluginDeps)
        if (d.expectedLocalId.trim().isNotEmpty) d.expectedLocalId,
    ],
    mcpServerIds: [
      for (final d in member.mcpDeps)
        if (d.id.trim().isNotEmpty) d.id,
    ],
  );
}
```

Delete `identityBundleForLanding`, `unionConfigBundles`, and `_unionOrdered`.

- [ ] **Step 2: Deduplicate key normalize in plan builder**

In `session_runtime_plan_builder.dart`:

1. Import `../expert_hub/expert_landing_preflight.dart`.
2. Replace `_normalizeExpertKey(...)` calls with `resolveLandingSessionExpertKey(...)`.
3. Delete private `_normalizeExpertKey`.

- [ ] **Step 3: Run unit tests — expect PASS**

```bash
cd client && flutter test test/services/compose/compose_landing_bundle_test.dart \
  test/services/launch/session_runtime_plan_builder_test.dart
```

Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/compose/compose_landing_bundle.dart \
  client/lib/services/launch/session_runtime_plan_builder.dart
git commit -m "feat(compose): merge expert deps into landing slash bundle"
```

---

### Task 3: Wire Landing + session review call sites

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart`
- Modify: `client/lib/pages/chat/session_history_review.dart`

- [ ] **Step 1: Update `_slashBundleForDraft` in landing**

Change signature to accept hub state (or read it inside `build` and pass through):

```dart
ConfigBundle _slashBundleForDraft(
  LandingLaunchContext draft,
  List<TeamProfile> teams,
  ExpertHubState? hubState,
) {
  TeamProfile? team;
  if (!draft.isPersonal) {
    final teamId = draft.teamId?.trim() ?? '';
    if (teamId.isNotEmpty) {
      team = teams.where((t) => t.id == teamId).firstOrNull;
    }
  }
  return slashBundleForLanding(
    draft: draft,
    team: team,
    workspace: _workspaceProjectBundle,
    hubState: hubState,
  );
}
```

Remove unused `LaunchProfileCubit` param if it was only for the old path.

In `build`, where slashBundle is computed:

```dart
final hubState = _expertHubState(context);
final slashBundle = _slashBundleForDraft(_currentDraft(), teams, hubState);
```

Ensure `compose_landing_bundle.dart` import still resolves; drop any leftover `identityBundleForLanding` / `unionConfigBundles` references.

- [ ] **Step 2: Update `_slashBundle` in session_history_review**

```dart
ConfigBundle _slashBundle(BuildContext context) {
  final draft = _enhanceDraft();
  ExpertHubState? hubState;
  try {
    hubState = context.watch<ExpertHubCubit>().state;
  } on Object {
    hubState = null;
  }
  return slashBundleForLanding(
    draft: draft,
    team: widget.team,
    workspace: _workspaceProjectBundle,
    hubState: hubState,
  );
}
```

Prefer matching the file’s existing `_expertHubState`-style try/watch helper if one already exists (there is a `watch<ExpertHubCubit>` nearby ~line 379) — reuse that instead of duplicating try/catch.

Update the call site that passes `slashBundle: _slashBundle()` to pass context / use the helper consistently.

- [ ] **Step 3: Analyze + targeted tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/services/compose/compose_landing_bundle.dart \
  lib/services/launch/session_runtime_plan_builder.dart \
  lib/pages/home_workspace/workspace/workspace_chat_landing.dart \
  lib/pages/chat/session_history_review.dart

flutter test test/services/compose/compose_landing_bundle_test.dart \
  test/services/compose/compose_trigger_query_test.dart \
  test/services/launch/session_runtime_plan_builder_test.dart
```

Expected: no errors; tests PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart \
  client/lib/pages/chat/session_history_review.dart
git commit -m "feat(compose): wire expert slash bundle on landing and review"
```

---

### Task 4: Grep cleanup + verification

**Files:** any remaining references

- [x] **Step 1: Confirm old symbols are gone**

```bash
cd client && rg 'identityBundleForLanding|unionConfigBundles' lib test
```

Expected: no matches.

- [x] **Step 2: Broader compose-related tests (optional but preferred)**

```bash
cd client && flutter test test/services/compose/
```

Expected: PASS.

- [x] **Step 3: Commit only if Step 1/2 forced extra fixes**; otherwise done.

---

## Manual check (implementer)

1. Landing Simple, no expert selected → type `/` → Skills includes default expert’s installed deps (e.g. using-superpowers if installed).
2. Select an expert with skillDeps → `/` lists those installed skills plus workspace-assigned ones.
3. Switch to Team mode → `/` shows team + workspace skills only (not Simple expert chip deps).
