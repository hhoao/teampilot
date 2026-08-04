# Team launch config single source — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make team launch config Preset **xor** Custom; stage Claude (and shared resolvers) from launch-resolved pod seats so inherit + replicas never miss third-party credentials.

**Architecture:** `TeamProfile` normalize helpers; materialize stops stamping custom maps onto inherit seats; `resolveTeamLaunchBundle` / Claude settings load only the active shape; `resolveLaunchExtras` consumes `ctx.members` (already `memberForLaunch`’d pods). Remove legacy team provider bind API.

**Tech Stack:** Flutter unit tests (temp dirs for contributeLaunch), existing `ConfigProfileService` / provider fixtures.

**Spec:** `docs/superpowers/specs/2026-08-04-team-launch-config-single-source-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/team_config.dart` (or small `team_launch_config.dart`) | `TeamLaunchShape`, `teamLaunchShape`, `normalizedLaunchConfig`, `asPresetLaunch`, `asCustomLaunch` |
| `client/lib/services/cli/preset_resolver.dart` | Preset shape: no custom-map fallback when preset missing |
| `client/lib/services/expert_hub/expert_member_materializer.dart` | Inherit: do not stamp provider/model/effort from team custom maps; clear dirty inherit overrides |
| `client/lib/repositories/launch_profile_repository.dart` / index load | Normalize teams on load |
| `client/lib/cubits/launch_profile_cubit.dart` | `setTeamActivePreset` → asPresetLaunch; delete legacy bind API; normalize on updateSelected |
| `client/lib/services/app/onboarding_service.dart` | Remove legacy bind call |
| `client/lib/services/provider/claude/claude_provider_settings_resolver.dart` | Shape-aware resolveProviderId / team / member |
| `client/lib/services/cli/registry/config_profile/claude_config_profile_capability.dart` | `resolveLaunchExtras(launchResolvedMembers)`; no `team.members` iteration; official link all native seats |
| Tests | New + rewrite obsolete bind / dual-state tests |

---

### Task 1: Team launch shape helpers (TDD)

**Files:**
- Modify or create helpers next to `TeamProfile` (`team_config.dart` or `team_launch_config.dart`)
- Create/extend: `client/test/models/team_config_test.dart` (or dedicated `team_launch_config_test.dart`)

- [ ] **Step 1: Failing tests**

```dart
test('normalizedLaunchConfig: preset clears custom maps', () {
  final dirty = TeamProfile(
    id: 't',
    name: 'T',
    activePresetId: 'preset-1',
    providerIdsByTool: {'claude': 'claude-official'},
    modelsByTool: {'claude': 'x'},
    cliEffortLevels: {'claude': 'high'},
  );
  final n = dirty.normalizedLaunchConfig();
  expect(teamLaunchShape(n), TeamLaunchShape.preset);
  expect(n.providerIdsByTool, isEmpty);
  expect(n.modelsByTool, isEmpty);
  expect(n.cliEffortLevels, isEmpty);
  expect(n.activePresetId, 'preset-1');
});

test('asCustomLaunch clears preset', () { ... });
test('asPresetLaunch clears all custom map keys', () { ... });
```

- [ ] **Step 2: Run — FAIL**
- [ ] **Step 3: Implement helpers**
- [ ] **Step 4: PASS → Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(team): add exclusive TeamLaunchShape normalize helpers

EOF
)"
```

---

### Task 2: `resolveTeamLaunchBundle` — no custom fallback in preset shape (TDD)

**Files:**
- Modify: `preset_resolver.dart`
- Modify: `client/test/services/cli/preset_resolver_test.dart`

- [ ] **Step 1: Failing test**

```dart
test('preset shape with missing preset id does not fall back to providerIdsByTool', () {
  final team = TeamProfile(
    id: 't',
    name: 'T',
    activePresetId: 'missing-preset',
    // even if maps were non-empty before normalize, resolver must ignore them
    providerIdsByTool: {'claude': 'should-not-use'},
  ).normalizedLaunchConfig(); // maps cleared
  // Also test raw dirty team if resolver normalizes internally — prefer normalize first
  final bundle = resolveTeamLaunchBundle(team: team, globalPresets: []);
  expect(bundle.provider, isEmpty);
  expect(bundle.isConfigured, isFalse);
});
```

- [ ] **Step 2–4: Implement (if shape preset && preset not found → empty provider; never read custom maps) → PASS → Commit**

```bash
git commit -m "$(cat <<'EOF'
fix(launch): stop custom-map fallback when team preset is missing

