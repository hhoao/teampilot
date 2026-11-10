# Qoder CN CLI Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `qoderclicn` ("Qoder CLI CN") as an independent, ACP-only agent identity that can coexist with the existing global `qodercli` integration.

**Architecture:** Introduce a `QoderFlavor` value object carrying every international-vs-CN difference (identity, executable, provider preset, website/install URL, auth namespace, machine-login fallback). Parameterize the Qoder provider and runtime capability stacks with that flavor, then register two `QoderCliTool` instances (`QoderFlavor.global`, `QoderFlavor.cn`) behind a new `CliTool.qoderCn` enum identity.

**Tech Stack:** Dart/Flutter, `CliToolRegistry` capabilities, slang l10n, `dart run tool/run_tests.dart`, `flutter analyze`.

## Global Constraints

- Never invoke `flutter test` directly. Use `cd client && dart run tool/run_tests.dart <paths/options>`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` then `cd client && dart run tool/run_tests.dart`.
- Stage explicit paths only; never `git add -A`.
- Do not commit `client/google_fonts/`, `.qoder/`, or `.superpowers/`.
- No new dependencies.
- Do not add `if (cli == CliTool.qoderCn)` checks outside the existing registry/capability seams; flavor differences belong in `QoderFlavor`-driven capabilities.
- CN is ACP-only: launch `[qoderclicn, '--acp']`; never fall back to PTY.
- CN must never read `~/.qoder/.auth`; its auth namespace is `qoder-cn` and `allowMachineAuthFallback` is `false`.
- CN install URL is `https://qoder.com.cn/install`; global install URL remains `https://download.qoder.com/qodercli/install.sh`.
- l10n edits go into `client/lib/i18n/*.i18n.json`; regenerate with `cd client && dart run slang`.
- Highest-risk assumption (from the spec): `qoderclicn` supports hidden `--acp` and `QODER_CONFIG_DIR`. Task 5's gated integration smoke is the acceptance gate; if it fails, stop and mark CN unsupported instead of adding a PTY fallback.

---

## File Structure

**Create**

- `client/lib/services/cli/qoder/qoder_flavor.dart` — the flavor descriptor.
- `client/lib/services/cli/qoder/capabilities/executable_cn.dart` — CN executable identity + installer.
- `client/test/services/cli/qoder/qoder_auth_store_namespace_test.dart` — namespace/fallback isolation.
- `client/test/services/cli/qoder/qoder_flavor_runtime_test.dart` — global-flavor runtime defaults.
- `client/test/services/cli/qoder/qoder_cn_registry_test.dart` — CN registration.
- `client/test/services/cli/qoder/qoder_cn_provider_test.dart` — CN presets and session-home isolation.
- `client/test/services/cli/qoder/qoder_cn_auth_store_test.dart` — CN auth paths/no fallback.
- `client/test/services/cli/qoder/qoder_cn_executable_test.dart` — CN executable metadata/remote locate.
- `client/test/services/cli/qoder/qoder_cn_runtime_test.dart` — CN prompt/history/hook identity.
- `client/test/integration/qoder_cn_acp_local_smoke_test.dart` — gated real `qoderclicn --acp` acceptance.

**Modify**

- `client/lib/models/team_config.dart`
- `client/lib/services/cli/qoder/qoder_tool.dart`
- `client/lib/services/cli/qoder/provider_presets.dart`
- `client/lib/services/cli/qoder/capabilities/provider.dart`
- `client/lib/services/cli/qoder/capabilities/headless.dart`
- `client/lib/services/cli/qoder/capabilities/prompt.dart`
- `client/lib/services/cli/qoder/capabilities/acp.dart`
- `client/lib/services/cli/qoder/capabilities/acp_background_transcript.dart`
- `client/lib/services/cli/qoder/capabilities/history/ai_history_capability.dart`
- `client/lib/services/cli/qoder/capabilities/usage/session_usage.dart`
- `client/lib/services/cli/qoder/capabilities/hook_writer.dart`
- `client/lib/services/cli/qoder/provider/qoder_auth_store.dart`
- `client/lib/services/cli/qoder/provider/qoder_models_service.dart`
- `client/lib/services/cli/qoder/provider/qoder_provider_settings_resolver.dart`
- `client/lib/services/cli/qoder/provider/qoder_provider_form_section.dart`
- `client/lib/services/cli/registry/built_in_cli_tools.dart`
- `client/lib/pages/usage/usage_format.dart`
- `client/lib/widgets/cli/cli_brand_icon.dart`
- `client/lib/l10n/l10n_extensions.dart`
- `client/lib/widgets/app_provider/provider_credential_action_bar.dart`
- `client/lib/widgets/app_provider/provider_credential_messages.dart`
- `client/lib/models/hook_event.dart`
- `client/lib/services/hook/import/hook_event_name_mapper.dart`
- `client/lib/services/hook/import/hook_import_parser.dart`
- `client/lib/pages/hooks/hook_import_dialog.dart`
- `client/lib/services/storage/workspace_cli_cache.dart`
- `client/lib/i18n/appProvider_en.i18n.json`
- `client/lib/i18n/appProvider_zh.i18n.json`
- `client/lib/l10n/translations_en.g.dart` (generated)
- `client/lib/l10n/translations_zh.g.dart` (generated)
- `client/test/models/team_config_cli_tool_test.dart`
- `client/test/models/simple_launch_identity_test.dart`
- `client/test/integration/support/cli_test_profile.dart`
- `client/test/integration/qoder_acp_local_smoke_test.dart`
- `client/test/services/cli/qoder/qoder_models_service_test.dart`
- `client/test/services/cli/qoder/qoder_headless_test.dart`
- `client/test/services/cli/qoder/capabilities/usage/qoder_session_usage_test.dart`
- `client/test/pages/usage/usage_format_test.dart`

---

### Task 1: Parameterize the Qoder provider stack with `QoderFlavor`

