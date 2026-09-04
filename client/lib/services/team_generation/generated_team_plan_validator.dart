import 'package:collection/collection.dart';

import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../models/team_generation_settings.dart';
import '../../models/workspace_folder.dart';
import '../../utils/team/team_member_naming.dart';
import 'models/generated_team_plan.dart';
import 'models/team_generation_launch.dart';
import 'models/team_target_probe.dart';
import 'team_generation_context_payload.dart';

/// Pure validator result with bounded preview data (no credentials/paths).
final class GeneratedTeamValidationResult {
  const GeneratedTeamValidationResult({
    required this.isValid,
    required this.issues,
    required this.normalizedPlan,
    required this.revision,
    required this.roster,
    required this.activePresetId,
    required this.destinationLaunch,
  });

  final bool isValid;
  final List<TeamGenerationIssue> issues;
  final GeneratedTeamPlan normalizedPlan;
  final String revision;

  /// Derived roster preview slots (id, expertKey, overrides).
  final List<RosterSlotPreview> roster;
  final String activePresetId;
  final GeneratedDestinationLaunch? destinationLaunch;

  List<String> get issueCodes => [for (final issue in issues) issue.code];
}

/// Lightweight roster preview row derived during validation.
final class RosterSlotPreview {
  const RosterSlotPreview({
    required this.id,
    required this.expertKey,
    required this.activePresetId,
    required this.cli,
    required this.replicas,
  });

  final String id;
  final String expertKey;

  /// `__inherit__` or an explicit preset id.
  final String activePresetId;

  /// Set only for a mixed explicit preset; otherwise null (inherit team cli).
  final CliTool? cli;
  final int replicas;
}

/// Input bundle for one validation run; everything frozen at workflow start.
final class GeneratedTeamValidationInput {
  const GeneratedTeamValidationInput({
    required this.settings,
    required this.probe,
    required this.installedResourceIds,
    required this.stagedResourceIds,
    required this.existingExpertKeys,
    required this.presetDigests,
    required this.currentFolders,
  });

  final TeamGenerationSettingsSnapshot settings;
  final TeamTargetProbeSnapshot probe;
  final Set<String> installedResourceIds;
  final Set<String> stagedResourceIds;
  final Set<String> existingExpertKeys;

  /// presetId -> digest of cli/provider/model/effort at workflow start.
  final Map<String, String> presetDigests;

  /// Live folders captured at validation (to detect workspace drift).
  final List<WorkspaceFolder> currentFolders;
}

/// Pure plan validation: parse → normalize → every launch invariant.
final class GeneratedTeamPlanValidator {
  const GeneratedTeamPlanValidator();

