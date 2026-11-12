# app_shell.dart Bootstrap Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the subsystem wiring inside `buildAppShell()` into focused `lib/app/bootstrap/*` modules, reducing `client/lib/app/app_shell.dart` from 5099 lines to roughly 1200–1400 lines with zero behavior change.

**Architecture:** Keep `buildAppShell()` as the composition root and orchestrator. Each subsystem becomes a top-level `wireXxx(...)` function (Dart record return) in `lib/app/bootstrap/`; late-assigned or mutable dependencies are passed as getters. Startup lifecycle closures that span subsystems become small controller classes in Phase 3. Initialization order, teardown, and registration identity are preserved in every task.

**Tech Stack:** Dart 3, Flutter, flutter_bloc, project test runner `tool/run_tests.dart`.

## Global Constraints

- Never run `flutter test` directly. Always `cd client && dart run tool/run_tests.dart <paths>` (shared build-cache lock).
- Inner loop is `cd client && flutter analyze`; fix analyzer errors before running tests.
- Do not change initialization order, teardown semantics, or registration counts in any task.
- `late final` dependencies must be passed as getters (`ChatCubit Function() chatCubit`), never by value.
- Mutable captured state (`homeTarget`, `termuxConfigCache`, remote-boot flags) must remain owned by one holder; never copy it into an extracted function.
- Keep every source-level pin assertion in tests; only change where the test reads from.
- Commit only files touched by the current task. Do not `git add -A`.
- No `print`; user-facing errors use l10n, diagnostics use `AppLogger`.
- Each task ends with: `flutter analyze` clean, targeted tests green, commit.

## File Structure

```
client/lib/app/
  app_shell.dart                         # AppShell class + buildAppShell orchestrator + teardown
  team_pilot_bootstrap.dart              # NEW (Task 0): bootstrap widget + retry state
  bootstrap/
    managed_provider_control_plane.dart  # Task 0
    provider_usage_http_client.dart      # Task 0
    cursor_usage_stack.dart              # Task 0
    session_usage_wiring.dart            # Task 1
    catalog_wiring.dart                  # Task 2
    session_state_wiring.dart            # Task 3
    install_wiring.dart                  # Task 4
    hub_wiring.dart                      # Task 5
    workspace_wiring.dart                # Task 6
    connect_wiring.dart                  # Task 7
    command_wiring.dart                  # Task 8
    managed_provider_wiring.dart         # Task 9
    automation_wiring.dart               # Task 10
    agent_runtime_wiring.dart            # Task 11
    catalog_runtime_wiring.dart          # Task 12
    chat_session_wiring.dart             # Task 13
    session_runtime_wiring.dart          # Task 14
    app_settings_wiring.dart             # Task 15
    ssh_plane_wiring.dart                # Task 16
    vault_wiring.dart                    # Task 17
    home_plane_wiring.dart               # Task 18
    platform_wiring.dart                 # Task 19
    home_plane_switch.dart               # Task 20
    shell_boot.dart                      # Task 21
client/test/support/
  app_shell_source.dart                  # Task 0: concatenated lib/app source for source pins
```

## Extraction Procedure (applies to Tasks 1–19)

Tasks are sized as one independently reviewable extraction. If review bandwidth prefers the spec’s ~11-PR cadence, batch adjacent tasks (for example Tasks 1–2, 3–4) into one PR after each task’s checks pass; never batch across the phase boundaries (Task 0, 19/20, 21/22).

For every extraction task:

1. **Cut the anchored block verbatim** from `buildAppShell()` into the new file. Do not retype or reformat it.
2. **Wrap it in a top-level function** with the exact record type and function name given in the task. The function body starts with the cut block. A local used only inside the block stays internal; a local referenced by later code must be added to the record and re-assigned at the call site.
3. **Derive captured dependencies mechanically:** run `flutter analyze`. Each undefined identifier is a captured dependency. Add it as a named parameter:
   - immutable value already constructed → pass by value;
   - `late final` (e.g. `chatCubit`, `cliPresetsCubit`, `homeTargetController`) → pass a getter `T Function()`;
   - mutable `var` / state that changes later (e.g. `homeTarget`) → pass a getter or controller, never a snapshot.
4. **Replace the original block with the call site** shown in the task. Assign returned fields to the original local names so downstream code is untouched.
5. **Do not add error handling, comments, or behavior.** A pure move must not alter the body.
6. Run the task’s verification commands and commit.

If a block references a symbol that is assigned *later* in `buildAppShell`, the getter is mandatory — a value parameter will crash at call time with `LateInitializationError`.

---

### Task 0: Source-pin test helper + pure file moves (PR-0)

**Files:**
- Create: `client/test/support/app_shell_source.dart`
- Create: `client/lib/app/team_pilot_bootstrap.dart`
- Create: `client/lib/app/bootstrap/managed_provider_control_plane.dart`
- Create: `client/lib/app/bootstrap/provider_usage_http_client.dart`
- Create: `client/lib/app/bootstrap/cursor_usage_stack.dart`
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/main.dart`
- Modify: `client/test/app/agent_presence_wiring_test.dart`
- Modify: `client/test/app/app_shell_bootstrap_retry_test.dart`
- Modify: `client/test/integration/home_unreachable_boot_test.dart`

**Interfaces:**
- Produces: `String readAppBootstrapSource()` — sorted concatenation of every `.dart` file under `lib/app/`.
- Produces: `TeamPilotBootstrap` in `lib/app/team_pilot_bootstrap.dart`.
- Produces: `ManagedProviderControlPlane`, `ManagedProviderControlPlaneLease`, `buildDefaultManagedProviderUsageRegistry` in `lib/app/bootstrap/managed_provider_control_plane.dart`.
- Produces: `DefaultProviderUsageHttpClient` (public rename of `_DefaultProviderUsageHttpClient`) in `lib/app/bootstrap/provider_usage_http_client.dart`.
- Produces: `CursorUsageStack` (public rename of `_CursorUsageStack`), `warmCursorUsage` (public rename of `_warmCursorUsage`) in `lib/app/bootstrap/cursor_usage_stack.dart`.

- [ ] **Step 1: Add the source helper**

Create `client/test/support/app_shell_source.dart`:

```dart
import 'dart:io';

/// Concatenated source of the app composition root and its bootstrap modules.
///
/// Source-pin tests assert on wiring that is not behavior-testable. Reading the
/// whole `lib/app/` tree keeps those pins valid when wiring moves between
/// files during the bootstrap split.
String readAppBootstrapSource() {
  final files =
      Directory('lib/app')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files.map((file) => file.readAsStringSync()).join('\n');
}
```

- [ ] **Step 2: Point the three source-pin tests at the helper**

In `client/test/app/agent_presence_wiring_test.dart`:
- Add `import '../support/app_shell_source.dart';`
- Replace `final src = File('lib/app/app_shell.dart').readAsStringSync();` with `final src = readAppBootstrapSource();`
- Leave the expected construction path as `'lib/app/app_shell.dart: 1'` for now; Step 4 changes it after the state moves.

In `client/test/app/app_shell_bootstrap_retry_test.dart`:
- Add `import '../support/app_shell_source.dart';`
- Replace `final src = File('lib/app/app_shell.dart').readAsStringSync();` with `final src = readAppBootstrapSource();`

In `client/test/integration/home_unreachable_boot_test.dart`:
- Add `import '../support/app_shell_source.dart';`
- Replace the `src = File('lib/app/app_shell.dart').readAsStringSync()...` assignment with `src = readAppBootstrapSource().replaceAll(RegExp(r'\s+'), ' ');`

- [ ] **Step 3: Run analyze and the pin tests before moving anything**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/app/agent_presence_wiring_test.dart test/app/app_shell_bootstrap_retry_test.dart test/integration/home_unreachable_boot_test.dart
```

