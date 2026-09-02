import '../../models/discoverable_member.dart';
import '../../models/discoverable_team.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';
import '../../repositories/launch_profile_repository.dart';
import '../../repositories/session_repository.dart';
import '../../services/expert_hub/local_expert_store.dart';
import '../../services/launch/member_placement_save.dart';
import '../../services/team_generation/models/team_generation_job.dart';
import '../../services/team_generation/team_generation_job_store.dart';
import '../../utils/logging/logger.dart';
import '../../utils/team/team_member_naming.dart';

/// Minimal resource-provisioning seam the commit service calls after the
/// profile receipt succeeds. Implemented by the full provisioner in the app
/// composition layer; tests supply fakes.
abstract interface class TeamProfileResourceProvisioner {
  Future<void> provision(TeamProfile team);
}

/// Promotes builder-owned catalog payloads once the generated profile is
/// durable. Normal catalog mutations stay outside this workflow.
abstract interface class TeamGenerationResourcePromoter {
  Future<void> promote({
    required String workspaceId,
    required String workflowId,
  });

  Future<bool> isPromotionComplete({
    required String workspaceId,
    required String workflowId,
  });
}

/// Result of a successful or partially-failed commit.
final class GeneratedTeamCommitResult {
  const GeneratedTeamCommitResult({
    required this.team,
    required this.workspace,
    required this.preparedPlacement,
  });

  final TeamProfile team;
  final Workspace workspace;
  final PreparedMemberPlacementSave preparedPlacement;
}

/// Raised when a commit step fails; [profilePersisted] marks the
/// forward-recovery boundary (plan: profile receipt succeeded).
final class TeamGenerationCommitException implements Exception {
  TeamGenerationCommitException(
    this.code,
    this.message, {
    required this.profilePersisted,
  });

  final String code;
  final String message;
  final bool profilePersisted;

  @override
  String toString() => 'TeamGenerationCommitException($code): $message';
}

/// Receipt-driven transaction: promote resources → persist experts →
/// persist profile → persist placement → provision → publish.
///
/// Before the profile receipt succeeds, failures compensate workflow-owned
/// effects. After it succeeds, failures are recorded and recovery finishes
/// forward; the visible team is never deleted.
final class GeneratedTeamCommitService {
  GeneratedTeamCommitService({
    required TeamGenerationJobStore jobStore,
    required LocalExpertStore expertStore,
    required LaunchProfileRepository profileRepository,
    required SessionRepository sessionRepository,
    required TeamProfileResourceProvisioner resourceProvisioner,
    required GeneratedTeamStatePublisher publisher,
    TeamGenerationResourcePromoter? resourcePromoter,
  }) : _jobStore = jobStore,
       _expertStore = expertStore,
       _profileRepository = profileRepository,
       _sessionRepository = sessionRepository,
       _resourceProvisioner = resourceProvisioner,
       _publisher = publisher,
       _resourcePromoter = resourcePromoter;

  final TeamGenerationJobStore _jobStore;
  final LocalExpertStore _expertStore;
  final LaunchProfileRepository _profileRepository;
  final SessionRepository _sessionRepository;
  final TeamProfileResourceProvisioner _resourceProvisioner;
  final GeneratedTeamStatePublisher _publisher;
  final TeamGenerationResourcePromoter? _resourcePromoter;