  Future<GeneratedTeamValidationResult> validate({
    required GeneratedTeamValidationInput input,
    required Map<String, Object?> planJson,
  }) async {
    final issues = <TeamGenerationIssue>[];
    GeneratedTeamPlan plan;
    try {
      plan = GeneratedTeamPlan.fromJson(planJson);
    } on FormatException catch (e) {
      return GeneratedTeamValidationResult(
        isValid: false,
        issues: [
          TeamGenerationIssue(
            code: 'plan_parse_failed',
            detail: e.message,
            severity: TeamGenerationIssueSeverity.error,
          ),
        ],
        normalizedPlan: GeneratedTeamPlan(
          teamName: '',
          teamDescription: '',
          mode: '',
          members: const [],
          skillIds: const [],
          pluginIds: const [],
          mcpServerIds: const [],
          revision: '',
        ),
        revision: '',
        roster: const [],
        activePresetId: '',
        destinationLaunch: null,
      );
    }
    plan = _normalizePlacements(plan);

    final frozen = input.settings;
    final poolById = <String, EffectiveGenerateModelPoolEntry>{
      for (final entry in frozen.modelPool)
        if (effectiveTeamGenerationPoolEntryId(entry).trim().isNotEmpty)
          effectiveTeamGenerationPoolEntryId(entry).trim(): entry,
    };
    if (poolById.isEmpty) {
      issues.add(_error('model_pool_empty'));
    }

    // Mode must equal the frozen mode.
    if (plan.mode != frozen.teamMode.value) {
      issues.add(_error('mode_mismatch'));
    }

    // Member count 2..5, exactly one canonical singleton lead.
    if (plan.members.length < 2 || plan.members.length > 5) {
      issues.add(_error('member_count_out_of_range'));
    }
    final leads = plan.members
        .where((member) => member.name == TeamMemberNaming.teamLeadName)
        .toList();
    if (leads.length != 1) {
      issues.add(_error('lead_count_invalid'));
    } else if (leads.single.replicas != 1) {
      issues.add(_error('lead_replicas_invalid'));
    }

    // Unique normalized ids, no collisions.
    final ids = <String>{};
    for (final member in plan.members) {
      final id = member.name == TeamMemberNaming.teamLeadName
          ? TeamMemberNaming.teamLeadName
          : TeamMemberNaming.slugMemberName(member.name);
      if (!ids.add(id)) {
        issues.add(_error('duplicate_member_id', detail: id));
      }
    }

    // Role overlap.
    final roles = <String>{};
    for (final member in plan.members) {
      if (!roles.add(member.role.toLowerCase())) {
        issues.add(_error('overlapping_roles', detail: member.role));
      }
    }

    // Preset references.
    for (final member in plan.members) {
      final presetId = member.presetId;
      if (presetId.isEmpty) continue;
      if (!poolById.containsKey(presetId)) {
        issues.add(_error('preset_not_in_snapshot', detail: presetId));
        continue;
      }
      final digest = input.presetDigests[presetId];
      final entry = poolById[presetId]!;
      final currentDigest = _presetDigest(entry.preset);
      if (digest == null) {
        issues.add(_error('preset_deleted_since_start', detail: presetId));
      } else if (digest != currentDigest) {
        issues.add(_error('preset_changed_since_start', detail: presetId));
      }
    }

    // Resources exist or are staged by this workflow.
    for (final id in plan.skillIds) {
      if (!input.installedResourceIds.contains(id) &&
          !input.stagedResourceIds.contains(id)) {
        issues.add(_error('resource_missing', detail: id));
      }
    }
    for (final id in plan.pluginIds) {
      if (!input.installedResourceIds.contains(id) &&
          !input.stagedResourceIds.contains(id)) {
        issues.add(_error('resource_missing', detail: id));
      }
    }
    for (final id in plan.mcpServerIds) {
      if (!input.installedResourceIds.contains(id) &&
          !input.stagedResourceIds.contains(id)) {
        issues.add(_error('resource_missing', detail: id));
      }
    }

    // Placement: targets probed/current, counts sum to replicas, CLI facts.
    for (final member in plan.members) {
      final presetId = member.presetId.isEmpty
          ? (frozen.modelPool.isNotEmpty
                ? effectiveTeamGenerationPoolEntryId(frozen.modelPool.first)
                : '')
          : member.presetId;
      final entry = poolById[presetId];
      final sum = member.placement.values.fold(0, (a, b) => a + b);
      if (sum != member.replicas) {
        issues.add(
          _error(
            'placement_sum_mismatch',
            detail: '${member.name}: $sum != ${member.replicas}',
          ),
        );
      }
      for (final entry0 in member.placement.entries) {
        final target = input.probe.byTarget(entry0.key);
        if (target == null ||
            target.status != TeamTargetProbeStatus.available) {
          issues.add(_error('target_cli_unavailable', detail: entry0.key));
          continue;
        }
        if (entry != null) {
          final cliProbe = target.probeFor(entry.preset.cli.value);
          if (cliProbe == null || !cliProbe.available) {
            issues.add(
              _error(
                'target_cli_unavailable',
                detail: '${entry0.key}:${entry.preset.cli.value}',
              ),
            );
          }
        }
      }
      // Native: every preset CLI must match nativeCli.
      if (frozen.teamMode == TeamMode.native &&
          entry != null &&
          entry.preset.cli != frozen.nativeCli) {
        issues.add(_error('native_pool_cli_mismatch', detail: presetId));
      }
    }

    // Workspace drift.
    if (!_sameFolders(input.currentFolders, _foldersOf(input))) {
      issues.add(_error('workspace_changed_since_start'));
    }

    final valid = issues.isEmpty;
    final revision = plan.computeRevision();
    final roster = <RosterSlotPreview>[];
    for (final member in plan.members) {
      final id = member.name == TeamMemberNaming.teamLeadName
          ? TeamMemberNaming.teamLeadName
          : TeamMemberNaming.slugMemberName(member.name);
      final explicit = member.presetId;
      final entry = explicit.isEmpty ? null : poolById[explicit];
      roster.add(
        RosterSlotPreview(
          id: id,
          expertKey: _expertKey(
            member.role,
            member.responsibilities,
            member.workingMethod,
          ),
          activePresetId: explicit.isEmpty
              ? TeamProfile.inheritPresetId
              : explicit,
          // Mixed explicit preset pins only the CLI; provider/model/effort
          // stay empty so presets remain the single source of truth.
          cli: frozen.teamMode == TeamMode.mixed && entry != null
              ? entry.preset.cli
              : null,
          replicas: member.replicas,
        ),
      );
    }
    final activePresetId = frozen.modelPool.isEmpty
        ? ''
        : effectiveTeamGenerationPoolEntryId(frozen.modelPool.first);
    final destination = valid ? _destinationLaunch(input, plan) : null;
    return GeneratedTeamValidationResult(
      isValid: valid,
      issues: issues,
      normalizedPlan: plan,
      revision: revision,
      roster: roster,
      activePresetId: activePresetId,
      destinationLaunch: destination,
    );
  }