Expected: PASS. The helper still sees everything in `app_shell.dart`.

- [ ] **Step 4: Move the four pure blocks**

Move verbatim (cut from `app_shell.dart`, paste into the new file):

1. `class ManagedProviderControlPlane` through the end of `class ManagedProviderControlPlaneLease`, plus the top-level `buildDefaultManagedProviderUsageRegistry` function → `bootstrap/managed_provider_control_plane.dart`.
2. `class _DefaultProviderUsageHttpClient` → `bootstrap/provider_usage_http_client.dart`, rename to `DefaultProviderUsageHttpClient`.
3. `class _CursorUsageStack` and top-level `_warmCursorUsage` → `bootstrap/cursor_usage_stack.dart`, rename to `CursorUsageStack` and `warmCursorUsage`.
4. `class TeamPilotBootstrap` and `class _TeamPilotBootstrapState` → `team_pilot_bootstrap.dart`.

Then update references in `app_shell.dart`:
- `_DefaultProviderUsageHttpClient()` → `DefaultProviderUsageHttpClient()`
- `_CursorUsageStack(` → `CursorUsageStack(`
- `_warmCursorUsage(` → `warmCursorUsage(`
- Add imports for the four new files.
- In `main.dart`, add `import 'app/team_pilot_bootstrap.dart';`.

In `client/test/app/agent_presence_wiring_test.dart`, change the expected construction path to `'lib/app/team_pilot_bootstrap.dart: 1'` (the projection now lives beside the state).

Add only the imports the analyzer reports as needed in each moved file.

- [ ] **Step 5: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/app test/integration/home_unreachable_boot_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/main.dart \
  client/lib/app/team_pilot_bootstrap.dart \
  client/lib/app/bootstrap/managed_provider_control_plane.dart \
  client/lib/app/bootstrap/provider_usage_http_client.dart \
  client/lib/app/bootstrap/cursor_usage_stack.dart \
  client/test/support/app_shell_source.dart \
  client/test/app/agent_presence_wiring_test.dart \
  client/test/app/app_shell_bootstrap_retry_test.dart \
  client/test/integration/home_unreachable_boot_test.dart
git commit -m "refactor(app-shell): move bootstrap widget and support types out"
```

Expected: `app_shell.dart` drops by roughly 700 lines.

---

### Task 1: Session usage + notifications (PR-1)

**Files:**
- Create: `client/lib/app/bootstrap/session_usage_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef SessionUsageWiring = ({
  CursorUsageApiClient cursorUsageApiClient,
  SessionUsageCubit sessionUsageCubit,
  Future<void> Function() warmStartupCaches,
  NotificationCubit notificationCubit,
  Future<void> Function() notificationBootstrap,
  ProgressActivityCubit progressActivityCubit,
});

SessionUsageWiring wireSessionUsage({
  required HomeStorage storage,
  required CliToolRegistry registry,
  required SessionRepository sessions,
  required LaunchProfileRepository teams,
});
```

- Consumes: `HomeStorage`, `CliToolRegistry`, `SessionRepository`, `LaunchProfileRepository` from earlier wiring.

- [ ] **Step 1: Extract the block**

Cut from `final cursorUsageApiClient = CursorUsageApiClient();` through the end of `final progressActivityCubit = ProgressActivityCubit(...)` (includes the `cursorStack` closure, `sessionUsageServices`, `SessionUsageCubit`, `warmStartupCaches`, notification cubit/bootstrap, `NotificationRecorder.install`).

Create `session_usage_wiring.dart` with the typedef and `wireSessionUsage` above; body is the cut block. Change its internal returns to a record with the six fields. Keep `cursorUsageApiClient` construction inside.

- [ ] **Step 2: Replace the call site**

```dart
final sessionUsage = wireSessionUsage(
  storage: homeStorage,
  registry: cliToolRegistry,
  sessions: sessionRepo,
  teams: identityRepository,
);
final cursorUsageApiClient = sessionUsage.cursorUsageApiClient;
final sessionUsageCubit = sessionUsage.sessionUsageCubit;
final warmStartupCaches = sessionUsage.warmStartupCaches;
final notificationCubit = sessionUsage.notificationCubit;
final notificationBootstrap = sessionUsage.notificationBootstrap;
final progressActivityCubit = sessionUsage.progressActivityCubit;
```

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/app/session_usage_services_test.dart test/app/app_shell_provider_usage_bootstrap_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/session_usage_wiring.dart
git commit -m "refactor(app-shell): extract session usage wiring"
```

---

### Task 2: Skill / extension / plugin / MCP catalog wiring (PR-2)

**Files:**
- Create: `client/lib/app/bootstrap/catalog_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef SkillCatalogWiring = ({
  SkillRepository skillRepository,
  SkillInstallService skillInstallService,
  SkillAcquisitionEngine skillAcquisitionEngine,
});

typedef ExtensionCatalogWiring = ({
  ExtensionRepository extensionRepository,
  WorkspaceProjectConfigRepository workspaceProjectConfigRepository,
  CliPresetsRepository cliPresetsRepository,
});

typedef PluginMcpWiring = ({
  PluginRepository pluginRepository,
  McpRepository mcpRepository,
});

SkillCatalogWiring wireSkillCatalog({required HomeStorage storage});
ExtensionCatalogWiring wireExtensionCatalog({required HomeStorage storage});
PluginMcpWiring wirePluginMcp({required HomeStorage storage});
```

- [ ] **Step 1: Extract three non-contiguous blocks in place**

Cut and move:
1. `final skillManifest = ...` through `final skillAcquisitionEngine = SkillAcquisitionEngine(...)` → `wireSkillCatalog`.
2. `final extensionRepository = ...` through `final cliPresetsRepo = CliPresetsRepository(...)` → `wireExtensionCatalog`.
3. `final pluginRepository = ...` and `final mcpRepository = ...` → `wirePluginMcp`.

Keeping three functions preserves the original construction positions; do not merge them into one call.

- [ ] **Step 2: Replace each call site**

```dart
final skillCatalog = wireSkillCatalog(storage: homeStorage);
final skillRepo = skillCatalog.skillRepository;
final skillInstallService = skillCatalog.skillInstallService;
final skillAcquisitionEngine = skillCatalog.skillAcquisitionEngine;
```

```dart
final extensionCatalog = wireExtensionCatalog(storage: homeStorage);
final extensionRepository = extensionCatalog.extensionRepository;
final workspaceProjectConfigRepository =
    extensionCatalog.workspaceProjectConfigRepository;
final cliPresetsRepo = extensionCatalog.cliPresetsRepository;
```

```dart
final pluginMcp = wirePluginMcp(storage: homeStorage);
final pluginRepository = pluginMcp.pluginRepository;
final mcpRepository = pluginMcp.mcpRepository;
```

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/services/skill test/app/team_generation_bootstrap_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/catalog_wiring.dart
git commit -m "refactor(app-shell): extract catalog repository wiring"
```

---

### Task 3: Session state + home index prefetch (PR-3)

**Files:**
- Create: `client/lib/app/bootstrap/session_state_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef LlmConfigWiring = ({
  LlmConfigCubit cubit,
  String? Function() pathOverrideForLaunch,
});