EOF
)"
```

---

### Task 3: Materialize inherit without stamping custom maps (TDD)

**Files:**
- Modify: `expert_member_materializer.dart`
- Test: extend expert materializer / team config tests

- [ ] **Step 1: Failing test**

```dart
test('inherit member under preset team keeps empty provider after materialize', () async {
  // team activePresetId set, providerIdsByTool empty (normalized)
  // slot with activePresetId __inherit__ or empty
  // materialize → member.provider empty, activePresetId == inheritPresetId
});

test('inherit member clears dirty stamped provider on materialize', () {
  // slot overrides somehow had provider set while inherit — clear them
});
```

- [ ] **Step 2–4: Change `_applyTeamInheritance`: if inherit (null/empty/`__inherit__`), set `__inherit__` and **do not** copy `team.providerForCli` / model / effort; if inherit and provider non-empty, clear → PASS → Commit**

```bash
git commit -m "$(cat <<'EOF'
fix(team): stop stamping custom providers onto inherit members

EOF
)"
```

---

### Task 4: Load/save normalize + cubit exclusivity; remove bind API

**Files:**
- `launch_profile_repository.dart` / index decode path — normalize `TeamProfile` after fromJson
- `launch_profile_cubit.dart` — `setTeamActivePreset` uses `asPresetLaunch`; `updateTeamCustomLaunch` already clears preset; remove legacy team provider bind API
- `onboarding_service.dart` — remove bind call (onboarding should set preset or custom explicitly if needed)
- Delete/replace tests in `team_cubit_test.dart` that assert bind behavior
- Add test: `setTeamActivePreset` clears `providerIdsByTool`

- [ ] **Step 1: Failing cubit/repo tests for exclusivity + load dirty JSON**
- [ ] **Step 2–4: Implement → PASS → Commit**

```bash
git commit -m "$(cat <<'EOF'
refactor(team): exclusive preset vs custom launch; remove legacy bind API

EOF
)"
```

---

### Task 5: Claude provider settings resolver shape-aware (TDD)

**Files:**
- `claude_provider_settings_resolver.dart`
- New or extend resolver tests with temp provider catalog

- [ ] **Step 1: Tests**

```dart
test('resolveTeamClaudeSettings uses preset provider when shape is preset', () async { ... });
test('resolveProviderId ignores providerIdsByTool in preset shape', () async { ... });
```

- [ ] **Step 2–4: Implement using `resolveTeamLaunchBundle` + presets list (inject presets or pass bundle) → PASS → Commit**

Note: Resolver today has no preset list — either pass `List<CliPreset>` into resolve methods, or resolve provider id in capability via `memberForLaunch` only and simplify resolver to `resolve(String? providerId)`. Prefer: capability builds provider ids from launch-resolved members; team-level settings from `launchResolvedMembers` first seat / bundle.provider. Keep resolver API minimal and shape-safe.

**Recommended minimal change:**  
`resolveTeamClaudeSettings(team, {required String? teamProviderId})` where caller passes `resolveTeamLaunchBundle(...).provider`. Same for `resolveProviderId` — delete dual scan or gate behind custom shape only.

- [ ] **Commit**

```bash
git commit -m "$(cat <<'EOF'
fix(claude): resolve team provider from launch shape only

