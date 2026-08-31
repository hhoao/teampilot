# Agentic Team Generate-and-Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a visible, recoverable Team Builder session that uses workflow-scoped MCP tools to generate, validate, persist, launch, and hand off to an AI-created native or mixed team.

**Architecture:** Landing snapshots the original task and global generation settings into a durable workspace job, then creates a purpose-tagged Simple session using the normal launch pipeline. A managed Team Builder skill uses the existing Catalog MCP in a generation-only staging scope and a dedicated Team Composer MCP for context, probes, validation, and idempotent finalization; repository-level services commit the generated team and machine placement before the existing session pipeline opens the destination and delivers the immutable original prompt. The job is the write-ahead log for restart recovery, while workflow authorization requires the persisted session purpose plus an ephemeral token written only into that builder session's MCP transport config.

**Tech Stack:** Dart 3, Flutter, `flutter_bloc`, TeamPilot `Filesystem`/`AppStorage`/`WorkspaceLayout`, JSON-RPC MCP over `TeammateBusMcpGateway`, CLI capability registry, `synchronized` through `LockPool`, existing session/prompt-delivery pipelines, `package:test` and Flutter widget tests.

## Global Constraints

- Keep the existing `HomeNewTeamDialog` headless `TeamConfigGenerator` flow unchanged; do not modify `team_config_prompt*`, `team_config_draft.dart`, or `team_draft_roster_mapper.dart`.
- Global model-pool order is strength order; the first effective preset is the fixed team default, and every pool entry may be reused by multiple members.
- `generateLaunch => !isPersonal`; switching to Simple or selecting a concrete team clears generation mode without discarding the last concrete `teamId`.
- Builder generation must run in a visible, normal Simple session; do not add a headless request or progress overlay.
- Derive target candidates only from live `Workspace.folders`; probes are read-only, bounded, output-limited, and never install or upgrade a CLI.
- Mutating MCP operations require a matching `teamGeneration` session purpose, workspace ID, workflow ID, and an unguessable token stored only in builder runtime MCP config.
- New catalog acquisitions remain under the workflow `staging/` directory and are not globally installed or workspace-bound before commit.
- The model never writes TeamPilot profile, workspace, session, placement, or catalog manifests directly.
- Generated plans contain 2–5 distinct member types, exactly one singleton `team-lead`, only frozen pool preset IDs, and only current folder-backed targets.
- Native generation uses one native-team-capable CLI; mixed generation synchronizes only the selected preset's `cli` into member overrides and never duplicates provider/model/effort.
- Commit and handoff are receipt-driven and idempotent; after profile persistence, recovery completes forward rather than deleting the visible team.
- Deliver the exact composed Landing text once to the generated lead through the existing durable direct-to-PTY path.
- Delete the builder only after destination delivery, finalize-response flush, and builder idle/quiet; failures retain recoverable sessions.
- Completed jobs retain at most 100 tombstones per workspace and tombstones older than 30 days are pruned; tombstones contain no prompt, plan, probe, token, or catalog payload.
- Use `Tp*` controls for new reusable UI, `flutter_bloc` for state, localized user errors, and `AppLogger` for diagnostics.
- Tests touching `AppStorage` use `setUpTestAppStorage()` and `tearDownTestAppStorage()`; subprocess, SSH, catalog, PTY readiness, and clocks use injected fakes.
- New integration tests use `@Tags(['integration'])`.
- Before completion run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.

---

## File map and locked responsibilities

### New domain and service files

| File | Single responsibility |
|---|---|
| `client/lib/models/team_generation_settings.dart` | Stored pool rows, effective preset snapshots, deterministic settings revision, and runtime filtering. |
| `client/lib/services/team_generation/team_generation_settings_store.dart` | Atomic global settings persistence only. |
| `client/lib/services/team_generation/models/generated_team_plan.dart` | Versioned MCP plan JSON and normalized member/resource value objects. |
| `client/lib/services/team_generation/models/team_generation_launch.dart` | Frozen Landing/workspace launch input and validated destination working set. |
| `client/lib/services/team_generation/models/team_target_probe.dart` | Typed target/CLI/fact probe records and JSON. |
| `client/lib/services/team_generation/models/team_generation_job.dart` | Durable workflow state, errors, staged resources, and idempotency receipts. |
| `client/lib/services/team_generation/team_generation_job_store.dart` | Per-workflow atomic mutation, scans, cancellation cleanup, tombstone compaction/pruning. |
| `client/lib/services/team_generation/team_generation_workflow_executor.dart` | Serialize workflow mutations and cancellation across MCP/coordinator callers. |
| `client/lib/services/team_generation/team_generation_authorizer.dart` | Ephemeral token issuance/rotation and session/job authorization. |
| `client/lib/services/team_generation/team_generation_compatibility.dart` | Capability-composed generator and team-preset compatibility checks. |
| `client/lib/services/team_generation/team_generation_context_service.dart` | Redacted immutable context returned to the builder. |
| `client/lib/services/team_generation/team_target_probe_service.dart` | Read-only concurrent probes of folder-backed runtime targets. |
| `client/lib/services/team_generation/generated_team_plan_validator.dart` | Pure parse/normalize/validation and preview construction. |
| `client/lib/services/team_generation/catalog/catalog_generation_stager.dart` | Workflow-only catalog references, staged payloads, promotion, and compensation. |
| `client/lib/services/team_generation/generated_team_commit_service.dart` | Receipt-driven experts/resources/profile/placement/provisioning transaction. |
| `client/lib/services/provider/team_profile_resource_provisioner.dart` | Provision one explicit team profile tree and resolved resources without selected-cubit state. |
| `client/lib/cubits/team/generated_team_state_publisher.dart` | Publish already-persisted generated team/workspace snapshots to Flutter cubits. |
| `client/lib/services/team_generation/team_generation_handoff_service.dart` | Idempotent destination session selection, open, readiness, and exact prompt delivery. |
| `client/lib/services/team_generation/team_generation_session_port.dart` | Flutter-free session lifecycle/activity/delivery boundary used by workflow services. |
| `client/lib/cubits/team/cubit_team_generation_session_port.dart` | Adapt `ChatCubit` and repositories to the workflow session port. |
| `client/lib/services/team_generation/team_generation_builder_idle_waiter.dart` | Wait for the session port's existing turn-complete signal with bounded grace. |
| `client/lib/services/team_generation/team_generation_cleanup_service.dart` | Builder deletion, staging scrub, and tombstone completion after all cleanup gates. |
| `client/lib/services/team_generation/team_generation_coordinator.dart` | Preflight, start, resume, cancel, observe, and recovery dispatch. |
| `client/lib/services/team_generation/team_generation_recovery_service.dart` | Bootstrap scan and pre-/post-commit recovery policy. |
| `client/lib/services/team_generation/mcp/team_composer_mcp_constants.dart` | Server/path/header/tool constants. |
| `client/lib/services/team_generation/mcp/team_composer_mcp_transport.dart` | Local/remote MCP config with workflow-token header. |
| `client/lib/services/team_generation/mcp/team_composer_mcp_handler.dart` | JSON-RPC schema dispatch and post-response-flush callback envelope. |
| `client/lib/services/team_generation/providers/managed_team_builder_skill_provider.dart` | Materialize the app-owned builder skill into only builder sessions. |
| `client/lib/services/team_generation/providers/team_builder_skill_md.dart` | Source-of-truth Dart string for the managed skill. |
| `client/lib/services/team_generation/managed_skills/team-builder/SKILL.md` | Auditable source mirror of the managed skill. |
| `client/lib/cubits/team_generation_cubit.dart` | Thin Flutter state adapter around settings and coordinator streams. |
| `client/lib/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart` | Global generation settings editor. |
| `client/lib/pages/home_workspace/workspace/workspace_landing_generation_preflight.dart` | Landing-only localized preflight presentation. |
| `client/lib/pages/chat/team_generation_builder_status.dart` | Session-purpose-specific status row and Cancel action. |

### Existing files changed at their existing seams

| Area | Files |
|---|---|
| Paths and persistence | `client/lib/services/storage/app_storage.dart`, `client/lib/services/storage/workspace_layout.dart`, `docs/workspace-storage-layout.md` |
| Landing intent | `client/lib/models/landing_launch_context.dart`, `client/lib/services/home_workspace/landing_prefs_store.dart`, `client/lib/utils/workspace/landing_draft_resolver.dart` |
| Session purpose threading | `client/lib/models/app_session.dart`, `client/lib/cubits/chat/model/session_create_request.dart`, `client/lib/cubits/chat/model/session_persist_params.dart`, `client/lib/services/launch/session_provisional_builder.dart`, `client/lib/services/launch/session_launch_pipeline.dart`, `client/lib/cubits/chat/session_launch_service.dart`, `client/lib/repositories/session_repository.dart` |
| Builder resource injection | `client/lib/services/expert_hub/builtin_member_templates.dart`, `client/lib/services/provider/config_profile_service.dart`, `client/lib/services/session/session_lifecycle_service.dart` |
| Catalog generation scope | `client/lib/services/catalog/catalog_kind.dart`, `catalog_mcp_handler.dart`, `catalog_mcp_transport.dart`, `catalog_runtime.dart`, the three catalog modules/tool schemas, `services/skill/skill_install_service.dart`, and `services/plugin/plugin_install_service.dart` |
| MCP gateway | `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart` |
| Commit/provision/publication | `client/lib/services/expert_hub/local_expert_store.dart`, `client/lib/cubits/team/team_resource_sync_service.dart`, `client/lib/cubits/team/generated_team_state_publisher.dart`, `client/lib/cubits/launch_profile_cubit.dart`, `client/lib/cubits/chat_cubit.dart` |
| Exact prompt delivery | `client/lib/services/prompt_delivery/prompt_delivery.dart`, `prompt_delivery_coordinator.dart`, `client/lib/cubits/chat/tab_member_pty_delivery.dart`, `tab_session_runtime_coordinator.dart` |
| Landing and workbench UI | `client/lib/pages/team_hub/team_landing_chip_menu.dart`, `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`, `workspace_chat_pane.dart`, `client/lib/pages/chat_workbench.dart` |
| Composition root | `client/lib/app/app_shell.dart`, `client/lib/main.dart` |
| Localization | `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` |

### Cross-task interfaces (names are fixed for later tasks)

```dart
final class TeamGenerationSettingsSnapshot {
  const TeamGenerationSettingsSnapshot({
    required this.revision,
    required this.capturedAt,
    required this.teamMode,
    required this.nativeCli,
    required this.modelPool,
  });

  final String revision;
  final int capturedAt;
  final TeamMode teamMode;
  final CliTool nativeCli;
  final List<EffectiveGenerateModelPoolEntry> modelPool;
}

final class TeamGenerationGeneratorSnapshot {
  const TeamGenerationGeneratorSnapshot({
    required this.cli,
    required this.provider,
    required this.model,
    required this.effort,
    required this.presetId,
  });

  final CliTool cli;
  final String provider;
  final String model;
  final String effort;
  final String presetId;

  SimpleLaunchIdentity toBuilderIdentity() => SimpleLaunchIdentity(
    cli: cli,
    provider: provider,
    model: model,
    effort: effort,
    presetId: presetId,
    expertKey: 'teampilot/builtin/team-builder',
  );
}

enum TeamGenerationPhase {
  created,
  probing,
  planning,
  validating,
  committing,
  launching,
  delivering,
  delivered,
  cleaning,
  complete,
  failed,
  cancelled,
}

enum TeamGenerationReceiptState { reserved, succeeded, failed, unknown }

enum TeamGenerationIssueSeverity { warning, error }

final class TeamGenerationReceipt {
  const TeamGenerationReceipt({
    required this.state,
    this.value = '',
    this.digest = '',
    this.updatedAt = 0,
  });

  final TeamGenerationReceiptState state;
  final String value;
  final String digest;
  final int updatedAt;
}

final class TeamGenerationPrincipal {
  const TeamGenerationPrincipal({
    required this.sessionId,
    required this.workspaceId,
    required this.workflowId,
  });

  final String sessionId;
  final String workspaceId;
  final String workflowId;
}

final class TeamGenerationIssue {
  const TeamGenerationIssue({
    required this.code,
    required this.path,
    required this.message,
    required this.severity,
  });

  final String code;
  final String path;
  final String message;
  final TeamGenerationIssueSeverity severity;
}

final class GeneratedDestinationLaunch {
  const GeneratedDestinationLaunch({
    required this.folderId,
    required this.projectFolderPath,
    required this.workingDirectoryPath,
    required this.leadTargetId,
  });

  final String folderId;
  final String projectFolderPath;
  final String workingDirectoryPath;
  final String leadTargetId;
}

final class GeneratedTeamValidationResult {
  const GeneratedTeamValidationResult({
    required this.revision,
    required this.normalizedPlan,
    required this.preview,
    required this.placement,
    required this.destination,
    required this.issues,
  });

  final String revision;
  final GeneratedTeamPlan normalizedPlan;
  final TeamProfile? preview;
  final MemberPlacementByTarget placement;
  final GeneratedDestinationLaunch? destination;
  final List<TeamGenerationIssue> issues;
  bool get isValid =>
      preview != null &&
      destination != null &&
      issues.every((issue) => issue.severity != TeamGenerationIssueSeverity.error);
}

final class TeamComposerMcpResult {
  const TeamComposerMcpResult(this.response, {this.afterResponseFlushed});

  final JsonRpcResponse? response;
  final Future<void> Function()? afterResponseFlushed;
}
```

## Task 1: Global generation settings and effective pool snapshots

**Files:**
- Create: `client/lib/models/team_generation_settings.dart`
- Create: `client/lib/services/team_generation/team_generation_settings_store.dart`
- Modify: `client/lib/services/storage/app_storage.dart`
- Test: `client/test/services/team_generation/team_generation_settings_store_test.dart`
- Test: `client/test/models/team_generation_settings_test.dart`

**Interfaces:**
- Consumes: `CliPreset`, `TeamMode`, `CliToolRegistry`, `TeamBehaviorCapability`.
- Produces: `GenerateModelPoolEntry`, `EffectiveGenerateModelPoolEntry`, `TeamGenerationSettings`, `TeamGenerationSettingsSnapshot`, `TeamGenerationGeneratorSnapshot`, `resolveTeamGenerationSettingsSnapshot(...)`, and `TeamGenerationSettingsStore.load/save`.

- [ ] **Step 1: Write failing serialization, normalization, and filtering tests**

```dart
test('load preserves order and broken refs while first duplicate wins', () async {
  final fs = InMemoryFilesystem();
  final store = TeamGenerationSettingsStore(fs: fs, pathOverride: '/tp/ui/team-generation-settings.json');
  await fs.ensureDir('/tp/ui');
  await fs.writeString('/tp/ui/team-generation-settings.json', jsonEncode({
    'schemaVersion': 1,
    'teamMode': 'mixed',
    'nativeCli': 'claude',
    'modelPool': [
      {'presetId': 'strong', 'description': 'lead', 'tags': ['reasoning']},
      {'presetId': 'missing', 'description': 'keep visible', 'tags': []},
      {'presetId': 'strong', 'description': 'duplicate', 'tags': ['drop']},
    ],
  }));

  final loaded = await store.load();

  expect(loaded.modelPool.map((entry) => entry.presetId), ['strong', 'missing']);
  expect(loaded.modelPool.first.description, 'lead');
});

test('native snapshot filters by native cli and ranks after filtering', () {
  final settings = TeamGenerationSettings(
    teamMode: TeamMode.native,
    nativeCli: CliTool.claude,
    modelPool: const [
      GenerateModelPoolEntry(presetId: 'codex', description: '', tags: []),
      GenerateModelPoolEntry(presetId: 'claude-strong', description: 'lead', tags: ['strong']),
    ],
  );
  final snapshot = resolveTeamGenerationSettingsSnapshot(
    settings: settings,
    presets: [preset('codex', CliTool.codex), preset('claude-strong', CliTool.claude)],
    registry: CliToolRegistry.builtIn(),
    capturedAt: 42,
  );

  expect(snapshot.modelPool.single.rank, 1);
  expect(snapshot.modelPool.single.preset.id, 'claude-strong');
  expect(snapshot.capturedAt, 42);
});
```

- [ ] **Step 2: Run the focused tests and confirm missing-type failures**

Run: `cd client && dart run tool/run_tests.dart test/models/team_generation_settings_test.dart test/services/team_generation/team_generation_settings_store_test.dart`

Expected: FAIL because the settings model/store and `teamGenerationSettingsJson` path do not exist.

- [ ] **Step 3: Implement immutable settings rows and deterministic effective snapshots**

