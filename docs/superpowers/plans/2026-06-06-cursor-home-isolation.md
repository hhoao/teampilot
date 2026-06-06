# Cursor HOME Isolation & Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace mixed-mode Cursor `--plugin-dir` bus wiring with per-member fake `HOME` + native `~/.cursor/` provisioning, plus full Cursor provider auth (login + import).

**Architecture:** Provider auth snapshots live under `providers/cursor/{id}/home/.cursor/`. At mixed launch, `CursorHomeProvisioner` copies auth into `members/…/cursor/home/.cursor/` and writes bus overlay files. `CursorLaunchEnvironment` sets `HOME`/`USERPROFILE`. All plugin-dir legacy code is deleted.

**Tech Stack:** Flutter/Dart (`client/`), `flutter_bloc`, existing `Filesystem` / `AppProviderRepository` / `ConfigProfileService` patterns (Claude + Codex).

**Spec:** `docs/superpowers/specs/2026-06-06-cursor-home-isolation-design.md`

---

## File map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `client/lib/services/provider/cursor/cursor_home_layout.dart` | Path helpers under fake HOME |
| Create | `client/lib/services/provider/cursor/cursor_auth_artifacts.dart` | Auth file catalog |
| Create | `client/lib/services/provider/cursor/cursor_home_bus_overlay.dart` | Pure bus file builders (replaces plugin) |
| Create | `client/lib/services/provider/cursor/cursor_home_provisioner.dart` | Launch-time merge |
| Create | `client/lib/services/provider/cursor/cursor_launch_environment.dart` | HOME env map |
| Create | `client/lib/services/provider/cursor/cursor_provider_settings_resolver.dart` | Provider resolution |
| Create | `client/lib/services/provider/cursor/cursor_provider_credentials_service.dart` | Login/import/probe |
| Modify | `client/lib/services/cli/registry/config_profile/cursor_config_profile_capability.dart` | Mixed vs standalone branches |
| Delete | `client/lib/services/cli/registry/config_profile/cursor_team_bus_plugin.dart` | Legacy plugin layout |
| Modify | `client/lib/services/cli/cli_tool_adapter.dart` | Remove `cursorPluginDir` |
| Modify | `client/lib/services/session/launch_command_builder.dart` | Remove plugin-dir relay |
| Modify | `client/lib/services/terminal/terminal_session.dart` | Remove plugin-dir relay |
| Modify | `client/lib/services/session/session_lifecycle_service.dart` | `memberConfigDir` includes cursor home |
| Modify | `client/lib/repositories/app_provider_repository.dart` | Cursor provider dir cleanup |
| Modify | `client/lib/cubits/app_provider_cubit.dart` | Cursor credential API |
| Modify | `client/lib/widgets/app_provider/app_provider_form_sheet.dart` | Cursor preset + actions |
| Modify | `client/lib/widgets/app_provider/team_tool_provider_selectors.dart` | Cursor selector |
| Create | tests under `client/test/services/provider/cursor/` | Unit tests |
| Modify | `client/test/services/cli/cursor_cli_tool_adapter_test.dart` | Update mixed expectations |
| Delete | `client/test/services/cli/config_profile/cursor_team_bus_plugin_test.dart` | Replaced |

---

### Task 0: Discover Cursor auth artifacts

**Files:**
- Create: `client/lib/services/provider/cursor/cursor_auth_artifacts.dart`
- Create: `client/test/services/provider/cursor/cursor_auth_artifacts_test.dart`

- [ ] **Step 1: Run isolated login on dev machine**

```bash
TMP_HOME=$(mktemp -d)
HOME="$TMP_HOME" cursor-agent login   # or documented login subcommand
find "$TMP_HOME/.cursor" -type f | sort
```

Record every file path relative to `.cursor/`.

- [ ] **Step 2: Write artifact catalog**

```dart
// client/lib/services/provider/cursor/cursor_auth_artifacts.dart
abstract final class CursorAuthArtifacts {
  CursorAuthArtifacts._();

  /// Files that must exist for [CredentialProbe] ready state.
  static const requiredForAuth = <String>[
    'cli-config.json',
    // append discovered token/state files from Step 1
  ];

  /// Written on every mixed launch; never copied from provider store.
  static const busGenerated = <String>[
    'rules/role.mdc',
    'hooks.json',
    'hooks/idle.sh',
    'mcp.json',
  ];

  static bool isBusGenerated(String relativePath) =>
      busGenerated.contains(relativePath);
}
```

- [ ] **Step 3: Test catalog non-empty**

```dart
// client/test/services/provider/cursor/cursor_auth_artifacts_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/cursor/cursor_auth_artifacts.dart';

void main() {
  test('requiredForAuth includes cli-config.json', () {
    expect(CursorAuthArtifacts.requiredForAuth, contains('cli-config.json'));
  });
}
```

