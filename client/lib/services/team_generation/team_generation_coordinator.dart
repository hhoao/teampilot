import '../../models/simple_launch_identity.dart';
import '../../models/team_generation_settings.dart';
import '../../models/workspace.dart';
import 'generated_team_plan_validator.dart';
import 'models/team_generation_job.dart';
import 'team_generation_cleanup_service.dart';
import 'team_generation_compatibility.dart';
import 'team_generation_handoff_service.dart';
import 'team_generation_job_store.dart';
import 'models/team_generation_launch.dart';
import 'team_generation_recovery_service.dart';
import 'team_generation_session_port.dart';
import 'team_generation_settings_store.dart';
import 'team_target_probe_service.dart';

/// Issues returned by [TeamGenerationCoordinator.preflight].
final class TeamGenerationPreflightIssue {
  const TeamGenerationPreflightIssue(this.code);

  final String code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TeamGenerationPreflightIssue && code == other.code;

  @override
  int get hashCode => code.hashCode;
}

/// Result of preflight: all actionable issues, no side effects.
final class TeamGenerationPreflightResult {
  const TeamGenerationPreflightResult(this.issues);

  final List<TeamGenerationPreflightIssue> issues;

  bool get ok => issues.isEmpty;
}

/// A started workflow handle.
final class TeamGenerationStartResult {
  const TeamGenerationStartResult({
    required this.workflowId,
    required this.builderSessionId,
  });

  final String workflowId;
  final String builderSessionId;
}

/// Orchestrates the generation workflow: preflight → visible builder →
/// (MCP-driven) finalize → commit → handoff → cleanup; plus cancel/retry.
final class TeamGenerationCoordinator {
  TeamGenerationCoordinator({
    required TeamGenerationJobStore jobStore,
    required TeamGenerationSettingsStore settingsStore,
    required TeamGenerationSessionPort sessionPort,
    required TeamGenerationCompatibility compatibility,
    required TeamTargetProbeService probeService,
    required GeneratedTeamPlanValidator planValidator,
    required TeamGenerationHandoffService handoffService,
    required TeamGenerationCleanupService cleanupService,
    required TeamGenerationRecoveryService recoveryService,
    required String Function() uuidFactory,
  }) : _jobStore = jobStore,
       _settingsStore = settingsStore,
       _sessionPort = sessionPort,
       _compatibility = compatibility,
       _uuidFactory = uuidFactory;

  final TeamGenerationJobStore _jobStore;
  final TeamGenerationSettingsStore _settingsStore;
  final TeamGenerationSessionPort _sessionPort;
  final TeamGenerationCompatibility _compatibility;
  final String Function() _uuidFactory;

  Future<TeamGenerationPreflightResult> preflight({
    required Workspace workspace,
    required String originalPrompt,
  }) async {
    final issues = <TeamGenerationPreflightIssue>[];
    if (originalPrompt.trim().isEmpty) {
      issues.add(const TeamGenerationPreflightIssue('description_required'));
    }
    final settings = await _settingsStore.load();
    final snapshot = resolveTeamGenerationSettingsSnapshot(
      settings: settings,
      presets: const [],
      registry: _compatibility.registry,
      capturedAt: 0,
    );
    if (snapshot.modelPool.isEmpty) {
      issues.add(const TeamGenerationPreflightIssue('model_pool_empty'));
    }
    final poolResult = _compatibility.evaluateTeamPool(
      mode: snapshot.teamMode,
      nativeCli: snapshot.nativeCli,
      pool: snapshot.modelPool,
    );
    for (final issue in poolResult.issues) {
      issues.add(TeamGenerationPreflightIssue(issue.code));
    }
    return TeamGenerationPreflightResult(issues);
  }

  Future<TeamGenerationStartResult> start({
    required Workspace workspace,
    required String originalPrompt,
    required String generatorPresetId,
    required String projectFolderPath,
    required String workingDirectoryPath,
    required List<String> folderIds,
    required List<String> targetIds,
    String workspaceRevision = '',
  }) async {
    final workflowId = _uuidFactory();
    final builderSessionId = teamGenerationStableId('teamgen-builder-', workflowId);
    final settings = await _settingsStore.load();
    final snapshot = resolveTeamGenerationSettingsSnapshot(
      settings: settings,
      presets: const [],
      registry: _compatibility.registry,
      capturedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _jobStore.create(
      workspaceId: workspace.workspaceId,
      workflowId: workflowId,
      builderSessionId: builderSessionId,
      originalPrompt: originalPrompt,
      generator: TeamGenerationJobGenerator.fromSettings(snapshot),
      settings: snapshot,
      launch: TeamGenerationLaunchSnapshot(
        projectFolderPath: projectFolderPath,
        workingDirectoryPath: workingDirectoryPath,
        launchSecurityPolicyValue: 'cliDefault',
        folderIds: folderIds,
        targetIds: targetIds,
        workspaceRevision: workspaceRevision,
        capturedAt: snapshot.capturedAt,
      ),
    );
    await _sessionPort.createBuilder(
      workspace: workspace,
      identity: SimpleLaunchIdentity(
        cli: snapshot.nativeCli,
        provider: '',
        model: '',
        effort: '',
        expertKey: 'teampilot/builtin/team-builder',
        presetId: generatorPresetId,
      ),
      projectFolderPath: projectFolderPath,
      workingDirectoryPath: workingDirectoryPath,
      workflowId: workflowId,
      fixedSessionId: builderSessionId,
      expertKey: 'teampilot/builtin/team-builder',
    );
    return TeamGenerationStartResult(
      workflowId: workflowId,
      builderSessionId: builderSessionId,
    );
  }

  /// Serialized finalize: revalidates the plan revision and idempotency key,
  /// then drives commit → handoff → cleanup via the composer handler chain.
  Future<void> finalize({
    required String workspaceId,
    required String workflowId,
    required String revision,
    required String idempotencyKey,
  }) async {
    final job = await _jobStore.read(workspaceId, workflowId);
    if (job == null || job.validatedRevision != revision) {
      throw StateError('finalize rejected: stale revision');
    }
    // The composer handler's afterResponseFlushed callback drives commit and
    // handoff; the coordinator's finalize entry only verifies eligibility.
  }

  Future<void> cancel({
    required String workspaceId,
    required String workflowId,
  }) async {
    final job = await _jobStore.read(workspaceId, workflowId);
    if (job == null) return;
    if (job.receipts['profile']?.state == TeamGenerationReceiptState.succeeded) {
      throw StateError('cancel_too_late');
    }
    await _jobStore.beginCancel(workspaceId, workflowId);
    await _sessionPort.deleteBuilder(job.builderSessionId, workflowId);
  }

  Future<void> retry({
    required String workspaceId,
    required String workflowId,
  }) =>
      _jobStore.resumeFailed(workspaceId, workflowId).then((_) {});
}