```dart
@immutable
final class GenerateModelPoolEntry {
  const GenerateModelPoolEntry({
    required this.presetId,
    this.description = '',
    this.tags = const [],
  });

  final String presetId;
  final String description;
  final List<String> tags;

  factory GenerateModelPoolEntry.fromJson(Map<String, Object?> json) =>
      GenerateModelPoolEntry(
        presetId: (json['presetId'] as String? ?? '').trim(),
        description: (json['description'] as String? ?? '').trim(),
        tags: List.unmodifiable({
          for (final value in (json['tags'] as List? ?? const []))
            if (value is String && value.trim().isNotEmpty) value.trim(),
        }),
      );

  Map<String, Object?> toJson() => {
    'presetId': presetId,
    if (description.isNotEmpty) 'description': description,
    if (tags.isNotEmpty) 'tags': tags,
  };
}

@immutable
final class EffectiveGenerateModelPoolEntry {
  const EffectiveGenerateModelPoolEntry({
    required this.rank,
    required this.source,
    required this.preset,
  });

  final int rank;
  final GenerateModelPoolEntry source;
  final CliPreset preset;
}

TeamGenerationSettingsSnapshot resolveTeamGenerationSettingsSnapshot({
  required TeamGenerationSettings settings,
  required List<CliPreset> presets,
  required CliToolRegistry registry,
  required int capturedAt,
}) {
  final byId = {for (final preset in presets) preset.id.trim(): preset};
  final effective = <EffectiveGenerateModelPoolEntry>[];
  for (final entry in settings.modelPool) {
    final preset = byId[entry.presetId.trim()];
    if (preset == null || registry.tryGet(preset.cli)?.isLaunchSupported != true) continue;
    if (settings.teamMode == TeamMode.native && preset.cli != settings.nativeCli) continue;
    effective.add(EffectiveGenerateModelPoolEntry(
      rank: effective.length + 1,
      source: entry,
      preset: preset,
    ));
  }
  final canonical = jsonEncode({
    'teamMode': settings.teamMode.value,
    'nativeCli': settings.nativeCli.value,
    'modelPool': [for (final entry in effective) {
      'rank': entry.rank,
      'source': entry.source.toJson(),
      'preset': {
        'id': entry.preset.id,
        'name': entry.preset.name,
        'cli': entry.preset.cli.value,
        'provider': entry.preset.provider,
        'model': entry.preset.model,
        'effort': entry.preset.effort,
      },
    }],
  });
  return TeamGenerationSettingsSnapshot(
    revision: sha256.convert(utf8.encode(canonical)).toString(),
    capturedAt: capturedAt,
    teamMode: settings.teamMode,
    nativeCli: settings.nativeCli,
    modelPool: List.unmodifiable(effective),
  );
}
```

- [ ] **Step 4: Implement atomic global persistence and the canonical AppPaths getter**

```dart
static String teamGenerationSettingsJsonForTeampilotRoot(String teampilotRoot) =>
    _pathUnderTeampilotRoot(teampilotRoot, 'ui/team-generation-settings.json');

String get teamGenerationSettingsJson =>
    teamGenerationSettingsJsonForTeampilotRoot(basePath);
```

```dart
final class TeamGenerationSettingsStore {
  TeamGenerationSettingsStore({Filesystem? fs, String? pathOverride})
      : _fsOverride = fs,
        _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;
  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path => _pathOverride ?? AppStorage.paths.teamGenerationSettingsJson;

  Future<TeamGenerationSettings> load() async {
    try {
      final raw = await _fs.readString(_path);
      if (raw == null || raw.trim().isEmpty) return const TeamGenerationSettings();
      return TeamGenerationSettings.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } on Object {
      return const TeamGenerationSettings();
    }
  }

  Future<void> save(TeamGenerationSettings settings) async {
    final normalized = settings.normalized();
    await _fs.ensureDir(_fs.pathContext.dirname(_path));
    await _fs.atomicWrite(_path, const JsonEncoder.withIndent('  ').convert(normalized.toJson()));
  }
}
```

- [ ] **Step 5: Run the focused tests and commit**

Run: `cd client && dart run tool/run_tests.dart test/models/team_generation_settings_test.dart test/services/team_generation/team_generation_settings_store_test.dart`

Expected: PASS.

```bash
git add client/lib/models/team_generation_settings.dart client/lib/services/team_generation/team_generation_settings_store.dart client/lib/services/storage/app_storage.dart client/test/models/team_generation_settings_test.dart client/test/services/team_generation/team_generation_settings_store_test.dart
git commit -m "feat(team-generation): persist ranked model pool settings"
```

## Task 2: Landing generation-mode persistence invariant

**Files:**
- Modify: `client/lib/models/landing_launch_context.dart`
- Modify: `client/lib/services/home_workspace/landing_prefs_store.dart`
- Modify: `client/lib/utils/workspace/landing_draft_resolver.dart`
- Modify: `client/test/models/landing_launch_context_test.dart`
- Modify: `client/test/utils/workspace/landing_draft_resolver_test.dart`
- Modify: `client/test/services/home_workspace/workspace_launch_prefs_store_test.dart`

**Interfaces:**
- Consumes: existing Landing context/prefs serialization.
- Produces: normalized `LandingLaunchContext.generateLaunch` and `LandingPrefs.generateLaunch` with old-JSON default `false`.

- [ ] **Step 1: Add failing round-trip and invariant tests**

```dart
test('generate launch survives prefs round trip in team mode', () async {
  await store.save('workspace-1', const LandingPrefs(
    isPersonal: false,
    generateLaunch: true,
    teamId: 'last-team',
  ));
  final loaded = await store.prefsFor('workspace-1');
  expect(loaded?.generateLaunch, isTrue);
  expect(loaded?.teamId, 'last-team');
});

test('personal context always clears generate launch', () {
  const draft = LandingLaunchContext(isPersonal: true, generateLaunch: true);
  expect(draft.generateLaunch, isFalse);
  expect(draft.copyWith(isPersonal: false, generateLaunch: true).generateLaunch, isTrue);
  expect(draft.copyWith(isPersonal: true).generateLaunch, isFalse);
});
```

- [ ] **Step 2: Run the tests and verify constructor failures**

Run: `cd client && dart run tool/run_tests.dart test/models/landing_launch_context_test.dart test/utils/workspace/landing_draft_resolver_test.dart test/services/home_workspace/workspace_launch_prefs_store_test.dart`

Expected: FAIL because `generateLaunch` is not defined.

- [ ] **Step 3: Normalize the flag in the model and thread JSON/load/save**

```dart
const LandingLaunchContext({
  required this.isPersonal,
  bool generateLaunch = false,
  this.presetId,
  this.teamId,
  this.projectFolderPath,
  this.expertKey,
  this.workingDirectoryPath,
  this.launchSecurityPolicy = LaunchSecurityPolicy.fullAccess,
  this.cli,
  this.provider,
  this.model,
  this.effort,
}) : generateLaunch = !isPersonal && generateLaunch;

final bool generateLaunch;
```

```dart
LandingLaunchContext copyWith({
  bool? isPersonal,
  bool? generateLaunch,
  Object? presetId = _unset,
  String? teamId,
  Object? projectFolderPath = _unset,
  Object? expertKey = _unset,
  Object? workingDirectoryPath = _unset,
  LaunchSecurityPolicy? launchSecurityPolicy,
  Object? cli = _unset,
  Object? provider = _unset,
  Object? model = _unset,
  Object? effort = _unset,
}) {
  final nextPersonal = isPersonal ?? this.isPersonal;
  return LandingLaunchContext(
    isPersonal: nextPersonal,
    generateLaunch: !nextPersonal && (generateLaunch ?? this.generateLaunch),
    presetId: presetId == _unset ? this.presetId : presetId as String?,
    teamId: teamId ?? this.teamId,
    projectFolderPath: projectFolderPath == _unset ? this.projectFolderPath : projectFolderPath as String?,
    expertKey: expertKey == _unset ? this.expertKey : expertKey as String?,
    workingDirectoryPath: workingDirectoryPath == _unset ? this.workingDirectoryPath : workingDirectoryPath as String?,
    launchSecurityPolicy: launchSecurityPolicy ?? this.launchSecurityPolicy,
    cli: cli == _unset ? this.cli : cli as CliTool?,
    provider: provider == _unset ? this.provider : provider as String?,
    model: model == _unset ? this.model : model as String?,
    effort: effort == _unset ? this.effort : effort as String?,
  );
}
```

Add `'generateLaunch': generateLaunch` to `LandingPrefs.toJson`, decode with `m['generateLaunch'] as bool? ?? false`, and pass the field in both `resolveLandingDraft` and `persistLandingDraft`. Include the field in equality and `hashCode`.

- [ ] **Step 4: Run the Landing tests and commit**

Run: `cd client && dart run tool/run_tests.dart test/models/landing_launch_context_test.dart test/utils/workspace/landing_draft_resolver_test.dart test/services/home_workspace/workspace_launch_prefs_store_test.dart`

Expected: PASS, including old JSON defaulting to ordinary Landing mode.

```bash
git add client/lib/models/landing_launch_context.dart client/lib/services/home_workspace/landing_prefs_store.dart client/lib/utils/workspace/landing_draft_resolver.dart client/test/models/landing_launch_context_test.dart client/test/utils/workspace/landing_draft_resolver_test.dart client/test/services/home_workspace/workspace_launch_prefs_store_test.dart
git commit -m "feat(team-generation): persist landing generation mode"
```

## Task 3: Purpose-tagged builder sessions through the normal create pipeline

**Files:**
- Modify: `client/lib/models/app_session.dart`
- Modify: `client/lib/cubits/chat/model/session_create_request.dart`
- Modify: `client/lib/cubits/chat/model/session_persist_params.dart`
- Modify: `client/lib/services/launch/session_provisional_builder.dart`
- Modify: `client/lib/services/launch/session_launch_pipeline.dart`
- Modify: `client/lib/cubits/chat/session_launch_service.dart`
- Modify: `client/lib/repositories/session_repository.dart`
- Create: `client/test/models/app_session_purpose_test.dart`
- Create: `client/test/services/launch/session_generation_purpose_pipeline_test.dart`

**Interfaces:**
- Consumes: `SessionCreateRequest -> provisional -> SessionPersistParams -> SessionRepository.createSession`.
- Produces: `SessionPurpose.normal`, `SessionPurpose.teamGeneration`, `AppSession.purpose`, and `AppSession.workflowId` on both provisional and persisted records.

- [ ] **Step 1: Write failing backward-compatibility and pipeline tests**

```dart
test('unknown and missing session purpose fail closed to normal', () {
  final base = {'sessionId': 's', 'workspaceId': 'w', 'createdAt': 1};
  expect(AppSession.fromJson(base).purpose, SessionPurpose.normal);
  expect(AppSession.fromJson({...base, 'purpose': 'future-admin'}).purpose, SessionPurpose.normal);
});

test('team generation purpose and workflow survive JSON round trip', () {
  final session = AppSession(
    sessionId: 'builder',
    workspaceId: 'workspace',
    purpose: SessionPurpose.teamGeneration,
    workflowId: 'workflow',
    createdAt: 1,
  );
  expect(AppSession.fromJson(session.toJson()), session);
});
```

```dart
test('create request persists builder purpose and workflow', () async {
  final request = SessionCreateRequest(
    workspace: workspace,
    isPersonal: true,
    purpose: SessionPurpose.teamGeneration,
    workflowId: 'workflow-1',
    fixedSessionId: 'builder-1',
  );
  final status = await chat.requestCreateAndOpenSession(request);
  expect(status, SessionOpenStatus.opened);
  await harness.waitForPersisted('builder-1');
  final session = await repository.findById('builder-1');
  expect(session?.purpose, SessionPurpose.teamGeneration);
  expect(session?.workflowId, 'workflow-1');
});
```

- [ ] **Step 2: Run the focused tests and verify they fail on missing fields**

Run: `cd client && dart run tool/run_tests.dart test/models/app_session_purpose_test.dart test/services/launch/session_generation_purpose_pipeline_test.dart`

Expected: FAIL because `SessionPurpose`, `purpose`, and `workflowId` do not exist.

- [ ] **Step 3: Add fail-closed session purpose serialization**

```dart
enum SessionPurpose {
  normal('normal'),
  teamGeneration('teamGeneration');

  const SessionPurpose(this.value);
  final String value;

  static SessionPurpose decode(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    return SessionPurpose.values.firstWhere(
      (purpose) => purpose.value == value,
      orElse: () => SessionPurpose.normal,
    );
  }
}

bool isValidTeamGenerationWorkflowId(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value);
```

Add `purpose` (default `normal`) and trimmed `workflowId` (default empty) to both AppSession constructors, `fromJson`, `copyWith`, equality, hash, and `toJson`. Normalize `workflowId` to empty whenever purpose is not `teamGeneration`, including unknown persisted purpose values. Emit `purpose` and `workflowId` only when non-default/non-empty, preserving old schema compatibility.

- [ ] **Step 4: Thread the two fields through every create-stage object**

```dart
class SessionCreateRequest {
  const SessionCreateRequest({
    required this.workspace,
    required this.isPersonal,
    this.purpose = SessionPurpose.normal,
    this.workflowId = '',
    this.team,
    this.member,
    this.repo,
    this.cli,
    this.simpleIdentity,
    this.workingDirectory,
    this.emptyDisplayTitleFallback = 'New Chat',
    this.fixedSessionId,
    this.expertKey,
    this.continueOverrides,
    this.preserveWorkbenchView = false,
  });

  final SessionPurpose purpose;
  final String workflowId;
}
```

Mirror these defaults in `SessionPersistParams`, pass them into `buildProvisionalSession`, copy them into `SessionPersistParams`, pass them in `_persistSessionIfNeeded`, and add named parameters to `SessionRepository.createSession`. At `SessionCreateRequest` consumption before a tab is surfaced, require `isValidTeamGenerationWorkflowId(workflowId.trim())` for `teamGeneration`; reject blank, separators, dots, whitespace, or values over 128 characters with `ArgumentError.value`.

- [ ] **Step 5: Run pipeline and legacy session tests, then commit**

Run: `cd client && dart run tool/run_tests.dart test/models/app_session_purpose_test.dart test/services/launch/session_generation_purpose_pipeline_test.dart test/repositories/session_repository_test.dart`

Expected: PASS; existing normal sessions serialize without workflow privileges.

```bash
git add client/lib/models/app_session.dart client/lib/cubits/chat/model/session_create_request.dart client/lib/cubits/chat/model/session_persist_params.dart client/lib/services/launch/session_provisional_builder.dart client/lib/services/launch/session_launch_pipeline.dart client/lib/cubits/chat/session_launch_service.dart client/lib/repositories/session_repository.dart client/test/models/app_session_purpose_test.dart client/test/services/launch/session_generation_purpose_pipeline_test.dart
git commit -m "feat(team-generation): persist builder session purpose"
```

## Task 4: Durable workflow job, WAL receipts, tombstones, and authorization

**Files:**
- Create: `client/lib/services/team_generation/models/team_generation_job.dart`
- Create: `client/lib/services/team_generation/models/team_generation_launch.dart`
- Create: `client/lib/services/team_generation/team_generation_job_store.dart`
- Create: `client/lib/services/team_generation/team_generation_workflow_executor.dart`
- Create: `client/lib/services/team_generation/team_generation_authorizer.dart`
- Modify: `client/lib/services/storage/workspace_layout.dart`
- Modify: `docs/workspace-storage-layout.md`
- Test: `client/test/services/team_generation/team_generation_job_store_test.dart`
- Test: `client/test/services/team_generation/team_generation_workflow_executor_test.dart`
- Test: `client/test/services/team_generation/team_generation_authorizer_test.dart`

**Interfaces:**
- Consumes: `TeamGenerationSettingsSnapshot`, `TeamGenerationGeneratorSnapshot`, immutable original prompt and Landing launch choices, `AppSession.purpose/workflowId`, `Filesystem`, injected clock/ID/token factories.
- Produces: `TeamGenerationLaunchSnapshot`, `GeneratedDestinationLaunch`, `TeamGenerationJob`, `TeamGenerationReceipt`, `teamGenerationStableId(...)`, `TeamGenerationWorkflowExecutor`, `TeamGenerationJobStore.create/read/mutate/reserveEffect/recordCleanupReceipt/resumeFailed/listRecoverable/compactComplete/beginCancel/deleteCancelled`, `TeamGenerationPrincipal`, and `TeamGenerationAuthorizer.issue/authorize/revoke`.
- Disk contract: `WorkspaceLayout.teamGenerationJobFile(workspaceId, workflowId)` is `<workspace>/team-generation/<workflowId>/job.json`; all uncommitted payloads live below its sibling `staging/`.

- [ ] **Step 1: Write failing job round-trip and transition tests**

```dart
test('job round-trips prompt, snapshot, phase, and receipts', () async {
  final store = buildJobStore(clock: () => DateTime.utc(2026, 8, 31));
  final created = await store.create(
    workspaceId: 'ws',
    workflowId: 'wf',
    originalPrompt: 'exact\nrequest',
    generator: generatorSnapshot,
    settings: settingsSnapshot,
    launch: launchSnapshot,
  );

  await store.mutate('ws', 'wf', (job) => job.copyWith(
    phase: TeamGenerationPhase.committing,
    receipts: {
      ...job.receipts,
      'profile': const TeamGenerationReceipt(
        state: TeamGenerationReceiptState.succeeded,
        value: 'team-1',
      ),
    },
  ));

  final loaded = await store.read('ws', 'wf');
  expect(created.originalPrompt, 'exact\nrequest');
  expect(loaded!.settings.revision, settingsSnapshot.revision);
  expect(loaded.phase, TeamGenerationPhase.committing);
  expect(loaded.receipts['profile']!.value, 'team-1');
});

test('rejects phase regression and receipt value replacement', () async {
  final store = buildJobStore();
  await seedCreatedJob(store);
  await store.mutate('ws', 'wf', (job) => job.copyWith(
    phase: TeamGenerationPhase.launching,
    receipts: {'profile': succeededReceipt('team-1')},
  ));

  expect(
    () => store.mutate('ws', 'wf', (job) => job.copyWith(
      phase: TeamGenerationPhase.planning,
      receipts: {'profile': succeededReceipt('team-2')},
    )),
    throwsA(isA<StateError>()),
  );
});
```

- [ ] **Step 2: Run the job tests and confirm missing types fail**

Run: `cd client && dart run tool/run_tests.dart test/services/team_generation/team_generation_job_store_test.dart`