  List<WorkspaceFolder> _foldersOf(GeneratedTeamValidationInput input) =>
      input.currentFolders;

  bool _sameFolders(List<WorkspaceFolder> a, List<WorkspaceFolder> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path || a[i].targetId != b[i].targetId) {
        return false;
      }
    }
    return true;
  }

  String _presetDigest(CliPreset preset) => [
    'cli:',
    preset.cli.value,
    'provider:',
    preset.provider,
    'model:',
    preset.model,
    'effort:',
    preset.effort,
  ].join('|');

  String _expertKey(String role, String responsibilities, String method) =>
      'local/generated/${generatedExpertKeyFrom(generatedExpertKeyJson({'role': role, 'responsibilities': responsibilities, 'workingMethod': method}))}';

  GeneratedDestinationLaunch? _destinationLaunch(
    GeneratedTeamValidationInput input,
    GeneratedTeamPlan plan,
  ) {
    if (input.currentFolders.isEmpty) return null;
    final lead = plan.members
        .where((member) => member.name == TeamMemberNaming.teamLeadName)
        .firstOrNull;
    final leadTarget =
        lead?.placement.entries
            .where((entry) => entry.value > 0)
            .map((entry) => entry.key)
            .firstOrNull ??
        WorkspaceFolder.localTargetId;
    final matching =
        input.currentFolders
            .where((folder) => _canonical(folder.targetId) == leadTarget)
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final folder = matching.isNotEmpty
        ? matching.first
        : (input.currentFolders.toList()
                ..sort((a, b) => a.path.compareTo(b.path)))
              .first;
    return GeneratedDestinationLaunch(
      folderId: folder.path,
      projectFolderPath: folder.path,
      workingDirectoryPath: folder.path,
      leadTargetId: leadTarget,
    );
  }

  String _canonical(String targetId) {
    final trimmed = targetId.trim();
    return trimmed.isEmpty ? WorkspaceFolder.localTargetId : trimmed;
  }

  GeneratedTeamPlan _normalizePlacements(GeneratedTeamPlan plan) {
    return GeneratedTeamPlan(
      teamName: plan.teamName,
      teamDescription: plan.teamDescription,
      mode: plan.mode,
      members: [
        for (final member in plan.members)
          GeneratedTeamMemberPlan(
            name: member.name,
            role: member.role,
            responsibilities: member.responsibilities,
            workingMethod: member.workingMethod,
            presetId: member.presetId,
            replicas: member.replicas,
            placement: _normalizePlacement(member.placement),
          ),
      ],
      skillIds: plan.skillIds,
      pluginIds: plan.pluginIds,
      mcpServerIds: plan.mcpServerIds,
      revision: '',
    );
  }

  Map<String, int> _normalizePlacement(Map<String, int> placement) {
    final normalized = <String, int>{};
    for (final entry in placement.entries) {
      if (entry.value < 1) continue;
      final targetId = _canonical(entry.key);
      normalized[targetId] = (normalized[targetId] ?? 0) + entry.value;
    }
    return normalized;
  }

  TeamGenerationIssue _error(String code, {String detail = ''}) =>
      TeamGenerationIssue(
        code: code,
        detail: detail,
        severity: TeamGenerationIssueSeverity.error,
      );
}

/// Re-exported typed issue shared with the compatibility service.
typedef TeamGenerationIssue = GeneratedTeamIssue;
typedef TeamGenerationIssueSeverity = GeneratedTeamIssueSeverity;

/// Severity for validator issues (warnings do not block validity).
enum GeneratedTeamIssueSeverity { warning, error }

final class GeneratedTeamIssue {
  const GeneratedTeamIssue({
    required this.code,
    this.detail = '',
    this.severity = GeneratedTeamIssueSeverity.error,
  });

  final String code;
  final String detail;
  final GeneratedTeamIssueSeverity severity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeneratedTeamIssue &&
          code == other.code &&
          detail == other.detail &&
          severity == other.severity;

  @override
  int get hashCode => Object.hash(code, detail, severity);
}