  /// Commits the validated plan recorded on the job.
  Future<GeneratedTeamCommitResult> commit({
    required Workspace workspace,
    required String workflowId,
    required String validatedRevision,
  }) async {
    final job = await _jobStore.read(workspace.workspaceId, workflowId);
    if (job == null) {
      throw TeamGenerationCommitException(
        'workflow_missing',
        'no job for $workflowId',
        profilePersisted: false,
      );
    }
    if (job.validatedRevision.isEmpty ||
        job.validatedRevision != validatedRevision) {
      throw TeamGenerationCommitException(
        'stale_validated_revision',
        'validated revision mismatch',
        profilePersisted: false,
      );
    }

    // 1. Reserve team name/id deterministically.
    final reservation = job.teamReservation ?? _reserve(workflowId, job);
    await _jobStore.mutate(workspace.workspaceId, workflowId, (current) {
      return current.copyWith(teamReservation: reservation);
    });

    try {
      // 2. Promote staged resources (receipt-driven, idempotent).
      await _reserveAndRun(
        workspaceId: workspace.workspaceId,
        workflowId: workflowId,
        effect: 'promote',
        run: () async {
          await _resourcePromoter?.promote(
            workspaceId: workspace.workspaceId,
            workflowId: workflowId,
          );
          return reservation.teamId;
        },
      );

      // 3. Persist generated experts.
      await _reserveAndRun(
        workspaceId: workspace.workspaceId,
        workflowId: workflowId,
        effect: 'expert',
        run: () async {
          final existingKeys = await _expertStore.loadAll();
          final known = existingKeys.map((member) => member.key).toSet();
          for (final member in _generatedMembers(job, reservation)) {
            final key = member.key;
            if (!known.add(key)) continue;
            if (!await _expertStore.containsKey(key)) {
              await _expertStore.putClone(member);
            }
          }
          return '${_generatedMembers(job, reservation).length}';
        },
      );

      // 4. Persist the team profile — the forward-recovery boundary.
      final team = _buildTeamProfile(job, reservation);
      await _reserveAndRun(
        workspaceId: workspace.workspaceId,
        workflowId: workflowId,
        effect: 'profile',
        run: () async {
          final existing = await _profileRepository.loadTeamProfiles();
          final current = existing
              .where((profile) => profile.id == reservation.teamId)
              .firstOrNull;
          if (current == null) {
            await _profileRepository.save(team);
          }
          return reservation.teamId;
        },
      );

      // 5. Placement + provision + publication: forward recovery from here.
      try {
        final folders = workspace.folders;
        final placement = _validatedPlacement(job, team);
        final prepared = prepareMemberPlacementSave(
          team: team,
          folders: folders,
          placement: placement,
        );
        if (!prepared.leadValid) {
          throw TeamGenerationCommitException(
            'lead_placement_invalid',
            'lead placement is invalid',
            profilePersisted: true,
          );
        }
        await _sessionRepository.updateWorkspaceMemberPlacement(
          workspace.workspaceId,
          team.id,
          targets: prepared.targets,
        );
        await _reserveAndRun(
          workspaceId: workspace.workspaceId,
          workflowId: workflowId,
          effect: 'provision',
          run: () async {
            await _resourceProvisioner.provision(team);
            return team.id;
          },
        );
        await _publisher.publish(team: team, workspace: workspace);

        final updated = await _jobStore.mutate(
          workspace.workspaceId,
          workflowId,
          (current) => current.copyWith(teamId: reservation.teamId),
        );
        return GeneratedTeamCommitResult(
          team: team,
          workspace: updated.workspaceId.isEmpty ? workspace : workspace,
          preparedPlacement: prepared,
        );
      } on TeamGenerationCommitException {
        rethrow;
      } on Object catch (e) {
        throw TeamGenerationCommitException(
          'post_profile_failure',
          e.toString(),
          profilePersisted: true,
        );
      }
    } on TeamGenerationCommitException catch (e) {
      if (!e.profilePersisted) {
        // Compensate workflow-owned effects before the profile boundary.
        await _compensateExperts(job);
      }
      rethrow;
    }
  }

  Future<void> _reserveAndRun({
    required String workspaceId,
    required String workflowId,
    required String effect,
    required Future<String> Function() run,
  }) async {
    final alreadySucceeded = await _succeededReceipt(
      workspaceId,
      workflowId,
      effect,
    );
    if (alreadySucceeded != null) return;
    await _jobStore.mutate(workspaceId, workflowId, (current) {
      return current.copyWith(
        receipts: {
          ...current.receipts,
          effect: const TeamGenerationReceipt(
            state: TeamGenerationReceiptState.reserved,
          ),
        },
      );
    });
    String value;
    try {
      value = await run();
    } on Object catch (e) {
      // Ambiguous exception: check whether the effect actually landed.
      final landed = await _verifyEffect(workspaceId, workflowId, effect);
      await _jobStore.mutate(workspaceId, workflowId, (current) {
        return current.copyWith(
          receipts: {
            ...current.receipts,
            effect: landed
                ? TeamGenerationReceipt(
                    state: TeamGenerationReceiptState.succeeded,
                    value: effect,
                  )
                : TeamGenerationReceipt(
                    state: TeamGenerationReceiptState.failed,
                    value: e.toString(),
                  ),
          },
        );
      });
      rethrow;
    }
    await _jobStore.mutate(workspaceId, workflowId, (current) {
      return current.copyWith(
        receipts: {
          ...current.receipts,
          effect: TeamGenerationReceipt(
            state: TeamGenerationReceiptState.succeeded,
            value: value,
          ),
        },
      );
    });
  }