Expected: FAIL because the job model, paths, and store do not exist.

- [ ] **Step 3: Add canonical paths, versioned JSON, and monotonic mutation**

Add these methods to `WorkspaceLayout`:

```dart
String teamGenerationDir(String workspaceId) =>
    _ctx.join(workspaceDir(workspaceId), 'team-generation');

String teamGenerationWorkflowDir(String workspaceId, String workflowId) =>
    _ctx.join(
      teamGenerationDir(workspaceId),
      requireValidTeamGenerationWorkflowId(workflowId),
    );

String teamGenerationJobFile(String workspaceId, String workflowId) =>
    _ctx.join(teamGenerationWorkflowDir(workspaceId, workflowId), 'job.json');

String teamGenerationStagingDir(String workspaceId, String workflowId) =>
    _ctx.join(teamGenerationWorkflowDir(workspaceId, workflowId), 'staging');
```

`requireValidTeamGenerationWorkflowId` delegates to the session-model validator and throws before path joining. Scans ignore invalid directory names and report them as recovery-integrity diagnostics; they never join a decoded ID containing separators.

Define `TeamGenerationLaunchSnapshot` with project-folder path, working-directory path, launch security policy, workspace folder IDs/target IDs, workspace revision, and capture time. Define `GeneratedDestinationLaunch` in the same file so job persistence does not depend on the later plan parser. Define `TeamGenerationJob.schemaVersion = 1` with `workspaceId`, `workflowId`, `builderSessionId`, `destinationSessionId`, `teamReservation`, `teamId`, `originalPrompt`, `generator`, `settings`, `launch`, `phase`, `resumePhase`, `attempt`, raw versioned `probeSnapshotJson`, raw canonical `normalizedPlanJson`, `planRevision`, `validatedRevision`, `validatedDestination`, `finalizeIdempotencyKey`, `receipts`, raw `stagedResources`, `error`, `createdAt`, and `updatedAt`. Later services own typed decoding of their JSON payloads; the job model validates only size/version envelopes. `teamGenerationStableId(prefix, workflowId)` is `prefix` plus the first 20 lowercase hex characters of SHA-256 over the workflow ID, so IDs never depend on unsafe workflow characters.

Write with a sibling temporary file followed by `Filesystem.rename`; serialize mutations through `LockPool` keyed by `workspaceId/workflowId`. Give active phases explicit monotonic ranks rather than relying on enum indexes. A normal mutation may advance, stay in its current phase, enter `failed` with `resumePhase` set to the last safe active phase, or enter pre-profile `cancelled`. Only `resumeFailed` may leave `failed`, and it restores exactly `resumePhase` while clearing the error. `reserveEffect` rejects `cancelled/complete` jobs; `recordCleanupReceipt` is the only receipt writer allowed during cancellation:

```dart
bool canAdvance(TeamGenerationPhase from, TeamGenerationPhase to) =>
    to == TeamGenerationPhase.failed ||
    to == TeamGenerationPhase.cancelled ||
    (activePhaseRank[to] ?? -1) >= (activePhaseRank[from] ?? 1 << 30);

bool canReplaceReceipt(TeamGenerationReceipt? before, TeamGenerationReceipt after) =>
    before == null ||
    before.state != TeamGenerationReceiptState.succeeded ||
    (after.state == TeamGenerationReceiptState.succeeded && before.value == after.value);
```

Implement `TeamGenerationWorkflowExecutor.run(workspaceId, workflowId, body)` as an in-memory future queue. Every mutating Catalog/Composer entry and coordinator `finalize/retry/cancel` uses this same instance, re-reads the durable job after entering, and never recursively re-enters it. Repository substeps called from an already serialized coordinator path do not enqueue again.

```dart
test('cancel waits for an admitted effect and later effects see cancelled', () async {
  final first = executor.run('ws', 'wf', () async {
    events.add('effect-start');
    await release.future;
    events.add('effect-end');
  });
  final cancel = executor.run('ws', 'wf', () async {
    await store.beginCancel('ws', 'wf');
    events.add('cancelled');
  });
  final late = executor.run('ws', 'wf', () async {
    await store.reserveEffect('ws', 'wf', 'late');
  });
  release.complete();
  await first;
  await cancel;
  await expectLater(late, throwsA(isA<StateError>()));
  expect(events, ['effect-start', 'effect-end', 'cancelled']);
});
```

- [ ] **Step 4: Write failing tombstone and cancellation tests**

```dart
test('complete scrubs sensitive data and prunes by age and count', () async {
  final store = buildJobStore(clock: mutableClock.call);
  await seedCompleteJobs(store, count: 102, oldest: DateTime.utc(2026, 6, 1));

  await store.compactComplete('ws', 'wf-101');

  final jobs = await store.listAll('ws');
  expect(jobs, hasLength(100));
  expect(jobs.every((job) => job.originalPrompt.isEmpty), isTrue);
  expect(jobs.every((job) => job.normalizedPlanJson == null && job.probeSnapshotJson == null), isTrue);
  expect(jobs.every((job) => job.stagedResources.isEmpty), isTrue);
});

test('pre-commit cancel blocks new effects and removes its directory last', () async {
  final store = buildJobStore();
  final job = await seedPlanningJob(store, stagedFile: 'skills/new/SKILL.md');

  await store.beginCancel(job.workspaceId, job.workflowId);

  final cancelled = await store.read('ws', 'wf');
  expect(cancelled!.phase, TeamGenerationPhase.cancelled);
  expect(() => store.resumeFailed('ws', 'wf'), throwsA(isA<StateError>()));
  expect(await fs.exists(layout.teamGenerationStagingDir('ws', 'wf')), isTrue);

  await seedCancellationCleanupReceipts(store);
  await store.deleteCancelled('ws', 'wf');
  expect(await fs.exists(layout.teamGenerationWorkflowDir('ws', 'wf')), isFalse);
});

test('recoverable failure resumes only its recorded safe phase', () async {
  await seedFailedJob(store, resumePhase: TeamGenerationPhase.validating);
  final resumed = await store.resumeFailed('ws', 'wf');
  expect(resumed.phase, TeamGenerationPhase.validating);
  expect(resumed.error, isNull);
});

test('workflow ids cannot escape the workspace generation directory', () {
  expect(
    () => layout.teamGenerationJobFile('ws', '../other'),
    throwsA(isA<ArgumentError>()),
  );
});
```

- [ ] **Step 5: Implement bounded tombstones and document storage**

`TeamGenerationJob.fromJson` treats `phase: complete` as a tombstone variant in which generator/settings/launch and other sensitive active fields must be absent; every non-complete job requires them. `compactComplete` must erase the prompt, generated plan, validation preview, probe output, generator/pool payloads, and staged catalog metadata, retaining only workflow/team/destination IDs plus delivery and cleanup receipts. `deleteCancelled` requires succeeded builder-deleted and staging-deleted receipts, then removes the entire cancelled workflow directory. `pruneTombstones` deletes complete job directories older than 30 days, then retains the newest 100 per workspace. Update `docs/workspace-storage-layout.md` with `team-generation/<workflowId>/job.json` and `staging/`, including the sensitive-data scrubbing and cancelled-directory removal rules.

- [ ] **Step 6: Write failing purpose-plus-token authorization tests**

```dart
test('authorizes only the persisted builder session and one live token', () async {
  final auth = TeamGenerationAuthorizer(
    sessionLookup: fakeSessionLookup,
    jobStore: store,
    tokenFactory: () => 'token-1',
  );
  await seedBuilderSession(
    sessionId: 'builder',
    workspaceId: 'ws',
    workflowId: 'wf',
  );
  final token = await auth.issue(
    const TeamGenerationPrincipal(
      sessionId: 'builder',
      workspaceId: 'ws',
      workflowId: 'wf',
    ),
  );

  expect(await auth.authorize(principal: principal('builder', 'ws', 'wf'), token: token), isTrue);
  expect(await auth.authorize(principal: principal('normal', 'ws', 'wf'), token: token), isFalse);
  expect(await auth.authorize(principal: principal('builder', 'ws', 'wf'), token: 'wrong'), isFalse);
});
```

- [ ] **Step 7: Implement ephemeral authorization and restart rotation**

Store only a SHA-256 digest of the current token in memory, never in `job.json`. `issue` revokes the prior token for the workflow, checks that the job is active, the persisted session has `purpose == teamGeneration`, and the same `workflowId/workspaceId`, then returns the raw token once to runtime config assembly. Authorization fails immediately for cancelled/complete/corrupt jobs. On process restart recovery issues a new token and rematerializes only the builder session MCP config. `revoke` removes the in-memory digest on cancel or completion.

- [ ] **Step 8: Run focused tests, inspect disk JSON, then commit**

Run: `cd client && dart run tool/run_tests.dart test/services/team_generation/team_generation_job_store_test.dart test/services/team_generation/team_generation_workflow_executor_test.dart test/services/team_generation/team_generation_authorizer_test.dart`

Expected: PASS; serialized `job.json` never contains the issued token.

```bash
git add client/lib/services/team_generation/models/team_generation_job.dart client/lib/services/team_generation/models/team_generation_launch.dart client/lib/services/team_generation/team_generation_job_store.dart client/lib/services/team_generation/team_generation_workflow_executor.dart client/lib/services/team_generation/team_generation_authorizer.dart client/lib/services/storage/workspace_layout.dart docs/workspace-storage-layout.md client/test/services/team_generation/team_generation_job_store_test.dart client/test/services/team_generation/team_generation_workflow_executor_test.dart client/test/services/team_generation/team_generation_authorizer_test.dart
git commit -m "feat(team-generation): add durable workflow jobs"
```

## Task 5: Builder expert, managed skill, resource injection, and CLI compatibility

**Files:**
- Create: `client/lib/services/team_generation/team_generation_compatibility.dart`
- Create: `client/lib/services/team_generation/providers/managed_team_builder_skill_provider.dart`
- Create: `client/lib/services/team_generation/providers/team_builder_skill_md.dart`
- Create: `client/lib/services/team_generation/managed_skills/team-builder/SKILL.md`
- Modify: `client/lib/services/expert_hub/builtin_member_templates.dart`
- Modify: `client/lib/services/provider/config_profile_service.dart`
- Modify: `client/lib/services/session/session_lifecycle_service.dart`
- Test: `client/test/services/team_generation/team_generation_compatibility_test.dart`
- Test: `client/test/services/team_generation/managed_team_builder_skill_provider_test.dart`
- Test: `client/test/services/session/team_generation_session_resources_test.dart`

**Interfaces:**
- Consumes: `CliToolRegistry`, `CliToolDefinition.isLaunchSupported`, `CliSessionCapability`, `SkillCapability`, `McpCapability`, `TeamBehaviorCapability`, `AppSession.purpose`.
- Produces: `TeamGenerationCompatibility.evaluateGenerator/evaluateTeamPool`, capability-derived `builderSecurityPolicy`, built-in expert key `teampilot/builtin/team-builder`, managed skill ID `teampilot/internal/team-builder`, and `SessionResourceProviderResolver`.

- [ ] **Step 1: Write failing compatibility matrix tests**

```dart
test('generator needs launch, session, skill, and mcp capabilities', () {
  final result = compatibility.evaluateGenerator(
    preset: codexPreset,
    registry: registryWith(mcp: false),
  );
  expect(result.isCompatible, isFalse);
  expect(result.issues.single.code, 'generator_mcp_unsupported');
});

test('native pool requires one native-team-capable cli', () {
  final result = compatibility.evaluateTeamPool(
    mode: TeamMode.native,
    nativeCli: CliTool.codex,
    pool: [codexPreset],
    registry: registryWith(nativeTeam: false),
  );
  expect(result.issues.map((issue) => issue.code), contains('native_team_unsupported'));
});

test('mixed pool may span launchable clis', () {
  final result = compatibility.evaluateTeamPool(
    mode: TeamMode.mixed,
    nativeCli: CliTool.claude,
    pool: [claudePreset, codexPreset],
    registry: fullyCapableRegistry,
  );
  expect(result.isCompatible, isTrue);
});

test('builder policy prefers read-only and never escalates to full access', () {
  final readOnly = compatibility.evaluateGenerator(
    preset: claudePreset,
    registry: registryAccepting(LaunchSecurityPolicy.askReadOnlyTrusted),
  );
  final fallback = compatibility.evaluateGenerator(
    preset: codexPreset,
    registry: registryAccepting(LaunchSecurityPolicy.cliDefault),
  );
  expect(readOnly.builderSecurityPolicy, LaunchSecurityPolicy.askReadOnlyTrusted);
  expect(fallback.builderSecurityPolicy, LaunchSecurityPolicy.cliDefault);
  expect(fallback.builderSecurityPolicy, isNot(LaunchSecurityPolicy.fullAccess));
});
```

- [ ] **Step 2: Run the compatibility test and confirm it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/team_generation/team_generation_compatibility_test.dart`

Expected: FAIL because the composed compatibility service does not exist.

- [ ] **Step 3: Implement capability-composed checks without CLI branches**

Return typed `TeamGenerationIssue`s. Do not compare against individual `CliTool` enum values. Generator checks use the tool definition and its registered capabilities. Ask the registered launch-argument/constraint pipeline whether `LaunchSecurityPolicy.askReadOnlyTrusted` is representable; use it when valid and otherwise use `cliDefault`, never `fullAccess`, for the builder. Native checks require every effective pool entry to match `nativeCli` and require `TeamBehaviorCapability.supportsNativeTeam`; mixed checks require every preset CLI to be launch-supported and session-launch-capable. Preserve the first compatible entry as the team default.

- [ ] **Step 4: Write the managed skill source and its mirror test**

The skill must instruct the builder to:

1. call `get_generation_context` before planning;
2. use Catalog search/read freely and generation-scoped mutation only when a missing resource is necessary;
3. call `probe_workspace_targets` before assigning machines;
4. treat pool rank 1 as strongest, prefer earlier presets for the lead/critical roles and later presets for lighter roles, while allowing reuse;
5. design only 2–5 non-overlapping roles and avoid adding a role without concrete value;
6. call `validate_team_plan` until `valid: true`;
7. call `finalize_team_generation` exactly once with the validated plan, revision, and one idempotency key;
8. never edit TeamPilot JSON manifests or deliver the original prompt to another session itself;
9. explain structured blockers in the visible conversation and ask the user only when credentials or an unavailable target require action;
10. stop after finalization is accepted and let TeamPilot perform commit, switching, delivery, and cleanup.

```dart
test('managed builder skill source and materialized mirror are identical', () async {
  final provider = ManagedTeamBuilderSkillProvider();
  final resource = await provider.resolve('teampilot/internal/team-builder');
  final mirror = await File(
    'lib/services/team_generation/managed_skills/team-builder/SKILL.md',
  ).readAsString();

  expect(resource!.content, teamBuilderSkillMd);
  expect(mirror, teamBuilderSkillMd);
  expect(mirror, contains('finalize_team_generation'));
});
```

- [ ] **Step 5: Add the internal expert and purpose-aware provider resolver**

Add an app-owned `DiscoverableMember` whose stable key is `teampilot/builtin/team-builder`, with only the managed builder skill dependency. Introduce this seam in `session_lifecycle_service.dart`:

```dart
typedef SessionResourceProviderResolver = ResourceProviderSet Function(
  AppSession session,
  ResourceProviderSet defaults,
);
```

When `session.purpose == SessionPurpose.teamGeneration`, return defaults augmented with `ManagedTeamBuilderSkillProvider`; for normal sessions return `defaults` unchanged. Thread the resolved provider set through `ConfigProfileService.applySimpleSessionFilesystem`, `stageSimpleSessionLaunch`, and `prepareSimpleSessionLaunch`, matching the already-injectable `contributeSimpleSessionLaunch` path.

- [ ] **Step 6: Write and run resource isolation tests**

```dart
test('builder gets managed skill while normal simple session does not', () async {
  final builderPlan = await lifecycle.prepareLaunch(builderSession);
  final normalPlan = await lifecycle.prepareLaunch(normalSession);

  expect(await skillExists(builderPlan, 'team-builder'), isTrue);
  expect(await skillExists(normalPlan, 'team-builder'), isFalse);
});
```

Run: `cd client && dart run tool/run_tests.dart test/services/team_generation/team_generation_compatibility_test.dart test/services/team_generation/managed_team_builder_skill_provider_test.dart test/services/session/team_generation_session_resources_test.dart`

Expected: PASS; normal session snapshots are unchanged.

- [ ] **Step 7: Commit the builder capability slice**

```bash
git add client/lib/services/team_generation/team_generation_compatibility.dart client/lib/services/team_generation/providers/managed_team_builder_skill_provider.dart client/lib/services/team_generation/providers/team_builder_skill_md.dart client/lib/services/team_generation/managed_skills/team-builder/SKILL.md client/lib/services/expert_hub/builtin_member_templates.dart client/lib/services/provider/config_profile_service.dart client/lib/services/session/session_lifecycle_service.dart client/test/services/team_generation/team_generation_compatibility_test.dart client/test/services/team_generation/managed_team_builder_skill_provider_test.dart client/test/services/session/team_generation_session_resources_test.dart
git commit -m "feat(team-generation): provision managed builder capability"
```

## Task 6: Team Composer MCP transport, gateway isolation, and immutable context

**Files:**
- Create: `client/lib/services/team_generation/team_generation_context_service.dart`
- Create: `client/lib/services/team_generation/mcp/team_composer_mcp_constants.dart`
- Create: `client/lib/services/team_generation/mcp/team_composer_mcp_transport.dart`
- Create: `client/lib/services/team_generation/mcp/team_composer_mcp_handler.dart`
- Modify: `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart`
- Test: `client/test/services/team_generation/team_generation_context_service_test.dart`
- Test: `client/test/services/team_generation/team_composer_mcp_handler_test.dart`
- Test: `client/test/services/team_bus/team_composer_mcp_gateway_test.dart`

**Interfaces:**
- Consumes: `TeamGenerationAuthorizer`, `TeamGenerationJobStore`, `TeamGenerationPrincipal`, `TeamGenerationSettingsSnapshot`.
- Produces: `/team-composer/mcp`, header `X-Team-Generation-Token`, tools `get_generation_context`, `probe_workspace_targets`, `validate_team_plan`, `finalize_team_generation`, and `TeamComposerMcpResult`.

- [ ] **Step 1: Write failing immutable-context tests**

```dart
test('context is derived from the frozen job and omits secrets', () async {
  final context = await service.getContext(principal('builder', 'ws', 'wf'));

  expect(context['originalPrompt'], 'exact task');
  expect(context['settingsRevision'], frozenSnapshot.revision);
  expect(context['modelPool'][0]['rank'], 1);
  expect(context['modelPool'][0]['presetId'], 'strong');
  expect(jsonEncode(context), isNot(contains('apiKey')));
  expect(jsonEncode(context), isNot(contains('token-1')));
});
```

- [ ] **Step 2: Implement redacted context from the job, not live settings**

Return `workflowId`, `workspaceId`, original prompt, requested team mode, generator CLI summary, ordered effective model pool (`rank`, `presetId`, `cli`, `provider`, `model`, `effort`, `description`, `tags`), frozen Landing project/worktree/security choices, workspace folder IDs/names/target IDs, current probe status/results, existing and staged catalog resources, roster/placement/launch constraints, and the plan schema version. Bound installed-resource summaries to 200 per kind with a `truncated` flag; the builder uses Catalog search for the remainder. Never re-read mutable global settings for an active workflow.

- [ ] **Step 3: Write failing gateway authorization and tool-schema tests**

```dart
test('gateway rejects absent token before handler dispatch', () async {
  final response = await postJsonRpc(
    path: '/team-composer/mcp',
    headers: {'X-Session': 'builder'},
    method: 'tools/call',
    params: {'name': 'get_generation_context', 'arguments': <String, Object?>{}},
  );
  expect(response.error!.code, -32001);
  expect(handler.calls, isEmpty);
});

