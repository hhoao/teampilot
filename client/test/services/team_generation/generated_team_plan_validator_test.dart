import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/team_generation/generated_team_plan_validator.dart';
import 'package:teampilot/services/team_generation/models/team_target_probe.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';

CliPreset preset(String id, CliTool cli) => CliPreset(
  id: id,
  name: id,
  cli: cli,
  provider: 'official',
  model: 'model',
  createdAt: 0,
  updatedAt: 0,
);

GeneratedTeamValidationInput input({
  String memberPreset = 'claude-strong',
  Map<String, int> leadPlacement = const {'local': 1},
  Map<String, int> workerPlacement = const {'local': 1},
}) {
  final frozen = TeamGenerationSettingsSnapshot(
    revision: 'frozen-rev',
    capturedAt: 42,
    teamMode: TeamMode.mixed,
    nativeCli: CliTool.claude,
    modelPool: [
      EffectiveGenerateModelPoolEntry(
        rank: 1,
        source: GenerateModelPoolEntry(
          id: 'claude-strong',
          cli: CliTool.claude,
          provider: 'official',
          model: 'model',
        ),
        preset: preset('claude-strong', CliTool.claude),
      ),
      EffectiveGenerateModelPoolEntry(
        rank: 2,
        source: GenerateModelPoolEntry(
          id: 'codex-fast',
          cli: CliTool.codex,
          provider: 'official',
          model: 'model',
        ),
        preset: preset('codex-fast', CliTool.codex),
      ),
    ],
  );
  final probe = TeamTargetProbeSnapshot(
    capturedAt: 1,
    targets: [
      TeamTargetProbe(
        targetId: 'local',
        status: TeamTargetProbeStatus.available,
        folderIds: const ['/a'],
        cliProbes: [
          const TeamTargetCliProbe(cliValue: 'claude', available: true),
          const TeamTargetCliProbe(cliValue: 'codex', available: true),
        ],
      ),
      TeamTargetProbe(
        targetId: 'ssh-1',
        status: TeamTargetProbeStatus.available,
        folderIds: const ['/b'],
        cliProbes: [
          const TeamTargetCliProbe(cliValue: 'claude', available: true),
        ],
      ),
    ],
  );
  return GeneratedTeamValidationInput(
    settings: frozen,
    probe: probe,
    installedResourceIds: {'existing/skill', 'existing-mcp'},
    stagedResourceIds: const {},
    existingExpertKeys: const {},
    presetDigests: {
      'claude-strong': _digest(preset('claude-strong', CliTool.claude)),
      'codex-fast': _digest(preset('codex-fast', CliTool.codex)),
    },
    currentFolders: const [
      WorkspaceFolder(path: '/a', targetId: 'local'),
      WorkspaceFolder(path: '/b', targetId: 'ssh-1'),
    ],
  );
}

String _digest(CliPreset preset) => [
  'cli:',
  preset.cli.value,
  'provider:',
  preset.provider,
  'model:',
  preset.model,
  'effort:',
  preset.effort,
].join('|');

Map<String, Object?> planJson({
  int memberCount = 2,
  int leads = 1,
  String? memberPreset = 'claude-strong',
  Map<String, int>? leadPlacement = const {'local': 1},
  Map<String, int>? workerPlacement = const {'local': 1},
}) {
  final members = <Map<String, Object?>>[];
  for (var li = 0; li < leads; li++) {
    members.add({
      'name': TeamMemberNaming.teamLeadName,
      'role': 'Delivery Lead',
      'responsibilities': 'Own decomposition and integration',
      'workingMethod': 'Delegate, review evidence, integrate',
      if (memberPreset != null) 'presetId': memberPreset,
      'replicas': 1,
      if (leadPlacement != null) 'placement': leadPlacement,
    });
  }
  for (var i = members.length; i < memberCount; i++) {
    members.add({
      'name': 'worker-$i',
      'role': 'Worker',
      'responsibilities': 'Implements tasks',
      'workingMethod': 'Test-first small diffs',
      'presetId': 'codex-fast',
      'replicas': 1,
      if (workerPlacement != null) 'placement': workerPlacement,
    });
  }
  return {
    'schemaVersion': 1,
    'team': {
      'name': 'Delivery Team',
      'description': 'Ships the request',
      'mode': 'mixed',
    },
    'members': members,
    'resources': {
      'skillIds': ['existing/skill'],
      'pluginIds': <String>[],
      'mcpServerIds': ['existing-mcp'],
    },
  };
}

void main() {
  late GeneratedTeamPlanValidator validator;

  setUp(() {
    validator = GeneratedTeamPlanValidator();
  });

  test('valid mixed plan validates with roster preview', () async {
    final result = await validator.validate(
      input: input(),
      planJson: planJson(),
    );
    // ignore: avoid_print
    expect(result.issueCodes.join(','), isEmpty, reason: 'issues');
    expect(result.isValid, isTrue);
    expect(result.roster.first.id, TeamMemberNaming.teamLeadName);
    final worker = result.roster.firstWhere((slot) => slot.id == 'worker-1');
    expect(worker.overridesPresetId, 'codex-fast');
    expect(worker.cli, CliTool.codex);
    expect(result.destinationLaunch, isNotNull);
    expect(result.destinationLaunch!.leadTargetId, 'local');
  });

  test('requires 2-5 roles and one singleton canonical lead', () async {
    final result = await validator.validate(
      input: input(),
      planJson: planJson(leads: 2, memberCount: 6),
    );
    expect(result.isValid, isFalse);
    expect(
      result.issueCodes,
      containsAll(['member_count_out_of_range', 'lead_count_invalid']),
    );
    expect(
      result.issueCodes.where((code) => code == 'duplicate_member_id'),
      everyElement(anything),
    );
  });

  test('rejects live preset drift and unavailable mixed placement', () async {
    final result = await validator.validate(
      input: input(),
      planJson: planJson(
        memberPreset: 'deleted-after-start',
        workerPlacement: {'ssh-9': 1},
      ),
    );
    expect(
      result.issueCodes,
      containsAll(['preset_not_in_snapshot', 'target_cli_unavailable']),
    );
  });

  test('missing preset inherits the fixed team default', () async {
    final result = await validator.validate(
      input: input(),
      planJson: planJson(memberPreset: null),
    );
    expect(result.isValid, isTrue);
    final lead = result.roster.first;
    expect(lead.overridesPresetId, TeamProfile.inheritPresetId);
    expect(lead.cli, isNull);
  });

  test('rejects a worker whose placement is missing', () async {
    final result = await validator.validate(
      input: input(),
      planJson: planJson(workerPlacement: null),
    );

    expect(result.isValid, isFalse);
    expect(result.issueCodes, contains('placement_sum_mismatch'));
    expect(
      result.issues
          .singleWhere((issue) => issue.code == 'placement_sum_mismatch')
          .detail,
      contains('worker-1'),
    );
  });

  test('canonicalizes placement before returning the commit plan', () async {
    final result = await validator.validate(
      input: input(),
      planJson: planJson(workerPlacement: const {'': 1, 'local': 0}),
    );

    expect(result.isValid, isTrue);
    expect(result.normalizedPlan.members.last.placement, {'local': 1});
  });
}

extension _SlotX on RosterSlotPreview {
  String get overridesPresetId => activePresetId;
}