typedef SessionStateWiring = ({
  LaunchProfileRepository identityRepository,
  SessionLifecycleService sessionLifecycleService,
  SessionRepository sessionRepo,
});

LlmConfigWiring wireLlmConfig({
  required AppSettingsRepository appSettings,
  required HomeStorage storage,
  required SessionPreferencesCubit sessionPreferences,
  required ConnectionModeService Function() connectionMode,
  required SshProfileCubit Function() sshProfiles,
  required SshClientFactory sshClientFactory,
});

SessionStateWiring wireSessionState({
  required HomeStorage storage,
  required RuntimeContextRegistry runtimeContexts,
  required RuntimeTarget Function() homeTarget,
  required ExtensionRepository extensionRepository,
  required WorkspaceProjectConfigRepository workspaceConfig,
  required CliPresetsRepository cliPresets,
  required CliToolRegistry cliToolRegistry,
  required SkillRepository skillRepository,
  required SessionPreferencesCubit sessionPreferences,
  required SshProfileRepository sshProfiles,
  required CliPresetsCubit Function() cliPresetsCubit,
  required String Function() resolveSshProfileId,
});

typedef HomeIndexPrefetchWiring = ({Future<void>? homeIndexPrefetch});

HomeIndexPrefetchWiring wireHomeIndexPrefetch({
  required AppBootstrapCubit? bootstrapCubit,
  required ConnectionModeService connectionMode,
  required Future<void>? nativePrefetch,
  required SessionRepository sessions,
  required LaunchProfileRepository identities,
});
```

- [ ] **Step 1: Extract in three functions**

Move `LlmConfigCubit` + `llmConfigPathOverrideForLaunch` → `wireLlmConfig`; move `identityRepository` / `sessionLifecycleService` / `sessionRepo` construction → `wireSessionState`; move `prefetchHomeIndex` + `bindHomeIndexPrefetch` → `wireHomeIndexPrefetch`. Keep their original call positions.

- [ ] **Step 2: Replace call sites**

```dart
final llmConfig = wireLlmConfig(
  appSettings: appSettings,
  storage: homeStorage,
  sessionPreferences: sessionPreferencesCubit,
  connectionMode: () => connectionModeService,
  sshProfiles: () => sshProfileCubit,
  sshClientFactory: sshClientFactory,
);
llmConfigCubit = llmConfig.cubit;
final llmConfigPathOverrideForLaunch = llmConfig.pathOverrideForLaunch;
```

```dart
final sessionState = wireSessionState(
  storage: homeStorage,
  runtimeContexts: runtimeContextRegistry,
  homeTarget: defaultTargetResolver,
  extensionRepository: extensionRepository,
  workspaceConfig: workspaceProjectConfigRepository,
  cliPresets: cliPresetsRepo,
  cliToolRegistry: cliToolRegistry,
  skillRepository: skillRepo,
  sessionPreferences: sessionPreferencesCubit,
  sshProfiles: sshProfileRepo,
  cliPresetsCubit: () => cliPresetsCubit,
  resolveSshProfileId: (id) => sshProfileById(id)?.id ?? id,
);
identityRepository = sessionState.identityRepository;
sessionLifecycleService = sessionState.sessionLifecycleService;
sessionRepo = sessionState.sessionRepo;
```

```dart
final homeIndex = wireHomeIndexPrefetch(
  bootstrapCubit: bootstrapCubit,
  connectionMode: connectionModeService,
  defaultWorkspaceDirectoryFuture: defaultWorkspaceDirectoryFuture,
  nativePrefetch: homeIndexPrefetchFuture,
  sessions: sessionRepo,
  identities: identityRepository,
);
final homeIndexPrefetch = homeIndex.homeIndexPrefetch;
```

If the analyzer shows `sessionLifecycleService` must be assigned before `identityRepository`, keep the original assignment order inside `wireSessionState`.

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/app/home_index_prefetch_test.dart test/app/team_generation_bootstrap_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/session_state_wiring.dart
git commit -m "refactor(app-shell): extract session state wiring"
```

---

### Task 4: Repo clone + install jobs (PR-4)

**Files:**
- Create: `client/lib/app/bootstrap/install_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef InstallWiring = ({
  RepoCloneCubit repoCloneCubit,
  InstallJobRegistry installJobRegistry,
  SkillRegistryConfig skillRegistryConfig,
});

InstallWiring wireInstallJobs({
  required HomeStorage storage,
  required SshProfileRepository sshProfiles,
  required SshClientFactory sshClientFactory,
  required RuntimeContextRegistry runtimeContexts,
  required RuntimeTarget Function() homeTarget,
  required ProgressActivityCubit progressActivity,
  required CliToolRegistry cliToolRegistry,
  required SessionPreferencesCubit sessionPreferences,
  required WorkspaceImportService importService,
  required AppUpdateService appUpdateService,
  required AppSettingsRepository appSettings,
  required bool deferHomePlaneLoads,
  required String Function() resolveSshProfileId,
});
```

- [ ] **Step 1: Extract the block**

Cut from `Future<ProcessRunHandle> repoCloneSshSpawner(...)` through `final skillRegistryConfig = ...` and move into `wireInstallJobs`; return the three fields.

- [ ] **Step 2: Replace the call site**

```dart
final installWiring = wireInstallJobs(
  storage: homeStorage,
  sshProfiles: sshProfileRepo,
  sshClientFactory: sshClientFactory,
  runtimeContexts: runtimeContextRegistry,
  homeTarget: defaultTargetResolver,
  progressActivity: progressActivityCubit,
  cliToolRegistry: cliToolRegistry,
  sessionPreferences: sessionPreferencesCubit,
  importService: workspaceImportService,
  appUpdateService: appUpdateService,
  appSettings: appSettings,
  deferHomePlaneLoads: deferHomePlaneLoads,
  resolveSshProfileId: (id) => sshProfileById(id)?.id ?? id,
);
final repoCloneCubit = installWiring.repoCloneCubit;
final installJobRegistry = installWiring.installJobRegistry;
final skillRegistryConfig = installWiring.skillRegistryConfig;
```

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/services/install test/app/team_generation_bootstrap_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/install_wiring.dart
git commit -m "refactor(app-shell): extract install job wiring"
```

---

### Task 5: Team hub + expert hub (PR-5)

**Files:**
- Create: `client/lib/app/bootstrap/hub_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef HubWiring = ({
  CatalogWorkspaceBinder catalogWorkspaceBinder,
  TeamHubFavoritesStore teamHubFavorites,
  ExpertHubCatalog expertHubCatalog,
  ExpertCapabilityResolver expertCapabilityResolver,
  MemberRosterService memberRosterService,
  SessionRuntimePlanBuilder sessionRuntimePlanBuilder,
  Future<void> Function(String mcpId) unbindMcpEverywhere,
});