test('authorized builder sees exactly four composer tools', () async {
  final response = await authorizedPost(method: 'tools/list');
  expect(
    toolNames(response),
    ['get_generation_context', 'probe_workspace_targets', 'validate_team_plan', 'finalize_team_generation'],
  );
});
```

- [ ] **Step 4: Implement transport config and gateway route**

`TeamComposerMcpTransport.buildConfig` must use the gateway's loopback URL for local sessions and existing remote relay/tunnel addressing for remote sessions. Add `X-Session` and `X-Team-Generation-Token`; never put the token in command arguments or environment variables. Add `attachTeamComposerHandler(...)` beside `attachCatalogHandler(...)`. The gateway resolves `AppSession` by `X-Session`, builds `TeamGenerationPrincipal`, calls `TeamGenerationAuthorizer.authorize`, and only then dispatches JSON-RPC.

- [ ] **Step 5: Implement strict JSON-RPC schemas and post-flush envelope**

`TeamComposerMcpHandler` exposes fixed `inputSchema` objects with `additionalProperties: false`. `probe_workspace_targets` accepts only optional `{refresh: boolean}`. `validate_team_plan` takes `{plan: object}`. `finalize_team_generation` takes `{plan: object, validationRevision: string, idempotencyKey: string}` with the key limited to 1–128 ASCII letters, digits, `.`, `_`, `:`, or `-`; it parses and revalidates the supplied plan, requires its canonical revision to equal both `validationRevision` and the job's current validated revision, and persists the first accepted idempotency key. Repeating the same key returns the same receipts; a different plan after profile persistence returns `immutable_commit`. For every request, return a `TeamComposerMcpResult`; gateway handling must be ordered exactly as follows:

Route `probe_workspace_targets`, `validate_team_plan`, and `finalize_team_generation` through the shared `TeamGenerationWorkflowExecutor` and reauthorize/re-read the active job after entering it. `get_generation_context` is read-only and does not take the mutation queue.

```dart
final result = await handler.handle(request, principal);
await _writeJsonRpc(response, result.response);
await response.close();
if (result.afterResponseFlushed case final callback?) {
  unawaited(_runTeamGenerationPostFlush(callback));
}
```

`_runTeamGenerationPostFlush` awaits the callback and logs any failure through `AppLogger`; the callback must not run when response write/close fails.

- [ ] **Step 6: Run MCP isolation tests, then commit**

Run: `cd client && dart run tool/run_tests.dart test/services/team_generation/team_generation_context_service_test.dart test/services/team_generation/team_composer_mcp_handler_test.dart test/services/team_bus/team_composer_mcp_gateway_test.dart`

Expected: PASS; unauthorized sessions cannot list or call tools, and finalization starts only after response close.

```bash
git add client/lib/services/team_generation/team_generation_context_service.dart client/lib/services/team_generation/mcp/team_composer_mcp_constants.dart client/lib/services/team_generation/mcp/team_composer_mcp_transport.dart client/lib/services/team_generation/mcp/team_composer_mcp_handler.dart client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart client/test/services/team_generation/team_generation_context_service_test.dart client/test/services/team_generation/team_composer_mcp_handler_test.dart client/test/services/team_bus/team_composer_mcp_gateway_test.dart
git commit -m "feat(team-generation): expose authorized composer mcp"
```

## Task 7: Read-only workspace-target probing

**Files:**
- Create: `client/lib/services/team_generation/models/team_target_probe.dart`
- Create: `client/lib/services/team_generation/team_target_probe_service.dart`
- Test: `client/test/services/team_generation/team_target_probe_service_test.dart`

**Interfaces:**
- Consumes: live `Workspace.folders`, `RuntimeTargetRegistry`, `RuntimeContextRegistry`, `hostOneShotRunnerForContext`, `RemoteCliReadinessService.probe`, frozen effective preset CLIs.
- Produces: canonical `TeamTargetProbeSnapshot`, per-target `TeamTargetProbe`, per-CLI `TeamTargetCliProbe`, and `TeamGenerationTargetRef` IDs accepted by validation.

- [ ] **Step 1: Write failing candidate, timeout, and truncation tests**

```dart
test('probes each distinct live folder target once and keeps folder refs', () async {
  final result = await service.probe(
    workspace: workspaceWithFolders([
      folder('a', targetId: 'local'),
      folder('b', targetId: 'ssh-1'),
      folder('c', targetId: 'ssh-1'),
    ]),
    clis: {CliTool.claude, CliTool.codex},
  );

  expect(result.targets.map((target) => target.targetId), ['local', 'ssh-1']);
  expect(result.targets.last.folderIds, ['b', 'c']);
  expect(fakeRunner.callsFor('ssh-1'), 1);
});

test('timeout is a bounded unavailable result and output is truncated', () async {
  fakeRunner.block('ssh-1');
  fakeRunner.answer('local', stdout: 'x' * 20000);

  final result = await service.probe(workspace: workspace, clis: {CliTool.claude});

  expect(result.byTarget('ssh-1').status, TeamTargetProbeStatus.timeout);
  expect(result.byTarget('local').diagnostic.length, lessThanOrEqualTo(2048));
});
```

- [ ] **Step 2: Run the probe test and confirm it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/team_generation/team_target_probe_service_test.dart`

Expected: FAIL because the typed snapshot and probe service do not exist.

- [ ] **Step 3: Implement canonical target derivation and bounded concurrency**

Resolve each non-empty `WorkspaceFolder.targetId` through the live runtime-target registry; canonicalize the home target to `local`; reject stale target IDs as typed unavailable facts rather than silently substituting local. Probe unique targets concurrently with a limit of four and a 12-second timeout per target. Each runner invocation may execute only version/path/capability discovery commands already used by `RemoteCliReadinessService`; it must not call install, upgrade, package-manager, file-write, or shell-redirection commands.

Reuse a complete snapshot for 60 seconds when workspace revision and required CLI set match; `{refresh: true}` bypasses only that cache, never target derivation or authorization. One unreachable target remains a structured unavailable option and does not fail the other candidates.

- [ ] **Step 4: Persist a redacted probe snapshot in the workflow job**

The snapshot contains `capturedAt`, `targetId`, transport kind, associated folder IDs, OS/architecture, readable workspace-folder facts, CPU count, memory, free disk, and one fact per required CLI: `available`, executable path basename, version, and diagnostic code. Limit every diagnostic field to 2 KiB and omit usernames, hostnames, full home paths, credentials, and raw environment variables. `probe_workspace_targets` advances the job through `probing` to `planning` and replaces only the current pre-validation snapshot.

- [ ] **Step 5: Run probe tests and commit**

Run: `cd client && dart run tool/run_tests.dart test/services/team_generation/team_target_probe_service_test.dart`

Expected: PASS; fake runners observe no mutating commands.

```bash
git add client/lib/services/team_generation/models/team_target_probe.dart client/lib/services/team_generation/team_target_probe_service.dart client/test/services/team_generation/team_target_probe_service_test.dart
git commit -m "feat(team-generation): probe workspace targets safely"
```

## Task 8: Versioned generated-plan parser and pure validator

**Files:**
- Create: `client/lib/services/team_generation/models/generated_team_plan.dart`
- Create: `client/lib/services/team_generation/generated_team_plan_validator.dart`
- Test: `client/test/services/team_generation/generated_team_plan_test.dart`
- Test: `client/test/services/team_generation/generated_team_plan_validator_test.dart`

**Interfaces:**
- Consumes: frozen settings snapshot, current probe snapshot, installed/staged resource IDs, existing expert keys, and raw `validate_team_plan` JSON.
- Produces: `GeneratedTeamPlan`, `GeneratedTeamMemberPlan`, `GeneratedResourcePlan`, normalized `MemberPlacementByTarget`, `GeneratedDestinationLaunch`, deterministic plan/revision JSON, and `GeneratedTeamValidationResult`.

- [ ] **Step 1: Freeze the JSON contract in failing parser tests**

The only accepted top-level shape is:

```json
{
  "schemaVersion": 1,
  "team": {
    "name": "Delivery Team",
    "description": "Ships the request",
    "mode": "mixed"
  },
  "members": [
    {
      "name": "team-lead",
      "role": "Delivery Lead",
      "responsibilities": "Own decomposition and integration",
      "workingMethod": "Delegate, review evidence, integrate",
      "presetId": "strong",
      "replicas": 1,
      "placement": {"local": 1}
    }
  ],
  "resources": {
    "skillIds": ["existing/skill"],
    "pluginIds": [],
    "mcpServerIds": ["existing-mcp"]
  }
}
```

```dart
test('strict parser rejects unknown keys and non-integer replica counts', () {
  expect(
    () => GeneratedTeamPlan.fromJson({...validPlanJson, 'provider': 'secret'}),
    throwsA(isA<FormatException>()),
  );
  expect(
    () => GeneratedTeamPlan.fromJson(planJson(replicas: 1.5)),
    throwsA(isA<FormatException>()),
  );
});

test('canonical revision ignores map insertion order', () {
  final a = GeneratedTeamPlan.fromJson(validPlanJson);
  final b = GeneratedTeamPlan.fromJson(reorderedValidPlanJson);
  expect(a.revision, b.revision);
});
```

- [ ] **Step 2: Run parser tests and confirm missing-model failure**

Run: `cd client && dart run tool/run_tests.dart test/services/team_generation/generated_team_plan_test.dart`

Expected: FAIL because the generated-plan types do not exist.

- [ ] **Step 3: Implement strict decode, canonical encode, and revision hashing**

Reject unknown properties at every object level, blank team/member/role/responsibility/method text, values outside `replicas: 1..8`, and payloads above 128 KiB before decoding. `presetId` may be absent/blank to inherit the fixed team default. Do not accept `cli`, `provider`, `model`, `effort`, profile IDs, expert keys, filesystem paths, commands, or MCP credentials from the model. Canonical JSON recursively sorts map keys, preserves list order, and hashes UTF-8 bytes with SHA-256 for `revision`.

- [ ] **Step 4: Write failing semantic validation tests**

```dart
test('requires 2-5 roles and one singleton canonical lead', () {
  final result = validate(planWith(leads: 2, memberCount: 6));
  expect(result.isValid, isFalse);
  expect(result.issues.map((issue) => issue.code), containsAll([
    'member_count_out_of_range',
    'lead_count_invalid',
  ]));
});

test('rejects live preset drift and unavailable mixed placement', () {
  final result = validate(planWith(
    memberPreset: 'deleted-after-start',
    placement: {'ssh-1': 1},
  ));
  expect(result.issues.map((issue) => issue.code), containsAll([
    'preset_not_in_snapshot',
    'target_cli_unavailable',
  ]));
});

test('mixed preview syncs cli only and preserves first preset as team default', () {
  final result = validate(validMixedPlan);
  final worker = result.preview!.roster.singleWhere((slot) => slot.id == 'worker');
  expect(result.preview!.activePresetId, frozenPool.first.presetId);
  expect(worker.overrides.activePresetId, 'codex-fast');
  expect(worker.overrides.cli, CliTool.codex);
  expect(worker.overrides.provider, isEmpty);
  expect(worker.overrides.model, isEmpty);
  expect(worker.overrides.effort, isEmpty);
});

test('missing preset inherits the fixed team default', () {
  final result = validate(planWith(memberPreset: null));
  final worker = result.preview!.roster.singleWhere((slot) => slot.id == 'worker');
  expect(worker.overrides.activePresetId, TeamProfile.inheritPresetId);
  expect(worker.overrides.cli, isNull);
});
```

- [ ] **Step 5: Implement normalization and every launch invariant**

Normalize IDs with `TeamMemberNaming`; force the lead ID to `team-lead`; reject collisions after normalization. Validate:

- plan `team.mode` exactly equals the frozen settings mode;
- 2–5 member types with non-overlapping roles, unique IDs derived from `name` through `TeamMemberNaming`, and exactly one singleton `team-lead`;
- a blank/missing `presetId` normalizes to `TeamProfile.inheritPresetId`; every explicit ID exists in the frozen pool, and an unknown ID is an error rather than a fallback; the default and every selected preset still exist globally with the same CLI/provider/model/effort digest as the snapshot, otherwise report `preset_deleted_since_start` or `preset_changed_since_start`;
- every requested resource ID is installed or recorded in this workflow's staged-resource set; resolve plugin-contributed skills/MCP through `PluginBundleResolver` and resource providers before judging the bundle;
- every member-local placement contains only probed current folder-backed targets; transpose it to `MemberPlacementByTarget`; every member's counts sum to `replicas`; no zero/negative count;
- native: every preset CLI equals `settings.nativeCli`, every role is placed on one shared target, and that target reports the native CLI available;
- mixed: each target reports the assigned member preset's CLI available;
- lead placement is valid according to `leadPlacementValid` after `prepareMemberPlacementSave`;
- current workspace revision/folder ownership still matches the job snapshot, remote requirements pass existing launch-readiness services, and the constructed preview passes `TeamConfigLaunchValidator`.

Derive each generated expert from `role`, `responsibilities`, and `workingMethod`; build its stable key as `'local/generated/${sha256.convert(utf8.encode(canonicalExpertJson)).toString().substring(0, 24)}'`. Build roster overrides with explicit or inherit `activePresetId`; set `cli` only for a mixed explicit preset; leave `provider/model/effort` empty. Build the preview `TeamProfile` with `activePresetId = frozenPool.first.presetId`, `cli = settings.nativeCli` in native mode or `frozenPool.first.preset.cli` in mixed mode, and the fully resolved resource IDs from the plan.

Derive `GeneratedDestinationLaunch` from the validated lead/native target: keep the frozen Landing project folder and worktree when they belong to that target; otherwise choose the lexicographically first current workspace folder on the target and use its root as working directory. Return that deterministic fallback as a warning in the preview so machine assignment and the actual destination runtime cannot diverge.

Emit warnings, without weakening hard errors, when the lead explicitly uses a lower-ranked preset, all workers are concentrated on one optional target despite alternatives, or an optional target has only partial probe facts.

- [ ] **Step 6: Persist only valid revisions for finalization**

`validate_team_plan` writes the normalized plan, its revision, validation issues, validated destination launch, and probe/settings/workspace revisions to the job. It sets `validatedRevision` only when `isValid`; a later probe, workspace change, or plan replacement clears `validatedRevision` and `validatedDestination`. Return a bounded preview containing team name, member names/roles/presets/CLIs, resources, target assignments, destination folder, and issue codes without exposing credentials.

- [ ] **Step 7: Run parser and validator tests, then commit**

Run: `cd client && dart run tool/run_tests.dart test/services/team_generation/generated_team_plan_test.dart test/services/team_generation/generated_team_plan_validator_test.dart`

Expected: PASS; invalid JSON never reaches commit and mixed overrides contain no duplicated model configuration.

```bash
git add client/lib/services/team_generation/models/generated_team_plan.dart client/lib/services/team_generation/generated_team_plan_validator.dart client/test/services/team_generation/generated_team_plan_test.dart client/test/services/team_generation/generated_team_plan_validator_test.dart
git commit -m "feat(team-generation): validate generated team plans"
```

## Task 9: Catalog generation scope with true staging and promotion

