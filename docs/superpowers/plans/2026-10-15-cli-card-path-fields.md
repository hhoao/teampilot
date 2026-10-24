# CLI Card Path Fields Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore an editable single-line path `TextField` on each CLI readiness card, with the installed version as a field suffix and Install / Browse / Locate / Upgrade as text buttons on the same row; persist Claude/Codex ACP adapter paths.

**Architecture:** `SessionPreferences.acpAdapterPaths` mirrors `cliExecutablePaths`. The cubit prefers a stored absolute adapter path over boot discovery, then the launch host already feeds that path into `capabilityToPlan`. The card replaces read-only `_ResourceRow` with a shared path-field row widget (label + `TextField` + version suffix + action buttons). Cursor / OpenCode / Gemini keep a single CLI field; the personal ACP switch stays at the card bottom when `showsPersonalAcpSwitch` is true.

**Tech Stack:** Flutter, `SessionPreferences` JSON, existing `CliReadinessCard` / `AppKeys` / `kSessionPathPersistDebounce`, `cd client && dart run tool/run_tests.dart` (never `flutter test`).

## Global Constraints

- Settings UI stays registry-driven: no new `if (cli == …)` in `pages/config/`.
- Cursor curl installer: never show Upgrade.
- Gemini: no ACP field row, no personal ACP switch.
- Android: adapter Install / Locate / Browse hidden; personal ACP switch disabled.
- Blurring a field that only displays a discovered path must not copy discovery into `cliExecutablePaths` or `acpAdapterPaths`.
- User-stored absolute paths win over `mergeLocatedAcpAdapters` / CLI discovery.
- Tests: `cd client && dart run tool/run_tests.dart <paths>`; never `flutter test`.
- If the worktree needs it: `RUN_TESTS_ALLOW_PUB_SOURCE_MISMATCH=1`.
- Do not touch `/home/hhoa/git/hhoa/teampilot` dirty submodule WIP unrelated to this spec.

## File map

| File | Role |
|------|------|
| `client/lib/models/session_preferences.dart` | Persist `acpAdapterPaths` |
| `client/test/models/session_preferences_test.dart` | JSON round-trip |
| `client/lib/cubits/session_preferences_cubit.dart` | Store / resolve adapter paths |
| `client/test/cubits/session_preferences_cubit_test.dart` | Persist, merge skip, resolve order |
| `client/lib/app/app_shell.dart` | Pass `resolveAcpAdapterPath` into ChatCubit |
| `client/lib/utils/ui/app_keys.dart` | ACP field / browse / reset keys |
| `client/lib/pages/config/cli_readiness_path_row.dart` | Shared path field row |
| `client/lib/pages/config/cli_readiness_card.dart` | Use the row; drop `_ResourceRow` |
| `client/test/pages/config/cli_config_section_test.dart` | Field/button/layout assertions |
| `client/test/smoke/app_shell_smoke_test.dart` | Claude `TextField` still present |

---

### Task 1: Persist `acpAdapterPaths` on SessionPreferences

**Files:**
- Modify: `client/lib/models/session_preferences.dart`
- Test: `client/test/models/session_preferences_test.dart`

**Interfaces:**
- Consumes: existing `_cliExecutablePathsFromJson` / `_normalizeCliExecutablePaths`
- Produces: `SessionPreferences.acpAdapterPaths` (`Map<String, String>`, keyed by `CliTool.value`), constructor / `fromJson` / `copyWith` / `toJson`, `acpAdapterPathFor(String toolId)`

- [ ] **Step 1: Write the failing test**

Add to `client/test/models/session_preferences_test.dart`:

```dart
test('acpAdapterPaths round-trip and omit empties', () {
  final prefs = SessionPreferences(
    acpAdapterPaths: const {
      'claude': '/opt/claude-agent-acp',
      'codex': '',
    },
  );
  expect(prefs.acpAdapterPathFor('claude'), '/opt/claude-agent-acp');
  expect(prefs.acpAdapterPathFor('codex'), '');
  final restored = SessionPreferences.fromJson(prefs.toJson());
  expect(restored.acpAdapterPaths, {'claude': '/opt/claude-agent-acp'});
  expect(
    SessionPreferences.fromJson(const {}).acpAdapterPaths,
    isEmpty,
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart --plain-name 'acpAdapterPaths round-trip'
```

