# Extension System — Phase 3b (Per-team override UI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-team "Extensions" section to Team Config where each extension can be set to *Follow global / On / Off* for the selected team.

**Architecture:** A new `TeamConfigSection.extensions` renders `_TeamExtensionsSection`, which lists the built-in extensions (from `ExtensionCubit.state.rows`) and, per extension, a tri-state control bound to `ExtensionRepository.teamOverrides[teamId][id]` (`null` = follow global, `true`/`false` = force). Reads/writes go through two new `ExtensionCubit` methods (`teamOverrides` / `setTeamOverride`). The resolution `effectiveEnabled(teamId, id) = override ?? globalEnabled` already exists (Phase 1 model) and is already honored by codegraph's MCP path (Phase 2 `team_cubit`).

**Tech Stack:** Dart / Flutter, `flutter_bloc`, `go_router`, the Phase-3a `ExtensionCubit` + `ExtensionRepository`, the Team Config workspace framework (`TeamConfigSection`, `_Card`, `_CardHeader`, `WorkspaceAdaptiveSectionPage`).

**Builds on Phase 3a (must be landed first):** `ExtensionCubit` (provided app-wide in `app_shell`), `ExtensionRepository` with `setTeamOverride`/`load`, `ExtensionState.effectiveEnabled`.

**Scope note — rtk caveat:** per-team override is fully honored for **mcp-server** effects (codegraph) because `team_cubit` resolves `effectiveEnabledIds(teamId)` (Phase 2). The **rtk settings-hook** effect still resolves *global* enablement in `config_profile_service` (Phase 3a). So a per-team rtk override is recorded and shown in the UI but does **not yet** change the rtk hook (which honors global). This is the one deferred item from the design; surface it with a hint string on the rtk row rather than hiding the control. Fully threading teamId through `ConfigProfileDelegate` for per-team rtk is future work (out of scope here).

---

## File Structure

**Modified files:**

| File | Change |
|------|--------|
| `client/lib/cubits/extension_cubit.dart` | Add `teamOverrides(teamId)` + `setTeamOverride(teamId, id, value)`. |
| `client/lib/pages/team_config_page.dart` | Add `TeamConfigSection.extensions` (enum + switches + icon + dispatch); add `_TeamExtensionsSection` + `_TeamExtensionRow`. |
| `client/lib/router/app_router.dart` | Add `/team-config/extensions` route. |
| `client/lib/l10n/app_en.arb` + `app_zh.arb` | Team-extensions strings. |

**Test:** `client/test/cubits/extension_cubit_test.dart` (extend with override-method tests).

> All commands run from `client/` unless noted.

---

## Task 1: `ExtensionCubit` team-override methods

**Files:**
- Modify: `client/lib/cubits/extension_cubit.dart`
- Test: `client/test/cubits/extension_cubit_test.dart` (extend)

- [ ] **Step 1: Add the failing tests (append inside the existing `main()`)**

```dart
  test('teamOverrides reads only the requested team map', () async {
    final fs = InMemoryFilesystem();
    final cubit = ExtensionCubit(
      _repo(fs),
      ExtensionAcquisitionEngine(runner: (c) async => const CliInstallerCommandResult(exitCode: 0)),
      detector: _detector(),
    );

    await cubit.setTeamOverride('team-a', 'codegraph', true);
    await cubit.setTeamOverride('team-a', 'rtk', false);

    final a = await cubit.teamOverrides('team-a');
    expect(a, {'codegraph': true, 'rtk': false});
    expect(await cubit.teamOverrides('team-b'), isEmpty);
  });

  test('setTeamOverride(null) clears the override', () async {
    final fs = InMemoryFilesystem();
    final cubit = ExtensionCubit(
      _repo(fs),
      ExtensionAcquisitionEngine(runner: (c) async => const CliInstallerCommandResult(exitCode: 0)),
      detector: _detector(),
    );
    await cubit.setTeamOverride('team-a', 'codegraph', true);
    await cubit.setTeamOverride('team-a', 'codegraph', null);
    expect(await cubit.teamOverrides('team-a'), isEmpty);
  });
```