  Future<bool> _verifyEffect(
    String workspaceId,
    String workflowId,
    String effect,
  ) async {
    final job = await _jobStore.read(workspaceId, workflowId);
    if (job == null) return false;
    switch (effect) {
      case 'expert':
        return Future.wait(
          _generatedMembers(
            job,
            job.teamReservation ?? _reserve(workflowId, job),
          ).map((member) => _expertStore.containsKey(member.key)),
        ).then((exists) => exists.every((value) => value));
      case 'profile':
        final teamId = job.teamReservation?.teamId ?? job.teamId;
        if (teamId.isEmpty) return false;
        return (await _profileRepository.loadTeamProfiles()).any(
          (profile) => profile.id == teamId,
        );
      case 'promote':
        return _resourcePromoter?.isPromotionComplete(
              workspaceId: workspaceId,
              workflowId: workflowId,
            ) ??
            job.stagedResources
                .where((resource) => resource.stagedPath.isNotEmpty)
                .isEmpty;
      case 'provision':
        // Provisioning has no durable observable effect outside its own
        // receipt, so an exception must remain failed rather than replayed.
        return false;
      default:
        return false;
    }
  }

  Future<String?> _succeededReceipt(
    String workspaceId,
    String workflowId,
    String effect,
  ) async {
    final job = await _jobStore.read(workspaceId, workflowId);
    final receipt = job?.receipts[effect];
    if (receipt?.state == TeamGenerationReceiptState.succeeded) {
      return receipt!.value;
    }
    return null;
  }

  TeamGenerationTeamReservation _reserve(
    String workflowId,
    TeamGenerationJob job,
  ) {
    final digest = teamGenerationStableId('', workflowId).substring(0, 8);
    final baseName = job.normalizedPlanJson?['team'] is Map
        ? (((job.normalizedPlanJson!['team'] as Map)['name'] as String?) ??
              'Team')
        : 'Team';
    var teamName = baseName.trim().isEmpty ? 'Team' : baseName.trim();
    var teamId = TeamMemberNaming.slugTeamId(teamName);
    teamName = '$teamName-$digest';
    teamId = '$teamId-$digest';
    return TeamGenerationTeamReservation(
      teamId: teamId,
      teamName: teamName,
      workflowDigest: digest,
    );
  }

  List<DiscoverableMember> _generatedMembers(
    TeamGenerationJob job,
    TeamGenerationTeamReservation reservation,
  ) {
    final planJson = job.normalizedPlanJson;
    if (planJson == null || planJson['members'] is! List) return const [];
    return [
      for (final raw in planJson['members'] as List)
        if (raw is Map)
          if (_normalizedMemberId(raw).isNotEmpty)
            DiscoverableMember(
              key:
                  'local/generated/${reservation.workflowDigest}/${_normalizedMemberId(raw)}',
              name: '${raw['role'] ?? raw['name'] ?? 'Member'}',
              description: '${raw['responsibilities'] ?? ''}',
              category: 'Generated',
              source: ExpertMemberSource.local,
              member: DiscoverableTeamMember(
                name: '${raw['name'] ?? 'member'}',
                responsibilities: '${raw['responsibilities'] ?? ''}',
                playbook: '${raw['workingMethod'] ?? ''}',
              ),
            ),
    ];
  }