**Files:**
- Create: `client/lib/services/team_generation/catalog/catalog_generation_stager.dart`
- Modify: `client/lib/services/catalog/catalog_kind.dart`
- Modify: `client/lib/services/catalog/catalog_mcp_handler.dart`
- Modify: `client/lib/services/catalog/catalog_mcp_transport.dart`
- Modify: `client/lib/services/catalog/catalog_runtime.dart`
- Modify: `client/lib/services/catalog/catalog_workspace_binder.dart`
- Modify: `client/lib/services/catalog/modules/skill_catalog_module.dart`
- Modify: `client/lib/services/catalog/modules/skill_catalog_tools.dart`
- Modify: `client/lib/services/catalog/modules/plugin_catalog_module.dart`
- Modify: `client/lib/services/catalog/modules/plugin_catalog_tools.dart`
- Modify: `client/lib/services/catalog/modules/mcp_catalog_module.dart`
- Modify: `client/lib/services/catalog/modules/mcp_catalog_tools.dart`
- Modify: `client/lib/services/skill/skill_install_service.dart`
- Modify: `client/lib/services/plugin/plugin_install_service.dart`
- Modify: `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart`
- Test: `client/test/services/catalog/catalog_generation_scope_test.dart`
- Test: `client/test/services/team_generation/catalog/catalog_generation_stager_test.dart`

**Interfaces:**
- Consumes: `CatalogRequest`, `CatalogKindModule`, workflow staging directory, skill/plugin/MCP discovery payloads, `TeamGenerationAuthorizer`, shared `TeamGenerationWorkflowExecutor`.
- Produces: `CatalogBindTo.generation`, `CatalogRequest.workflowId`, `CatalogGenerationStager.stage/reference/update/remove/promote/compensate`, `StagedCatalogResource`, `CatalogUserAction`, and structured `user_action_required`/`generation_staging_unsupported` failures.

- [ ] **Step 1: Write failing scope-isolation tests for all three catalog kinds**

```dart
for (final kind in ['skill', 'plugin', 'mcp']) {
  test('$kind generation install stages without global install or workspace bind', () async {
    final result = await callCatalog(
      kind: kind,
      op: CatalogOp.install,
      bindTo: CatalogBindTo.generation,
      workflowId: 'wf',
    );

    expect(result.boundTo, CatalogBindTo.generation);
    expect(await globalRepository(kind).loadAll(), isEmpty);
    expect((await workspaceConfig.load('ws')).allResourceIds, isEmpty);
    expect(await stager.list('ws', 'wf'), hasLength(1));
  });
}
```

- [ ] **Step 2: Run the scope test and confirm it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/catalog/catalog_generation_scope_test.dart`

Expected: FAIL because `generation` is not a bind scope and modules install globally.

- [ ] **Step 3: Extend request/session context without weakening normal Catalog policy**

Add `CatalogBindTo.generation`, optional `CatalogRequest.workflowId`, and `SessionPurpose/workflowId` to `CatalogMcpSession`. `CatalogRuntime.resolveCatalogSession` populates them from persisted `AppSession`. Normal sessions may use only `workspace`; builder sessions may search/list/read with existing semantics, but every install/import/create/update/unbind/delete must specify `bind_to: generation` and carry the session's workflow ID. `CatalogWorkspaceBinder` continues to reject non-workspace scopes and is never invoked for generation operations.

Add the generation value to each mutating tool's `bind_to` schema. Do not expose `workflow_id` as a model-supplied argument.

- [ ] **Step 4: Require the generation token on the Catalog route**

Extend `resolveCatalogMcpTransportConfig` with optional `teamGenerationToken`; when present, add `X-Team-Generation-Token` to both HTTP and local-bridge headers. At the gateway, a `teamGeneration` Catalog session must pass `TeamGenerationAuthorizer.authorize` before handler dispatch. A normal session presenting `bind_to: generation`, or a builder presenting `bind_to: workspace`, returns `code=bind_scope_forbidden` without calling a module.

- [ ] **Step 5: Add stage/promote primitives below repositories**

Add public staging APIs that copy validated payloads into a caller-provided directory without updating manifests or global indexes:

```dart
Future<StagedSkillInstall> stageFromDirectory({
  required String sourceDir,
  required String stagingDir,
});

Future<Skill> promoteStaged(StagedSkillInstall staged, {required bool overwrite});

Future<StagedPluginInstall> stageFromDirectory({
  required String sourceDir,
  required String stagingDir,
});

Future<Plugin> promoteStaged(StagedPluginInstall staged, {required bool overwrite});
```

For MCP, write a validated credential-preserving draft only below `staging/mcp/<id>.json`; call `McpRepository.upsert` only from promotion. Validate staged relative paths with `CatalogPathSandbox`; reject symlinks escaping the staged root and cap one resource at 20 MiB.

- [ ] **Step 6: Implement module delegation and safe acquisition limits**

Each module starts mutating handlers by delegating to one stager entry that runs through the shared workflow executor:

```dart
if (req.bindTo == CatalogBindTo.generation) {
  return generationStager.handleMcpMutation(kind: kind, op: op, request: req);
}
```

`handleMcpMutation` enters `TeamGenerationWorkflowExecutor`, reauthorizes/rechecks active job state, reserves its receipt, and holds that queue slot through staging plus the receipt write; internal promotion calls from finalization are already inside the same executor and use non-enqueuing methods. Existing globally installed resources are recorded as workflow references and not copied. New declarative directory/zip/git payloads are acquired into `staging/` and validated there. Authentication, credential, OAuth, or license steps return `code=user_action_required` plus a typed `CatalogUserAction` that identifies an existing settings/auth route; no secret enters the job or tool result. If a discovery result requires a script, package manager, arbitrary install command, or `SkillAcquisitionEngine` side-effectful instruction, return `code=generation_staging_unsupported` with the listing ID and a safe user-action message; do not execute it. Within generation scope, update/unbind/delete may only alter this workflow's staged payload/reference set.

- [ ] **Step 7: Write promotion and compensation tests**

```dart
test('promotion is idempotent by staged digest', () async {
  final staged = await stager.stageSkill(workflow, skillFixture);
  final first = await stager.promote(workflow, staged.ref);
  final second = await stager.promote(workflow, staged.ref);
  expect(second.id, first.id);
  expect(await skillRepository.loadAll(), hasLength(1));
});

test('compensation removes only unreferenced resources created by this workflow', () async {
  await seedInstalledSkill('shared');
  final shared = await stager.reference(workflow, kind: 'skill', id: 'shared');
  final created = await stager.stageSkill(workflow, skillFixture);
  await stager.promoteAll(workflow);

  await stager.compensate(workflow);

  expect(await skillRepository.findById(shared.id), isNotNull);
  expect(await skillRepository.findById(created.id), isNull);
});

test('compensation retains a promoted resource another workflow now references', () async {
  final created = await stager.stageSkill(workflow, skillFixture);
  await stager.promoteAll(workflow);
  await stager.reference(otherWorkflow, kind: 'skill', id: created.id);
  await stager.compensate(workflow);
  expect(await skillRepository.findById(created.id), isNotNull);
});
```

- [ ] **Step 8: Run staging tests and existing Catalog regression tests**

Run: `cd client && dart run tool/run_tests.dart test/services/catalog/catalog_generation_scope_test.dart test/services/team_generation/catalog/catalog_generation_stager_test.dart test/services/catalog/catalog_mcp_handler_test.dart test/services/catalog/catalog_mcp_gateway_test.dart test/services/catalog/catalog_workspace_binder_test.dart`

Expected: PASS; ordinary workspace Catalog behavior is unchanged and generation never mutates global/workspace state before promotion.

- [ ] **Step 9: Commit the catalog staging slice**

```bash
git add client/lib/services/team_generation/catalog/catalog_generation_stager.dart client/lib/services/catalog/catalog_kind.dart client/lib/services/catalog/catalog_mcp_handler.dart client/lib/services/catalog/catalog_mcp_transport.dart client/lib/services/catalog/catalog_runtime.dart client/lib/services/catalog/catalog_workspace_binder.dart client/lib/services/catalog/modules/skill_catalog_module.dart client/lib/services/catalog/modules/skill_catalog_tools.dart client/lib/services/catalog/modules/plugin_catalog_module.dart client/lib/services/catalog/modules/plugin_catalog_tools.dart client/lib/services/catalog/modules/mcp_catalog_module.dart client/lib/services/catalog/modules/mcp_catalog_tools.dart client/lib/services/skill/skill_install_service.dart client/lib/services/plugin/plugin_install_service.dart client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart client/test/services/catalog/catalog_generation_scope_test.dart client/test/services/team_generation/catalog/catalog_generation_stager_test.dart
git commit -m "feat(team-generation): stage catalog mutations by workflow"
```

## Task 10: Receipt-driven experts, profile, and placement commit

**Files:**
- Create: `client/lib/services/team_generation/generated_team_commit_service.dart`
- Create: `client/lib/services/provider/team_profile_resource_provisioner.dart`
- Modify: `client/lib/services/expert_hub/local_expert_store.dart`
- Modify: `client/lib/cubits/team/team_resource_sync_service.dart`
- Create: `client/lib/cubits/team/generated_team_state_publisher.dart`
- Modify: `client/lib/cubits/launch_profile_cubit.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/services/team_generation/generated_team_commit_service_test.dart`
- Test: `client/test/services/provider/team_profile_resource_provisioner_test.dart`
- Test: `client/test/cubits/team/generated_team_state_publisher_test.dart`

**Interfaces:**
- Consumes: one `GeneratedTeamValidationResult` whose revision equals `job.validatedRevision`, `CatalogGenerationStager`, `LocalExpertStore`, `LaunchProfileRepository`, `prepareMemberPlacementSave`, `TeamProfileResourceProvisioner`, `SessionRepository`.
- Produces: `GeneratedTeamCommitResult(team, workspace, preparedPlacement)`, deterministic team/expert IDs, persisted receipts, `GeneratedTeamStatePublisher`, and `LaunchProfileCubit.publishPersistedTeam`.

- [ ] **Step 1: Write failing happy-path transaction tests**

```dart
test('commits resources, experts, profile, and placement in order', () async {
  final result = await service.commit(
    workspace: workspace,
    workflowId: 'wf-12345678',
    validatedRevision: validResult.revision,
  );

  expect(result.team.id, reservedTeam.id);
  expect(events, [
    startsWith('promote:'),
    startsWith('expert:'),
    'profile:${reservedTeam.id}',
    'placement:${reservedTeam.id}',
    'provision:${reservedTeam.id}',
    'publish:${reservedTeam.id}',
  ]);
  expect(result.team.activePresetId, frozenPool.first.presetId);
  expect(result.team.roster.every((slot) => slot.expertKey.startsWith('local/generated/')), isTrue);
});

test('second commit returns receipt values without duplicate writes', () async {
  final first = await service.commit(
    workspace: workspace,
    workflowId: 'wf-12345678',
    validatedRevision: validResult.revision,
  );
  final writesAfterFirst = writeCounter.value;

  final second = await service.commit(
    workspace: workspace,
    workflowId: 'wf-12345678',
    validatedRevision: validResult.revision,
  );

  expect(second.team.id, first.team.id);
  expect(writeCounter.value, writesAfterFirst);
});

test('normal name collision reserves a stable suffixed name and id', () async {
  await profileRepository.save(existingTeam(name: 'Delivery Team'));
  final first = await service.commit(
    workspace: workspace,
    workflowId: 'wf-12345678',
    validatedRevision: validResult.revision,
  );
  final reservation = (await store.read('ws', 'wf-12345678'))!.teamReservation;
  expect(first.team.name, reservation.name);
  expect(first.team.id, reservation.id);
  expect(first.team.id, isNot(existingTeamId));
  expect(await profileRepository.loadTeamProfiles(), hasLength(2));
});
```

- [ ] **Step 2: Run commit tests and confirm missing-service failure**

Run: `cd client && dart run tool/run_tests.dart test/services/team_generation/generated_team_commit_service_test.dart`

Expected: FAIL because no generated-team transaction exists.

- [ ] **Step 3: Implement deterministic materialization and per-effect receipts**

Reserve name and ID before the first side effect. Start with the normalized generated display name and `TeamMemberNaming.slugTeamId`; if either collides with an existing unrelated profile, suffix both with the first eight characters from `teamGenerationStableId('', workflowId)`. Persist the final pair in `job.teamReservation` and always reuse it. Never overwrite a profile whose digest does not match the reserved workflow result. For every effect, atomically write a `reserved` receipt, perform the effect, then write `succeeded(value, digest)`; on an ambiguous exception read the repository and set `succeeded` if the expected digest exists, otherwise `unknown`.

Materialize `DiscoverableMember` records from normalized member role/responsibility/working-method fields using the content-derived keys from Task 8 and `LocalExpertStore.putClone`. Materialize `TeamRosterSlot`s referencing those expert keys and preserve only the validated preset/CLI/replica overrides. Extend `LocalExpertStore` with injected-filesystem `containsKey` and `delete`; compensation deletes only keys created by this workflow that no persisted team references.

- [ ] **Step 4: Mark profile persistence as the forward-recovery boundary**

Commit order is fixed:

1. re-read the job and reject a stale/missing `validatedRevision`;
2. promote workflow resources and resolve final IDs;
3. persist generated experts;
4. persist the final `TeamProfile` with `LaunchProfileRepository.save`;
5. build `PreparedMemberPlacementSave` and persist workspace placement;
6. await team profile-tree creation and team skill/plugin/MCP resource synchronization;
7. publish the already persisted team/workspace snapshots to cubits.

Before the profile receipt succeeds, compensate newly promoted resources and newly created generated experts on failure. After the profile receipt succeeds, do not delete the team or dependencies: persist the error and let recovery finish placement/publication/launch forward.

Extract `TeamProfileResourceProvisioner` from the target-specific parts of `TeamResourceSyncService`: it accepts an explicit `TeamProfile`, calls `ConfigProfileService.ensureTeamProfile`, validates installed plugins, resolves plugin MCP contributions, and calls `ProfileMcpLinkerService.syncForProfile`. Existing selected-team sync methods delegate to it, so generated commit never changes selected cubit state to provision resources.

- [ ] **Step 5: Add an explicit post-persistence publication adapter**

```dart
void publishPersistedTeam(TeamProfile team, {bool select = true});

abstract interface class GeneratedTeamStatePublisher {
  Future<void> publish({
    required TeamProfile team,
    required Workspace workspace,
  });
}
```

`GeneratedTeamCommitService` validates `leadValid`, calls `SessionRepository.updateWorkspaceMemberPlacement` itself, and treats a missing workspace as a post-profile recoverable failure. Only after placement and resource provisioning receipts succeed does it call `GeneratedTeamStatePublisher`. Its cubit adapter patches `ChatCubit` with the already persisted workspace and calls `LaunchProfileCubit.publishPersistedTeam`, which upserts/selects by ID without writing disk or rescanning repositories.

- [ ] **Step 6: Write failure-boundary tests**

```dart
test('failure before profile compensates workflow-owned effects', () async {
  profileRepository.failNextSave();
  await expectLater(() => commit(), throwsA(isA<TeamGenerationCommitException>()));
  expect(await stager.promotedBy('wf'), isEmpty);
  expect(await generatedExperts(), isEmpty);
  expect((await store.read('ws', 'wf'))!.receipts['profile']?.state, isNot(TeamGenerationReceiptState.succeeded));
});

test('failure after profile retains visible team for forward recovery', () async {
  placementStore.failNextSave();
  await expectLater(() => commit(), throwsA(isA<TeamGenerationCommitException>()));
  expect(await profileRepository.findTeam(reservedTeam.id), isNotNull);
  expect((await store.read('ws', 'wf'))!.receipts['profile']!.state, TeamGenerationReceiptState.succeeded);
  expect(await stager.promotedBy('wf'), isNotEmpty);
});
```

- [ ] **Step 7: Run commit and publication tests, then commit**

Run: `cd client && dart run tool/run_tests.dart test/services/team_generation/generated_team_commit_service_test.dart test/services/provider/team_profile_resource_provisioner_test.dart test/cubits/team/generated_team_state_publisher_test.dart`

Expected: PASS; the profile-success receipt is the only rollback/forward boundary.

```bash
git add client/lib/services/team_generation/generated_team_commit_service.dart client/lib/services/provider/team_profile_resource_provisioner.dart client/lib/services/expert_hub/local_expert_store.dart client/lib/cubits/team/team_resource_sync_service.dart client/lib/cubits/team/generated_team_state_publisher.dart client/lib/cubits/launch_profile_cubit.dart client/lib/cubits/chat_cubit.dart client/test/services/team_generation/generated_team_commit_service_test.dart client/test/services/provider/team_profile_resource_provisioner_test.dart client/test/cubits/team/generated_team_state_publisher_test.dart
git commit -m "feat(team-generation): commit generated teams transactionally"
```

## Task 11: Idempotent destination session launch and exact prompt handoff

**Files:**
- Create: `client/lib/services/team_generation/team_generation_handoff_service.dart`
- Create: `client/lib/services/team_generation/team_generation_session_port.dart`
- Modify: `client/lib/services/prompt_delivery/prompt_delivery.dart`
- Modify: `client/lib/services/prompt_delivery/prompt_delivery_coordinator.dart`
- Modify: `client/lib/cubits/chat/tab_member_pty_delivery.dart`
- Modify: `client/lib/cubits/chat/tab_session_runtime_coordinator.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/services/team_generation/team_generation_handoff_service_test.dart`
- Test: `client/test/services/prompt_delivery/prompt_delivery_idempotency_test.dart`

**Interfaces:**
- Consumes: committed `TeamProfile`, validated `GeneratedDestinationLaunch`, frozen destination security policy, `TeamGenerationSessionPort`, `PromptDeliveryStore`, immutable `job.originalPrompt`, and injected `GeneratedTeamSelectionWriter`.
- Produces: deterministic destination session and delivery receipts, `DirectPromptDeliveryResult`, selected/open destination tab, `TeamGenerationHandoffResult(destinationSessionId, deliveryId)`, and explicit `confirmUnknownDelivery/retryUnknownDelivery` recovery operations.

Define `TeamGenerationSessionPort` with purpose-specific `createBuilder`, `createDestination`, `open`, `rename`, `sessionById`, `waitForInputReady`, `deliverTracked`, `delete`, `select`, and per-session activity-stream methods. Its methods derive the builder/destination member IDs internally and accept no arbitrary deletion target from MCP input. Workflow services depend only on this port; the Flutter adapter is added in Task 13.

- [ ] **Step 1: Write failing prompt-delivery idempotency tests**

```dart
test('explicit delivery id returns the same record and never resubmits', () async {
  final first = await coordinator.submit(PromptDeliveryRequest(
    seat: seat,
    cli: CliTool.codex,
    text: 'exact\nrequest',
    deliveryId: 'teamgen-wf-0',
  ));
  await coordinator.issueSubmit(first.id);

  final restored = await coordinator.submit(PromptDeliveryRequest(
    seat: seat,
    cli: CliTool.codex,
    text: 'exact\nrequest',
    deliveryId: 'teamgen-wf-0',
  ));

  expect(restored.id, first.id);
  expect(commands.submitCount, 1);
});