- [ ] **Step 4: Run test**

```bash
cd client && flutter test test/services/provider/cursor/cursor_auth_artifacts_test.dart
```

Expected: PASS

---

### Task 1: `CursorHomeLayout` path helpers

**Files:**
- Create: `client/lib/services/provider/cursor/cursor_home_layout.dart`
- Create: `client/test/services/provider/cursor/cursor_home_layout_test.dart`

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';

void main() {
  test('cursorDir joins home root', () {
    const layout = CursorHomeLayout();
    expect(layout.cursorDir('/fake/home'), '/fake/home/.cursor');
    expect(layout.roleRule('/fake/home'), '/fake/home/.cursor/rules/role.mdc');
    expect(layout.hooksConfig('/fake/home'), '/fake/home/.cursor/hooks.json');
    expect(layout.mcpConfig('/fake/home'), '/fake/home/.cursor/mcp.json');
  });
}
```

- [ ] **Step 2: Implement**

```dart
import 'package:path/path.dart' as p;

final class CursorHomeLayout {
  const CursorHomeLayout();

  static const cursorDirName = '.cursor';
  static const rulesDirName = 'rules';
  static const roleRuleFileName = 'role.mdc';
  static const hooksDirName = 'hooks';
  static const hooksFileName = 'hooks.json';
  static const idleScriptFileName = 'idle.sh';
  static const mcpFileName = 'mcp.json';
  static const cliConfigFileName = 'cli-config.json';

  String cursorDir(String homeRoot) => p.join(homeRoot, cursorDirName);

  String roleRule(String homeRoot) =>
      p.join(cursorDir(homeRoot), rulesDirName, roleRuleFileName);

  String hooksConfig(String homeRoot) =>
      p.join(cursorDir(homeRoot), hooksFileName);

  String idleScript(String homeRoot) =>
      p.join(cursorDir(homeRoot), hooksDirName, idleScriptFileName);

  String mcpConfig(String homeRoot) =>
      p.join(cursorDir(homeRoot), mcpFileName);

  String cliConfig(String homeRoot) =>
      p.join(cursorDir(homeRoot), cliConfigFileName);
}
```

- [ ] **Step 3: Run test** — expect PASS

---

### Task 2: `CursorHomeBusOverlay` (replace `CursorTeamBusPlugin`)

**Files:**
- Create: `client/lib/services/provider/cursor/cursor_home_bus_overlay.dart`
- Create: `client/test/services/provider/cursor/cursor_home_bus_overlay_test.dart`
- Delete: `client/lib/services/cli/registry/config_profile/cursor_team_bus_plugin.dart`
- Delete: `client/test/services/cli/config_profile/cursor_team_bus_plugin_test.dart`

- [ ] **Step 1: Port tests from old plugin test file**

Test `hooksConfig` uses top-level `hooks.json` (not `hooks/hooks.json`).
Test `mcp.json` body includes teammate-bus server name.
Test `roleRule` has `alwaysApply: true` frontmatter.
Test `idleScript` POSTs `/idle` with `X-Member` header.
Test `parseBusPort` unchanged.

- [ ] **Step 2: Implement overlay builders**

Move logic from `cursor_team_bus_plugin.dart` with these changes:
- Remove `manifest()` / `.cursor-plugin/` entirely
- Add `buildMcpJson({memberId, port})` writing flat `mcp.json` schema per Cursor docs
- Rename `hooksConfig` → writes native `hooks.json` at `.cursor` root
- Keep `idleScript`, `parseBusPort`, `roleRule` helpers

- [ ] **Step 3: Delete old files** (no imports remain after Task 5)

- [ ] **Step 4: Run tests**

```bash
cd client && flutter test test/services/provider/cursor/cursor_home_bus_overlay_test.dart
```

---

### Task 3: `CursorLaunchEnvironment`

**Files:**
- Create: `client/lib/services/provider/cursor/cursor_launch_environment.dart`
- Create: `client/test/services/provider/cursor/cursor_launch_environment_test.dart`

- [ ] **Step 1: Test mixed env keys**

```dart
test('forMixed sets HOME and USERPROFILE', () {
  final env = CursorLaunchEnvironment.forMixed(
    homeRoot: '/data/member/home',
    useWslPaths: false,
  );
  expect(env['HOME'], '/data/member/home');
  expect(env['USERPROFILE'], '/data/member/home');
});
```

- [ ] **Step 2: Implement**

```dart
import '../../session/launch_command_builder.dart';

abstract final class CursorLaunchEnvironment {
  static Map<String, String> forMixed({
    required String homeRoot,
    required bool useWslPaths,
  }) {
    final home = useWslPaths
        ? LaunchCommandBuilder.normalizePathForCli(
            homeRoot,
            useWslPaths: true,
          )
        : homeRoot;
    return {'HOME': home, 'USERPROFILE': home};
  }