**Files:**
- Create: `client/lib/services/cli/qoder/qoder_flavor.dart`
- Modify: `client/lib/services/cli/qoder/provider/qoder_auth_store.dart`
- Modify: `client/lib/services/cli/qoder/provider/qoder_models_service.dart`
- Modify: `client/lib/services/cli/qoder/provider/qoder_provider_settings_resolver.dart`
- Modify: `client/lib/services/cli/qoder/capabilities/provider.dart`
- Modify: `client/lib/services/cli/qoder/provider/qoder_provider_form_section.dart`
- Test: `client/test/services/cli/qoder/qoder_auth_store_namespace_test.dart`
- Test: `client/test/services/cli/qoder/qoder_models_service_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `QoderFlavor` with `cli`, `executableName`, `displayName`, `providerId`, `providerLabel`, `websiteUrl`, `installUrl`, `authNamespace`, `allowMachineAuthFallback`, and `static const global`.
  - `QoderAuthStore({..., String namespace = 'qoder', bool useMachineFallback = true})`.
  - `QoderModelsService({..., String namespace = 'qoder', bool useMachineAuthFallback = true})`.
  - `QoderProviderSettingsResolver({..., CliTool cli = CliTool.qoder, String? toolKey})`.
  - `QoderProviderCapability({..., QoderFlavor flavor = QoderFlavor.global})`.
  - `QoderProviderFormSection({..., required CliTool cli})`.

- [ ] **Step 1: Write the failing auth-store namespace test**

Create `client/test/services/cli/qoder/qoder_auth_store_namespace_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/qoder/provider/qoder_auth_store.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  test('namespace moves login and provider stores under its own root', () {
    final store = QoderAuthStore(
      fs: fs,
      basePath: '/app',
      pathContext: p.posix,
      machineHome: '/home/me',
      namespace: 'qoder-cn',
    );

    expect(store.loginRoot('work'), '/app/cli-login/qoder-cn/work');
    expect(store.loginConfigDir('work'), '/app/cli-login/qoder-cn/work/config');
    expect(store.providerAuthDir('work'), '/app/providers/qoder-cn/work');
  });

  test('disabled machine fallback ignores an existing ~/.qoder login', () async {
    await fs.ensureDir('/home/me/.qoder/.auth');
    await fs.atomicWrite('/home/me/.qoder/.auth/user', 'MACHINE');
    await fs.atomicWrite('/home/me/.qoder/.auth/machine_id', 'MID');

    final store = QoderAuthStore(
      fs: fs,
      basePath: '/app',
      pathContext: p.posix,
      machineHome: '/home/me',
      namespace: 'qoder-cn',
      useMachineFallback: false,
    );

    expect(await store.authSourceDir('work'), isNull);
    expect(
      await store.seedSessionAuth(
        providerId: 'work',
        sessionConfigDir: '/sessions/s1/qoder-cn',
      ),
      isFalse,
    );
    expect((await fs.stat('/sessions/s1/qoder-cn/.auth')).exists, isFalse);
  });

  test('enabled fallback keeps the existing global behavior', () async {
    await fs.ensureDir('/home/me/.qoder/.auth');
    await fs.atomicWrite('/home/me/.qoder/.auth/user', 'MACHINE');
    await fs.atomicWrite('/home/me/.qoder/.auth/machine_id', 'MID');

    final store = QoderAuthStore(
      fs: fs,
      basePath: '/app',
      pathContext: p.posix,
      machineHome: '/home/me',
    );

    expect(await store.authSourceDir('work'), '/home/me/.qoder/.auth');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/qoder/qoder_auth_store_namespace_test.dart`
Expected: compile failure because `QoderAuthStore` has no `namespace`/`useMachineFallback` parameters.

- [ ] **Step 3: Add `QoderFlavor.global` and parameterize the auth store**

Create `client/lib/services/cli/qoder/qoder_flavor.dart`:

```dart
import '../../../models/team_config.dart';

/// Distribution-specific Qoder CLI identity.
///
/// The global and CN builds share the same ACP protocol and config-dir
/// contract, but they are separate binaries with separate provider catalogs
/// and separate account stores.
final class QoderFlavor {
  const QoderFlavor({
    required this.cli,
    required this.executableName,
    required this.displayName,
    required this.providerId,
    required this.providerLabel,
    required this.websiteUrl,
    required this.installUrl,
    required this.authNamespace,
    required this.allowMachineAuthFallback,
  });

  final CliTool cli;
  final String executableName;
  final String displayName;
  final String providerId;
  final String providerLabel;
  final String websiteUrl;
  final String installUrl;
  final String authNamespace;
  final bool allowMachineAuthFallback;

  static const global = QoderFlavor(
    cli: CliTool.qoder,
    executableName: 'qodercli',
    displayName: 'Qoder CLI',
    providerId: 'qoder',
    providerLabel: 'Qoder',
    websiteUrl: 'https://qoder.com',
    installUrl: 'https://download.qoder.com/qodercli/install.sh',
    authNamespace: 'qoder',
    allowMachineAuthFallback: true,
  );
}
```

In `qoder_auth_store.dart`, change the constructor and add fields:

```dart
  QoderAuthStore({
    required this.fs,
    required this.basePath,
    required this.pathContext,
    String? machineHome,
    this.namespace = 'qoder',
    this.useMachineFallback = true,
  }) : machineHome =
           machineHome ??
           (Platform.environment['HOME'] ??
               Platform.environment['USERPROFILE'] ??
               '');

  final Filesystem fs;
  final String basePath;
  final p.Context pathContext;
  final String machineHome;
  final String namespace;
  final bool useMachineFallback;
```

Change the two roots:

```dart
  String loginRoot(String providerId) =>
      pathContext.join(basePath, 'cli-login', namespace, _safe(providerId));
```

```dart
  String providerAuthDir(String providerId) =>
      pathContext.join(basePath, 'providers', namespace, _safe(providerId));
```

Change `authSourceDir` so the machine fallback is gated:

```dart
    if (!useMachineFallback || machineHome.isEmpty) return null;
```

- [ ] **Step 4: Run the auth-store test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/qoder/qoder_auth_store_namespace_test.dart test/services/cli/qoder/qoder_auth_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing models-service namespace test**

Append this test inside `client/test/services/cli/qoder/qoder_models_service_test.dart` (before the closing `}` of `main`):

```dart
  test('namespace drives the probe dir, auth source and disk cache', () async {
    await fs.ensureDir('/app/providers/qoder-cn/work');
    await fs.atomicWrite('/app/providers/qoder-cn/work/user', 'CNUSER');
    await fs.atomicWrite('/app/providers/qoder-cn/work/machine_id', 'CNMID');
    var calls = 0;
    final service = QoderModelsService(
      fs: fs,
      basePath: '/app',
      machineHome: '/home/me',
      namespace: 'qoder-cn',
      executable: 'qoderclicn',
      useMachineAuthFallback: false,
      opener:
          ({required executable, required configDir, required timeout}) async {
            calls++;
            expect(executable, 'qoderclicn');
            expect(configDir, '/app/tmp/qoder-cn-models/work');
            expect(
              await fs.readString(p.join(configDir, '.auth', 'user')),
              'CNUSER',
            );
            return const QoderModelsSnapshot(
              modelIds: ['auto'],
              names: {'auto': 'Auto'},
            );
          },
    );

    await service.ensureLoaded(providerId: 'work');

    expect(calls, 1);
    expect(
      await fs.readString('/app/cache/qoder-cn_models/work.json'),
      isNotNull,
    );
  });

  test('CN-style storage never probes from the machine login', () async {
    await fs.ensureDir('/home/me/.qoder/.auth');
    await fs.atomicWrite('/home/me/.qoder/.auth/user', 'MACHINE');
    await fs.atomicWrite('/home/me/.qoder/.auth/machine_id', 'MID');
    var calls = 0;
    final service = QoderModelsService(
      fs: fs,
      basePath: '/app',
      machineHome: '/home/me',
      namespace: 'qoder-cn',
      executable: 'qoderclicn',
      useMachineAuthFallback: false,
      opener:
          ({required executable, required configDir, required timeout}) async {
            calls++;
            return const QoderModelsSnapshot(modelIds: ['auto']);
          },
    );

    await service.ensureLoaded(providerId: 'missing');

    expect(calls, 0);
    expect(service.modelIdsFor(providerId: 'missing'), isEmpty);
  });
```

- [ ] **Step 6: Run the models test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/qoder/qoder_models_service_test.dart`
Expected: compile failure because `QoderModelsService` has no `namespace`/`useMachineAuthFallback` parameters.

- [ ] **Step 7: Parameterize `QoderModelsService`**

In `qoder_models_service.dart`, add constructor parameters:

```dart
    this.namespace = 'qoder',
    this.useMachineAuthFallback = true,
```

Add fields next to `executable`:

```dart
  final String namespace;
  final bool useMachineAuthFallback;
```

Change the probe config dir in `_fetchLive`:

```dart
    final configDir = roots.fs.pathContext.join(
      roots.basePath,
      'tmp',
      '$namespace-models',
      _safeSegment(providerId),
    );
```

Pass the namespace/fallback into the auth store:

```dart
    final store = QoderAuthStore(
      fs: roots.fs,
      basePath: roots.basePath,
      pathContext: roots.fs.pathContext,
      machineHome: machineHome,
      namespace: namespace,
      useMachineFallback: useMachineAuthFallback,
    );
```

Change the cache path:

```dart
  String _cacheFilePath(_ResolvedStorage roots, String key) => roots
      .fs
      .pathContext
      .join(roots.basePath, 'cache', '${namespace}_models', '$key.json');
```

- [ ] **Step 8: Run the models test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/qoder/qoder_models_service_test.dart`
Expected: PASS.

- [ ] **Step 9: Parameterize the resolver, provider and form section**

Replace `client/lib/services/cli/qoder/provider/qoder_provider_settings_resolver.dart` with:

```dart
import '../../../../models/app_provider_config.dart';
import '../../../../models/team_config.dart';
import '../../../../repositories/app_provider_repository.dart';
import '../../../io/filesystem.dart';
import '../../../storage/home_storage.dart';

/// Resolves Qoder providers from the app catalog for session launch.
/// Member binding wins, then the team default, then a lone catalogued
/// provider.
final class QoderProviderSettingsResolver {
  QoderProviderSettingsResolver({
    required String basePath,
    required HomeStorage storage,
    Filesystem? fs,
    AppProviderRepository? repository,
    CliTool cli = CliTool.qoder,
    String? toolKey,
  }) : _cli = cli,
       _toolKey = toolKey ?? cli.value,
       _repository =
           repository ??
           AppProviderRepository(basePath: basePath, fs: fs, storage: storage);

  final AppProviderRepository _repository;
  final CliTool _cli;
  final String _toolKey;

  Future<AppProviderConfig?> findById(String? providerId) async {
    final trimmed = providerId?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return _repository.findById(_cli, trimmed);
  }

  Future<AppProviderConfig?> resolveForLaunch({
    required TeamProfile team,
    TeamMemberConfig? member,
  }) async {
    final selected = member;
    if (selected != null && selected.isValid) {
      final fromMember = await findById(selected.provider);
      if (fromMember != null) return fromMember;
    }
    final fromTeam = team.providerIdsByTool[_toolKey]?.trim() ?? '';
    if (fromTeam.isNotEmpty) {
      final byId = await findById(fromTeam);
      if (byId != null) return byId;
    }
    return resolveSole();
  }

  /// The single catalogued provider, if exactly one exists (standalone
  /// default).
  Future<AppProviderConfig?> resolveSole() async {
    final providers = await _repository.loadProviders(_cli);
    return providers.length == 1 ? providers.first : null;
  }
}
```

In `provider.dart`, change the constructor and add the flavor field:

```dart
  const QoderProviderCapability({
    this.storage,
    this.modelsService,
    this.flavor = QoderFlavor.global,
  });

  final HomeStorage? storage;

  /// Live account catalog; absent in the pre-configure registry (tests/args).
  final QoderModelsService? modelsService;

  final QoderFlavor flavor;
```

Add the import:

```dart
import '../qoder_flavor.dart';
```

Change `_authStore`:

```dart
    return QoderAuthStore(
      fs: home.fs,
      basePath: home.paths.basePath,
      pathContext: home.fs.pathContext,
      machineHome: home.home,
      namespace: flavor.authNamespace,
      useMachineFallback: flavor.allowMachineAuthFallback,
    );
```

Change the catalog identity:

```dart
  @override
  CliTool get catalogCli => flavor.cli;

  @override
  String? get defaultOfficialProviderId => flavor.providerId;
```

Change the login executable:

```dart
  @override
  String get loginExecutableName => flavor.executableName;
```

Change `buildLoginDialog`'s store:

```dart
    final store = QoderAuthStore(
      fs: storage.fs,
      basePath: storage.paths.basePath,
      pathContext: storage.fs.pathContext,
      namespace: flavor.authNamespace,
      useMachineFallback: flavor.allowMachineAuthFallback,
    );
```

Change `materializeSessionHome`'s session tool dir and settings write:

```dart
    final configDir = delegate.sessionToolDir(
      ctx.scope.workspaceId,
      ctx.scope.sessionId,
      flavor.cli.value,
      memberId: ctx.scope.memberId,
    );
```

```dart
    await delegate.writeSettingsFile(
      settingsPath,
      settings,
      tool: flavor.cli.value,
      teamId: ctx.team?.id,
      workspaceId: ctx.workspaceId,
    );
```

Change the launch resolver construction:

```dart
    final resolver = QoderProviderSettingsResolver(
      basePath: ctx.catalog.basePath,
      fs: ctx.catalog.fs,
      storage: home,
      cli: flavor.cli,
    );
```

Change `buildExtraSection` to pass the CLI:

```dart
    return QoderProviderFormSection(
      cli: flavor.cli,
      effort: props.extra[QoderFormExtraKeys.effort]?.toString() ?? '',
      contextWindow:
          props.extra[QoderFormExtraKeys.contextWindow]?.toString() ?? '',
      defaultModel: props.defaultModel,
      onEffortChanged: (value) => props.onExtraChanged({
        ...props.extra,
        QoderFormExtraKeys.effort: value,
      }),
      onContextWindowChanged: (value) => props.onExtraChanged({
        ...props.extra,
        QoderFormExtraKeys.contextWindow: value,
      }),
    );
```

In `qoder_provider_form_section.dart`, add the required field:

```dart
  const QoderProviderFormSection({
    required this.cli,
    required this.effort,
    required this.contextWindow,
    required this.defaultModel,
    required this.onEffortChanged,
    required this.onContextWindowChanged,
    super.key,
  });

  final CliTool cli;
```

Use it in the effort picker and its synthetic provider:

```dart
          CliEffortPickerField(
            cli: widget.cli,
            value: widget.effort,
            model: widget.defaultModel,
            provider: AppProviderConfig(
              id: '${widget.cli.value}-form',
              cli: widget.cli,
              name: widget.cli.value == 'qoder-cn' ? 'Qoder CN' : 'Qoder',
              defaultModel: widget.defaultModel,
            ),
            onChanged: widget.onEffortChanged,
          ),
```

- [ ] **Step 10: Run the focused provider tests and analyze**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/qoder/qoder_provider_materialize_test.dart test/services/cli/qoder/qoder_provider_catalog_test.dart test/services/cli/qoder/qoder_provider_form_test.dart test/services/cli/qoder/qoder_models_service_test.dart test/services/cli/qoder/qoder_auth_store_test.dart test/services/cli/qoder/qoder_auth_store_namespace_test.dart`
Expected: PASS.

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors.

- [ ] **Step 11: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/cli/qoder/qoder_flavor.dart \
  client/lib/services/cli/qoder/provider/qoder_auth_store.dart \
  client/lib/services/cli/qoder/provider/qoder_models_service.dart \
  client/lib/services/cli/qoder/provider/qoder_provider_settings_resolver.dart \
  client/lib/services/cli/qoder/capabilities/provider.dart \
  client/lib/services/cli/qoder/provider/qoder_provider_form_section.dart \
  client/test/services/cli/qoder/qoder_auth_store_namespace_test.dart \
  client/test/services/cli/qoder/qoder_models_service_test.dart
git commit -m "refactor(qoder): parameterize provider stack by flavor"
```

---

### Task 2: Parameterize the Qoder runtime capabilities with `QoderFlavor`

**Files:**
- Modify: `client/lib/services/cli/qoder/capabilities/acp.dart`
- Modify: `client/lib/services/cli/qoder/capabilities/acp_background_transcript.dart`
- Modify: `client/lib/services/cli/qoder/capabilities/headless.dart`
- Modify: `client/lib/services/cli/qoder/capabilities/prompt.dart`
- Modify: `client/lib/services/cli/qoder/capabilities/usage/session_usage.dart`
- Modify: `client/lib/services/cli/qoder/capabilities/history/ai_history_capability.dart`
- Modify: `client/lib/services/cli/qoder/capabilities/hook_writer.dart`
- Test: `client/test/services/cli/qoder/qoder_flavor_runtime_test.dart`

**Interfaces:**
- Consumes: `QoderFlavor` from Task 1.
- Produces:
  - `QoderAcpCapability({String transcriptFallbackPrefix = 'qoder'})`.
  - `QoderAcpBackgroundTranscriptSource({..., String fallbackPrefix = 'qoder'})`.
  - `QoderHeadlessCapability({HomeStorage? storage, QoderFlavor flavor = QoderFlavor.global})`, `executable => flavor.executableName`.
  - `QoderPromptCapability({QoderFlavor flavor = QoderFlavor.global})`, `String get toolId`.
  - `QoderSessionUsageCapability({QoderFlavor flavor = QoderFlavor.global})`.
  - `QoderAiHistoryCapability({QoderFlavor flavor = QoderFlavor.global})`.
  - `QoderHookWriter({String denyReason = ..., QoderFlavor flavor = QoderFlavor.global})`.

- [ ] **Step 1: Write the failing runtime-flavor test**

Create `client/test/services/cli/qoder/qoder_flavor_runtime_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/qoder/capabilities/headless.dart';
import 'package:teampilot/services/cli/qoder/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/qoder/capabilities/hook_writer.dart';
import 'package:teampilot/services/cli/qoder/capabilities/prompt.dart';
import 'package:teampilot/services/cli/qoder/qoder_flavor.dart';

void main() {
  test('global flavor keeps the qoder runtime identity', () {
    const prompt = QoderPromptCapability();
    expect(prompt.toolId, 'qoder');
    expect(prompt.providerId, 'qoder');

    const history = QoderAiHistoryCapability();
    expect(history.adapter.id, 'qoder');
    expect(history.tailFallbackPrefix, 'qoder');

    const writer = QoderHookWriter();
    expect(writer.nativeEvent(HookEvent.sessionStart), 'SessionStart');
  });

  test('headless executable is resolved from the flavor', () {
    const cap = QoderHeadlessCapability(flavor: QoderFlavor.global);
    expect(cap.executable, 'qodercli');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/qoder/qoder_flavor_runtime_test.dart`
Expected: compile failure because the capabilities do not accept `flavor` yet.

- [ ] **Step 3: Parameterize the ACP background transcript prefix**

In `acp_background_transcript.dart`:

```dart
  QoderAcpBackgroundTranscriptSource({
    required super.fs,
    required super.sessionToolDir,
    required super.sessionId,
    String fallbackPrefix = 'qoder',
  }) : super(lineAppend: appendQoderJsonlEvent, fallbackPrefix: fallbackPrefix);
```

In `acp.dart`, add the constructor parameter and field:

```dart
  const QoderAcpCapability({this.transcriptFallbackPrefix = 'qoder'});

  static const configDirEnvKey = 'QODER_CONFIG_DIR';

  final String transcriptFallbackPrefix;
```

Pass it into the source:

```dart
  }) => QoderAcpBackgroundTranscriptSource(
    fs: fs,
    sessionToolDir: sessionToolDir,
    sessionId: sessionId,
    fallbackPrefix: transcriptFallbackPrefix,
  );
```

- [ ] **Step 4: Parameterize headless**

In `headless.dart`, add the flavor import and constructor field:

```dart
import '../qoder_flavor.dart';
```

```dart
  const QoderHeadlessCapability({
    this.storage,
    this.flavor = QoderFlavor.global,
  });

  @override
  final HomeStorage? storage;

  final QoderFlavor flavor;
```

Change the executable:

```dart
  @override
  String get executable => flavor.executableName;
```

Change the headless interactive context:

```dart
    final interactive = interactiveContextForHeadless(ctx, flavor.cli);
```

Change the auth store in `provision`:

```dart
    final store = QoderAuthStore(
      fs: fs,
      basePath: basePath,
      pathContext: fs.pathContext,
      machineHome: home,
      namespace: flavor.authNamespace,
      useMachineFallback: flavor.allowMachineAuthFallback,
    );
```

Change the resolver in `_resolveProvider`:

```dart
    final resolver = QoderProviderSettingsResolver(
      basePath: basePath,
      fs: fs,
      storage: homeStorage,
      cli: flavor.cli,
    );
```

- [ ] **Step 5: Parameterize the prompt capability**

Replace `client/lib/services/cli/qoder/capabilities/prompt.dart` with:

```dart
import 'dart:async';

import '../../../chat/launch/staging/manifest/work_plane_paths.dart';
import '../../../resource/contribution/resource_origin.dart';
import '../../registry/capabilities/prompt_capability.dart';
import '../../registry/member_role_provision.dart';
import '../qoder_flavor.dart';

/// Qoder reads a hierarchical `AGENTS.md` memory file (user-level one lives in
/// `QODER_CONFIG_DIR`); the member role prompt is materialized there.
final class QoderPromptCapability
    implements PromptCapability, PromptContributionProvider {
  const QoderPromptCapability({this.flavor = QoderFlavor.global});

  final QoderFlavor flavor;

  static const contextFileName = 'AGENTS.md';

  String get toolId => flavor.cli.value;

  @override
  String get providerId => toolId;

  @override
  FutureOr<Iterable<PromptContribution>> provide(PromptProviderContext ctx) {
    final member = ctx.member;
    if (member == null || !member.isValid) return const [];
    final roleId = '$toolId-member-role';
    return [
      PromptContribution(
        id: roleId,
        title: 'Member role',
        scope: PromptScope.member,
        content: MemberRoleProvision.composeRolePrompt(
          member: member,
          forceTeamLeadDelegateMode: ctx.forceTeamLeadDelegateMode,
          mixed: ctx.mixed,
        ).trim(),
        origin: ContributionOrigin(
          providerId: toolId,
          kind: ResourceOriginKind.cliBuiltIn,
          sourceId: roleId,
        ),
      ),
    ];
  }

  @override
  Future<PromptMaterializeResult> materialize(
    PromptMaterializeContext ctx, {
    required PromptDocument document,
  }) async {
    final paths = ctx.paths;
    final scope = ctx.scope;
    final member = ctx.member;
    if (paths == null || scope == null || member == null || !member.isValid) {
      return const PromptMaterializeResult();
    }
    final prompt = document.content;
    if (prompt.isEmpty) return const PromptMaterializeResult();
    final configDir = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    await paths.fs.ensureDir(configDir);
    await paths.fs.atomicWrite(
      paths.joinWork(configDir, contextFileName),
      '$prompt\n',
    );
    return const PromptMaterializeResult(written: true);
  }
}
```

- [ ] **Step 6: Parameterize session usage**

In `session_usage.dart`, add the import and field:

```dart
import '../../qoder_flavor.dart';
```

```dart
  const QoderSessionUsageCapability({this.flavor = QoderFlavor.global});

  final QoderFlavor flavor;
```

Change the source id:

```dart
            id: '${flavor.cli.value}-jsonl:$full',
```

Change the event identity and request prefix:

```dart
      final requestId = '${flavor.cli.value}:$messageId';
      final event = SessionUsageEvent(
        requestId: requestId,
        cli: flavor.cli,
```

- [ ] **Step 7: Parameterize AI history**

In `history/ai_history_capability.dart`, add the import and field:

```dart
import '../../qoder_flavor.dart';
```

```dart
  const QoderAiHistoryCapability({this.flavor = QoderFlavor.global});

  final QoderFlavor flavor;
```

Change the adapter and prefix:

```dart
  @override
  AiTranscriptAdapter get adapter => QoderAiTranscriptAdapter(id: flavor.cli.value);

  @override
  String get tailFallbackPrefix => flavor.cli.value;
```

Change the adapter class:

```dart
final class QoderAiTranscriptAdapter implements AiTranscriptAdapter {
  const QoderAiTranscriptAdapter({this.id = 'qoder'});

  @override
  final String id;

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async => const [];
}
```

- [ ] **Step 8: Parameterize the hook writer**

In `hook_writer.dart`, add the import and field:

```dart
import '../qoder_flavor.dart';
```

```dart
  const QoderHookWriter({
    this.denyReason = 'TeamPilot hook policy',
    this.flavor = QoderFlavor.global,
  });

  final String denyReason;
  final QoderFlavor flavor;
```

Change `nativeEvent`:

```dart
  @override
  String? nativeEvent(HookEvent event) =>
      HookEventCapability.nativeEvent(event, flavor.cli);
```

- [ ] **Step 9: Run the runtime and existing Qoder tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/qoder/`
Expected: PASS.

- [ ] **Step 10: Analyze and commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors.

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/cli/qoder/capabilities/acp.dart \
  client/lib/services/cli/qoder/capabilities/acp_background_transcript.dart \
  client/lib/services/cli/qoder/capabilities/headless.dart \
  client/lib/services/cli/qoder/capabilities/prompt.dart \
  client/lib/services/cli/qoder/capabilities/usage/session_usage.dart \
  client/lib/services/cli/qoder/capabilities/history/ai_history_capability.dart \
  client/lib/services/cli/qoder/capabilities/hook_writer.dart \
  client/test/services/cli/qoder/qoder_flavor_runtime_test.dart
git commit -m "refactor(qoder): parameterize runtime capabilities by flavor"
```

---

### Task 3: Add the `qoder-cn` identity and register it

**Files:**
- Create: `client/lib/services/cli/qoder/capabilities/executable_cn.dart`
- Modify: `client/lib/models/team_config.dart`
- Modify: `client/lib/services/cli/qoder/qoder_flavor.dart`
- Modify: `client/lib/services/cli/qoder/provider_presets.dart`
- Modify: `client/lib/services/cli/qoder/qoder_tool.dart`
- Modify: `client/lib/services/cli/registry/built_in_cli_tools.dart`
- Modify: `client/lib/i18n/appProvider_en.i18n.json`
- Modify: `client/lib/i18n/appProvider_zh.i18n.json`
- Modify: `client/lib/pages/usage/usage_format.dart`
- Modify: `client/lib/widgets/cli/cli_brand_icon.dart`
- Modify: `client/lib/l10n/l10n_extensions.dart`
- Modify: `client/lib/widgets/app_provider/provider_credential_action_bar.dart`
- Modify: `client/lib/widgets/app_provider/provider_credential_messages.dart`
- Modify: `client/lib/models/hook_event.dart`
- Modify: `client/lib/services/hook/import/hook_event_name_mapper.dart`
- Modify: `client/lib/services/hook/import/hook_import_parser.dart`
- Modify: `client/lib/pages/hooks/hook_import_dialog.dart`
- Modify: `client/lib/services/storage/workspace_cli_cache.dart`
- Modify: `client/lib/l10n/translations_en.g.dart` (generated)
- Modify: `client/lib/l10n/translations_zh.g.dart` (generated)
- Test: `client/test/models/team_config_cli_tool_test.dart`
- Test: `client/test/models/simple_launch_identity_test.dart`
- Test: `client/test/integration/support/cli_test_profile.dart`
- Test: `client/test/integration/qoder_acp_local_smoke_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1-2.
- Produces:
  - `CliTool.qoderCn` with value `'qoder-cn'`.
  - `QoderFlavor.cn` and `QoderFlavor.isCn`.
  - `QoderCnExecutableCapability` with executable `qoderclicn`, preferences key `qoder-cn`.
  - `QoderProviderPresets.global`, `.cn`, `.all`.
  - `QoderCliTool({QoderFlavor flavor = QoderFlavor.global, ...})` (no longer `const`), `id => flavor.cli`.
  - Two registry entries under `CliTool.qoder` and `CliTool.qoderCn`.

- [ ] **Step 1: Write the failing enum test**

Append to `client/test/models/team_config_cli_tool_test.dart`:

```dart
  test('CliTool has a qoder-cn value that parses round-trip', () {
    expect(CliTool.qoderCn.value, 'qoder-cn');
    expect(CliTool.tryParse('qoder-cn'), CliTool.qoderCn);
    expect(CliTool.tryParse('Qoder-CN'), CliTool.qoderCn);
  });
```

Replace the existing length test:

```dart
  test('CliTool.values length is 9 after adding antigravity and qoder', () {
    expect(CliTool.values.length, 9);
  });
```

with:

```dart
  test('CliTool.values length is 10 after adding qoder-cn', () {
    expect(CliTool.values.length, 10);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/models/team_config_cli_tool_test.dart`
Expected: compile failure because `CliTool.qoderCn` does not exist.

- [ ] **Step 3: Add the enum value**

In `client/lib/models/team_config.dart`:

```dart
/// Backend CLI identity (`flashskyai`, `codex`, `claude`, `opencode`,
/// `cursor`, `gemini`, `codebuddy`, `antigravity`, `qoder`, or `qoder-cn`).
```

```dart
  antigravity('antigravity'),
  qoder('qoder'),
  qoderCn('qoder-cn');
```

- [ ] **Step 4: Add `QoderFlavor.cn` and `isCn`**

In `qoder_flavor.dart`, append inside the class:

```dart
  static const cn = QoderFlavor(
    cli: CliTool.qoderCn,
    executableName: 'qoderclicn',
    displayName: 'Qoder CLI CN',
    providerId: 'qoder-cn',
    providerLabel: 'Qoder CN',
    websiteUrl: 'https://qoder.com.cn',
    installUrl: 'https://qoder.com.cn/install',
    authNamespace: 'qoder-cn',
    allowMachineAuthFallback: false,
  );

  bool get isCn => cli == CliTool.qoderCn;
```

- [ ] **Step 5: Add the CN executable capability**

Create `client/lib/services/cli/qoder/capabilities/executable_cn.dart`:

```dart
import 'dart:io' show Platform;

import '../../../../l10n/app_localizations.dart';
import '../../installer_types.dart';
import '../../remote_cli_locator.dart';
import '../../registry/capabilities/cli_executable_capability.dart';
import '../../registry/installer/installer_context.dart';
import '../../registry/installer/npm_installer_capability.dart';

/// Qoder CLI CN (`qoderclicn`) identity and installer.
///
/// The CN distribution uses the official `https://qoder.com.cn/install`
/// script (which redirects to `static.qoder.com.cn`). It is not published on
/// npm, so the global npm installer does not apply.
final class QoderCnExecutableCapability implements CliExecutableCapability {
  const QoderCnExecutableCapability();

  static const executableName = 'qoderclicn';
  static const displayName = 'Qoder CLI CN';
  static const installScript =
      'curl -fsSL https://qoder.com.cn/install | bash';

  @override
  String label(AppLocalizations l10n) => l10n.appProvider.toolQoderCn;

  @override
  String get defaultExecutableName => executableName;

  @override
  String get preferencesPathKey => 'qoder-cn';

  @override
  Future<String?> locateRemote(SshCommandRunner run) =>
      const DefaultRemoteCliLocator(executableName).locate(run);

  @override
  CliExecutablePathRowSpec get executablePathRowSpec =>
      const CliExecutablePathRowSpec(
        titleKey: null,
        subtitleKey: null,
        fieldKey: 'qoder-cn-cli-executable-path-field',
        browseKey: 'qoder-cn-cli-executable-path-browse-button',
        resetKey: 'qoder-cn-cli-executable-path-reset-button',
        debouncerTag: 'qoder_cn_cli_executable_path',
        installKey: 'qoder-cn-cli-install-button',
        showDividerBelow: true,
      );

  @override
  bool get supportsInstaller => !Platform.isWindows;

  @override
  Future<CliInstallResult> install(CliInstallContext context) {
    if (Platform.isWindows) {
      return Future.value(
        const CliInstallResult(
          success: false,
          message:
              'Qoder CLI CN has no supported in-app installer on Windows. '
              'Install qoderclicn manually, then set its path here.',
        ),
      );
    }
    return switch (context.mode) {
      CliInstallMode.local => _installLocal(context),
      CliInstallMode.ssh => _installSsh(context),
    };
  }

  Future<CliInstallResult> _installLocal(CliInstallContext context) async {
    final host = context.host;
    host.report(CliInstallPhase.installingCli, detail: displayName);
    final install = await host.runLocal(
      CliInstallerCommand.unixShellScript(installScript),
      phase: CliInstallPhase.installingCli,
      streamOutput: true,
    );
    if (install.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage('$displayName install failed', install),
      );
    }
    if (host.isCancelled) return _cancelled();
    host.report(CliInstallPhase.locatingExecutable);
    final path = await host.locateExecutable(executableName);
    if (path == null) {
      return const CliInstallResult(
        success: false,
        message:
            'Qoder CLI CN install finished but qoderclicn could not be '
            'located. Add ~/.local/bin to PATH if needed.',
      );
    }
    return CliInstallResult(
      success: true,
      message: '$displayName installed.',
      executablePath: path,
    );
  }

  Future<CliInstallResult> _installSsh(CliInstallContext context) async {
    final profile = context.sshProfile;
    if (profile == null) {
      return const CliInstallResult(
        success: false,
        message: 'Select an SSH server before installing Qoder CLI CN remotely.',
      );
    }
    final host = context.host;
    host.report(CliInstallPhase.installingCli, detail: displayName);
    final install = await host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(installScript),
    );
    if (install.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage(
          'Remote $displayName install failed',
          install,
        ),
      );
    }
    if (host.isCancelled) return _cancelled();
    host.report(CliInstallPhase.locatingExecutable);
    final resolved = await host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(
        NpmInstallerCapability.remotePostInstallLocateScript(executableName),
      ),
    );
    final path = firstInstallerOutputLine(resolved);
    if (path == null) {
      return CliInstallResult(
        success: false,
        message:
            '$displayName install finished but qoderclicn could not be '
            'located on ${profile.hostIdentifier}.',
      );
    }
    return CliInstallResult(
      success: true,
      message: '$displayName installed on ${profile.hostIdentifier}.',
      executablePath: path,
    );
  }

  static CliInstallResult _cancelled() =>
      const CliInstallResult(success: false, message: 'Cancelled');
}
```

- [ ] **Step 6: Add CN provider presets**

Replace `client/lib/services/cli/qoder/provider_presets.dart` with:

```dart
import '../../../models/app_provider_config.dart';