HubWiring wireHubs({
  required String nativeAppDataPath,
  required HomeStorage storage,
  required LaunchProfileCubit teamCubit,
  required LaunchProfileRepository identityRepository,
  required SkillRepository skillRepository,
  required ExtensionRepository extensionRepository,
  required WorkspaceProjectConfigRepository workspaceConfig,
  required CliPresetsCubit Function() cliPresetsCubit,
});
```

- [ ] **Step 1: Extract the hub block**

Cut from `final catalogWorkspaceBinder = CatalogWorkspaceBinder(...)` through `final sessionRuntimePlanBuilder = SessionRuntimePlanBuilder(...)`. Keep the `unbindMcpEverywhere` closure inside this function; do not create a second registration.

- [ ] **Step 2: Replace the call site**

```dart
final hubs = wireHubs(
  nativeAppDataPath: nativeAppDataPath,
  storage: homeStorage,
  teamCubit: teamCubit,
  identityRepository: identityRepository,
  skillRepository: skillRepo,
  extensionRepository: extensionRepository,
  workspaceConfig: workspaceProjectConfigRepository,
  cliPresetsCubit: () => cliPresetsCubit,
);
final catalogWorkspaceBinder = hubs.catalogWorkspaceBinder;
final expertHubCatalog = hubs.expertHubCatalog;
final expertCapabilityResolver = hubs.expertCapabilityResolver;
final memberRosterService = hubs.memberRosterService;
final sessionRuntimePlanBuilder = hubs.sessionRuntimePlanBuilder;
final unbindMcpEverywhere = hubs.unbindMcpEverywhere;
```

`unbindMcpEverywhere` is defined inside the moved block, so it is produced by `wireHubs` and must not appear in its parameter list.

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/services/team_hub test/services/expert_hub test/app/team_generation_bootstrap_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/hub_wiring.dart
git commit -m "refactor(app-shell): extract hub wiring"
```

---

### Task 6: Workspace registries + workbench (PR-6)

**Files:**
- Create: `client/lib/app/bootstrap/workspace_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef WorkspaceWiring = ({
  LayoutCubit layoutCubit,
  FloatingWorkspaceCubit floatingWorkspaceCubit,
  FloatingWorkspacePersistence floatingWorkspacePersistence,
  WorkspaceToolsCubit workspaceToolsCubit,
  WorkspaceTerminalRegistry workspaceTerminalRegistry,
  GitRepoStore gitRepoStore,
  WorkspaceFileTreeStore workspaceFileTreeStore,
  WorkspaceSearchIndexes workspaceSearchIndexes,
  WorkspaceWorktreeRegistry workspaceWorktreeRegistry,
  WorkspaceSessionGroupsRegistry workspaceSessionGroupsRegistry,
  WorkspaceToolsScopeRegistry workspaceToolsScopeRegistry,
  WorkspaceRunRegistry workspaceRunRegistry,
  ConfigCubit configCubit,
});

WorkspaceWiring wireWorkspaces({
  required SharedPreferences preferences,
  required HomeStorage storage,
  required ExtensionRepository extensionRepository,
  required WorkspaceProjectConfigRepository workspaceConfig,
  required SessionLifecycleService sessionLifecycleService,
  required SshProfileRepository sshProfiles,
  required SshClientFactory sshClientFactory,
  required RuntimeTarget Function() homeTarget,
  required ChatCubit Function() chatCubit,
});
```

- [ ] **Step 1: Extract the registry block**

Cut from `final layoutCubit = LayoutCubit(...)` through `final configCubit = ConfigCubit();`. The `workspaceSessionGroupsRegistry` factory closure references `chatCubit`; pass the getter through.

- [ ] **Step 2: Replace the call site**

```dart
final workspaces = wireWorkspaces(
  preferences: preferences,
  storage: homeStorage,
  extensionRepository: extensionRepository,
  workspaceConfig: workspaceProjectConfigRepository,
  sessionLifecycleService: sessionLifecycleService,
  sshProfiles: sshProfileRepo,
  sshClientFactory: sshClientFactory,
  homeTarget: defaultTargetResolver,
  chatCubit: () => chatCubit,
);
final layoutCubit = workspaces.layoutCubit;
final floatingWorkspaceCubit = workspaces.floatingWorkspaceCubit;
final floatingWorkspacePersistence = workspaces.floatingWorkspacePersistence;
final workspaceToolsCubit = workspaces.workspaceToolsCubit;
final workspaceTerminalRegistry = workspaces.workspaceTerminalRegistry;
final gitRepoStore = workspaces.gitRepoStore;
final workspaceFileTreeStore = workspaces.workspaceFileTreeStore;
final workspaceSearchIndexes = workspaces.workspaceSearchIndexes;
final workspaceWorktreeRegistry = workspaces.workspaceWorktreeRegistry;
final workspaceSessionGroupsRegistry = workspaces.workspaceSessionGroupsRegistry;
final workspaceToolsScopeRegistry = workspaces.workspaceToolsScopeRegistry;
final workspaceRunRegistry = workspaces.workspaceRunRegistry;
final configCubit = workspaces.configCubit;
```

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/services/workspace test/app/plane_cache_ownership_guard_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/workspace_wiring.dart
git commit -m "refactor(app-shell): extract workspace registry wiring"
```

---

### Task 7: Connect backend (PR-7)

**Files:**
- Create: `client/lib/app/bootstrap/connect_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef ConnectWiring = ({
  ConnectCubit? connectCubit,
  ConnectSshBackend? embeddedSshServer,
  ConnectSshBackend? systemSshdBackend,
  PairedDeviceStore? connectDeviceStore,
});

ConnectWiring wireConnectBackend({
  required String nativeAppDataPath,
  required SshProfileRepository sshProfiles,
  required SshClientFactory sshClientFactory,
  required RuntimeTarget Function() homeTarget,
});
```

- [ ] **Step 1: Extract the platform-gated Connect block**

Cut `ConnectCubit? connectCubit;` through the end of the `if (!Platform.isAndroid) { ... }` block (desktop embedded sshd / system sshd / paired device store). Keep the Android null defaults.

- [ ] **Step 2: Replace the call site**

```dart
final connect = wireConnectBackend(
  nativeAppDataPath: nativeAppDataPath,
  sshProfiles: sshProfileRepo,
  sshClientFactory: sshClientFactory,
  homeTarget: defaultTargetResolver,
);
ConnectCubit? connectCubit = connect.connectCubit;
ConnectSshBackend? embeddedSshServer = connect.embeddedSshServer;
ConnectSshBackend? systemSshdBackend = connect.systemSshdBackend;
PairedDeviceStore? connectDeviceStore = connect.connectDeviceStore;
```

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/services/connect test/services/ssh
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/connect_wiring.dart
git commit -m "refactor(app-shell): extract connect backend wiring"
```

---

### Task 8: Command bus + terminal shell wiring (PR-8)

**Files:**
- Create: `client/lib/app/bootstrap/command_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef CommandWiring = ({
  CommandBus commandBus,
  ShortcutCubit shortcutCubit,
  WorkspaceChromeCommands workspaceChromeCommands,
  RunCommandHost runCommandHost,
  WorkspaceSearchHost workspaceSearchHost,
  WorkspaceContentSearchHost workspaceContentSearchHost,
  UiZoomBaseline uiZoomBaseline,
  TerminalTransportFactory transportFactory,
  WorkspaceShellConnector workspaceShellConnector,
  WorkspaceTerminalSessionOps workspaceTerminalSessionOps,
  WorkspaceTerminalRunService workspaceTerminalRunService,
});

CommandWiring wireCommands({
  required HomeStorage storage,
  required SshClientFactory sshClientFactory,
  required CliToolRegistry cliToolRegistry,
  required ChatCubit Function() chatCubit,
  required WorkbenchCubit Function() workbenchCubit,
});
```

- [ ] **Step 1: Extract the command/terminal block**

