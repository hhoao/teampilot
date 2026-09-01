import 'dart:async';

import '../../models/cli_preset.dart';
import '../../models/simple_launch_identity.dart';
import '../../models/team_generation_settings.dart';
import '../../models/workspace.dart';
import 'generated_team_plan_validator.dart';
import 'generated_team_commit_service.dart';
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
      identical(this, other) ||
      other is TeamGenerationPreflightIssue && code == other.code;

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
    required GeneratedTeamCommitService commitService,
    required String Function() uuidFactory,
    Future<Workspace?> Function(String workspaceId)? workspaceResolver,
    List<CliPreset> Function()? presets,
  }) : _jobStore = jobStore,
       _settingsStore = settingsStore,
       _sessionPort = sessionPort,
       _compatibility = compatibility,
       _handoffService = handoffService,
       _cleanupService = cleanupService,
       _commitService = commitService,
       _workspaceResolver = workspaceResolver ?? ((_) async => null),
       _presets = presets ?? (() => const <CliPreset>[]),
       _uuidFactory = uuidFactory;

  final TeamGenerationJobStore _jobStore;
  final TeamGenerationSettingsStore _settingsStore;
  final TeamGenerationSessionPort _sessionPort;
  final TeamGenerationCompatibility _compatibility;
  final TeamGenerationHandoffService _handoffService;
  final TeamGenerationCleanupService _cleanupService;
  final GeneratedTeamCommitService _commitService;
  final Future<Workspace?> Function(String workspaceId) _workspaceResolver;
  final List<CliPreset> Function() _presets;
  final String Function() _uuidFactory;
  final Map<String, Future<void>> _completionTails = {};

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
      presets: _presets(),
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
    final builderSessionId = teamGenerationStableId(
      'teamgen-builder-',
      workflowId,
    );
    final settings = await _settingsStore.load();
    final snapshot = resolveTeamGenerationSettingsSnapshot(
      settings: settings,
      presets: _presets(),
      registry: _compatibility.registry,
      capturedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _jobStore.create(
      workspaceId: workspace.workspaceId,
      workflowId: workflowId,
      builderSessionId: builderSessionId,
      originalPrompt: originalPrompt,
      generator: TeamGenerationJobGenerator.fromSettings(
        snapshot,
        generatorPresetId: generatorPresetId,
      ),
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
      identity: SimpleLaunchIdentity.resolve(
        preset: _presets().where((p) => p.id == generatorPresetId).firstOrNull,
        cli: snapshot.nativeCli,
        expertKey: 'teampilot/builtin/team-builder',
        presetId: generatorPresetId,
      ),
      projectFolderPath: projectFolderPath,
      workingDirectoryPath: workingDirectoryPath,
      workflowId: workflowId,
      fixedSessionId: builderSessionId,
      expertKey: 'teampilot/builtin/team-builder',
    );
    await _sessionPort.waitForInputReady(
      builderSessionId,
      builderSessionId,
      directToPty: true,
    );
    final kickoff = buildTeamGenerationKickoff(originalPrompt);
    final kickoffId = teamGenerationStableId('teamgen-kickoff-', workflowId);
    await _sessionPort.persistHistoryPending(
      builderSessionId,
      builderSessionId,
      kickoff,
      deliveryId: kickoffId,
    );
    final kickoffResult = await _sessionPort.deliverTracked(
      builderSessionId,
      builderSessionId,
      kickoff,
      directToPty: true,
      deliveryId: kickoffId,
    );
    if (!kickoffResult.submitted) {
      throw StateError('team-generation builder kickoff failed');
    }
    await _jobStore.mutate(workspace.workspaceId, workflowId, (current) {
      return current.copyWith(
        phase: TeamGenerationPhase.planning,
        receipts: {
          ...current.receipts,
          'builderKickoff': TeamGenerationReceipt(
            state: TeamGenerationReceiptState.succeeded,
            value: kickoffId,
          ),
        },
      );
    });
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
    await completeAccepted(job, idempotencyKey);
  }

  Future<void> completeAccepted(
    TeamGenerationJob accepted,
    String idempotencyKey,
  ) {
    final key = '${accepted.workspaceId}/${accepted.workflowId}';
    final previous = _completionTails[key] ?? Future<void>.value();
    final result = previous.then((_) async {
      final current = await _jobStore.read(
        accepted.workspaceId,
        accepted.workflowId,
      );
      if (current == null || current.phase == TeamGenerationPhase.complete) {
        return;
      }
      final workspace = await _workspaceFor(current.workspaceId);
      if (workspace == null) throw StateError('generation workspace missing');
      final committed = await _commitService.commit(
        workspace: workspace,
        workflowId: current.workflowId,
        validatedRevision: current.validatedRevision,
      );
      await _handoffService.handoff(
        workspace: workspace,
        team: committed.team,
        workflowId: current.workflowId,
      );
      final afterHandoff = await _jobStore.read(
        current.workspaceId,
        current.workflowId,
      );
      if (afterHandoff == null ||
          afterHandoff.phase == TeamGenerationPhase.complete) {
        return;
      }
      if (afterHandoff.receipts['finalizeResponseFlushed']?.state !=
          TeamGenerationReceiptState.succeeded) {
        await _jobStore.recordReceipt(
          current.workspaceId,
          current.workflowId,
          'finalizeResponseFlushed',
          const TeamGenerationReceipt(
            state: TeamGenerationReceiptState.succeeded,
          ),
        );
      }
      await _cleanupService.cleanup(
        workspaceId: current.workspaceId,
        workflowId: current.workflowId,
      );
    });
    final tail = result.then<void>((_) {}, onError: (_) {});
    _completionTails[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_completionTails[key], tail)) {
          _completionTails.remove(key);
        }
      }),
    );
    return result;
  }

  Future<Workspace?> _workspaceFor(String workspaceId) =>
      _workspaceResolver(workspaceId);

  Future<void> cancel({
    required String workspaceId,
    required String workflowId,
  }) async {
    final job = await _jobStore.read(workspaceId, workflowId);
    if (job == null) return;
    if (job.receipts['profile']?.state ==
        TeamGenerationReceiptState.succeeded) {
      throw StateError('cancel_too_late');
    }
    await _jobStore.beginCancel(workspaceId, workflowId);
    await _sessionPort.deleteBuilder(job.builderSessionId, workflowId);
  }

  Future<void> retry({
    required String workspaceId,
    required String workflowId,
  }) => _jobStore.resumeFailed(workspaceId, workflowId).then((_) {});
}