test('explicit delivery id rejects a mismatched seat or text', () async {
  await coordinator.submit(request(deliveryId: 'fixed', text: 'one'));
  expect(
    () => coordinator.submit(request(deliveryId: 'fixed', text: 'two')),
    throwsA(isA<StateError>()),
  );
});
```

- [ ] **Step 2: Add optional delivery IDs without changing normal sends**

Add `String? deliveryId` to `PromptDeliveryRequest` and the two Chat runtime delivery methods. In `PromptDeliveryCoordinator.submit`, when an explicit ID exists, read it before active-seat recovery; return it only if seat, CLI, and exact text match. Otherwise create with that ID. Calls without an explicit ID retain the current generated-ID behavior.

Add a tracked direct-delivery variant returning `DirectPromptDeliveryResult(id, submissionResult, durableState)`; keep the existing string-returning method as a compatibility wrapper for ordinary callers. It handles an existing explicit record as follows: `created/waitingForInputSurface/staged` may advance to submit; `submitIssued/confirmed/submittedUnknown` returns its ID without issuing submit; `failed` returns its ID without issuing submit. This branch must preserve the existing queue fence and direct-to-PTY behavior.

- [ ] **Step 3: Write failing destination creation and exact-delivery tests**

```dart
test('creates one team session, selects it, and sends the byte-identical prompt to lead', () async {
  final result = await service.handoff(workspace: workspace, workflowId: 'wf');

  expect(chat.createRequests, hasLength(1));
  expect(chat.createRequests.single.team!.id, committedTeam.id);
  expect(chat.selectedSessionId, result.destinationSessionId);
  expect(chat.readyCalls.single, ('team-lead', true));
  expect(chat.deliveryCalls.single.message, job.originalPrompt);
  expect(chat.deliveryCalls.single.directToPty, isTrue);
});

test('recovery reopens destination and retains ambiguous submit without replay', () async {
  await seedDestinationReceipt('destination');
  await seedPromptDelivery(
    id: 'teamgen-wf-0',
    state: PromptDeliveryState.submitIssued,
    text: job.originalPrompt,
  );

  await expectLater(
    () => service.handoff(workspace: workspace, workflowId: 'wf'),
    throwsA(isA<PromptDeliveryUnknownException>()),
  );
  expect(chat.openRequests, hasLength(1));
  expect(chat.deliveryCalls, isEmpty);
  expect((await store.read('ws', 'wf'))!.error!.code, 'prompt_delivery_unknown');
});
```

- [ ] **Step 4: Reserve and reuse a deterministic destination session**

Under the workflow queue, reserve `destinationSessionId = teamGenerationStableId('teamgen-', workflowId)` before calling the session port. Invoke `GeneratedTeamSelectionWriter` to select/publish the committed team and persist its Landing recent-team state. If `sessionById` returns no session, call `createDestination` with the committed team, canonical lead member, the validator's `GeneratedDestinationLaunch` project folder/working directory, frozen launch security policy, and fixed session ID; otherwise call `open`. The port adapter delegates to `ChatCubit.requestCreateAndOpenSession/requestOpenSession`. Require `SessionOpenStatus.opened`, then persist the destination receipt and phase `launching`. The existing launch gates and `SessionLifecycleService` remain the only path that provisions/connects member terminals.

- [ ] **Step 5: Deliver the immutable prompt with recovery-safe attempts**

After the destination is the selected tab, call:

```dart
await sessionPort.waitForInputReady(
  destinationSessionId,
  TeamMemberNaming.teamLeadName,
  directToPty: true,
);
final delivery = await sessionPort.deliverTracked(
  destinationSessionId,
  TeamMemberNaming.teamLeadName,
  job.originalPrompt,
  directToPty: true,
  deliveryId: reservedDeliveryId,
);
```

Reserve `teamGenerationStableId('teamgen-prompt-$attempt-', workflowId)` in the job before the call. When the tracked call returns `PromptSubmissionResult.submitted`, atomically record the succeeded delivery receipt before advancing; a later exact runtime confirmation may strengthen its diagnostics but is not required. Explicit `dropped/failed` outcomes guarantee the fence did not submit and may reserve a new attempt after readiness. If recovery finds `submitIssued` or `submittedUnknown` without a succeeded job receipt, the prior effect is ambiguous: never replay it automatically, keep both sessions, and surface `prompt_delivery_unknown` through the existing failed-message/recovery UI for explicit user resolution. Cap live no-effect retries at three per coordinator run.

`confirmUnknownDelivery` verifies the ambiguous delivery belongs to this workflow/destination/lead and records a user-confirmed succeeded receipt without PTY IO. `retryUnknownDelivery` requires a separate explicit duplicate-risk confirmation, records that authorization, reserves a new delivery ID, and performs one tracked retry. Neither operation accepts arbitrary session/member/text input.

- [ ] **Step 6: Preserve exact text and title behavior**

Do not trim, normalize, prefix, or append the prompt sent to PTY. Use the existing session-title/first-user-line capture on that exact delivery; the builder prompt and generated summary never become the destination's first user message. Set phase `delivering` before readiness and `delivered` only after the succeeded delivery receipt.

- [ ] **Step 7: Run handoff and prompt-delivery regressions, then commit**

Run: `cd client && dart run tool/run_tests.dart test/services/prompt_delivery/prompt_delivery_idempotency_test.dart test/services/team_generation/team_generation_handoff_service_test.dart test/cubits/chat/tab_member_pty_delivery_test.dart`

Expected: PASS; crashes at every receipt boundary create at most one destination session and at most one submitted prompt effect.

```bash
git add client/lib/services/team_generation/team_generation_handoff_service.dart client/lib/services/team_generation/team_generation_session_port.dart client/lib/services/prompt_delivery/prompt_delivery.dart client/lib/services/prompt_delivery/prompt_delivery_coordinator.dart client/lib/cubits/chat/tab_member_pty_delivery.dart client/lib/cubits/chat/tab_session_runtime_coordinator.dart client/lib/cubits/chat_cubit.dart client/test/services/team_generation/team_generation_handoff_service_test.dart client/test/services/prompt_delivery/prompt_delivery_idempotency_test.dart
git commit -m "feat(team-generation): hand off exact prompt idempotently"
```

## Task 12: Response-flush, builder-idle, and cleanup gates

**Files:**
- Create: `client/lib/services/team_generation/team_generation_builder_idle_waiter.dart`
- Create: `client/lib/services/team_generation/team_generation_cleanup_service.dart`
- Test: `client/test/services/team_generation/team_generation_builder_idle_waiter_test.dart`
- Test: `client/test/services/team_generation/team_generation_cleanup_service_test.dart`

**Interfaces:**
- Consumes: `TeamGenerationSessionPort` activity stream backed by `SessionActivity.isReadyToChat`, delivery receipt, finalize-response-flushed receipt, purpose-checked port deletion, `TeamGenerationAuthorizer`.
- Produces: `TeamGenerationBuilderIdleWaiter.wait`, three-gate `TeamGenerationCleanupService.cleanup`, retained recoverable builder on timeout/failure, and compact complete tombstone.

- [ ] **Step 1: Write failing idle/quiet-window tests**

```dart
test('waits for ready and a quiet window after finalize response', () async {
  final waiting = waiter.wait(
    sessionId: 'builder',
    quietWindow: const Duration(milliseconds: 750),
    timeout: const Duration(seconds: 30),
  );
  activities.emit('builder', busyActivity);
  activities.emit('builder', readyActivity);
  fakeAsync.elapse(const Duration(milliseconds: 500));
  activities.emit('builder', busyActivity);
  activities.emit('builder', readyActivity);
  fakeAsync.elapse(const Duration(milliseconds: 750));

  expect(await waiting, TeamGenerationBuilderIdleResult.idle);
});

test('timeout is recoverable and does not imply idle', () async {
  final result = await waiter.wait(
    sessionId: 'builder',
    quietWindow: const Duration(milliseconds: 750),
    timeout: const Duration(seconds: 1),
  );
  expect(result, TeamGenerationBuilderIdleResult.timeout);
});
```

- [ ] **Step 2: Implement the existing activity signal adapter**

Read the current activity first, then subscribe through `TeamGenerationSessionPort`. Its cubit adapter maps `ChatCubit.state.sessionActivities[sessionId]?.isReadyToChat`; start/restart the quiet timer only while ready, and cancel it on any busy transition or session disappearance. Return `missing` separately so recovery can proceed when a prior cleanup already removed the builder. Inject timer/clock behavior for tests; do not infer idle from terminal output text.

- [ ] **Step 3: Write failing cleanup-gate tests**

```dart
test('does not delete before delivery, response flush, and idle are all durable', () async {
  for (final missing in ['delivery', 'responseFlush', 'idle']) {
    final harness = cleanupHarness(missingGate: missing);
    final result = await harness.service.cleanup(workflowId: 'wf');
    expect(result, TeamGenerationCleanupResult.deferred);
    expect(harness.deletedSessions, isEmpty);
  }
});

test('deletes builder then scrubs staging, revokes token, and compacts job', () async {
  final harness = cleanupHarness();
  await harness.service.cleanup(workflowId: 'wf');

  expect(harness.events, [
    'delete-session:builder',
    'delete-staging:wf',
    'revoke-token:wf',
    'compact-job:wf',
  ]);
  expect((await harness.store.read('ws', 'wf'))!.phase, TeamGenerationPhase.complete);
});
```

- [ ] **Step 4: Implement ordered, idempotent cleanup**

Require succeeded `promptDelivery` and `finalizeResponseFlushed` receipts. Wait for idle; a timeout records `cleanup_waiting_for_builder_idle`, leaves phase `delivered`, and returns without deletion. Once idle succeeds, persist `builderIdle` receipt and phase `cleaning`, then:

1. verify builder ID differs from destination ID;
2. call the session port's purpose/workflow-checked delete only if the builder still exists;
3. verify `SessionRepository.findById(builderId) == null` and persist `builderDeleted`;
4. delete workflow staging and persist `stagingDeleted`;
5. revoke the token;
6. call `TeamGenerationJobStore.compactComplete`.

Every completed step is skipped on recovery. Never delete the destination session or committed profile as compensation.

- [ ] **Step 5: Connect the gateway flush callback to a durable receipt**

The `finalize_team_generation` handler first persists `finalizeAccepted` with the canonical plan revision and idempotency key, then returns a success payload containing `{accepted: true, workflowId, phase: "committing"}` plus an `afterResponseFlushed` callback. The callback first persists the `finalizeResponseFlushed` succeeded receipt and only then dispatches commit/handoff/cleanup. If the process dies after acceptance but before the flush receipt, recovery may finish commit/handoff forward but must retain the builder until a repeated idempotent finalization produces a durable flush receipt.

- [ ] **Step 6: Run cleanup tests and commit**

Run: `cd client && dart run tool/run_tests.dart test/services/team_generation/team_generation_builder_idle_waiter_test.dart test/services/team_generation/team_generation_cleanup_service_test.dart test/services/team_bus/team_composer_mcp_gateway_test.dart`

Expected: PASS; timeout and crash tests leave the builder recoverable, while a fully gated run removes it once.

```bash
git add client/lib/services/team_generation/team_generation_builder_idle_waiter.dart client/lib/services/team_generation/team_generation_cleanup_service.dart client/lib/services/team_generation/mcp/team_composer_mcp_handler.dart client/test/services/team_generation/team_generation_builder_idle_waiter_test.dart client/test/services/team_generation/team_generation_cleanup_service_test.dart client/test/services/team_bus/team_composer_mcp_gateway_test.dart
git commit -m "feat(team-generation): gate builder cleanup safely"
```

## Task 13: Coordinator, recovery policy, builder MCP injection, and app wiring

**Files:**
- Create: `client/lib/services/team_generation/team_generation_coordinator.dart`
- Create: `client/lib/services/team_generation/team_generation_recovery_service.dart`
- Create: `client/lib/cubits/team_generation_cubit.dart`
- Create: `client/lib/cubits/team/cubit_team_generation_session_port.dart`
- Modify: `client/lib/services/launch/session_shell_connector.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/main.dart`
- Test: `client/test/services/team_generation/team_generation_coordinator_test.dart`
- Test: `client/test/services/team_generation/team_generation_recovery_service_test.dart`
- Test: `client/test/services/session/team_generation_mcp_injection_test.dart`
- Test: `client/test/cubits/team/cubit_team_generation_session_port_test.dart`

**Interfaces:**
- Consumes: AI feature settings/presets, generation settings store, all Tasks 4–12 services/ports, gateway and Catalog runtime; only the app-layer port adapter consumes `ChatCubit`.
- Produces: `TeamGenerationCoordinator.preflight/start/finalize/cancel/retry/confirmUnknownDelivery/retryUnknownDelivery`, `TeamGenerationRecoveryService.recoverAll`, `TeamGenerationCubit`, and purpose-aware MCP injection for builder sessions.

- [ ] **Step 1: Write the failing frozen-generator recovery test**

```dart
test('restart uses the job generator snapshot after global AI settings change', () async {
  await seedCreatedWorkflow(generator: codexGeneratorSnapshot);
  await aiSettings.save(AiFeatureId.teamGenerate, claudeFeatureSetting);
  await recovery.recoverAll();
  expect(sessionPort.openedBuilderIdentity, codexGeneratorSnapshot.toBuilderIdentity());
});
```

Use the `TeamGenerationGeneratorSnapshot` defined in Task 1. The later implementation resolves it once from `resolveAiFeatureSetting(AiFeatureId.teamGenerate)` during preflight, converts a missing `activePresetId` to the empty provenance string, and persists it in `TeamGenerationJob`; no credentials are stored.

- [ ] **Step 2: Write failing preflight/start tests**

```dart
test('preflight returns all actionable issues without creating a job', () async {
  final result = await coordinator.preflight(
    workspace: workspace,
    originalPrompt: ' ',
  );
  expect(result.issues.map((issue) => issue.code), containsAll([
    'description_required',
    'team_generate_ai_not_configured',
    'model_pool_empty',
  ]));
  expect(await jobStore.listAll(workspace.workspaceId), isEmpty);
});

test('start creates and opens a visible purpose-tagged simple builder', () async {
  final workflow = await coordinator.start(
    workspace: workspace,
    originalPrompt: 'Build the release pipeline',
    repo: sessionRepository,
  );

  final request = chat.createRequests.single;
  expect(request.isPersonal, isTrue);
  expect(request.purpose, SessionPurpose.teamGeneration);
  expect(request.workflowId, workflow.workflowId);
  expect(request.expertKey, 'teampilot/builtin/team-builder');
  expect(request.simpleIdentity!.cli, generatorSnapshot.cli);
  expect(chat.selectedSessionId, workflow.builderSessionId);
});
```

- [ ] **Step 3: Implement preflight and visible builder start**

Preflight accumulates localized issue codes for blank prompt, missing/unconfigured `teamGenerate` feature, incompatible generator CLI, no effective pool, incompatible native/mixed pool, invalid frozen project/worktree selection, and no live workspace folder target. It has no side effects. Immediately before job creation, snapshot the exact composed message, Landing project/worktree/security choices, workspace folder IDs/targets, and a deterministic workspace revision over those launch-relevant fields.

On success, generate workflow and builder session IDs, create the job first, then call `TeamGenerationSessionPort.createBuilder` with the frozen generator identity, frozen project folder/working directory, `purpose: teamGeneration`, matching `workflowId`, built-in builder expert, fixed session ID, capability-derived non-escalating builder security policy, `emptyDisplayTitleFallback: 'Team Builder'`, and `preserveWorkbenchView: true`. After persistence, rename it with `buildTeamGenerationBuilderTitle(job.originalPrompt, maxLength: 60)`, which sanitizes the first user line and prefixes `Building team · `. Wait for its input surface and send one deterministic tracked kickoff delivery constructed exactly as:

```dart
final kickoff =
    'Build and launch the optimal TeamPilot team for the task below.\n'
    'Follow the managed Team Builder skill and use Team Composer until '
    'finalize_team_generation succeeds.\n\n'
    '${job.originalPrompt}';