abstract final class QoderProviderPresets {
  const QoderProviderPresets._();

  static const global = <AppProviderPreset>[
    AppProviderPreset(
      id: 'qoder',
      label: 'Qoder',
      template: AppProviderConfig(
        id: 'qoder',
        cli: CliTool.qoder,
        name: 'Qoder',
        websiteUrl: 'https://qoder.com',
        category: AppProviderCategory.official,
        isOfficial: true,
        apiKeyField: 'api_key',
        defaultModel: 'auto',
        icon: 'qoder',
        notes:
            'Isolated login: Sign in opens a Qoder login terminal that does '
            'not touch your global ~/.qoder account.',
      ),
    ),
  ];

  static const cn = <AppProviderPreset>[
    AppProviderPreset(
      id: 'qoder-cn',
      label: 'Qoder CN',
      template: AppProviderConfig(
        id: 'qoder-cn',
        cli: CliTool.qoderCn,
        name: 'Qoder CN',
        websiteUrl: 'https://qoder.com.cn',
        category: AppProviderCategory.official,
        isOfficial: true,
        apiKeyField: 'api_key',
        defaultModel: 'auto',
        icon: 'qoder',
        notes:
            'Isolated login: Sign in opens a Qoder CN login terminal that does '
            'not touch your global Qoder account.',
      ),
    ),
  ];