Expected: FAIL (`acpAdapterPaths` isn't a named parameter / getter).

- [ ] **Step 3: Add the field**

In `SessionPreferences`:

- Constructor: `Map<String, String> acpAdapterPaths = const {}` next to `toolchainPaths`.
- Initializer list: `acpAdapterPaths = Map.unmodifiable(_normalizeCliExecutablePaths(acpAdapterPaths))`.
- `fromJson`: `acpAdapterPaths: _cliExecutablePathsFromJson(json['acpAdapterPaths'])`.
- Field: `final Map<String, String> acpAdapterPaths;`
- Getter: `String acpAdapterPathFor(String toolId) => acpAdapterPaths[toolId]?.trim() ?? '';`
- `copyWith`: optional `Map<String, String>? acpAdapterPaths` passed through.
- `toJson`: `'acpAdapterPaths': acpAdapterPaths`.

Missing JSON key → empty map.

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/session_preferences.dart client/test/models/session_preferences_test.dart
git commit -m "feat(prefs): persist ACP adapter paths"
```

---

### Task 2: Cubit store / resolve adapter path; launch uses it

**Files:**
- Modify: `client/lib/cubits/session_preferences_cubit.dart`
- Modify: `client/lib/app/app_shell.dart` (the `discoveredAcpAdapterPath:` argument)
- Test: `client/test/cubits/session_preferences_cubit_test.dart`

**Interfaces:**
- Consumes: `SessionPreferences.acpAdapterPaths` / `copyWith` from Task 1
- Produces:
  - `String configuredAcpAdapterPath(CliTool cli)`
  - `Future<void> setAcpAdapterPathFor(CliTool cli, String value)`
  - `String resolveAcpAdapterPath(CliTool cli)` — stored trim if non-empty, else `discoveredAcpAdapterPath(cli)`
  - `hasKnownAcpAdapter` true when stored or discovered looks absolute
  - `mergeLocatedAcpAdapters` skips a CLI that already has a non-empty stored path

- [ ] **Step 1: Write the failing tests**

Add to `client/test/cubits/session_preferences_cubit_test.dart` (reuse `makeCubit`; add `locatedAcpAdapters` to its constructor args if missing):

```dart
test('setAcpAdapterPathFor persists and beats discovery', () async {
  final cubit = await makeCubit();
  await cubit.load();
  cubit.mergeLocatedAcpAdapters({
    CliTool.claude: '/discovered/claude-agent-acp',
  });
  await cubit.setAcpAdapterPathFor(CliTool.claude, '/opt/claude-agent-acp');
  expect(cubit.configuredAcpAdapterPath(CliTool.claude), '/opt/claude-agent-acp');
  expect(cubit.resolveAcpAdapterPath(CliTool.claude), '/opt/claude-agent-acp');
  expect(cubit.hasKnownAcpAdapter(CliTool.claude), isTrue);

  cubit.mergeLocatedAcpAdapters({
    CliTool.claude: '/other/claude-agent-acp',
  });
  expect(cubit.resolveAcpAdapterPath(CliTool.claude), '/opt/claude-agent-acp');
  expect(
    cubit.state.preferences.acpAdapterPaths['claude'],
    '/opt/claude-agent-acp',
  );
});

test('resolveAcpAdapterPath falls back to discovery when stored empty', () async {
  final cubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(await SharedPreferences.getInstance()),
    locatedAcpAdapters: const {CliTool.claude: '/usr/bin/claude-agent-acp'},
  );
  await cubit.load();
  expect(cubit.configuredAcpAdapterPath(CliTool.claude), '');
  expect(cubit.resolveAcpAdapterPath(CliTool.claude), '/usr/bin/claude-agent-acp');
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd client && dart run tool/run_tests.dart test/cubits/session_preferences_cubit_test.dart --plain-name 'setAcpAdapterPathFor'
```

Expected: FAIL (`setAcpAdapterPathFor` / `resolveAcpAdapterPath` missing).

- [ ] **Step 3: Implement cubit methods**

Key by `cli.value` (adapter paths are not `preferencesPathKey`).

```dart
String configuredAcpAdapterPath(CliTool cli) =>
    state.preferences.acpAdapterPathFor(cli.value);

Future<void> setAcpAdapterPathFor(CliTool cli, String value) {
  final next = Map<String, String>.of(state.preferences.acpAdapterPaths);
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    next.remove(cli.value);
  } else {
    next[cli.value] = trimmed;
  }
  return _save(state.preferences.copyWith(acpAdapterPaths: next));
}

String resolveAcpAdapterPath(CliTool cli) {
  final stored = configuredAcpAdapterPath(cli);
  if (stored.isNotEmpty) return stored;
  return discoveredAcpAdapterPath(cli);
}
```

Update `hasKnownAcpAdapter`:

```dart
bool hasKnownAcpAdapter(CliTool cli) {
  if (_looksLikeAbsolutePath(configuredAcpAdapterPath(cli))) return true;
  return _looksLikeAbsolutePath(discoveredAcpAdapterPath(cli));
}
```

At the start of the `mergeLocatedAcpAdapters` loop body, skip when `configuredAcpAdapterPath(entry.key).isNotEmpty`.

In `app_shell.dart`, change the ChatCubit argument to:

```dart
discoveredAcpAdapterPath: sessionPreferencesCubit.resolveAcpAdapterPath,
```

`capabilityToPlan` already uses an absolute discovered callback then falls back to `capability.agentExecutable` — no signature change.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd client && dart run tool/run_tests.dart test/cubits/session_preferences_cubit_test.dart --plain-name 'AcpAdapter'
```

Also run:

```bash
cd client && dart run tool/run_tests.dart test/cubits/session/acp/acp_launch_wiring_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/session_preferences_cubit.dart client/lib/app/app_shell.dart client/test/cubits/session_preferences_cubit_test.dart
git commit -m "feat(prefs): prefer stored ACP adapter path at launch"
```

---

### Task 3: Path-field row + card rewrite

**Files:**
- Create: `client/lib/pages/config/cli_readiness_path_row.dart`
- Modify: `client/lib/pages/config/cli_readiness_card.dart`
- Modify: `client/lib/utils/ui/app_keys.dart`
- Test: `client/test/pages/config/cli_config_section_test.dart`
- Test: `client/test/smoke/app_shell_smoke_test.dart`

**Interfaces:**
- Consumes: `setCliExecutablePathFor`, `setAcpAdapterPathFor`, `configuredAcpAdapterPath`, `resolveAcpAdapterPath`, `hasKnownAcpAdapter` from Task 2
- Produces: `CliReadinessPathRow` widget used twice (CLI + ACP) inside the card

Add keys:

```dart
static Key acpAdapterPathFieldFor(CliTool cli) =>
    Key('${cli.value}-acp-adapter-path-field');
static Key acpAdapterBrowseButtonFor(CliTool cli) =>
    Key('${cli.value}-acp-adapter-browse-button');
static Key acpAdapterResetButtonFor(CliTool cli) =>
    Key('${cli.value}-acp-adapter-path-reset-button');
```

Keep using `acpAdapterLocateButtonFor` for Locate (empty stored path). When stored path is set, show Reset with `acpAdapterResetButtonFor` (CLI already uses `cliExecutablePathResetButton` / `Key(spec.resetKey)`).

- [ ] **Step 1: Rewrite failing widget tests**

In `cli_config_section_test.dart`:

1. Ready-chip test: also `expect(find.byKey(AppKeys.claudeCliExecutablePathField), findsOneWidget);` and `expect(find.text('2.0.0'), findsWidgets);` (version suffix).
2. Replace `'Cursor and OpenCode ACP rows use CLI copy with no adapter install key'` with:

```dart
testWidgets('Cursor and OpenCode have no ACP path field', (tester) async {
  final cubit = await _makeCubit(
    locatedExecutables: const {
      CliTool.cursor: '/usr/local/bin/cursor-agent',
      CliTool.opencode: '/usr/local/bin/opencode',
    },
  );
  addTearDown(cubit.close);
  await tester.pumpWidget(_wrap(cubit));
  await tester.pump();
  expect(find.byKey(AppKeys.acpAdapterPathFieldFor(CliTool.cursor)), findsNothing);
  expect(find.byKey(AppKeys.acpAdapterPathFieldFor(CliTool.opencode)), findsNothing);
  expect(find.byKey(AppKeys.cursorPersonalAcpSwitch), findsOneWidget);
  expect(find.byKey(AppKeys.opencodePersonalAcpSwitch), findsOneWidget);
  expect(find.byKey(AppKeys.cursorCliUpgradeButton), findsNothing);
});
```

3. Add persist-on-edit (must not persist discovery on blur):

```dart
testWidgets('editing ACP field persists; blur of discovered path does not', (tester) async {
  final cubit = await _makeCubit(
    locatedExecutables: const {CliTool.claude: '/usr/local/bin/claude'},
    locatedAcpAdapters: const {CliTool.claude: '/usr/local/bin/claude-agent-acp'},
  );
  addTearDown(cubit.close);
  await tester.pumpWidget(_wrapCard(cubit));
  await tester.pump();
  expect(cubit.configuredAcpAdapterPath(CliTool.claude), '');

  final acpField = find.byKey(AppKeys.acpAdapterPathFieldFor(CliTool.claude));
  await tester.tap(acpField);
  await tester.pump();
  await tester.enterText(acpField, '/opt/custom-acp');
  await tester.pump(const Duration(milliseconds: 500));
  expect(cubit.configuredAcpAdapterPath(CliTool.claude), '/opt/custom-acp');
});
```

4. Locate success test: after tap Locate, also `expect(find.byKey(AppKeys.claudeCliExecutablePathField), findsOneWidget);` (already present). Keep install persistence test.

5. Gemini test unchanged (no ACP field / no Gemini switch).

Smoke test: keep `AppKeys.claudeCliExecutablePathField` (already a `TextField` key).

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart --plain-name 'Cursor and OpenCode have no ACP path field'
```

Expected: FAIL (ACP “uses CLI” row still built; new keys missing).

- [ ] **Step 3: Implement `CliReadinessPathRow` and rewire the card**

Create `cli_readiness_path_row.dart` as a `StatefulWidget` with:

- `label`, `fieldKey`, `controller` owned internally
- `storedPath`, `discoveredPath`, `version`
- `onPersist(String value)`
- `browseKey`, `onBrowse`
- `locateOrResetKey`, `locateLabel` / `resetLabel`, `onLocateOrReset`
- optional `installKey` / `onInstall` / `installing`
- optional `upgradeKey` / `onUpgrade`
- `enabled` (Android adapter: false → hide install/locate/browse)

Persist rule:

```dart
final trimmed = _controller.text.trim();
final stored = widget.storedPath.trim();
if (trimmed == stored) return;
if (stored.isEmpty && trimmed == widget.discoveredPath.trim()) return;
await widget.onPersist(trimmed);
```

Display: if `stored` non-empty, controller = stored; else controller = discovered (may be empty). Debounce with `kSessionPathPersistDebounce`. Version as `InputDecoration.suffix` (`Text(version)`, muted style). Actions: `OutlinedButton` / `TextButton` **outside** the field, same order as the spec: Install (if missing), Upgrade (if npm outdated), Browse, Locate or Reset.

In `cli_readiness_card.dart`:

- Delete `_ResourceRow`.
- CLI row: always `CliReadinessPathRow` with `fieldKey: Key(spec.fieldKey)`, persist `setCliExecutablePathFor`.
- ACP row: **only** if `_separateAdapter`. Persist `setAcpAdapterPathFor`. Hide adapter actions when `_isAndroid`.
- Else (Cursor / OpenCode / Gemini): do **not** render an ACP path row. If `_settings?.showsPersonalAcpSwitch == true`, keep the `SwitchListTile` at the bottom.
- Do not render `l10n.cliReadinessUsesCli`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd client && dart run tool/run_tests.dart \
  test/pages/config/cli_config_section_test.dart \
  test/smoke/app_shell_smoke_test.dart \
  test/cubits/session_preferences_cubit_test.dart \
  test/models/session_preferences_test.dart
```

Expected: All PASS.

Then:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: exit 0 (existing infos/warnings only).

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/config/cli_readiness_path_row.dart \
  client/lib/pages/config/cli_readiness_card.dart \
  client/lib/utils/ui/app_keys.dart \
  client/test/pages/config/cli_config_section_test.dart \
  client/test/smoke/app_shell_smoke_test.dart
git commit -m "feat(settings): restore CLI and ACP path fields with version suffix"
```

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| `TextField` + version suffix | 3 |
| Buttons outside field (Install / Upgrade / Browse / Locate / Reset) | 3 |
| Two rows only Claude / Codex | 3 |
| Cursor / OpenCode one CLI row + switch at bottom | 3 |
| Gemini no ACP row, no switch | 3 |
| `acpAdapterPaths` persist | 1–2 |
| Stored wins over discovery | 2 |
| Blur of discovered path does not persist | 3 |
| Launch stored → discovered → bare name | 2 (`resolveAcpAdapterPath` + existing `capabilityToPlan`) |
| Cursor no Upgrade | 3 (existing Upgrade gate + test) |
| Android adapter actions hidden | 3 |
| Registry-driven, no `if (cli == …)` | 3 (`_separateAdapter` / `_settings`) |
| Smoke Claude field key | 3 |
| Shared path-field widget | 3 |

## Placeholder scan

No TBD / “implement later” / “similar to Task N” without code.