```

Store a succeeded kickoff delivery receipt only when the tracked adapter returns `submitted`. On restart, never replay an unreceipted `submitIssued/submittedUnknown` kickoff automatically; retain the builder with `builder_kickoff_delivery_unknown` and offer a guarded user retry. The job remains independent from the tab, so closing/reopening the tab does not cancel generation.

If builder creation returns a non-open status before its persistence receipt, mark cancellation, remove any staged tab/session snapshot through the port, and delete the orphaned workflow directory before returning the localized start failure.

- [ ] **Step 4: Write failing purpose-aware MCP injection tests**

```dart
test('builder gets catalog and composer with one rotated workflow token', () async {
  final servers = await resolver.forSession(builderSession, localSeat);
  expect(servers.keys, containsAll(['teampilot', 'team-composer']));
  expect(header(servers['teampilot']!, 'X-Team-Generation-Token'), token);
  expect(header(servers['team-composer']!, 'X-Team-Generation-Token'), token);
});

test('normal simple session gets catalog only and no generation header', () async {
  final servers = await resolver.forSession(normalSession, localSeat);
  expect(servers.keys, contains('teampilot'));
  expect(servers.keys, isNot(contains('team-composer')));
  expect(jsonEncode(servers), isNot(contains('X-Team-Generation-Token')));
});
```

- [ ] **Step 5: Inject builder MCPs at the existing shell-connector seam**

Make `_extraMcpServersWithCatalog` asynchronous and pass the full persisted `AppSession`. For `teamGeneration`, issue/rotate one token with `TeamGenerationAuthorizer`, add it to the Catalog transport, and merge `TeamComposerMcpTransport.buildConfig` using the same local bridge or remote agent-status tunnel binding. For normal sessions retain the exact existing Catalog config. If token issuance fails, abort builder connection with a typed launch error; never launch a builder without Composer authorization.

- [ ] **Step 6: Implement finalize dispatch and serialized workflow commands**

Serialize `finalize/cancel/retry` through the shared `TeamGenerationWorkflowExecutor`; do not hold the job store's atomic-write lock while performing repository, runtime, or PTY effects, and call only non-enqueuing substeps from inside the executor. `finalize(workflowId, revision, idempotencyKey)` rechecks the accepted key and durable validated revision, advances through commit, handoff, and cleanup, and emits job snapshots after every phase. Concurrent/repeated calls join the queued/in-flight result or return the existing terminal receipt. `retry` calls `TeamGenerationJobStore.resumeFailed`, which restores only the recorded safe phase and clears the structured error. `cancel` is accepted only before the profile-success receipt; it records cancellation before stopping effects, then stops/deletes the builder, compensates staging, and removes the cancelled workflow directory last. After profile persistence it returns `cancel_too_late` and recovery continues forward.

- [ ] **Step 7: Write the recovery matrix before implementing recovery**

```dart
final cases = <RecoveryCase>[
  RecoveryCase('created, builder missing', action: RecoveryAction.cancelOrphanPrecommit),
  RecoveryCase('planning, builder exists', action: RecoveryAction.reopenBuilder),
  RecoveryCase('validated, finalize not flushed', action: RecoveryAction.reopenBuilder),
  RecoveryCase('finalize accepted, response not flushed', action: RecoveryAction.commitForwardRetainBuilder),
  RecoveryCase('flush receipt, no profile', action: RecoveryAction.commitForward),
  RecoveryCase('profile receipt, no placement', action: RecoveryAction.commitForward),
  RecoveryCase('placement receipt, no destination', action: RecoveryAction.launchForward),
  RecoveryCase('submitIssued prompt', action: RecoveryAction.cleanupForward),
  RecoveryCase('delivered, builder busy', action: RecoveryAction.deferCleanup),
];

for (final recoveryCase in cases) {
  test(recoveryCase.name, () async {
    await seed(recoveryCase);
    await recovery.recoverAll();
    expect(observedAction, recoveryCase.action);
  });
}
```

- [ ] **Step 8: Implement bootstrap recovery with no destructive guessing**

Scan all workspace job directories. Validate job/session/profile links before acting. Policy:

- pre-profile with no `finalizeAccepted` receipt: reopen a matching builder and reuse its kickoff delivery receipt; if the builder is missing, atomically cancel and clean the orphaned job instead of creating a privileged replacement;
- `finalizeAccepted`, a flush receipt, or a profile-success receipt: finish commit/handoff forward; without a flush receipt retain/reopen the builder and defer cleanup so the agent can repeat the accepted idempotent call;
- `failed` before profile: surface retry/cancel in the retained builder and wait for the user;
- `failed` after profile: automatically retry forward idempotent steps;
- `delivered/cleaning`: retry only cleanup gates;
- malformed or cross-workspace references: retain files, mark a sanitized `recovery_integrity_error`, and never delete a session/profile.

- [ ] **Step 9: Wire the object graph in dependency order**

In `app_shell.dart`, construct job/settings stores, authorizer, Catalog stager/runtime, Composer handler, gateway attachments, validator, commit/handoff/cleanup services, coordinator, and recovery service. In the Flutter composition layer construct `CubitTeamGenerationSessionPort` and `CubitGeneratedTeamStatePublisher`; services receive their interfaces, not cubits. Expose the coordinator/settings store in `AppShell`. In `main.dart`, provide one `TeamGenerationCubit` beside `AiFeatureSettingsCubit`, `CliPresetsCubit`, `LaunchProfileCubit`, and `ChatCubit`. Add a one-shot `onWorkbenchPortReady` callback at the existing Chat workbench-port attachment seam; it invokes `recoverAll()` only after Chat/LaunchProfile cubits, the gateway, workbench port, and session repository are ready. Guard it against duplicate widget attachments, log failures with `AppLogger`, and keep the UI usable.

- [ ] **Step 10: Run coordinator, injection, and recovery tests**

Run: `cd client && dart run tool/run_tests.dart test/services/team_generation/team_generation_coordinator_test.dart test/services/team_generation/team_generation_recovery_service_test.dart test/services/session/team_generation_mcp_injection_test.dart test/cubits/team/cubit_team_generation_session_port_test.dart`

Expected: PASS; a restarted workflow follows the matrix and no normal session receives Composer privileges.

- [ ] **Step 11: Commit orchestration and wiring**

```bash
git add client/lib/models/team_generation_settings.dart client/lib/services/team_generation/models/team_generation_job.dart client/lib/services/team_generation/team_generation_coordinator.dart client/lib/services/team_generation/team_generation_recovery_service.dart client/lib/cubits/team_generation_cubit.dart client/lib/cubits/team/cubit_team_generation_session_port.dart client/lib/services/launch/session_shell_connector.dart client/lib/cubits/chat_cubit.dart client/lib/app/app_shell.dart client/lib/main.dart client/test/services/team_generation/team_generation_coordinator_test.dart client/test/services/team_generation/team_generation_recovery_service_test.dart client/test/services/session/team_generation_mcp_injection_test.dart client/test/cubits/team/cubit_team_generation_session_port_test.dart
git commit -m "feat(team-generation): orchestrate and recover builder workflows"
```

## Task 14: Landing mode, global generation-settings UX, and start transition

**Files:**
- Create: `client/lib/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart`
- Create: `client/lib/pages/home_workspace/workspace/workspace_landing_generation_preflight.dart`
- Modify: `client/lib/pages/team_hub/team_landing_chip_menu.dart`
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_pane.dart`
- Modify: `client/lib/services/home_workspace/landing_prefs_store.dart`
- Modify: `client/lib/services/team/team_landing_recent_store.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/team_hub/team_landing_chip_menu_test.dart`
- Test: `client/test/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog_test.dart`
- Test: `client/test/pages/home_workspace/workspace/unbound_compose_generate_launch_test.dart`

**Interfaces:**
- Consumes: Task 2 `LandingLaunchContext.generateLaunch`, `TeamGenerationCubit`, `AiFeatureConfigRow`, `AiFeatureConfigureDialog`, `CliPresetsCubit`, global settings store.
- Produces: `TeamLandingChipAction.generateLaunch`, settings editor, localized preflight surface, and Landing-to-visible-builder transition.

Add the Landing/settings localization keys in this task before referencing generated accessors: `teamGenerateLaunch`, `teamGenerateSettingsTitle`, `teamGenerateGeneratorModel`, `teamGenerateTeamMode`, `teamGenerateNative`, `teamGenerateMixed`, `teamGenerateNativeCli`, `teamGenerateModelPool`, `teamGenerateAddModel`, `teamGenerateHiddenPresets(count)`, `teamGenerateMissingPreset(presetId)`, `teamGenerateDescription`, `teamGenerateTags`, `teamGenerateMoveUp`, `teamGenerateMoveDown`, `teamGenerateRemove`, `teamGenerateCapabilityNote`, `teamGenerateErrorDescriptionRequired`, `teamGenerateErrorAiNotConfigured`, `teamGenerateErrorPoolEmpty`, `teamGenerateErrorGeneratorUnsupported`, `teamGenerateErrorNativeUnsupported`, and `teamGenerateOpenSettings`. Use the exact English/Chinese text listed in Task 16's localization audit and run `flutter gen-l10n` before widget tests.

- [ ] **Step 1: Write failing team-menu and mode-invariant widget tests**

```dart
test('menu places Generate and launch after a divider and before Browse all', () {
  final specs = buildTeamLandingChipMenuSpecs(
    generateLaunchLabel: 'Generate and launch',
    browseAllLabel: 'Browse all',
    selectedTeamId: null,
    generateLaunchSelected: true,
    recentTeams: const [],
  );
  expect(itemValues(specs), [
    TeamLandingChipAction.generateLaunch,
    TeamLandingChipAction.browseAll,
  ]);
  expect(itemIcon(specs, TeamLandingChipAction.generateLaunch), Icons.auto_awesome_outlined);
});

testWidgets('selecting Simple clears generation while preserving last team id', (tester) async {
  final harness = await pumpLanding(tester, draft: generatedDraft(teamId: 'last-team'));
  await harness.selectSimple();
  expect(harness.draft.generateLaunch, isFalse);
  expect(harness.draft.isPersonal, isTrue);
  expect(harness.draft.teamId, 'last-team');
});
```

- [ ] **Step 2: Add the menu action and active chip appearance**

Add `generateLaunch` to `TeamLandingChipAction`; render a divider plus `Icons.auto_awesome_outlined` item before Browse all. In `_onTeamChipSelected`, selecting it applies `draft.copyWith(isPersonal: false, generateLaunch: true)`; selecting Simple or a concrete team applies `generateLaunch: false`. `_autoChipLabel` returns the localized Generate-and-launch label and `_autoChipSpecs` uses the active accent treatment while the mode is selected.

- [ ] **Step 3: Write failing settings-dialog interaction tests**

```dart
testWidgets('edits ordered pool without deleting hidden native-incompatible rows', (tester) async {
  final harness = await pumpGenerateSettings(
    tester,
    settings: settingsWithPool(['claude-strong', 'codex-fast']),
  );
  await harness.chooseMode(TeamMode.native);
  await harness.chooseNativeCli(CliTool.claude);
  expect(harness.visiblePoolIds, ['claude-strong']);
  expect(harness.hiddenCount, 1);
  await harness.save();
  expect(harness.saved.modelPool.map((entry) => entry.presetId), ['claude-strong', 'codex-fast']);
});

testWidgets('deleted preset is red, excluded from effective pool, and removable', (tester) async {
  final harness = await pumpGenerateSettings(tester, settings: settingsWithPool(['missing']));
  expect(harness.errorText, contains('missing'));
  expect(harness.canSave, isFalse);
  await harness.removePoolEntry('missing');
  expect(harness.poolRows, isEmpty);
});
```

- [ ] **Step 4: Build the global settings dialog with `Tp*` controls**

The dialog contains:

- Generator model: `AiFeatureConfigRow(featureId: AiFeatureId.teamGenerate)` and the existing `AiFeatureConfigureDialog`;
- Team mode segmented selection: native/mixed;
- Native CLI selection shown only in native mode;
- ordered model-pool rows showing CLI/provider/model/effort, editable description, tag chips, move up/down, and remove;
- Add model configuration: choose an existing global preset or open `CliPresetEditDialog`, then append its resulting ID;
- invalid deleted-preset rows retained and shown in error color with a removal action.
- a localized note that Team Builder will probe workspace machines and may acquire skills, plugins, and MCP servers for the generated team.

When switching to native mode and the current native CLI has no effective row, default it to the first valid stored pool preset's CLI. In native mode display matching-CLI rows plus every broken reference, retain nonmatching valid rows in storage, and show a localized hidden-count note. New choices are filtered to the native CLI. In mixed mode show the full order. Disable Save when the effective pool is empty, a visible reference is invalid, or generator configuration is missing. Save once through `TeamGenerationCubit.saveSettings`.

- [ ] **Step 5: Write failing submit/preflight transition tests**

```dart
testWidgets('generation submit bypasses concrete-team readiness and opens builder', (tester) async {
  final harness = await pumpLanding(
    tester,
    draft: generatedDraft(),
    composeText: 'Design a sync engine',
  );
  await harness.submit();

  expect(harness.teamReadinessCalls, 0);
  expect(harness.coordinatorStarts.single.originalPrompt, 'Design a sync engine');
  expect(harness.visibleSessionPurpose, SessionPurpose.teamGeneration);
  expect(harness.progressOverlayVisible, isFalse);
});

testWidgets('preflight errors keep Landing text and open settings action', (tester) async {
  final harness = await pumpLanding(
    tester,
    draft: generatedDraft(),
    composeText: 'Task',
    preflightIssues: [issue('model_pool_empty')],
  );
  await harness.submit();
  expect(harness.composeText, 'Task');
  expect(harness.localizedErrorVisible, isTrue);
  await harness.tapConfigure();
  expect(harness.generateSettingsVisible, isTrue);
});
```

- [ ] **Step 6: Branch submit before concrete-team launch gates**

In `_canSubmit`, generation requires nonblank compose text and no start already in progress. In `_submitAfterLaunchGate`, branch on `generateLaunch` before selected-team readiness/machine gates; let the existing `submitWorkspaceLandingMessage`/`ComposeClip` path produce the final text with attachments and file references, snapshot that exact string once, call coordinator preflight, show `WorkspaceLandingGenerationPreflight` on issues, then call `start` with the snapshot and current workspace/repository. Do not show the New Team streaming overlay. Clear the Landing input only after job creation and builder tab creation succeed; on failure preserve text and remain on Landing.

The existing team-settings gear opens `WorkspaceLandingGenerateSettingsDialog` while generation mode is active and retains the current concrete-team settings behavior otherwise.

- [ ] **Step 7: Persist the generated-team selection after handoff**

Implement the handoff callback with `LandingPrefsStore` plus `TeamLandingRecentStore`:

```dart
Future<void> selectGeneratedTeam(String workspaceId, String teamId);
Future<void> touchGeneratedTeamRecent(String teamId);
```

Serialize the preference read-modify-write with `LockPool` keyed by the prefs path. It preserves project folder, working directory, permission policy, and Simple choices, while writing `isPersonal: false`, `generateLaunch: false`, and `teamId`; the recent update reuses the existing dedupe/cap logic. Bind both as `GeneratedTeamSelectionWriter` and invoke it before destination creation so recovery and an unmounted Landing behave identically. Emit a `TeamGenerationCubit` destination event after the destination opens so a still-mounted Landing draft mirrors the same selection.

- [ ] **Step 8: Run Landing and settings tests, then commit**

Run: `cd client && flutter gen-l10n && dart run tool/run_tests.dart test/pages/team_hub/team_landing_chip_menu_test.dart test/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog_test.dart test/pages/home_workspace/workspace/unbound_compose_generate_launch_test.dart test/services/home_workspace/workspace_launch_prefs_store_test.dart test/services/team/team_landing_recent_store_test.dart`

Expected: PASS; submit visibly opens a builder session, and a successful handoff leaves the generated team selected for the next Landing.

```bash
git add client/lib/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart client/lib/pages/home_workspace/workspace/workspace_landing_generation_preflight.dart client/lib/pages/team_hub/team_landing_chip_menu.dart client/lib/pages/home_workspace/workspace/unbound_compose_body.dart client/lib/pages/home_workspace/workspace/workspace_chat_pane.dart client/lib/services/home_workspace/landing_prefs_store.dart client/lib/services/team/team_landing_recent_store.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/pages/team_hub/team_landing_chip_menu_test.dart client/test/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog_test.dart client/test/pages/home_workspace/workspace/unbound_compose_generate_launch_test.dart client/test/services/home_workspace/workspace_launch_prefs_store_test.dart client/test/services/team/team_landing_recent_store_test.dart
git commit -m "feat(team-generation): add landing generate and launch ux"
```

## Task 15: Builder-session progress, preview, retry, and cancel UX

**Files:**
- Create: `client/lib/pages/chat/team_generation_builder_status.dart`
- Modify: `client/lib/pages/chat_workbench.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/chat/team_generation_builder_status_test.dart`
- Test: `client/test/pages/chat_workbench_team_generation_test.dart`

**Interfaces:**
- Consumes: active `AppSession.purpose/workflowId`, `TeamGenerationCubit` job snapshots, coordinator `retry/cancel`.
- Produces: builder-only status chrome, normalized preview, safe actions, and automatic disappearance when the destination tab replaces the builder.