  TeamProfile _buildTeamProfile(
    TeamGenerationJob job,
    TeamGenerationTeamReservation reservation,
  ) {
    final planJson = job.normalizedPlanJson ?? const {};
    final roster = <TeamRosterSlot>[];
    if (planJson['members'] is List) {
      for (final raw in planJson['members'] as List) {
        if (raw is! Map) continue;
        final id = _normalizedMemberId(raw);
        if (id.isEmpty) continue;
        final explicit = '${raw['presetId'] ?? ''}';
        roster.add(
          TeamRosterSlot(
            id: id,
            expertKey: 'local/generated/${reservation.workflowDigest}/$id',
            overrides: TeamRosterSlotOverrides(
              activePresetId: explicit.isEmpty
                  ? TeamProfile.inheritPresetId
                  : explicit,
              replicas: _replicas(raw),
            ),
          ),
        );
      }
    }
    final mode = job.settings.teamMode;
    return TeamProfile(
      id: reservation.teamId,
      name: reservation.teamName,
      roster: roster,
      members: _teamMembers(planJson),
      cli: mode == TeamMode.native
          ? job.settings.nativeCli
          : (job.settings.modelPool.isNotEmpty
                ? job.settings.modelPool.first.preset.cli
                : CliTool.claude),
      teamMode: mode,
      activePresetId: job.settings.modelPool.isNotEmpty
          ? job.settings.modelPool.first.preset.id
          : null,
      skillIds: _resourceIdsWithStaged(job, 'skill', 'skillIds'),
      pluginIds: _resourceIdsWithStaged(job, 'plugin', 'pluginIds'),
      mcpServerIds: _resourceIdsWithStaged(job, 'mcp', 'mcpServerIds'),
      createdAt: job.createdAt,
    );
  }

  List<String> _resourceIds(Map<String, Object?> planJson, String key) {
    final resources = planJson['resources'];
    if (resources is! Map || resources[key] is! List) return const [];
    return [
      for (final value in resources[key] as List)
        if (value is String) value,
    ];
  }

  List<TeamMemberConfig> _teamMembers(Map<String, Object?> planJson) {
    final members = planJson['members'];
    if (members is! List) return const [];
    return [
      for (final raw in members)
        if (raw is Map)
          if (_normalizedMemberId(raw).isNotEmpty)
            TeamMemberConfig(
              id: _normalizedMemberId(raw),
              name: '${raw['role'] ?? raw['name'] ?? ''}',
              agentType: '${raw['role'] ?? ''}',
              responsibilities: '${raw['responsibilities'] ?? ''}',
              playbook: '${raw['workingMethod'] ?? ''}',
              replicas: _replicas(raw),
              activePresetId: '${raw['presetId'] ?? ''}'.isEmpty
                  ? TeamProfile.inheritPresetId
                  : '${raw['presetId']}',
            ),
    ];
  }

  List<String> _resourceIdsWithStaged(
    TeamGenerationJob job,
    String kind,
    String key,
  ) => {
    ..._resourceIds(job.normalizedPlanJson ?? const {}, key),
    for (final resource in job.stagedResources)
      if (resource.kind == kind && resource.refId.isNotEmpty) resource.refId,
  }.toList();

  MemberPlacementByTarget _validatedPlacement(
    TeamGenerationJob job,
    TeamProfile team,
  ) {
    final members = job.normalizedPlanJson?['members'];
    if (members is! List) return const {};
    final placement = <String, Map<String, int>>{};
    for (final raw in members) {
      if (raw is! Map) continue;
      final id = _normalizedMemberId(raw);
      if (id.isEmpty || !team.roster.any((slot) => slot.id == id)) {
        continue;
      }
      final counts = raw['placement'];
      if (counts is! Map) continue;
      for (final entry in counts.entries) {
        final targetId = '${entry.key}'.trim();
        final replicas = entry.value is num ? entry.value.toInt() : 0;
        if (targetId.isEmpty || replicas < 1) continue;
        (placement[targetId] ??= <String, int>{})[id] = replicas;
      }
    }
    return placement;
  }

  String _normalizedMemberId(Map raw) {
    final name = '${raw['name'] ?? ''}';
    return TeamMemberNaming.isTeamLeadName(name)
        ? TeamMemberNaming.teamLeadName
        : TeamMemberNaming.slugMemberName(name);
  }

  int _replicas(Map raw) {
    final value = raw['replicas'];
    return value is num ? value.toInt().clamp(0, 999) : 1;
  }

  Future<void> _compensateExperts(TeamGenerationJob job) async {
    try {
      final reservation = job.teamReservation ?? _reserve(job.workflowId, job);
      final keys = _generatedMembers(
        job,
        reservation,
      ).map((member) => member.key).toSet();
      for (final key in keys) {
        if (await _expertStore.containsKey(key)) {
          await _expertStore.delete(key);
        }
      }
    } on Object catch (e) {
      appLogger.w('[team-generation] expert compensation failed: $e');
    }
  }
}

/// Publishes already-persisted team/workspace snapshots to Flutter cubits.
abstract interface class GeneratedTeamStatePublisher {
  Future<void> publish({
    required TeamProfile team,
    required Workspace workspace,
  });
}