Cut from `final commandBus = CommandBus();` through the end of `final workspaceTerminalRunService = WorkspaceTerminalRunService();`, including the `registerShortcutsUiCommands`, `registerRunCommands`, `registerWorkspaceSearchCommands`, `registerWorkspaceContentSearchCommands`, `registerSessionCommands`, `registerSplitCommands`, and `registerLayoutCommands` calls if they are in this range. Keep each registration exactly once.

- [ ] **Step 2: Replace the call site**

```dart
final commands = wireCommands(
  storage: homeStorage,
  sshClientFactory: sshClientFactory,
  cliToolRegistry: cliToolRegistry,
  chatCubit: () => chatCubit,
  workbenchCubit: () => workbenchCubit,
);
final commandBus = commands.commandBus;
final shortcutCubit = commands.shortcutCubit;
final workspaceChromeCommands = commands.workspaceChromeCommands;
final runCommandHost = commands.runCommandHost;
final workspaceSearchHost = commands.workspaceSearchHost;
final workspaceContentSearchHost = commands.workspaceContentSearchHost;
final uiZoomBaseline = commands.uiZoomBaseline;
final transportFactory = commands.transportFactory;
final workspaceShellConnector = commands.workspaceShellConnector;
final workspaceTerminalSessionOps = commands.workspaceTerminalSessionOps;
final workspaceTerminalRunService = commands.workspaceTerminalRunService;
```

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/services/commands test/app/clean_end_state_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/command_wiring.dart
git commit -m "refactor(app-shell): extract command and terminal wiring"
```

---

### Task 9: Managed provider graph + hydration (PR-9)

**Files:**
- Create: `client/lib/app/bootstrap/managed_provider_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef ManagedProviderWiring = ({
  ManagedProviderCubit providerCubit,
  ManagedProviderUsageCubit usageCubit,
  ManagedProviderControlPlane controlPlane,
  ManagedProviderControlPlaneLease controlPlaneLease,
  Future<void> Function() hydrate,
});

ManagedProviderWiring wireManagedProviders({
  required HomeStorage storage,
  required VaultCubit vaultCubit,
  required VaultAccess vaultAccess,
  required SshProfileRepository sshProfiles,
  required GithubCredentialsStore githubCredentials,
  required SessionPreferencesCubit sessionPreferences,
  required ManagedProviderRepository? repositoryOverride,
  required ManagedProviderUsageRepository? usageRepositoryOverride,
  required ManagedProviderSecretStore? secretStoreOverride,
  required ManagedProviderUsageRegistry? usageRegistryOverride,
  required ManagedProviderUsageCoordinator? usageCoordinatorOverride,
  required ManagedProviderCubit? cubitOverride,
  required ManagedProviderUsageCubit? usageCubitOverride,
  required ProviderUsageHttpClient? httpClientOverride,
  required CliCredentialSourceResolver? cliCredentialsOverride,
});
```

- [ ] **Step 1: Extract the graph block**

Cut from `final resolvedManagedProviderSecretStore = ...` through `final managedProviderControlPlaneLease = ManagedProviderControlPlaneLease(...)`. This includes `vaultCubit.attachReferenceIndexer`, `openCredentialLoginUrl`, `appProviderLinkedCredentialLookup`, `AppProviderRepository.installDefaultLinkedCredentialLookup`, the CLI row janitor, and the startup sweep. Keep the startup sweep inside.

- [ ] **Step 2: Extract the hydration closure**

Cut `Future<void> hydrateManagedProviderData()` into the same file as a top-level function and have `wireManagedProviders` return it as `hydrate`. It must run later, so do not invoke it during wiring.

- [ ] **Step 3: Replace the call sites**

```dart
final managedProv = wireManagedProviders(
  storage: homeStorage,
  vaultCubit: vaultCubit,
  vaultAccess: vaultAccess,
  sshProfiles: sshProfileRepo,
  githubCredentials: githubCredentialsStore,
  sessionPreferences: sessionPreferencesCubit,
  repositoryOverride: managedProviderRepository,
  usageRepositoryOverride: managedProviderUsageRepository,
  secretStoreOverride: managedProviderSecretStore,
  usageRegistryOverride: managedProviderUsageRegistry,
  usageCoordinatorOverride: managedProviderUsageCoordinator,
  cubitOverride: managedProviderCubit,
  usageCubitOverride: managedProviderUsageCubit,
  httpClientOverride: managedProviderUsageHttpClient,
  cliCredentialsOverride: managedProviderCliCredentials,
);
final managedProviderControlPlane = managedProv.controlPlane;
final managedProviderControlPlaneLease = managedProv.controlPlaneLease;
final resolvedManagedProviderCubit = managedProv.providerCubit;
final resolvedManagedProviderUsageCubit = managedProv.usageCubit;
final hydrateManagedProviderData = managedProv.hydrate;
```

- [ ] **Step 4: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/app/app_shell_provider_usage_bootstrap_test.dart test/app/provider_vault_link_test.dart test/app/app_shell_bootstrap_retry_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/managed_provider_wiring.dart
git commit -m "refactor(app-shell): extract managed provider wiring"
```

---

### Task 10: Automation wiring (PR-10)

**Files:**
- Create: `client/lib/app/bootstrap/automation_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef AutomationWiring = ({
  AutomationCubit automationCubit,
  AutomationScheduler automationScheduler,
  StreamSubscription<CatalogMutationEvent> catalogSubscription,
});

AutomationRepository buildAutomationRepository({required HomeStorage storage});

AutomationWiring wireAutomationRuntime({
  required AutomationRepository repository,
  required AutomationScheduleCalculator scheduleCalculator,
  required CatalogRuntime catalogRuntime,
  required ChatCubit chatCubit,
});
```

- [ ] **Step 1: Split the non-contiguous automation block**

Keep three functions in the same file, called at their original positions:
1. `wireAutomationRepository` — `AutomationRepository` + `AutomationScheduleCalculator`.
2. `wireAutomationRuntime` — `AutomationCubit`, `HostAutomationCommandRunner`, `AutomationCommandExecutor`, `AutomationDispatcher`, `catalogRuntime.registry.register(AutomationCatalogModule(...))`, `automationCatalogSub`.
3. `wireAutomationScheduler` — if the scheduler construction is separable.

Return the cubit, scheduler, and subscription; assign to the original locals at the call site. Keep `refreshAutomations` closure inside `wireAutomationRuntime`.

- [ ] **Step 2: Replace the call sites**

```dart
final automationRepo = buildAutomationRepository(storage: homeStorage);
final scheduleCalculator = AutomationScheduleCalculator();
final automation = wireAutomationRuntime(
  repository: automationRepo,
  scheduleCalculator: scheduleCalculator,
  catalogRuntime: catalogRuntime,
  chatCubit: chatCubit,
);
automationCubit = automation.automationCubit;
automationScheduler = automation.automationScheduler;
final automationCatalogSub = automation.catalogSubscription;
```

If `scheduleCalculator` is already constructed before the automation cubit in the original order, keep its construction at that spot and pass it in.

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/services/automation test/app/team_generation_bootstrap_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/automation_wiring.dart
git commit -m "refactor(app-shell): extract automation wiring"
```

---

### Task 11: Agent runtime + prompt delivery (PR-11)

**Files:**
- Create: `client/lib/app/bootstrap/agent_runtime_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef AgentRuntimeWiring = ({
  TeammateBusMcpGateway teammateBusMcpGateway,
  AskUserAnswerPendingStore askUserAnswerPendingStore,
  AgentAttentionCubit agentAttentionCubit,
  SeatLeaseCubit seatLeaseCubit,
  AgentStatusSeatLookup agentStatusSeatLookup,
  AgentEventGateway agentEventGateway,
  AgentRuntime agentRuntime,
  PromptDeliveryCoordinator promptDeliveries,
});