> These reuse `_repo`, `_detector`, and the imports already at the top of `extension_cubit_test.dart` from Phase 3a.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/cubits/extension_cubit_test.dart`
Expected: FAIL — "The method 'setTeamOverride' isn't defined".

- [ ] **Step 3: Implement the two methods**

In `client/lib/cubits/extension_cubit.dart`, add to `ExtensionCubit` (next to `setGlobalEnabled`):

```dart
  /// Current per-team override map (`{extensionId: bool}`) for [teamId].
  Future<Map<String, bool>> teamOverrides(String teamId) async {
    final state = await _repository.load();
    return Map<String, bool>.from(state.teamOverrides[teamId] ?? const {});
  }

  /// [value] null clears the override (the team falls back to global).
  Future<void> setTeamOverride(String teamId, String id, bool? value) async {
    await _repository.setTeamOverride(teamId, id, value);
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/cubits/extension_cubit_test.dart`
Expected: PASS (Phase-3a tests + the 2 new ones).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/extension_cubit.dart client/test/cubits/extension_cubit_test.dart
git commit -m "feat(extensions): ExtensionCubit per-team override accessors"
```

---

## Task 2: l10n strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`

- [ ] **Step 1: Add to `app_en.arb`** (next to the existing `teamMcpNav`/`teamMcpManage` keys)

```json
  "teamExtensionsNav": "Extensions",
  "teamExtensionsTitle": "Extensions for this team",
  "teamExtensionsSubtitle": "Override which extensions run for this team. Default follows the global setting.",
  "teamExtensionFollowGlobal": "Follow global",
  "teamExtensionForceOn": "On",
  "teamExtensionForceOff": "Off",
  "teamExtensionEffectiveOn": "Active for this team",
  "teamExtensionEffectiveOff": "Inactive for this team",
  "teamExtensionRtkGlobalOnlyHint": "rtk currently applies globally; per-team override is not yet effective.",
```

- [ ] **Step 2: Add the same keys to `app_zh.arb`**

```json
  "teamExtensionsNav": "扩展",
  "teamExtensionsTitle": "本团队的扩展",
  "teamExtensionsSubtitle": "覆盖本团队启用哪些扩展，默认跟随全局设置。",
  "teamExtensionFollowGlobal": "跟随全局",
  "teamExtensionForceOn": "开启",
  "teamExtensionForceOff": "关闭",
  "teamExtensionEffectiveOn": "本团队已启用",
  "teamExtensionEffectiveOff": "本团队未启用",
  "teamExtensionRtkGlobalOnlyHint": "rtk 目前按全局生效，按团队覆盖暂未生效。",
```

- [ ] **Step 3: Regenerate localizations**

Run: `flutter pub get`
Expected: `app_localizations*.dart` regenerated with the new getters.

- [ ] **Step 4: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb
git commit -m "i18n(extensions): add per-team extension strings"
```

---

## Task 3: Add `TeamConfigSection.extensions` (enum + switches + dispatch)

**Files:**
- Modify: `client/lib/pages/team_config_page.dart`

The enum's switches are exhaustive — every one must get an `extensions` arm or the file won't compile.

- [ ] **Step 1: Add the enum value**

In `enum TeamConfigSection`, change the value list to insert `extensions` after `mcp`:

```dart
enum TeamConfigSection implements WorkspaceSectionDescriptor {
  team,
  skills,
  plugins,
  mcp,
  extensions,
  members;
```

- [ ] **Step 2: Update the `routeSegment` switch**

Add the arm:

```dart
    TeamConfigSection.extensions => 'extensions',
```

(The `routePath` switch needs no change — its default `_ => '$basePath/$routeSegment'` already covers `extensions`; only `members` is special-cased.)

- [ ] **Step 3: Update the `title` switch**

Add the arm:

```dart
    TeamConfigSection.extensions => l10n.teamExtensionsNav,
```

- [ ] **Step 4: Update the icon helper**

In `_teamConfigSectionIcon`, add:

```dart
  TeamConfigSection.extensions => Icons.power_outlined,
```

- [ ] **Step 5: Update the section dispatch in `TeamConfigPage.build`**

In the `switch (section)` (around L235), add before `TeamConfigSection.members`:

```dart
      TeamConfigSection.extensions => _TeamExtensionsSection(team: team),
```

- [ ] **Step 6: Analyze (expect one error: `_TeamExtensionsSection` undefined — fixed in Task 5)**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/team_config_page.dart`
Expected: a single "The function '_TeamExtensionsSection' isn't defined" error (resolved in Task 5). No *switch-not-exhaustive* errors — if any appear, a switch arm was missed above.

- [ ] **Step 7: Commit (after Task 5 lands so the file compiles)** — defer the commit; do Tasks 4 and 5 first, then commit them together in Task 5 Step 5.

---

## Task 4: Add the `/team-config/extensions` route

**Files:**
- Modify: `client/lib/router/app_router.dart`

- [ ] **Step 1: Add the route**

After the `/team-config/mcp` `GoRoute` (around L249), add:

```dart
        GoRoute(
          path: '/team-config/extensions',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TeamConfigPage(section: TeamConfigSection.extensions),
          ),
        ),
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings lib/router/app_router.dart`
Expected: "No issues found!" (`TeamConfigSection.extensions` exists from Task 3; `TeamConfigPage` already imported).

- [ ] **Step 3: Commit (with Task 5)** — defer; commit in Task 5 Step 5.

---

## Task 5: `_TeamExtensionsSection` + `_TeamExtensionRow`

**Files:**
- Modify: `client/lib/pages/team_config_page.dart`

Add the import and the two widget classes (place the classes next to `_TeamMcpSection`).

- [ ] **Step 1: Add the import**

At the top of `team_config_page.dart` with the other `../cubits/` imports:

```dart
import '../cubits/extension_cubit.dart';
```

- [ ] **Step 2: Add the section + row widgets**

```dart
enum _ExtOverrideChoice { followGlobal, forceOn, forceOff }

class _TeamExtensionsSection extends StatefulWidget {
  const _TeamExtensionsSection({required this.team});

  final TeamConfig team;

  @override
  State<_TeamExtensionsSection> createState() => _TeamExtensionsSectionState();
}

class _TeamExtensionsSectionState extends State<_TeamExtensionsSection> {
  Map<String, bool> _overrides = const {};

  @override
  void initState() {
    super.initState();
    context.read<ExtensionCubit>().load();
    _loadOverrides();
  }

  @override
  void didUpdateWidget(covariant _TeamExtensionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.team.id != widget.team.id) _loadOverrides();
  }

  Future<void> _loadOverrides() async {
    final map = await context.read<ExtensionCubit>().teamOverrides(widget.team.id);
    if (!mounted) return;
    setState(() => _overrides = map);
  }

  _ExtOverrideChoice _choiceFor(String id) {
    if (!_overrides.containsKey(id)) return _ExtOverrideChoice.followGlobal;
    return _overrides[id]!
        ? _ExtOverrideChoice.forceOn
        : _ExtOverrideChoice.forceOff;
  }

  bool _effective(ExtensionRow row) {
    final override = _overrides[row.id];
    return override ?? row.globalEnabled;
  }

  Future<void> _setChoice(String id, _ExtOverrideChoice choice) async {
    final value = switch (choice) {
      _ExtOverrideChoice.followGlobal => null,
      _ExtOverrideChoice.forceOn => true,
      _ExtOverrideChoice.forceOff => false,
    };
    await context.read<ExtensionCubit>().setTeamOverride(widget.team.id, id, value);
    await _loadOverrides();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = context.watch<ExtensionCubit>().state.rows;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardHeader(title: l10n.teamExtensionsTitle),
                const SizedBox(height: 6),
                Text(
                  l10n.teamExtensionsSubtitle,
                  style: AppTextStyles.of(context).bodySmall.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                ),
                const SizedBox(height: 14),
                for (final row in rows)
                  _TeamExtensionRow(
                    row: row,
                    choice: _choiceFor(row.id),
                    effective: _effective(row),
                    onChoice: (c) => _setChoice(row.id, c),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamExtensionRow extends StatelessWidget {
  const _TeamExtensionRow({
    required this.row,
    required this.choice,
    required this.effective,
    required this.onChoice,
  });

  final ExtensionRow row;
  final _ExtOverrideChoice choice;
  final bool effective;
  final ValueChanged<_ExtOverrideChoice> onChoice;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isRtk = row.id == 'rtk';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: workspaceInsetDecoration(cs, radius: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    style: AppTextStyles.of(context)
                        .body
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    effective
                        ? l10n.teamExtensionEffectiveOn
                        : l10n.teamExtensionEffectiveOff,
                    style: AppTextStyles.of(context).bodySmall.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                  if (isRtk)
                    Text(
                      l10n.teamExtensionRtkGlobalOnlyHint,
                      style: AppTextStyles.of(context).bodySmall.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                    ),
                ],
              ),
            ),
            DropdownButton<_ExtOverrideChoice>(
              value: choice,
              underline: const SizedBox.shrink(),
              onChanged: (c) {
                if (c != null) onChoice(c);
              },
              items: [
                DropdownMenuItem(
                  value: _ExtOverrideChoice.followGlobal,
                  child: Text(l10n.teamExtensionFollowGlobal),
                ),
                DropdownMenuItem(
                  value: _ExtOverrideChoice.forceOn,
                  child: Text(l10n.teamExtensionForceOn),
                ),
                DropdownMenuItem(
                  value: _ExtOverrideChoice.forceOff,
                  child: Text(l10n.teamExtensionForceOff),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

> `workspaceInsetDecoration` and `AppTextStyles` are already imported/used by `_TeamMcpRow` in this same file — no new import beyond `extension_cubit.dart`.

- [ ] **Step 3: Analyze the whole page + router**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/team_config_page.dart lib/router/app_router.dart`
Expected: "No issues found!"

- [ ] **Step 4: Sanity smoke (optional widget test)**

If a page widget-test harness is readily reusable (check `client/test/pages/` for an existing team-config or management-page widget test to copy `MaterialApp`/`BlocProvider`/l10n setup), add a smoke test that pumps `_TeamExtensionsSection` inside a `BlocProvider<ExtensionCubit>` with a loaded cubit and asserts a `DropdownButton<_ExtOverrideChoice>` renders per extension and that selecting `forceOff` calls `setTeamOverride`. If no harness is readily reusable, skip — Task 1's cubit tests cover the override logic and Step 3's analyze covers the widget compiles.

- [ ] **Step 5: Commit Tasks 3–5 together (file now compiles)**

```bash
git add client/lib/pages/team_config_page.dart client/lib/router/app_router.dart
git commit -m "feat(extensions): per-team extension override section in Team Config"
```

---

## Task 6: Full verification gate

- [ ] **Step 1: Analyze (whole project)**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: "No issues found!" — fix any new error/warning.

- [ ] **Step 2: Full test suite**

Run: `cd client && flutter test --exclude-tags integration`
Expected: all pass (Phase-1/2/3a + the new override-method tests).

- [ ] **Step 3: Confirm the override actually changes codegraph for a team**

Run: `flutter test test/cubits/team_cubit_extension_mcp_test.dart`
Expected: PASS — the Phase-2 wiring is unchanged; with a `teamOverride` set to `false`, `effectiveEnabledIds(teamId)` would exclude codegraph (already covered by `extension_repository_test.dart`'s `effectiveEnabledIds applies override over global`).

- [ ] **Step 4: Commit any fixups**

```bash
git add -A && git commit -m "chore(extensions): phase 3b verification fixups" || echo "nothing to commit"
```

---

## Self-Review

**1. Spec coverage (final slice of design spec §7, §9):**

| Spec element | Task |
|------|------|
| Per-team override UI (global default + per-team On/Off), §7/§9 | Tasks 3, 5 |
| Section reachable via Team Config nav + route | Tasks 3, 4 |
| Override read/write through the repository (`teamOverrides`/`setTeamOverride`) | Task 1 |
| Resolution honored for codegraph (mcp) end-to-end | already Phase 2; verified Task 6 Step 3 |
| Honest surfacing of the rtk-hook global-only caveat | Task 2 (`teamExtensionRtkGlobalOnlyHint`) + Task 5 (rtk row hint) |

This completes the design's enablement model. The only intentionally-deferred item (documented) is making the **rtk settings-hook** honor per-team override (requires threading `teamId` through `ConfigProfileDelegate`) — recorded + surfaced, not silently dropped.

**2. Placeholder scan:** No "TBD/TODO". Every code step has full code; run steps have commands + expected output. Task 5 Step 4 is an explicitly-optional smoke test with a concrete skip rationale (cubit tests + analyze cover the logic + compile). Tasks 3/4 defer their commit to Task 5 Step 5 so the repo never has a non-compiling commit (the enum value references `_TeamExtensionsSection` which only exists after Task 5).

**3. Type consistency:**
- `ExtensionCubit.teamOverrides(teamId)` → `Future<Map<String,bool>>` and `setTeamOverride(teamId, id, bool?)` (Task 1) consumed by `_TeamExtensionsSectionState` (Task 5).
- `ExtensionRow` fields `id`/`name`/`globalEnabled` (Phase 3a) consumed in Task 5; `context.watch<ExtensionCubit>().state.rows` matches `ExtensionUiState.rows` (Phase 3a).
- `TeamConfigSection.extensions` added to: value list, `routeSegment`, `title`, `_teamConfigSectionIcon`, and the `build` dispatch (Task 3) + the route (Task 4) — all exhaustive sites covered; `routePath`'s `_` default needs no arm.
- l10n getters (`teamExtensionsNav/Title/Subtitle`, `teamExtensionFollowGlobal/ForceOn/ForceOff`, `teamExtensionEffectiveOn/Off`, `teamExtensionRtkGlobalOnlyHint`) added in Task 2, consumed in Tasks 3 & 5.
- `_Card`/`_CardHeader`/`workspaceInsetDecoration`/`AppTextStyles` reused from the existing file (same usage as `_TeamMcpSection`/`_TeamMcpRow`).

No inconsistencies found.