EOF
)"
```

---

### Task 6: `resolveLaunchExtras` uses launch-resolved members (TDD) — **credential chain**

**Files:**
- `claude_config_profile_capability.dart`
- `config_profile_service.dart` (call site already has resolved roster)
- Test: `claude_config_profile_capability_test.dart` or `config_profile_service_test.dart`

- [ ] **Step 1: Failing contributeLaunch test**

Setup temp app root + write a third-party Claude provider with `ANTHROPIC_AUTH_TOKEN` + base URL. Team:

```dart
TeamProfile(
  id: 't',
  name: 'T',
  cli: CliTool.claude,
  teamMode: TeamMode.native,
  activePresetId: fixturePresetId, // provider = third-party
  members: [
    TeamMemberConfig(id: 'team-lead', name: 'team-lead', activePresetId: inherit),
    TeamMemberConfig(id: 'developer', name: 'developer', replicas: 2, activePresetId: inherit),
  ],
).normalizedLaunchConfig();
```

Pass **pod** list as `ctx.members` after `resolveTeamRosterForLaunch` + expand (or service `prepareTeamLaunch`).

Assert files:

```
settings/team-lead.json
settings/developer-0.json
settings/developer-1.json
```

each `env` contains `ANTHROPIC_AUTH_TOKEN` (or API key field) and `ANTHROPIC_BASE_URL`.

- [ ] **Step 2: Run — FAIL** (today developer-0/lead often missing token)

- [ ] **Step 3: Implement**

```dart
Future<ClaudeLaunchExtras> resolveLaunchExtras({
  required TeamProfile team,
  required List<TeamMemberConfig> launchResolvedMembers,
  required TeamMemberConfig? launchedMember,
  required ClaudeProviderSettingsResolver resolver,
}) async { ... }

// _loadMemberProviderSettings: for (m in launchResolvedMembers) settingsByMember[m.id] = await resolve(m.provider);
```

Wire `contributeLaunch` to pass `ctx.members` (already resolved by service).

- [ ] **Step 4: Sequential contributeLaunch** as `developer-0` then `developer-1` — all three files still have tokens.

- [ ] **Step 5: Official fixture** (optional same PR): link credentials for each seat on native full roster write (`_maybeLinkOfficialCredentials` loop).

- [ ] **Commit**

```bash
git commit -m "$(cat <<'EOF'
fix(claude): stage provider settings for all launch-resolved seats

EOF
)"
```

---

### Task 7: Member preset + validator + cleanup

**Files:** as needed

- [ ] Test: team preset + member explicit `memberPreset` → that seat uses member preset provider.
- [ ] Stale team preset id → launch validator blocks (align `TeamConfigLaunchValidator`).
- [ ] No remaining legacy team provider bind API call sites.
- [ ] Run:

```bash
cd client && flutter test \
  test/models/team_config_test.dart \
  test/services/cli/preset_resolver_test.dart \
  test/services/cli/config_profile/claude_config_profile_capability_test.dart \
  test/services/provider/config_profile_service_test.dart \
  test/cubits/team_cubit_test.dart \
  test/services/expert_hub/expert_capability_resolver_test.dart
```

(Adjust paths to files actually touched.)

- [ ] Mark spec status Approved/Implemented; optional one-line MATRIX note not required.

- [ ] **Commit**

```bash
git commit -m "$(cat <<'EOF'
test(team): cover launch-config exclusivity and stale preset validation

EOF
)"
```

---

### Task 8: Verify matrix unit harness still green; L2 optional

```bash
cd client && flutter test \
  test/integration/support/roster_shape_test.dart \
  test/integration/support/cli_message_matrix_harness_test.dart \
  test/integration/support/native_roster_assertions_test.dart
```

If Linux PTY + claude available:

```bash
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  flutter test --tags "integration && linux-pty" \
  test/integration/cli_message_matrix_claude_test.dart \
  --plain-name="replicated"
```

- [ ] **Commit only if product fixes needed for L2**

---

## Manual / CI notes

- Merge gate = Task 6–7 unit chain (auth env on all pod settings).
- L2 replicated is regression evidence when environment allows.
- No compat shims; dirty profiles normalize on load.

## Execution handoff

Plan complete. Two options:

1. **Subagent-Driven (recommended)** — fresh subagent per task  
2. **Inline Execution** — this session with checkpoints  

Which approach?