AgentRuntimeWiring wireAgentRuntime({
  required HomeStorage storage,
  required ChatCubit Function() chatCubit,
  required SessionLifecycleService sessionLifecycleService,
});
```

- [ ] **Step 1: Extract the runtime block**

Cut from `final teammateBusMcpGateway = TeammateBusMcpGateway();` through `sessionLifecycleService.attachAgentRuntime(agentRuntime);`, plus the `promptDeliveryStore` / `appScopedPromptDeliveries` block. Keep `appScopedPromptDeliveries` assigned to the outer nullable local through the returned field.

- [ ] **Step 2: Replace the call site**

```dart
final agentRuntimeWiring = wireAgentRuntime(
  storage: homeStorage,
  chatCubit: () => chatCubit,
  sessionLifecycleService: sessionLifecycleService,
);
final agentAttentionCubit = agentRuntimeWiring.agentAttentionCubit;
final seatLeaseCubit = agentRuntimeWiring.seatLeaseCubit;
final agentStatusSeatLookup = agentRuntimeWiring.agentStatusSeatLookup;
final agentRuntime = agentRuntimeWiring.agentRuntime;
appScopedPromptDeliveries = agentRuntimeWiring.promptDeliveries;
```

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/services/agent_runtime test/services/prompt_delivery
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/agent_runtime_wiring.dart
git commit -m "refactor(app-shell): extract agent runtime wiring"
```

---

### Task 12: Catalog runtime assembly (PR-12)

**Files:**
- Create: `client/lib/app/bootstrap/catalog_runtime_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
CatalogRuntime wireCatalogRuntime({
  required HomeStorage storage,
  required SessionRepository sessions,
  required RuntimeContextRegistry runtimeContexts,
  required SkillRepository skillRepository,
  required SkillInstallService skillInstall,
  required SkillAcquisitionEngine skillEngine,
  required PluginRepository pluginRepository,
  required McpRepository mcpRepository,
  required WorkspaceProjectConfigRepository workspaceConfig,
});
```

- [ ] **Step 1: Extract `CatalogRuntime.assemble(...)`**

Cut from `catalogRuntime = CatalogRuntime.assemble(` through its closing `);`. Return the runtime. Keep `catalogRuntime` declared in `buildAppShell` for the teardown catch.

- [ ] **Step 2: Replace the call site**

```dart
catalogRuntime = wireCatalogRuntime(
  storage: homeStorage,
  sessions: sessionRepo,
  runtimeContexts: runtimeContextRegistry,
  skillRepository: skillRepo,
  skillInstall: skillInstallService,
  skillEngine: skillAcquisitionEngine,
  pluginRepository: pluginRepository,
  mcpRepository: mcpRepository,
  workspaceConfig: workspaceProjectConfigRepository,
);
```

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/services/catalog test/app/app_shell_bootstrap_retry_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/catalog_runtime_wiring.dart
git commit -m "refactor(app-shell): extract catalog runtime assembly"
```

---

### Task 13: Chat session wiring (PR-13)

**Files:**
- Create: `client/lib/app/bootstrap/chat_session_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
ChatCubit wireChatSession({
  required HomeStorage storage,
  required SessionRepository sessions,
  required LaunchProfileCubit teams,
  required SessionLifecycleService lifecycle,
  required RuntimeContextRegistry runtimeContexts,
  required CliToolRegistry cliToolRegistry,
  required SessionPreferencesCubit sessionPreferences,
});
```

- [ ] **Step 1: Extract the `ChatCubit` construction block**

Cut from `chatCubit = ChatCubit(` through its closing `);` and move it into `wireChatSession`. Return the cubit; the call site assigns `chatCubit = wireChatSession(...)`.

- [ ] **Step 2: Replace the call site**

```dart
chatCubit = wireChatSession(
  storage: homeStorage,
  sessions: sessionRepo,
  teams: teamCubit,
  lifecycle: sessionLifecycleService,
  runtimeContexts: runtimeContextRegistry,
  cliToolRegistry: cliToolRegistry,
  sessionPreferences: sessionPreferencesCubit,
);
```

Add captured parameters reported by the analyzer.

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/cubits/chat test/app/team_generation_bootstrap_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/chat_session_wiring.dart
git commit -m "refactor(app-shell): extract chat session wiring"
```

---

### Task 14: Session runtime wiring (PR-14)

**Files:**
- Create: `client/lib/app/bootstrap/session_runtime_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef SessionRuntimeWiring = ({
  SessionRemoteActivityCubit sessionRemoteActivityCubit,
  SessionAuthority sessionAuthority,
  ChatSessionActivitySource activitySource,
  SessionProtocolController protocolController,
  AiHistoryLoader aiHistoryLoader,
  AiHistoryCubit aiHistoryCubit,
  MailboxCubit mailboxCubit,
  BoardCubit boardCubit,
});

SessionRuntimeWiring wireSessionRuntime({
  required HomeStorage storage,
  required ChatCubit chatCubit,
  required CliToolRegistry cliToolRegistry,
  required SessionLifecycleService lifecycle,
  required CliPresetsCubit Function() cliPresetsCubit,
});
```

- [ ] **Step 1: Extract the session runtime block**

Cut from `final mailboxCubit = MailboxCubit(...)` through the end of `final sessionProtocolController = SessionProtocolController(...)`, including `aiHistoryLoader`, `aiHistoryCubit`, remote activity/authority/activity source, and the content stream subscriptions. Return the cubits/values; assign at the call site.

- [ ] **Step 2: Replace the call site**

```dart
final sessionRuntime = wireSessionRuntime(
  storage: homeStorage,
  chatCubit: chatCubit,
  cliToolRegistry: cliToolRegistry,
  lifecycle: sessionLifecycleService,
  cliPresetsCubit: () => cliPresetsCubit,
);
final mailboxCubit = sessionRuntime.mailboxCubit;
final boardCubit = sessionRuntime.boardCubit;
final aiHistoryCubit = sessionRuntime.aiHistoryCubit;
final sessionRemoteActivityCubit = sessionRuntime.sessionRemoteActivityCubit;
final sessionAuthority = sessionRuntime.sessionAuthority;
final sessionProtocolController = sessionRuntime.protocolController;
```

Keep the subscription locals (`contentInvalidationSub`, etc.) declared in `buildAppShell` for the teardown catch; if they are created inside the function, return them too.

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/services/session_protocol test/cubits/chat test/app/clean_end_state_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/session_runtime_wiring.dart
git commit -m "refactor(app-shell): extract session runtime wiring"
```

---

### Task 15: App settings + preferences wiring (PR-15)

**Files:**
- Create: `client/lib/app/bootstrap/app_settings_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef AppSettingsWiring = ({
  SharedPrefsAppSettingsRepository appSettings,
  AiFeatureSettingsCubit aiFeatureSettingsCubit,
  DiscoverySettingsCubit discoverySettingsCubit,
  SessionPreferencesCubit sessionPreferencesCubit,
  String defaultWorkspaceDirectory,
  CliExecutableDiscovery cliExecutableDiscovery,
  CliToolRegistry cliToolRegistry,
});