Add the builder localization keys in this task before referencing generated accessors: `teamGenerateBuilderTitle`, `teamGenerateCancel`, `teamGenerateRetry`, `teamGenerateContinueSetup`, `teamGenerateCancelTitle`, `teamGenerateCancelBody`, every `teamGeneratePhase*` key, `teamGenerateErrorTargetUnavailable`, `teamGenerateErrorStagingUnsupported`, `teamGenerateErrorUserActionRequired`, `teamGenerateErrorPromptDeliveryUnknown`, `teamGenerateErrorRecoveryIntegrity`, `teamGenerateOpenLeadSession`, `teamGenerateDeliveryArrived`, `teamGenerateDeliverySendAgain`, `teamGenerateDeliveryRetryTitle`, and `teamGenerateDeliveryRetryBody`. Use the exact English/Chinese text listed in Task 16's localization audit and run `flutter gen-l10n` before widget tests.

- [ ] **Step 1: Write failing purpose-isolation and progress tests**

```dart
testWidgets('status is rendered only for a team-generation session', (tester) async {
  await pumpWorkbench(tester, session: builderSession, job: probingJob);
  expect(find.byType(TeamGenerationBuilderStatus), findsOneWidget);
  expect(find.text('Team Builder'), findsOneWidget);
  expect(find.text('Checking machines and CLIs…'), findsOneWidget);

  await pumpWorkbench(tester, session: normalSession, job: probingJob);
  expect(find.byType(TeamGenerationBuilderStatus), findsNothing);
});

testWidgets('valid plan shows roles, presets, resources, and machines', (tester) async {
  await pumpBuilderStatus(tester, job: validatedJob);
  expect(find.text('Delivery Team'), findsOneWidget);
  expect(find.text('Lead · claude-strong · Local'), findsOneWidget);
  expect(find.text('Worker ×2 · codex-fast · Build SSH'), findsOneWidget);
  expect(find.text('2 skills · 1 plugin · 1 MCP server'), findsOneWidget);
});
```

- [ ] **Step 2: Build a compact, accessible builder status component**

Place it above the session content inside `ChatWorkbench`, not in a modal or overlay. Add a `Team Builder` badge beside the purpose-specific session title. Map durable phases to localized copy:

- `created`: Preparing Team Builder;
- `probing`: Checking machines and CLIs;
- `planning`: Designing the team;
- `validating`: Validating the plan;
- `committing`: Creating experts and team;
- `launching`: Starting the generated team;
- `delivering`: Sending your task to the lead;
- `delivered/cleaning`: Finishing and cleaning up;
- `failed`: Generation needs attention.

Use a `Tp` progress indicator, phase text, and an expandable preview from `GeneratedTeamValidationResult`. Never display tokens, credentials, raw probe output, or full filesystem paths. Add semantic labels for progress and every action.

- [ ] **Step 3: Write failing retry/cancel policy tests**

```dart
testWidgets('pre-commit failure offers Retry and Cancel', (tester) async {
  final harness = await pumpBuilderStatus(tester, job: failedPlanningJob);
  expect(find.text('Retry'), findsOneWidget);
  expect(find.text('Cancel generation'), findsOneWidget);
  await harness.tapRetry();
  expect(harness.retryCalls, ['wf']);
});

testWidgets('profile-persisted failure cannot cancel and retries forward', (tester) async {
  final harness = await pumpBuilderStatus(tester, job: failedAfterProfileJob);
  expect(find.text('Cancel generation'), findsNothing);
  expect(find.text('Continue setup'), findsOneWidget);
  await harness.tapContinue();
  expect(harness.retryCalls, ['wf']);
});

testWidgets('ambiguous prompt offers inspect, arrived, and guarded resend', (tester) async {
  final harness = await pumpBuilderStatus(tester, job: promptDeliveryUnknownJob);
  expect(find.text('Open lead session'), findsOneWidget);
  expect(find.text('It arrived'), findsOneWidget);
  expect(find.text('Send again…'), findsOneWidget);
  await harness.tapSendAgain();
  expect(find.text('The lead might receive the task twice.'), findsOneWidget);
});
```

- [ ] **Step 4: Implement action rules and retained-session behavior**

Show Cancel only through `validating` and only when the profile receipt has not succeeded. Confirm cancellation with a `Tp` dialog explaining that staged resources and the temporary session will be removed. Show Retry for failed pre-commit work; show Continue setup for any post-profile failure. When the job carries a typed Catalog `user_action_required`, show its localized action and open only the existing allowlisted auth/settings route, then let Retry resume the same acquisition receipt. For `prompt_delivery_unknown`, show Open lead session, It arrived, and Send again actions; Send again requires a second dialog warning that the lead might receive the task twice. Closing the tab is not cancellation: the job remains durable and recovery may reopen the builder. Surface sanitized `TeamGenerationError.code` plus localized remediation; log technical cause through `AppLogger`.

- [ ] **Step 5: Verify destination switching and cleanup visuals**

When handoff selects the destination, `ChatWorkbench` naturally renders the destination session and its team roster. Do not navigate through a new route or leave a stale generation banner attached to the destination. If cleanup is deferred, the builder remains in the tab list and reopening it shows Finishing; once the cleanup receipt deletes it, existing tab removal behavior must choose the destination rather than Landing.

- [ ] **Step 6: Run builder UX tests and commit**

Run: `cd client && flutter gen-l10n && dart run tool/run_tests.dart test/pages/chat/team_generation_builder_status_test.dart test/pages/chat_workbench_team_generation_test.dart`

Expected: PASS; normal chats are unchanged and post-commit work cannot be cancelled destructively.

```bash
git add client/lib/pages/chat/team_generation_builder_status.dart client/lib/pages/chat_workbench.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/pages/chat/team_generation_builder_status_test.dart client/test/pages/chat_workbench_team_generation_test.dart
git commit -m "feat(team-generation): show recoverable builder progress"
```

## Task 16: Localization, end-to-end acceptance, regression suite, and release evidence

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Create: `client/test/integration/team_generation_end_to_end_test.dart`
- Create: `client/test/integration/team_generation_recovery_boundaries_test.dart`
- Create: `client/test/integration/team_generation_mcp_security_test.dart`
- Create: `client/test/l10n/team_generation_l10n_test.dart`
- Modify: `client/test/pages/home_workspace/home_workspace_new_team_dialog_page_test.dart`

**Interfaces:**
- Consumes: the complete feature graph and injected fake AI/CLI/target/catalog/clock services.
- Produces: bilingual user-facing strings, end-to-end evidence, crash-boundary evidence, MCP authorization evidence, and explicit legacy-flow regression coverage.

- [ ] **Step 1: Audit the exact English and Chinese ARB contract**

Tasks 14–15 add these key/value pairs. Audit them here and correct any mismatch; include placeholder metadata where braces appear:

| Key | English | 简体中文 |
|---|---|---|
| `teamGenerateLaunch` | Generate and launch | 生成并启动 |
| `teamGenerateSettingsTitle` | Generate and launch settings | 生成并启动设置 |
| `teamGenerateGeneratorModel` | Generator model | 生成模型 |
| `teamGenerateTeamMode` | Team mode | 团队模式 |
| `teamGenerateNative` | Native | 原生 |
| `teamGenerateMixed` | Mixed | 混合 |
| `teamGenerateNativeCli` | Native CLI | 原生 CLI |
| `teamGenerateModelPool` | Model configuration pool | 模型配置池 |
| `teamGenerateAddModel` | Add model configuration | 添加模型配置 |
| `teamGenerateHiddenPresets` | {count} configurations are hidden because they use another CLI. | {count} 个配置因使用其他 CLI 而隐藏。 |
| `teamGenerateMissingPreset` | Preset “{presetId}” no longer exists. | 预设“{presetId}”已不存在。 |
| `teamGenerateDescription` | Strengths and best uses | 强项与适用场景 |
| `teamGenerateTags` | Tags | 标签 |
| `teamGenerateMoveUp` | Move up | 上移 |
| `teamGenerateMoveDown` | Move down | 下移 |
| `teamGenerateRemove` | Remove | 移除 |
| `teamGenerateCapabilityNote` | Team Builder will check workspace machines and may acquire skills, plugins, and MCP servers for the generated team. | 团队构建器将检查工作区机器，并可能为生成的团队获取技能、插件和 MCP 服务器。 |
| `teamGenerateBuilderTitle` | Team Builder | 团队构建器 |
| `teamGenerateCancel` | Cancel generation | 取消生成 |
| `teamGenerateRetry` | Retry | 重试 |
| `teamGenerateContinueSetup` | Continue setup | 继续配置 |
| `teamGenerateCancelTitle` | Cancel team generation? | 取消团队生成？ |
| `teamGenerateCancelBody` | The temporary session and staged resources will be removed. | 临时会话和暂存资源将被移除。 |
| `teamGeneratePhaseCreated` | Preparing Team Builder… | 正在准备团队构建器… |
| `teamGeneratePhaseProbing` | Checking machines and CLIs… | 正在检查机器和 CLI… |
| `teamGeneratePhasePlanning` | Designing the team… | 正在设计团队… |
| `teamGeneratePhaseValidating` | Validating the plan… | 正在验证方案… |
| `teamGeneratePhaseCommitting` | Creating experts and team… | 正在创建专家和团队… |
| `teamGeneratePhaseLaunching` | Starting the generated team… | 正在启动生成的团队… |
| `teamGeneratePhaseDelivering` | Sending your task to the lead… | 正在将任务发送给负责人… |
| `teamGeneratePhaseCleaning` | Finishing and cleaning up… | 正在完成并清理… |
| `teamGeneratePhaseFailed` | Generation needs attention. | 生成过程需要处理。 |
| `teamGenerateErrorDescriptionRequired` | Describe the task to generate a team. | 请先描述需要团队处理的任务。 |
| `teamGenerateErrorAiNotConfigured` | Configure the generator model first. | 请先配置生成模型。 |
| `teamGenerateErrorPoolEmpty` | Add at least one valid model configuration. | 请至少添加一个有效的模型配置。 |
| `teamGenerateErrorGeneratorUnsupported` | The generator CLI must support sessions, skills, and MCP. | 生成 CLI 必须支持会话、技能和 MCP。 |
| `teamGenerateErrorNativeUnsupported` | The selected CLI does not support native teams. | 所选 CLI 不支持原生团队。 |
| `teamGenerateErrorTargetUnavailable` | A required machine or CLI is unavailable. | 所需机器或 CLI 当前不可用。 |
| `teamGenerateErrorStagingUnsupported` | This resource needs a manual installation step and cannot be staged safely. | 此资源需要人工安装，无法安全暂存。 |
| `teamGenerateErrorUserActionRequired` | Complete the required sign-in or configuration, then retry. | 请完成所需的登录或配置，然后重试。 |
| `teamGenerateErrorPromptDeliveryUnknown` | TeamPilot cannot confirm whether the lead received the task. | TeamPilot 无法确认负责人是否已收到任务。 |
| `teamGenerateErrorRecoveryIntegrity` | Recovery data could not be verified. The temporary session was kept. | 无法验证恢复数据，临时会话已保留。 |
| `teamGenerateOpenSettings` | Open generation settings | 打开生成设置 |
| `teamGenerateOpenLeadSession` | Open lead session | 打开负责人会话 |
| `teamGenerateDeliveryArrived` | It arrived | 已收到 |
| `teamGenerateDeliverySendAgain` | Send again… | 再次发送… |
| `teamGenerateDeliveryRetryTitle` | Send the task again? | 再次发送任务？ |
| `teamGenerateDeliveryRetryBody` | The lead might receive the task twice. | 负责人可能会收到两次任务。 |

Add `team_generation_l10n_test.dart` to load both ARB JSON maps and assert every key exists, placeholder-bearing entries have matching `@key.placeholders`, and neither locale contains a blank value.

Run: `cd client && flutter gen-l10n && dart run tool/run_tests.dart test/l10n/team_generation_l10n_test.dart`

Expected: generated localization accessors compile; do not hand-edit generated localization Dart files.

- [ ] **Step 2: Write the end-to-end integration test**

```dart
@Tags(['integration'])
void main() {
  testWidgets('Landing builds, commits, switches, delivers, and cleans up', (tester) async {
    final app = await TeamGenerationIntegrationHarness.pump(tester);
    await app.selectGenerateAndLaunch();
    await app.enterTask('Ship\nthis exact task');
    await app.submit();

    expect(app.activeSession.purpose, SessionPurpose.teamGeneration);
    await app.builder.call('get_generation_context');
    await app.builder.call('probe_workspace_targets');
    await app.builder.stageSkill(skillFixture);
    expect(await app.builder.validate(invalidPlan), isFalse);
    final revision = await app.builder.validate(validMixedPlan);
    await app.builder.finalize(revision);
    await app.flushFinalizeResponse();
    await app.completeBuilderTurn();
    await app.settleWorkflow();

    expect(app.activeSession.sessionTeam, app.generatedTeam.id);
    expect(app.activeMemberId, TeamMemberNaming.teamLeadName);
    expect(app.leadDeliveries.single.text, 'Ship\nthis exact task');
    expect(app.leadDeliveries.single.state, isNot(PromptDeliveryState.failed));
    expect(await app.sessionExists(app.builderSessionId), isFalse);
    expect(app.job.phase, TeamGenerationPhase.complete);
    expect(app.job.originalPrompt, isEmpty);
  });
}
```

Use fakes for terminal readiness/submission, AI feature settings, target probes, Catalog acquisition, runtime contexts, and clocks; no real process, SSH connection, or network request may occur.

- [ ] **Step 3: Write restart tests at every irreversible boundary**

Restart the assembled app graph after: job create, builder persist, kickoff `submitIssued`, staged resource write, valid plan write, finalize acceptance, finalize response flush, each promotion, each expert write, profile write, placement write, destination persist, prompt `submitIssued`, response/idle receipts, and builder delete. A crash after job create but before the builder persistence receipt must clean the orphaned pre-commit job and leave no builder/profile. For later pre-finalize-acceptance cases assert:

```dart
expect(await profilesWithWorkflow(workflowId), isEmpty);
expect(await destinationSessions(workflowId), isEmpty);
expect(await matchingBuilderSessions(workflowId), hasLength(1));
expect(await stagedResourcesFor(workflowId), hasNoDuplicates);
```

For finalize-accepted and later cases let recovery settle all safe forward steps, then assert:

```dart
expect(await profilesWithWorkflow(workflowId), hasLength(1));
expect(await destinationSessions(workflowId), hasLength(1));
expect((await submittedLeadPrompts(workflowId)).length, lessThanOrEqualTo(1));
expect(deliverySucceeded(job) || job.error?.code == 'prompt_delivery_unknown', isTrue);
expect(globalManifestReferencesAreValid(), isTrue);
expect(workspacePlacementReferencesAreValid(), isTrue);
```

Pre-profile injected failures must retain/reopen the builder or compensate workflow-owned staging. Post-profile failures must retain the team and converge forward.

- [ ] **Step 4: Write cross-session/workspace/token MCP security tests**

Cover normal session, wrong purpose, wrong workflow, wrong workspace, missing token, old rotated token, deleted builder, and malformed JSON. Assert Composer is never dispatched. Cover a valid builder using Catalog `bind_to: workspace` and a normal session using `bind_to: generation`; assert `bind_scope_forbidden`. Assert no token appears in `job.json`, session metadata, logs captured by the test sink, or MCP tool results.

- [ ] **Step 5: Lock the old New Team AI path as unchanged**

Extend `home_workspace_new_team_dialog_page_test.dart` to open New Team, choose AI generation, and assert it still invokes `TeamConfigGenerator`/dialog progress without creating `SessionPurpose.teamGeneration`, a workflow job, or a Team Composer server. Run its existing prompt/draft/mapper tests unchanged.

- [ ] **Step 6: Run the focused feature and regression suites**

Run:

```bash
cd client
dart run tool/run_tests.dart \
  test/services/team_generation \
  test/pages/home_workspace/workspace/unbound_compose_generate_launch_test.dart \
  test/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog_test.dart \
  test/pages/chat/team_generation_builder_status_test.dart \
  test/pages/chat_workbench_team_generation_test.dart \
  test/services/catalog/catalog_generation_scope_test.dart \
  test/services/prompt_delivery/prompt_delivery_idempotency_test.dart \
  test/services/ai/team_config_generator_test.dart \
  test/services/ai/team_config_prompt_test.dart \
  test/services/ai/team_config_draft_test.dart \
  test/services/ai/team_draft_roster_mapper_test.dart \
  test/pages/home_workspace/home_workspace_new_team_dialog_page_test.dart
```

Expected: PASS; the existing headless New Team flow remains green.

- [ ] **Step 7: Run integration, analysis, and the full test runner**

Run:

```bash
cd client
dart run tool/run_tests.dart --tags integration test/integration/team_generation_end_to_end_test.dart test/integration/team_generation_recovery_boundaries_test.dart test/integration/team_generation_mcp_security_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart
```

Expected: all commands exit 0. Review logs to confirm no token, credential, prompt, or raw probe output is emitted.

- [ ] **Step 8: Inspect repository hygiene and commit the acceptance slice**

Run: `git diff --check`

Expected: no whitespace errors. Verify `client/google_fonts/` is absent from `git status --short` and unrelated pre-existing changes are not staged.

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/l10n/team_generation_l10n_test.dart client/test/integration/team_generation_end_to_end_test.dart client/test/integration/team_generation_recovery_boundaries_test.dart client/test/integration/team_generation_mcp_security_test.dart client/test/pages/home_workspace/home_workspace_new_team_dialog_page_test.dart
git commit -m "test(team-generation): cover agentic launch end to end"
```