  static Map<String, String> forStandaloneConfigDir(String configDir) =>
      {'CURSOR_CONFIG_DIR': configDir};
}
```

- [ ] **Step 3: Run test** — PASS

---

### Task 4: `CursorProviderCredentialsService`

**Files:**
- Create: `client/lib/services/provider/cursor/cursor_provider_credentials_service.dart`
- Create: `client/test/services/provider/cursor/cursor_provider_credentials_service_test.dart`

Mirror `ClaudeProviderCredentialsService` structure:
- `providerHome(id)` → `{base}/providers/cursor/{id}/home`
- `probe` checks `CursorAuthArtifacts.requiredForAuth` under `providerHome/.cursor/`
- `loginEnvironment(providerId, {useWslPaths})` → `CursorLaunchEnvironment.forMixed(providerHome, …)`
- `runAuthLogin` runs `cursor-agent` login subcommand with login env
- `importFromGlobal` copies from `{homeDirectory}/.cursor/` auth files only
- `importFromDirectory` copies from selected `.cursor` path
- `syncAuthToMemberHome(providerHome, memberHome)` copies/symlinks auth files
- `revokeCredentials` deletes auth files under provider home

Use in-memory `Filesystem` fake in tests (pattern from existing credential tests).

- [ ] **Step 1–4:** TDD each method with tests then implementation

- [ ] **Step 5: Run**

```bash
cd client && flutter test test/services/provider/cursor/cursor_provider_credentials_service_test.dart
```

---

### Task 5: `CursorProviderSettingsResolver`

**Files:**
- Create: `client/lib/services/provider/cursor/cursor_provider_settings_resolver.dart`
- Create: `client/test/services/provider/cursor/cursor_provider_settings_resolver_test.dart`

Copy structure from `codex_provider_settings_resolver.dart`, replacing `codex` → `cursor`.

- [ ] Implement + test resolver priority (member → team → single provider)

---

### Task 6: `CursorHomeProvisioner`

**Files:**
- Create: `client/lib/services/provider/cursor/cursor_home_provisioner.dart`
- Create: `client/test/services/provider/cursor/cursor_home_provisioner_test.dart`

- [ ] **Step 1: Failing test — writes bus files under member home**

```dart
test('provision writes role rule and mcp when port set', () async {
  // fake fs, memberHome temp dir, member + port
  await provisioner.provision(
    memberHome: memberHome,
    provider: null,
    member: member,
    busPort: 4321,
    forceTeamLeadDelegateMode: false,
  );
  expect(await fs.stat(layout.roleRule(memberHome)).isFile, isTrue);
  expect(await fs.stat(layout.mcpConfig(memberHome)).isFile, isTrue);
});
```

- [ ] **Step 2: Implement provision steps** per spec (auth sync when provider ready, then overlay)

- [ ] **Step 3: Run test** — PASS

---

### Task 7: Rewrite `CursorConfigProfileCapability`

**Files:**
- Modify: `client/lib/services/cli/registry/config_profile/cursor_config_profile_capability.dart`
- Create: `client/test/services/cli/config_profile/cursor_config_profile_capability_test.dart`

- [ ] **Step 1: Test mixed branch emits HOME not CURSOR_CONFIG_DIR**

```dart
test('mixed contributes HOME and no plugin dir key', () async {
  final contribution = await capability.contributeLaunch(mixedCtx);
  expect(contribution.environment.containsKey('HOME'), isTrue);
  expect(contribution.environment.containsKey('CURSOR_CONFIG_DIR'), isFalse);
  expect(contribution.environment.containsKey('TEAMPILOT_CURSOR_PLUGIN_DIR'), isFalse);
});
```

- [ ] **Step 2: Test standalone still uses CURSOR_CONFIG_DIR**

- [ ] **Step 3: Implement**

```dart
// mixed:
final memberHome = join(cursorDir, 'home');
await provisioner.provision(...);
environment.addAll(CursorLaunchEnvironment.forMixed(
  homeRoot: memberHome,
  useWslPaths: ctx.useWslPaths, // add to ConfigProfileLaunchContext if missing
));
// standalone:
environment = CursorLaunchEnvironment.forStandaloneConfigDir(cursorDir);
```

Remove: `pluginDirEnvKey`, `_provisionBusPlugin`, all `CursorTeamBusPlugin` imports.

- [ ] **Step 4: Run tests** — PASS

---

### Task 8: Remove plugin-dir launch plumbing

**Files:**
- Modify: `client/lib/services/cli/cli_tool_adapter.dart`
- Modify: `client/lib/services/session/launch_command_builder.dart`
- Modify: `client/lib/services/terminal/terminal_session.dart`
- Modify: `client/test/services/cli/cursor_cli_tool_adapter_test.dart`

- [ ] **Step 1: Remove `cursorPluginDir` from `CliLaunchContext`**

- [ ] **Step 2: Remove from `LaunchCommandBuilder`**: param, `cursorPluginDirFromEnvironment`, `_launchOnlyEnvKeys` plugin entry

- [ ] **Step 3: Remove from `terminal_session.dart`** extraction/pass-through

- [ ] **Step 4: Update `CursorCliToolAdapter`**

Mixed mode: delete `--plugin-dir` / `--approve-mcps` block entirely.
Keep standalone route-B prompt logic.

- [ ] **Step 5: Update adapter tests**

Replace mixed plugin-dir test with:

```dart
test('mixed: no plugin-dir, no identity prompt', () {
  final args = adapter.buildArguments(CliLaunchContext(
    team: mixedTeam,
    member: member,
    workingDirectory: '/work',
  ));
  expect(args, isNot(contains('--plugin-dir')));
  expect(args, isNot(contains('You are the planner.')));
});
```

- [ ] **Step 6: Run**

```bash
cd client && flutter test test/services/cli/cursor_cli_tool_adapter_test.dart
```

---

### Task 9: Session lifecycle `memberConfigDir`

**Files:**
- Modify: `client/lib/services/session/session_lifecycle_service.dart`

- [ ] **Step 1: Extend `_memberConfigDirFromEnv`**

```dart
String _memberConfigDirFromEnv(Map<String, String> env) {
  return env['HOME']?.trim().isNotEmpty == true
      ? env['HOME']!
      : env['CLAUDE_CONFIG_DIR'] ??
          // ... existing keys
          '';
}
```

Only when `HOME` is set by cursor mixed launch (no conflict: other CLIs do not set HOME).

- [ ] **Step 2: Add test in existing session lifecycle test file if present, or skip if covered by config profile test**

---

### Task 10: Provider UI & cubit

**Files:**
- Create: `client/lib/models/provider_presets/cursor_provider_presets.dart`
- Modify: `client/lib/widgets/app_provider/app_provider_form_sheet.dart`
- Create: `client/lib/widgets/app_provider/cursor_credential_actions.dart` (mirror Claude)
- Modify: `client/lib/cubits/app_provider_cubit.dart`
- Modify: `client/lib/widgets/app_provider/team_tool_provider_selectors.dart`
- Modify: `client/lib/repositories/app_provider_repository.dart` — cursor stale dir cleanup optional

- [ ] **Step 1: Add preset**

```dart
abstract final class CursorProviderPresets {
  static const account = AppProviderPreset(
    id: 'cursor_account',
    name: 'Cursor Account',
    category: AppProviderCategory.official,
    // ...
  );
  static const all = [account];
}
```

Wire `appProviderPresetsFor(CliTool.cursor) => CursorProviderPresets.all`.

- [ ] **Step 2: Cubit methods** `probeCursorCredentials`, `loginCursorProvider`, `importCursorCredentials`, `revokeCursorProvider` delegating to `CursorProviderCredentialsService`.

- [ ] **Step 3: Credential actions widget** in provider form when `cli == CliTool.cursor`.

- [ ] **Step 4: Enable team provider selector for cursor**

---

### Task 11: Full verification

- [ ] **Step 1: Analyze + unit tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

Expected: zero errors; all new tests pass.

- [ ] **Step 2: Grep for legacy symbols (must be empty)**

```bash
rg 'CursorTeamBusPlugin|TEAMPILOT_CURSOR_PLUGIN_DIR|cursorPluginDir|--plugin-dir' client/
```

Expected: no matches (except changelog/spec docs if any).

- [ ] **Step 3: Manual mixed golden path (Linux PTY)**

1. Create Cursor provider → login via UI  
2. Create mixed cursor team, bind provider  
3. Launch member → verify `config-profiles/…/cursor/home/.cursor/rules/role.mdc` exists  
4. Confirm agent follows role; `wait_for_message` MCP available; stop hook hits bus  

Repeat on WSL and SSH profiles if available.

---

## Plan self-review (spec coverage)

| Spec section | Task |
|--------------|------|
| HOME-only mixed isolation | 3, 7, 8 |
| Native `.cursor` layout | 1, 2, 6 |
| Provider auth A+B | 0, 4, 10 |
| Team/member binding | 5, 10 |
| PTY/WSL/SSH env | 3, 7, 8 |
| Delete legacy plugin-dir | 2, 7, 8, 11 |
| Standalone unchanged | 7, 8 |
| Warnings | 7 |
| Tests | all tasks |

No TBD placeholders in task steps beyond Task 0 discovery list (explicitly gated).