Future<AppSettingsWiring> wireAppSettings({
  required SharedPreferences preferences,
  required Future<String>? defaultWorkspaceDirectoryFuture,
  required String nativeAppDataPath,
});
```

- [ ] **Step 1: Extract the pre-try settings block**

Cut from `final documentsFuture = ...` through the workspace directory creation, including `AcpFrameLogger.mirrorEnabled` and the `Future.wait` that loads session preferences. Keep the `boot(...)` calls in the same order.

- [ ] **Step 2: Replace the call site**

```dart
final settings = await wireAppSettings(
  preferences: preferences,
  defaultWorkspaceDirectoryFuture: defaultWorkspaceDirectoryFuture,
  nativeAppDataPath: nativeAppDataPath,
);
final appSettings = settings.appSettings;
final aiFeatureSettingsCubit = settings.aiFeatureSettingsCubit;
final discoverySettingsCubit = settings.discoverySettingsCubit;
final sessionPreferencesCubit = settings.sessionPreferencesCubit;
final defaultWorkspaceDirectory = settings.defaultWorkspaceDirectory;
final cliExecutableDiscovery = settings.cliExecutableDiscovery;
final cliToolRegistry = settings.cliToolRegistry;
```

The `boot` logger stays in `buildAppShell`; pass it in if the extracted block logs.

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/app/home_runtime_identity_test.dart test/app/clean_end_state_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/app_settings_wiring.dart
git commit -m "refactor(app-shell): extract app settings wiring"
```

---

### Task 16: SSH plane wiring (PR-16)

**Files:**
- Create: `client/lib/app/bootstrap/ssh_plane_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef SshPlaneWiring = ({
  SshKnownHostRepository sshKnownHosts,
  SshConnectionEvents sshConnectionEvents,
  SshClientFactory sshClientFactory,
  SshProfileWorkerManager workerManager,
  SshConnectionGate connectivityGate,
});

Future<SshPlaneWiring> wireSshTransport({
  required SharedPreferences preferences,
  required VaultService vaultService,
  required VaultAccess vaultAccess,
});
```

`homeTargetStore`, `sshProfileRepo`, `homeTargetFromId`, and `locateRemoteClis` stay in `buildAppShell`: they form the control-plane identity that many later blocks and the teardown rely on.

- [ ] **Step 1: Extract the SSH transport block**

Cut the declarations from `final pairedRelayTunnels = ...` through `final sshClientFactory = ...`, including `sshVaultEntryIdFor`, `sshWorkerAuthBridge`, `sshWorkerMetrics`, `sshWorkerLauncher`, `sshProfileWorkerManager`, `sshConnectivityGate`, and `waitForSshProfileRecovery`. Do not cut `homeTargetStore`, `homeTarget`, `sshProfileRepo`, `sshProfileById`, `sshProfileConnectivityKey`, or `locateRemoteClis`.

`sshCredentialStore` is constructed before the vault block; leave it in `buildAppShell` or extract it in Task 17 alongside the vault.

- [ ] **Step 2: Replace the call site**

```dart
final sshTransport = await wireSshTransport(
  preferences: preferences,
  vaultService: vaultService,
  vaultAccess: vaultAccess,
);
final sshKnownHostRepo = sshTransport.sshKnownHosts;
final sshConnectionEvents = sshTransport.sshConnectionEvents;
final sshClientFactory = sshTransport.sshClientFactory;
final sshProfileWorkerManager = sshTransport.workerManager;
final sshConnectivityGate = sshTransport.connectivityGate;
```

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/services/ssh test/integration/home_unreachable_boot_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/ssh_plane_wiring.dart
git commit -m "refactor(app-shell): extract SSH plane wiring"
```

---

### Task 17: Vault wiring (PR-17)

**Files:**
- Create: `client/lib/app/bootstrap/vault_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef VaultCoreWiring = ({
  SshCredentialStore sshCredentialStore,
  VaultService service,
  VaultAccess access,
  VaultCredentialCapture credentialCapture,
  VaultUnlockGate unlockGate,
});

Future<VaultCoreWiring> wireVaultCore({
  required SharedPreferences preferences,
  required String nativeAppDataPath,
});

typedef VaultStateWiring = ({
  VaultCubit cubit,
  StreamSubscription<StoragePlaneChange>? planeSyncSubscription,
});

VaultStateWiring wireVaultState({
  required HomeStorage storage,
  required SshProfileRepository sshProfiles,
  required GithubCredentialsStore githubCredentials,
});
```

- [ ] **Step 1: Extract the vault core block (in place)**

Cut from `final sshCredentialStore = ...` through `final vaultUnlockGate = ...` and move into `wireVaultCore`; return the five fields. This block sits between the settings block and the SSH transport block, so call it at the same position.

- [ ] **Step 2: Extract the vault state block (in place)**

Cut `vaultCubit = VaultCubit(...)` through the legacy importer / hydration sequence and `vaultPlaneSyncSub` into `wireVaultState`. Return `vaultCubit` and the subscription if the teardown catch still needs it.

- [ ] **Step 3: Replace the call sites**

```dart
final vaultCore = await wireVaultCore(
  preferences: preferences,
  nativeAppDataPath: nativeAppDataPath,
);
final sshCredentialStore = vaultCore.sshCredentialStore;
final vaultService = vaultCore.service;
final vaultAccess = vaultCore.access;
final vaultCredentialCapture = vaultCore.credentialCapture;
final vaultUnlockGate = vaultCore.unlockGate;
```

This block is called where the vault was constructed (before the SSH transport call). When it is extracted, update the Task 16 call site to use the returned values:

```dart
final sshTransport = await wireSshTransport(
  preferences: preferences,
  vaultService: vaultCore.service,
  vaultAccess: vaultCore.access,
);
```

```dart
final vaultState = wireVaultState(
  storage: homeStorage,
  sshProfiles: sshProfileRepo,
  githubCredentials: githubCredentialsStore,
);
vaultCubit = vaultState.cubit;
final vaultPlaneSyncSub = vaultState.planeSyncSubscription;
```

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/services/vault test/app/provider_vault_link_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/vault_wiring.dart
git commit -m "refactor(app-shell): extract vault wiring"
```

---

### Task 18: Home plane wiring (PR-18)

**Files:**
- Create: `client/lib/app/bootstrap/home_plane_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef HomePlaneWiring = ({
  RuntimeContextRegistry runtimeContextRegistry,
  HomeConnectResult initialHome,
  HomeStorage homeStorage,
  HomeVaultScope scope,
});

Future<HomePlaneWiring> wireHomePlane({
  required HomeTargetStore homeTargetStore,
  required SshProfileRepository sshProfiles,
  required RuntimeTarget Function() homeTarget,
});
```

- [ ] **Step 1: Extract the home plane block**

Cut from `final runtimeTargetRegistry = RuntimeTargetRegistry(...)` through `final scope = HomeVaultScope(...)`, including `HomeConnectAttempt`, the bounded attempt, `homeStorage`, device id, markdown store, and the vault scope. Keep `homeTarget` mutable outside and pass the getter. Drop any declared parameter the analyzer reports as unused.

- [ ] **Step 2: Replace the call site**