  static const all = <AppProviderPreset>[...global, ...cn];

  static AppProviderPreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
```

`provider_presets.dart` needs `CliTool`; `app_provider_config.dart` re-exports it? The existing file compiled with only that import, so keep it.

- [ ] **Step 7: Make `QoderCliTool` flavor-driven**

In `qoder_tool.dart`, add imports:

```dart
import 'capabilities/executable_cn.dart';
import 'qoder_flavor.dart';
```

Change the class doc comment:

```dart
/// Qoder CLI (`qodercli` or `qoderclicn`), ACP-only.
```

Replace only the class constructor (from `const QoderCliTool({` through its closing `});`) with the constructor below. Leave the class declaration and the existing field declarations untouched.

```dart
  QoderCliTool({
    QoderFlavor flavor = QoderFlavor.global,
    QoderTeamBehavior teamBehavior = const QoderTeamBehavior(),
    CliExecutableCapability? executable,
    CliSessionCapability session = const QoderCliSessionCapability(),
    QoderProviderCapability? provider,
    QoderTerminalBehavior terminalBehavior = const QoderTerminalBehavior(),
    MemberConfigInspectionCapability memberConfigInspection =
        const DefaultMemberConfigInspection(),
    QoderPluginCapability plugin = const QoderPluginCapability(),
    QoderChatInteraction chatInteraction = const QoderChatInteraction(),
    QoderChatInteraction runtimeEvents = const QoderChatInteraction(),
    SkillCapability skill = const DefaultSkillCapability(),
    QoderNativeCommands nativeCommands = const QoderNativeCommands(),
    QoderAiHistoryCapability? aiHistory,
    QoderSessionUsageCapability? sessionUsage,
    UserExtraArgsProvider userExtraArgs = const UserExtraArgsProvider(),
    QoderPromptCapability? prompt,
    QoderMcpCapability mcp = const QoderMcpCapability(),
    QoderHookWriter? hookWriter,
    QoderWorkspaceBaseInfo workspaceBaseInfo = const QoderWorkspaceBaseInfo(),
    CliLaunchSecurityCapability launchSecurity =
        const AcpAskFullAccessCliLaunchSecurityCapability(),
    QoderHeadlessCapability? headless,
    QoderAcpCapability? acp,
    AcpSettingsCapability acpSettings = const DefaultAcpSettingsCapability(
      usesSeparateAdapter: false,
    ),
    CliTransportCapability transport = const CliTransportCapability(
      supported: {CliTransport.acp},
    ),
  }) : _flavor = flavor,
       teamBehavior = teamBehavior,
       executable = executable ?? qoderExecutableForFlavor(flavor),
       session = session,
       provider = provider ?? QoderProviderCapability(flavor: flavor),
       terminalBehavior = terminalBehavior,
       memberConfigInspection = memberConfigInspection,
       plugin = plugin,
       chatInteraction = chatInteraction,
       runtimeEvents = runtimeEvents,
       skill = skill,
       nativeCommands = nativeCommands,
       aiHistory = aiHistory ?? QoderAiHistoryCapability(flavor: flavor),
       sessionUsage =
           sessionUsage ?? QoderSessionUsageCapability(flavor: flavor),
       userExtraArgs = userExtraArgs,
       prompt = prompt ?? QoderPromptCapability(flavor: flavor),
       mcp = mcp,
       hookWriter = hookWriter ?? QoderHookWriter(flavor: flavor),
       workspaceBaseInfo = workspaceBaseInfo,
       launchSecurity = launchSecurity,
       headless = headless ?? QoderHeadlessCapability(flavor: flavor),
       acp =
           acp ??
           QoderAcpCapability(transcriptFallbackPrefix: flavor.cli.value),
       acpSettings = acpSettings,
       transport = transport;
```

Add the flavor field next to the existing final fields:

```dart
  final QoderFlavor _flavor;
```

Change the identity getter:

```dart
  @override
  CliTool get id => _flavor.cli;
```

Append after the class:

```dart
CliExecutableCapability qoderExecutableForFlavor(QoderFlavor flavor) =>
    flavor.isCn
        ? const QoderCnExecutableCapability()
        : const QoderExecutableCapability();
```

- [ ] **Step 8: Add the CN provider preset selection to `QoderProviderCapability`**

In `provider.dart`, change:

```dart
  @override
  List<AppProviderPreset> get presets => QoderProviderPresets.all;
```

to:

```dart
  @override
  List<AppProviderPreset> get presets =>
      flavor.isCn ? QoderProviderPresets.cn : QoderProviderPresets.global;
```

- [ ] **Step 9: Register both flavors**

In `built_in_cli_tools.dart`, add:

```dart
import '../qoder/qoder_flavor.dart';
```

Replace the existing `registry.register(QoderCliTool(...))` block with:

```dart
  registry.register(
    QoderCliTool(
      flavor: QoderFlavor.global,
      provider: QoderProviderCapability(
        flavor: QoderFlavor.global,
        storage: storage,
        modelsService: storage == null
            ? null
            : QoderModelsService(
                storage: storage,
                namespace: QoderFlavor.global.authNamespace,
                executable: QoderFlavor.global.executableName,
                useMachineAuthFallback:
                    QoderFlavor.global.allowMachineAuthFallback,
              ),
      ),
      headless: QoderHeadlessCapability(
        flavor: QoderFlavor.global,
        storage: storage,
      ),
    ),
  );
  registry.register(
    QoderCliTool(
      flavor: QoderFlavor.cn,
      provider: QoderProviderCapability(
        flavor: QoderFlavor.cn,
        storage: storage,
        modelsService: storage == null
            ? null
            : QoderModelsService(
                storage: storage,
                namespace: QoderFlavor.cn.authNamespace,
                executable: QoderFlavor.cn.executableName,
                useMachineAuthFallback: QoderFlavor.cn.allowMachineAuthFallback,
              ),
      ),
      headless: QoderHeadlessCapability(
        flavor: QoderFlavor.cn,
        storage: storage,
      ),
    ),
  );
```

- [ ] **Step 10: Add the l10n key and regenerate**

In `client/lib/i18n/appProvider_en.i18n.json`, after `"toolQoder": "Qoder",` add:

```json
  "toolQoderCn": "Qoder CN",
```

In `client/lib/i18n/appProvider_zh.i18n.json`, after `"toolQoder": "Qoder",` add:

```json
  "toolQoderCn": "Qoder 国内版",
```

Run: `cd client && dart run slang`
Expected: regenerated `lib/l10n/translations_en.g.dart` and `lib/l10n/translations_zh.g.dart` contain `toolQoderCn`.

- [ ] **Step 11: Add CN branches to the usage and icon switches**

In `usage_format.dart`:

```dart
  CliTool.qoder => 'Qoder',
  CliTool.qoderCn => 'Qoder CN',
```

```dart
  CliTool.qoder => const Color(0xFF6B4EFF),
  CliTool.qoderCn => const Color(0xFF6B4EFF),
```

In `cli_brand_icon.dart`:

```dart
  CliTool.qoder => 'qoder',
  CliTool.qoderCn => 'qoder',
```

```dart
  CliTool.qoder => Icons.terminal,
  CliTool.qoderCn => Icons.terminal,
```

- [ ] **Step 12: Add CN branches to the label switches**

In `l10n_extensions.dart` `appProviderToolLabel`:

```dart
      CliTool.qoder => appProvider.toolQoder,
      CliTool.qoderCn => appProvider.toolQoderCn,
```

In `provider_credential_action_bar.dart`, add this line after every `CliTool.qoder` case in `_sectionTitle`, `_actionLabel` (login/importGlobal/importFile/revoke), and `_revokeConfirmMessage`:

```dart
    CliTool.qoderCn => l10n.appProvider.toolQoderCn,
```

The login case is the exception:

```dart
    CliTool.qoderCn => l10n.qoder.credentialsLogin,
```

In `provider_credential_messages.dart`:

```dart
    CliTool.qoder => l10n.qoder.credentialsSignedIn,
    CliTool.qoderCn => l10n.qoder.credentialsSignedIn,
```

```dart
    CliTool.qoder => l10n.qoder.credentialsActionFailed,
    CliTool.qoderCn => l10n.qoder.credentialsActionFailed,
```

- [ ] **Step 13: Add CN to the hook matrix**

In `hook_event.dart`, insert the following entries into the event maps shown. Each entry goes immediately after that event's existing `CliTool.qoder` entry.

`HookEvent.sessionStart`:

```dart
      CliTool.qoderCn: HookCliSupport(
        supported: true,
        nativeEvent: 'SessionStart',
      ),
```

`HookEvent.sessionEnd`:

```dart
      CliTool.qoderCn: HookCliSupport(
        supported: true,
        nativeEvent: 'SessionEnd',
      ),
```

`HookEvent.userPromptSubmit`:

```dart
      CliTool.qoderCn: HookCliSupport(
        supported: true,
        nativeEvent: 'UserPromptSubmit',
      ),
```

`HookEvent.preToolUse`:

```dart
      CliTool.qoderCn: HookCliSupport(
        supported: true,
        nativeEvent: 'PreToolUse',
      ),
```

`HookEvent.postToolUse`:

```dart
      CliTool.qoderCn: HookCliSupport(
        supported: true,
        nativeEvent: 'PostToolUse',
      ),
```

`HookEvent.postToolUseFailure`:

```dart
      CliTool.qoderCn: HookCliSupport(
        supported: true,
        nativeEvent: 'PostToolUseFailure',
      ),
```

`HookEvent.permissionRequest`:

```dart
      CliTool.qoderCn: HookCliSupport(
        supported: true,
        nativeEvent: 'PermissionRequest',
      ),
```

`HookEvent.stop`:

```dart
      CliTool.qoderCn: HookCliSupport(
        supported: true,
        nativeEvent: 'Stop',
      ),
```

`HookEvent.stopFailure`:

```dart
      CliTool.qoderCn: HookCliSupport(
        supported: true,
        nativeEvent: 'StopFailure',
      ),
```

`HookEvent.subagentStop`:

```dart
      CliTool.qoderCn: HookCliSupport(
        supported: true,
        nativeEvent: 'SubagentStop',
      ),
```

`HookEvent.preCompact`:

```dart
      CliTool.qoderCn: HookCliSupport(
        supported: true,
        nativeEvent: 'PreCompact',
      ),
```

`HookEvent.notification`:

```dart
      CliTool.qoderCn: HookCliSupport(
        supported: true,
        nativeEvent: 'Notification',
      ),
```

Do not add CN to `subagentStart` or `shellCommandRequest`.

- [ ] **Step 14: Add CN to hook import mappings**

In `hook_event_name_mapper.dart`, add after the `CliTool.qoder` map:

```dart
    CliTool.qoderCn: {
      'SessionStart': HookEvent.sessionStart,
      'SessionEnd': HookEvent.sessionEnd,
      'UserPromptSubmit': HookEvent.userPromptSubmit,
      'PreToolUse': HookEvent.preToolUse,
      'PostToolUse': HookEvent.postToolUse,
      'PostToolUseFailure': HookEvent.postToolUseFailure,
      'PermissionRequest': HookEvent.permissionRequest,
      'Stop': HookEvent.stop,
      'StopFailure': HookEvent.stopFailure,
      'SubagentStop': HookEvent.subagentStop,
      'PreCompact': HookEvent.preCompact,
      'Notification': HookEvent.notification,
    },
```

In `hook_import_parser.dart`, add:

```dart
    CliTool.qoderCn: const ClaudeFamilyHooksJsonDialect(),
```

In `hook_import_dialog.dart`, add to the CLI item list:

```dart
              CliTool.qoder,
              CliTool.qoderCn,
```

- [ ] **Step 15: Add CN to the workspace CLI cache group**

In `workspace_cli_cache.dart`:

```dart
    CliTool.qoder ||
    CliTool.qoderCn => const [],
```

- [ ] **Step 16: Update compile-time test switches**

In `client/test/models/simple_launch_identity_test.dart`, add:

```dart
      CliTool.qoderCn => 'qoder-cn',
```

In `client/test/integration/support/cli_test_profile.dart`, add the switch case:

```dart
      CliTool.qoder => _qoder,
      CliTool.qoderCn => _qoderCn,
```

Add the profile after `_qoder`:

```dart
  static final CliTestProfile _qoderCn = CliTestProfile(
    tool: CliTool.qoderCn,
    wire: CliTestWire.openaiChat,
    binaryName: 'qoderclicn',
    resolveBinary: () => whichOnPath('qoderclicn'),
    toolName: mapShortMcpToolRef,
    assistantVisibleMarkers: const [markA1, markA2, markA3],
    bootToPrompt: bootToPromptStub,
    dismissBootGates: dismissBootGatesStub,
    gatewayRedirectNotes:
        'N/A: qoder-cn targets ACP (`qoderclicn --acp`), not the '
        'mock-gateway matrix.',
  );
```

In `client/test/integration/qoder_acp_local_smoke_test.dart`, change:

```dart
    final registry = CliToolRegistry()..register(const QoderCliTool());
```

to:

```dart
    final registry = CliToolRegistry()..register(QoderCliTool());
```

- [ ] **Step 17: Run analyze and the focused tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors. Fix any remaining exhaustive `switch` the analyzer reports by adding a `CliTool.qoderCn` branch that mirrors `CliTool.qoder`.

Run: `cd client && dart run tool/run_tests.dart test/models/team_config_cli_tool_test.dart test/models/simple_launch_identity_test.dart test/services/cli/qoder/ test/services/cli/registry/`
Expected: PASS.

- [ ] **Step 18: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/models/team_config.dart \
  client/lib/services/cli/qoder/qoder_flavor.dart \
  client/lib/services/cli/qoder/capabilities/executable_cn.dart \
  client/lib/services/cli/qoder/provider_presets.dart \
  client/lib/services/cli/qoder/qoder_tool.dart \
  client/lib/services/cli/qoder/capabilities/provider.dart \
  client/lib/services/cli/registry/built_in_cli_tools.dart \
  client/lib/i18n/appProvider_en.i18n.json \
  client/lib/i18n/appProvider_zh.i18n.json \
  client/lib/l10n/translations_en.g.dart \
  client/lib/l10n/translations_zh.g.dart \
  client/lib/pages/usage/usage_format.dart \
  client/lib/widgets/cli/cli_brand_icon.dart \
  client/lib/l10n/l10n_extensions.dart \
  client/lib/widgets/app_provider/provider_credential_action_bar.dart \
  client/lib/widgets/app_provider/provider_credential_messages.dart \
  client/lib/models/hook_event.dart \
  client/lib/services/hook/import/hook_event_name_mapper.dart \
  client/lib/services/hook/import/hook_import_parser.dart \
  client/lib/pages/hooks/hook_import_dialog.dart \
  client/lib/services/storage/workspace_cli_cache.dart \
  client/test/models/team_config_cli_tool_test.dart \
  client/test/models/simple_launch_identity_test.dart \
  client/test/integration/support/cli_test_profile.dart \
  client/test/integration/qoder_acp_local_smoke_test.dart
git commit -m "feat(qoder-cn): register the Qoder CN CLI identity"
```

---

### Task 4: Add CN-specific behavior tests

**Files:**
- Create: `client/test/services/cli/qoder/qoder_cn_registry_test.dart`
- Create: `client/test/services/cli/qoder/qoder_cn_provider_test.dart`
- Create: `client/test/services/cli/qoder/qoder_cn_auth_store_test.dart`
- Create: `client/test/services/cli/qoder/qoder_cn_executable_test.dart`
- Create: `client/test/services/cli/qoder/qoder_cn_runtime_test.dart`
- Test: `client/test/services/cli/qoder/qoder_models_service_test.dart`
- Test: `client/test/services/cli/qoder/qoder_headless_test.dart`
- Test: `client/test/services/cli/qoder/capabilities/usage/qoder_session_usage_test.dart`
- Test: `client/test/pages/usage/usage_format_test.dart`

**Interfaces:**
- Consumes: `CliTool.qoderCn`, `QoderFlavor.cn`, `QoderCnExecutableCapability`, CN presets, CN registry entries.
- Produces: no production interfaces; this task pins the CN behavior.

- [ ] **Step 1: Write the CN registry test**

Create `client/test/services/cli/qoder/qoder_cn_registry_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_transport_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('qoder-cn registers every required capability', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final def = registry.tryGet(CliTool.qoderCn);
    expect(def, isNotNull);
    expect(def!.isLaunchSupported, isTrue);

    final exe = registry.capability<CliExecutableCapability>(CliTool.qoderCn)!;
    expect(exe.defaultExecutableName, 'qoderclicn');
    expect(exe.preferencesPathKey, 'qoder-cn');
    expect(exe.supportsInstaller, !Platform.isWindows);

    expect(registry.capability<AcpCapability>(CliTool.qoderCn), isNotNull);
    expect(
      registry.capability<ProviderCapability>(CliTool.qoderCn),
      isNotNull,
    );
    expect(
      registry.capability<CliTransportCapability>(CliTool.qoderCn)!.supported,
      {CliTransport.acp},
    );
    expect(registry.launchesAcpOnly(CliTool.qoderCn), isTrue);
    expect(registry.supportsNativeTeam(CliTool.qoderCn), isFalse);
    expect(registry.supportsMemberAgentPreset(CliTool.qoderCn), isFalse);
  });
}
```

- [ ] **Step 2: Write the CN provider and session-home test**

Create `client/test/services/cli/qoder/qoder_cn_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/cli/qoder/capabilities/provider.dart';
import 'package:teampilot/services/cli/qoder/provider_presets.dart';
import 'package:teampilot/services/cli/qoder/qoder_flavor.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('CN capability exposes only the qoder-cn preset', () {
    const cap = QoderProviderCapability(flavor: QoderFlavor.cn);

    expect(cap.catalogCli, CliTool.qoderCn);
    expect(cap.defaultOfficialProviderId, 'qoder-cn');
    expect(cap.loginExecutableName, 'qoderclicn');
    expect(cap.presets, hasLength(1));

    final preset = cap.presets.single;
    expect(preset.id, 'qoder-cn');
    expect(preset.template.cli, CliTool.qoderCn);
    expect(preset.template.websiteUrl, 'https://qoder.com.cn');
    expect(QoderProviderPresets.byId('qoder-cn')!.id, 'qoder-cn');
  });

  test('CN materializes an isolated qoder-cn session home', () async {
    final fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    final service = ConfigProfileService(
      basePath: '/tp',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      storage: storage,
    );
    const capability = QoderProviderCapability(flavor: QoderFlavor.cn);

    await fs.ensureDir('/tp/providers/qoder-cn/work');
    await fs.atomicWrite('/tp/providers/qoder-cn/work/user', 'CNUSER');
    await fs.atomicWrite('/tp/providers/qoder-cn/work/machine_id', 'CNMID');
    // The global provider store and the machine login must be ignored.
    await fs.ensureDir('/tp/providers/qoder/work');
    await fs.atomicWrite('/tp/providers/qoder/work/user', 'GLOBAL');
    await fs.atomicWrite('/tp/providers/qoder/work/machine_id', 'GLOBALMID');
    await fs.ensureDir('/home/test/.qoder/.auth');
    await fs.atomicWrite('/home/test/.qoder/.auth/user', 'MACHINE');
    await fs.atomicWrite('/home/test/.qoder/.auth/machine_id', 'MACHID');

    const member = TeamMemberConfig(id: 'm1', name: 'Member', provider: 'work');
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
    );

    final contribution = await capability.materializeSessionHome(
      sessionHomeContextFromLaunch(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: 'team-a',
          sessionId: scope.sessionId,
          scope: scope,
          member: member,
          members: const [member],
          workingDirectory: '/workspace/workspace',
          paths: service,
          catalog: service,
        ),
        CliTool.qoderCn,
      ),
    );

    final configDir =
        contribution.environment[QoderProviderCapability.configDirEnvKey]!;
    expect(configDir, contains('/runtime/qoder-cn'));
    expect(
      await fs.readString(p.posix.join(configDir, '.auth', 'user')),
      'CNUSER',
    );
    expect(
      await fs.readString(p.posix.join(configDir, '.auth', 'machine_id')),
      'CNMID',
    );
  });
}
```

- [ ] **Step 3: Write the CN auth-store test**

Create `client/test/services/cli/qoder/qoder_cn_auth_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/qoder/provider/qoder_auth_store.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late QoderAuthStore store;

  setUp(() {
    fs = InMemoryFilesystem();
    store = QoderAuthStore(
      fs: fs,
      basePath: '/app',
      pathContext: p.posix,
      machineHome: '/home/me',
      namespace: 'qoder-cn',
      useMachineFallback: false,
    );
  });

  test('login and provider roots use the qoder-cn namespace', () {
    expect(store.loginRoot('work'), '/app/cli-login/qoder-cn/work');
    expect(store.providerAuthDir('work'), '/app/providers/qoder-cn/work');
  });

  test('never reads the machine ~/.qoder login', () async {
    await fs.ensureDir('/home/me/.qoder/.auth');
    await fs.atomicWrite('/home/me/.qoder/.auth/user', 'MACHINE');
    await fs.atomicWrite('/home/me/.qoder/.auth/machine_id', 'MID');

    expect(await store.authSourceDir('work'), isNull);
    expect(
      await store.seedSessionAuth(
        providerId: 'work',
        sessionConfigDir: '/sessions/s1/qoder-cn',
      ),
      isFalse,
    );
    expect((await fs.stat('/sessions/s1/qoder-cn/.auth')).exists, isFalse);
  });

  test('seeds from the CN provider store only', () async {
    await store.fs.ensureDir(store.providerAuthDir('work'));
    await store.fs.atomicWrite('${store.providerAuthDir('work')}/user', 'CN');
    await store.fs.atomicWrite(
      '${store.providerAuthDir('work')}/machine_id',
      'CNMID',
    );

    expect(
      await store.seedSessionAuth(
        providerId: 'work',
        sessionConfigDir: '/sessions/s1/qoder-cn',
      ),
      isTrue,
    );
    expect(await fs.readString('/sessions/s1/qoder-cn/.auth/user'), 'CN');
  });
}
```

- [ ] **Step 4: Write the CN executable test**

Create `client/test/services/cli/qoder/qoder_cn_executable_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/qoder/capabilities/executable_cn.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';

void main() {
  test('CN executable identity and installer availability', () {
    const cap = QoderCnExecutableCapability();

    expect(cap.defaultExecutableName, 'qoderclicn');
    expect(cap.preferencesPathKey, 'qoder-cn');
    expect(cap.supportsInstaller, !Platform.isWindows);
    expect(
      QoderCnExecutableCapability.installScript,
      'curl -fsSL https://qoder.com.cn/install | bash',
    );
  });

  test('remote locate probes qoderclicn', () async {
    var command = '';
    final path = await const QoderCnExecutableCapability().locateRemote((
      value,
    ) async {
      command = value;
      return const SshCommandResult(
        exitCode: 0,
        stdout: '/usr/local/bin/qoderclicn\n',
      );
    });

    expect(command, contains('qoderclicn'));
    expect(path, '/usr/local/bin/qoderclicn');
  });
}
```

- [ ] **Step 5: Write the CN runtime identity test**

Create `client/test/services/cli/qoder/qoder_cn_runtime_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/qoder/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/qoder/capabilities/hook_writer.dart';
import 'package:teampilot/services/cli/qoder/capabilities/prompt.dart';
import 'package:teampilot/services/cli/qoder/qoder_flavor.dart';

void main() {
  test('CN prompt uses the qoder-cn session tool id', () {
    const cap = QoderPromptCapability(flavor: QoderFlavor.cn);
    expect(cap.toolId, 'qoder-cn');
    expect(cap.providerId, 'qoder-cn');
  });

  test('CN history reports the CN identity', () {
    const cap = QoderAiHistoryCapability(flavor: QoderFlavor.cn);
    expect(cap.adapter.id, 'qoder-cn');
    expect(cap.tailFallbackPrefix, 'qoder-cn');
  });

  test('CN hook writer uses Claude-family event names', () {
    const cap = QoderHookWriter(flavor: QoderFlavor.cn);
    expect(cap.nativeEvent(HookEvent.sessionStart), 'SessionStart');
    expect(cap.nativeEvent(HookEvent.preToolUse), 'PreToolUse');
    expect(cap.nativeEvent(HookEvent.subagentStart), isNull);
  });
}
```

- [ ] **Step 6: Extend the models, headless, usage and UI tests**

The CN models-service tests were added in Task 1 Step 5; this task's focused run covers them. Do not duplicate them.

In `qoder_headless_test.dart`, add the flavor import and this test inside `group('capability shape')`:

```dart
import 'package:teampilot/services/cli/qoder/qoder_flavor.dart';
```

```dart
    test('CN headless runs qoderclicn', () {
      const cap = QoderHeadlessCapability(flavor: QoderFlavor.cn);
      expect(cap.executable, 'qoderclicn');
    });
```

In `capabilities/usage/qoder_session_usage_test.dart`, add the flavor import:

```dart
import 'package:teampilot/services/cli/qoder/qoder_flavor.dart';
```

Append this test:

```dart
  test('tags CN scans with the CN cli and request prefix', () async {
    final ctx = _ctx();
    const capability = QoderSessionUsageCapability(flavor: QoderFlavor.cn);
    final path = p.join(_root, 'projects', 'proj', 'cn.jsonl');
    await ctx.fs.writeString(path, '${_assistantLine()}\n');

    final source = (await capability.discoverUsageSources(ctx)).single;
    expect(source.id, startsWith('qoder-cn-jsonl:'));

    final result = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );
    expect(result.events.single.cli, CliTool.qoderCn);
    expect(result.events.single.requestId, 'qoder-cn:m1');
  });
```

In `client/test/pages/usage/usage_format_test.dart`, add the import:

```dart
import 'package:teampilot/models/team_config.dart';
```

Add this expectation inside the builder:

```dart
            expect(
              usageRangeLabel(context, UsageRange.last24Hours),
              'Last 24 hours',
            );
            expect(
              usageRangeLabel(context, UsageRange.fourteenDays),
              'Last 14 days',
            );
            expect(usageCliLabel(context, CliTool.qoderCn), 'Qoder CN');
```

- [ ] **Step 7: Run the CN-focused tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/qoder/qoder_cn_registry_test.dart test/services/cli/qoder/qoder_cn_provider_test.dart test/services/cli/qoder/qoder_cn_auth_store_test.dart test/services/cli/qoder/qoder_cn_executable_test.dart test/services/cli/qoder/qoder_cn_runtime_test.dart test/services/cli/qoder/qoder_models_service_test.dart test/services/cli/qoder/qoder_headless_test.dart test/services/cli/qoder/capabilities/usage/qoder_session_usage_test.dart test/pages/usage/usage_format_test.dart`
Expected: PASS.

- [ ] **Step 8: Analyze and commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors.

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/test/services/cli/qoder/qoder_cn_registry_test.dart \
  client/test/services/cli/qoder/qoder_cn_provider_test.dart \
  client/test/services/cli/qoder/qoder_cn_auth_store_test.dart \
  client/test/services/cli/qoder/qoder_cn_executable_test.dart \
  client/test/services/cli/qoder/qoder_cn_runtime_test.dart \
  client/test/services/cli/qoder/qoder_models_service_test.dart \
  client/test/services/cli/qoder/qoder_headless_test.dart \
  client/test/services/cli/qoder/capabilities/usage/qoder_session_usage_test.dart \
  client/test/pages/usage/usage_format_test.dart
git commit -m "test(qoder-cn): cover CN identity, auth isolation and usage"
```

---

### Task 5: Full verification and the real ACP acceptance gate

**Files:**
- Create: `client/test/integration/qoder_cn_acp_local_smoke_test.dart`
- Modify: none expected; fix anything the verification surfaces inline.

**Interfaces:**
- Consumes: registered `CliTool.qoderCn`.
- Produces: a gated acceptance test that proves (or disproves) `qoderclicn --acp` + `QODER_CONFIG_DIR`.

- [ ] **Step 1: Add the gated CN ACP smoke test**

Create `client/test/integration/qoder_cn_acp_local_smoke_test.dart`:

```dart
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/session/acp/acp_launch_wiring.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/acp/acp_frame_logger.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/cli/qoder/qoder_flavor.dart';
import 'package:teampilot/services/cli/qoder/qoder_tool.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

/// End-to-end local smoke for the Qoder CN CLI over ACP.
///
/// Spawns the real `qoderclicn --acp` through the production seams and drives
/// one prompt turn. `QODER_CONFIG_DIR` points at a temp dir seeded from
/// `QODER_CN_AUTH_DIR` (must contain `user` and `machine_id`). The test skips
/// when the binary or the auth source is missing.
///
/// ```bash
/// QODER_CN_AUTH_DIR=/path/to/.auth \
///   dart run tool/run_tests.dart --tags integration \
///   test/integration/qoder_cn_acp_local_smoke_test.dart
/// ```
void main() {
  test('qoderclicn --acp completes initialize / session/new / prompt', () async {
    final executable = await _which('qoderclicn');
    final auth = Platform.environment['QODER_CN_AUTH_DIR'] ?? '';
    final hasAuthPair =
        auth.isNotEmpty &&
        File(p.join(auth, 'user')).existsSync() &&
        File(p.join(auth, 'machine_id')).existsSync();
    if (executable == null || !hasAuthPair) {
      // ignore: avoid_print
      print(
        '[qoder-cn-acp] skipped: qoderclicn or QODER_CN_AUTH_DIR '
        '({user,machine_id}) is missing',
      );
      return;
    }

    final temp = Directory.systemTemp.createTempSync('qoder-cn-acp-');
    Directory(p.join(temp.path, '.auth')).createSync(recursive: true);
    for (final name in const ['user', 'machine_id']) {
      File(p.join(auth, name)).copySync(p.join(temp.path, '.auth', name));
    }

    final registry = CliToolRegistry()
      ..register(QoderCliTool(flavor: QoderFlavor.cn));
    final logger = AcpFrameLogger(mirrorToLog: false);
    final runtime = AcpSessionRuntime(
      spawner: productionAcpSpawner(
        registry: registry,
        tool: CliTool.qoderCn,
        workingDirectory: temp.path,
        logger: logger,
        handshakeTimeout: const Duration(seconds: 60),
      ),
      logger: logger,
      launchPlanFor: acpLaunchPlanResolver(registry),
    );

    try {
      await runtime.start(
        tool: CliTool.qoderCn,
        executable: executable,
        sessionToolDir: temp.path,
        workingDirectory: temp.path,
        baseEnv: {'PATH': Platform.environment['PATH'] ?? ''},
      );
      expect(runtime.isStarted, isTrue);

      final reply = StringBuffer();
      final updates = runtime.updates.listen((update) {
        if (update is AcpMessageChunk && update.role == AcpRole.assistant) {
          reply.write(update.content);
        }
      });
      await runtime.prompt('Reply with exactly: pong');
      await updates.cancel();
      expect(reply.toString().toLowerCase(), contains('pong'));
    } finally {
      await runtime.close();
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort temp cleanup.
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<String?> _which(String name) async {
  try {
    final result = await Process.run('which', [name]);
    if (result.exitCode != 0) return null;
    final path = (result.stdout as String? ?? '').trim();
    return path.isEmpty ? null : path;
  } on ProcessException {
    return null;
  }
}
```

- [ ] **Step 2: Run the CN integration acceptance test**

Run:

```bash
cd client && QODER_CN_AUTH_DIR=/path/to/qoder-cn-auth \
  dart run tool/run_tests.dart --tags integration \
  test/integration/qoder_cn_acp_local_smoke_test.dart
```

Expected: PASS with a real `pong` reply.

If it skips because `qoderclicn` or the auth source is missing, record that in the final report; do not claim the CN ACP handshake is verified.

If it fails with no `initialize` response, STOP. Do not add a PTY fallback. Report that the CN build does not support `--acp`/`QODER_CONFIG_DIR` and mark `CliTool.qoderCn` unsupported.

- [ ] **Step 3: Run the full suite**

Run: `cd client && dart run tool/run_tests.dart`
Expected: PASS.

- [ ] **Step 4: Final analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors.

- [ ] **Step 5: Commit the acceptance test**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/test/integration/qoder_cn_acp_local_smoke_test.dart
git commit -m "test(qoder-cn): add gated real ACP acceptance smoke"
```

---

## Self-Review

**Spec coverage**

- New agent identity + coexistence: Task 3 (`CliTool.qoderCn`, two registry entries).
- Global/CN descriptor: Tasks 1 and 3 (`QoderFlavor`).
- CN executable, install script, remote locate: Task 3.
- CN provider preset and website: Task 3.
- Auth namespace and no machine fallback: Tasks 1, 3, 4.
- Models probe namespace/executable: Tasks 1, 3, 4.
- Session config dir/settings tool tagged `qoder-cn`: Task 1.
- Runtime capabilities (ACP transcript prefix, headless executable, prompt toolId, usage cli/requestId, history id, hook writer): Task 2.
- UI/l10n/hook/usage mappings: Task 3.
- Test compile updates: Task 3.
- CN behavior tests: Task 4.
- Real `--acp` acceptance gate: Task 5.

**Placeholder scan**

No `TBD`, `TODO`, "similar to Task N", or unimplemented steps. Every code step contains concrete code or an exact edit.

**Type consistency**

- `QoderFlavor` fields are used verbatim across tasks: `cli`, `executableName`, `providerId`, `authNamespace`, `allowMachineAuthFallback`, `isCn`.
- `QoderAuthStore` parameters are `namespace` and `useMachineFallback`.
- `QoderModelsService` parameters are `namespace` and `useMachineAuthFallback` (intentionally different from the store's flag name, matching the two consumers).
- `QoderCliTool` takes `QoderFlavor flavor`, stores it privately, and exposes `id => _flavor.cli`.
- `QoderProviderPresets` exposes `global`, `cn`, `all`, `byId`.
- `QoderCnExecutableCapability` is referenced by `qoderExecutableForFlavor` and the CN tests.