```dart
final homePlane = await wireHomePlane(
  homeTargetStore: homeTargetStore,
  sshProfiles: sshProfileRepo,
  homeTarget: defaultTargetResolver,
);
final runtimeContextRegistry = homePlane.runtimeContextRegistry;
final homeStorage = homePlane.homeStorage;
final scope = homePlane.scope;
final initialHome = homePlane.initialHome;
```

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/services/storage test/app/home_runtime_identity_test.dart test/integration/home_unreachable_boot_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/home_plane_wiring.dart
git commit -m "refactor(app-shell): extract home plane wiring"
```

---

### Task 19: Platform services wiring (PR-19)

**Files:**
- Create: `client/lib/app/bootstrap/platform_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
typedef PlatformWiring = ({
  GithubCredentialsStore githubCredentials,
  GithubAccountCubit githubAccountCubit,
  RemoteDownloadCatalogCubit remoteDownloadCatalogCubit,
  AppUpdateService appUpdateService,
  WorkspaceImportService workspaceImportService,
  TermuxConfig? termuxConfigCache,
});

Future<PlatformWiring> wirePlatformServices({
  required String nativeAppDataPath,
  required HomeStorage storage,
});
```

- [ ] **Step 1: Extract the GitHub/download block**

Cut from `final githubCredentialsStore = ...` through `final workspaceImportService = WorkspaceImportService();`, plus the termux config cache load (`var termuxConfigCache = await termuxConfigStore.load();`). Do not cut `termuxGateCubit`, `homeSshProfileCache`, or the SSH profile helper closures; they stay in `buildAppShell`.

- [ ] **Step 2: Replace the call site**

```dart
final platform = await wirePlatformServices(
  nativeAppDataPath: nativeAppDataPath,
  storage: homeStorage,
);
final githubCredentialsStore = platform.githubCredentials;
final githubAccountCubit = platform.githubAccountCubit;
final remoteDownloadCatalogCubit = platform.remoteDownloadCatalogCubit;
final appUpdateService = platform.appUpdateService;
final workspaceImportService = platform.workspaceImportService;
var termuxConfigCache = platform.termuxConfigCache;
```

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/services/github test/services/app_update test/app/clean_end_state_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/platform_wiring.dart
git commit -m "refactor(app-shell): extract platform service wiring"
```

---

### Task 20: `HomePlaneSwitchController` (PR-20)

**Files:**
- Create: `client/lib/app/bootstrap/home_plane_switch.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
class HomePlaneSwitchController {
  HomePlaneSwitchController({
    required RuntimeContextRegistry runtimeContexts,
    required SshProfileCubit sshProfiles,
  });

  Future<void> setHomeTarget(String id);
  Future<void> persistSshHomePathCacheIfLive();
  Future<HomeErrorKind?> rebindHomeStoragePlane();
  Future<void> switchHomeTarget(String id);
}
```

The constructor list above is the minimum; add a field for every captured dependency the analyzer reports. Never pass a callback that calls one of the controller's own methods (that would be circular).

- [ ] **Step 1: Move the closures into the class**

Move `persistSshHomePathCacheIfLive`, `setHomeTarget`, `rebindHomeStoragePlane`, and `switchHomeTarget` into the controller. Keep the bodies verbatim. The controller owns no new state: `homeTarget` stays in `buildAppShell` and is reached through a getter/callback.

- [ ] **Step 2: Replace the call sites**

```dart
final homePlaneSwitch = HomePlaneSwitchController(
  runtimeContexts: runtimeContextRegistry,
  sshProfiles: sshProfileCubit,
);
```

Replace direct calls with `homePlaneSwitch.setHomeTarget(...)`, `homePlaneSwitch.switchHomeTarget(...)`, etc. Pass any additional captured dependency at construction.

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/app/home_runtime_identity_test.dart test/integration/home_unreachable_boot_test.dart test/app/plane_cache_ownership_guard_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/home_plane_switch.dart
git commit -m "refactor(app-shell): extract home plane switch controller"
```

---

### Task 21: `ShellBootController` (PR-21)

**Files:**
- Create: `client/lib/app/bootstrap/shell_boot.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Produces:

```dart
class ShellBootController {
  ShellBootController({
    required HomeStorage storage,
    required AppBootstrapCubit? bootstrapCubit,
    required Future<void>? homeIndexPrefetch,
    required Future<void> Function() notificationBootstrap,
    required ChatCubit Function() chatCubit,
    required SessionRepository sessionRepo,
    required LaunchProfileRepository identityRepository,
    required LayoutCubit layoutCubit,
    required LaunchProfileCubit teamCubit,
    required ConnectionModeService connectionModeService,
    required RuntimeTarget Function() homeTarget,
    required Future<void> Function() hydrateManagedProviders,
    required Future<void> Function() sweepStaleMarketplaceClones,
    required Future<void> Function() applyHomeEventTransport,
  });

  Future<void> bootstrapAppData();
  Future<void> warmShellAndPrepareInteractive();
  Future<bool> runRemoteBootAfterConnect();
}
```

Add any further captured dependency the analyzer reports. Do not pass callbacks that invoke the controller's own methods.

- [ ] **Step 1: Move the boot chain**

Move `warmShellAndPrepareInteractive`, `runRemoteBootAfterConnectOnce`, `runRemoteBootAfterConnect`, `bootstrapAppData`, and `reconnectHomeSshIfNeeded` into the controller. The remote boot flags become private controller fields; they must not remain duplicated in `buildAppShell`.

- [ ] **Step 2: Wire the controller**

Construct it once after `homeStorage`, `bootstrapCubit`, and the remote-boot dependencies exist. Keep `bootstrapAppData: bootstrapAppData` in the `AppShell(...)` call pointing at `controller.bootstrapAppData`.

- [ ] **Step 3: Verify and commit**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/app/app_shell_bootstrap_retry_test.dart test/integration/home_unreachable_boot_test.dart
cd ..
git add client/lib/app/app_shell.dart client/lib/app/bootstrap/shell_boot.dart
git commit -m "refactor(app-shell): extract shell boot controller"
```

---

### Task 22: Orchestrator cleanup + final verification (PR-22)

**Files:**
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Consumes: every `wireXxx` function and controller from Tasks 1–21.

- [ ] **Step 1: Reorder nothing; only remove dead locals**

Delete locals that are now only used to feed a single wiring call and are never referenced later. Keep every `late final` assignment and the teardown catch unchanged.

- [ ] **Step 2: Check the line budget**

```bash
cd client
wc -l lib/app/app_shell.dart
```

Expected: roughly 1200–1400 lines. If still above 1500, identify the largest remaining contiguous block and extract it as an additional `bootstrap/*` module following the same procedure.

- [ ] **Step 3: Full verification**

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/app test/integration/home_unreachable_boot_test.dart
dart run tool/run_tests.dart   # full suite, once before delivery
```

Expected: all green. Confirm the three source-pin tests still contain all original assertions.

- [ ] **Step 4: Commit**

```bash
cd ..
git add client/lib/app/app_shell.dart
git commit -m "refactor(app-shell): finalize bootstrap split orchestration"
```

---

## Self-Review Notes

- Spec coverage: Phase 0 → Task 0; Phase 1 → Tasks 1–14; Phase 2 → Tasks 15–19; Phase 3 → Tasks 20–21; Phase 4 → Task 22.
- Extra files added during planning: `session_state_wiring.dart` (late-final session state), `catalog_runtime_wiring.dart`, `chat_session_wiring.dart`. These are required by the spec’s 1200–1400 line target and follow the same extraction rules.
- Type consistency: record field names in each task are unique and consumed exactly once at the call site; controller method names match the original closure names.
