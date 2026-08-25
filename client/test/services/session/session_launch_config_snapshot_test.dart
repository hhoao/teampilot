import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/session_continue_overrides_apply.dart';
import 'package:teampilot/services/session/session_launch_config_snapshot.dart';

void main() {
  const claudePresetA = CliPreset(
    id: 'preset-claude-a',
    name: 'Claude A',
    cli: CliTool.claude,
    provider: 'anthropic',
    model: 'claude-a',
    effort: 'high',
    createdAt: 0,
    updatedAt: 0,
  );

  const codexPreset = CliPreset(
    id: 'preset-codex',
    name: 'Codex',
    cli: CliTool.codex,
    provider: 'openai',
    model: 'gpt-5',
    effort: 'medium',
    createdAt: 0,
    updatedAt: 0,
  );

  test('snapshotTeamSessionContinueOverrides pins create-time preset per binding',
      () {
    const team = TeamProfile(
      id: 'team',
      name: 'Team',
      teamMode: TeamMode.mixed,
      cli: CliTool.claude,
      activePresetId: 'preset-claude-a',
      members: [
        TeamMemberConfig(
          id: 'team-lead',
          name: 'Lead',
          activePresetId: TeamProfile.inheritPresetId,
        ),
      ],
    );
    const bindings = [
      SessionMemberBinding(
        rosterMemberId: 'team-lead-0',
        typeId: 'team-lead',
        taskId: 'task-1',
        cli: CliTool.claude,
      ),
    ];

    final snap = snapshotTeamSessionContinueOverrides(
      base: const SessionContinueOverrides(),
      team: team,
      bindings: bindings,
      globalPresets: const [claudePresetA, codexPreset],
    );

    expect(
      snap.memberOverrides['team-lead-0']?.presetId,
      'preset-claude-a',
    );
    expect(snap.memberOverrides['team-lead-0']?.provider, 'anthropic');
    expect(snap.memberOverrides['team-lead-0']?.model, 'claude-a');
  });

  test(
    'presetForSessionConnect uses snapshot when team preset changed cross-CLI',
    () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        sessionTeam: 'team',
        members: const [
          SessionMemberBinding(
            rosterMemberId: 'team-lead-0',
            typeId: 'team-lead',
            taskId: 'task-1',
            cli: CliTool.claude,
          ),
        ],
        continueOverrides: const SessionContinueOverrides(
          memberOverrides: {
            'team-lead-0': SessionMemberContinueOverride(
              presetId: 'preset-claude-a',
              provider: 'anthropic',
              model: 'claude-a',
            ),
          },
        ),
        createdAt: 1,
      );
      const liveTeam = TeamProfile(
        id: 'team',
        name: 'Team',
        teamMode: TeamMode.mixed,
        cli: CliTool.claude,
        activePresetId: 'preset-codex',
        members: [
          TeamMemberConfig(
            id: 'team-lead',
            name: 'Lead',
            activePresetId: TeamProfile.inheritPresetId,
          ),
        ],
      );
      const member = TeamMemberConfig(
        id: 'team-lead-0',
        name: 'Lead',
        activePresetId: TeamProfile.inheritPresetId,
      );

      final preset = presetForSessionConnect(
        session: session,
        team: liveTeam,
        member: member,
        memberBinding: session.members.single,
        globalPresets: const [claudePresetA, codexPreset],
      );

      expect(preset?.id, 'preset-claude-a');
    },
  );

  test(
    'memberForSessionConnect keeps locked CLI when live team preset is different CLI',
    () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        sessionTeam: 'team',
        members: const [
          SessionMemberBinding(
            rosterMemberId: 'team-lead-0',
            typeId: 'team-lead',
            taskId: 'task-1',
            cli: CliTool.claude,
          ),
        ],
        createdAt: 1,
      );
      const liveTeam = TeamProfile(
        id: 'team',
        name: 'Team',
        teamMode: TeamMode.mixed,
        cli: CliTool.claude,
        activePresetId: 'preset-codex',
        members: [
          TeamMemberConfig(
            id: 'team-lead',
            name: 'Lead',
            activePresetId: TeamProfile.inheritPresetId,
          ),
        ],
      );
      const member = TeamMemberConfig(
        id: 'team-lead-0',
        name: 'Lead',
        activePresetId: TeamProfile.inheritPresetId,
      );

      final launchMember = memberForSessionConnect(
        session: session,
        team: liveTeam,
        member: member,
        memberBinding: session.members.single,
        globalPresets: const [claudePresetA, codexPreset],
      );

      expect(launchMember.cli, CliTool.claude);
      expect(launchMember.provider, isNot('openai'));
    },
  );

  test(
    'finalize after snapshot keeps create-time provider when team preset changed',
    () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        sessionTeam: 'team',
        members: const [
          SessionMemberBinding(
            rosterMemberId: 'team-lead-0',
            typeId: 'team-lead',
            taskId: 'task-1',
            cli: CliTool.claude,
          ),
        ],
        continueOverrides: const SessionContinueOverrides(
          memberOverrides: {
            'team-lead-0': SessionMemberContinueOverride(
              presetId: 'preset-claude-a',
              provider: 'anthropic',
              model: 'claude-a',
            ),
          },
        ),
        createdAt: 1,
      );
      const liveTeam = TeamProfile(
        id: 'team',
        name: 'Team',
        teamMode: TeamMode.mixed,
        cli: CliTool.claude,
        activePresetId: 'preset-codex',
        members: [
          TeamMemberConfig(
            id: 'team-lead',
            name: 'Lead',
            activePresetId: TeamProfile.inheritPresetId,
          ),
        ],
      );
      const member = TeamMemberConfig(
        id: 'team-lead-0',
        name: 'Lead',
        activePresetId: TeamProfile.inheritPresetId,
      );
      final preset = presetForSessionConnect(
        session: session,
        team: liveTeam,
        member: member,
        memberBinding: session.members.single,
        globalPresets: const [claudePresetA, codexPreset],
      );
      final launchMember = memberForSessionConnect(
        session: session,
        team: liveTeam,
        member: member,
        memberBinding: session.members.single,
        globalPresets: const [claudePresetA, codexPreset],
      );

      final shellMember = finalizeSessionLaunchMember(
        session: session,
        baseMember: launchMember,
        memberId: 'team-lead-0',
        isSimple: false,
        preset: preset,
        withPreset: (m, p) {
          if (p == null) return m;
          return m.copyWith(
            provider: p.provider,
            model: p.model,
            effort: p.effort,
            cli: p.cli,
            updateCli: true,
          );
        },
      );

      expect(shellMember.provider, 'anthropic');
      expect(shellMember.model, 'claude-a');
      expect(shellMember.cli, CliTool.claude);
      expect(shellMember.id, 'team-lead-0');
    },
  );

  test(
    'memberForSessionConnect keeps numbered instance id for replicated type',
    () {
      const liveTeam = TeamProfile(
        id: 'team',
        name: 'Team',
        teamMode: TeamMode.mixed,
        cli: CliTool.claude,
        members: [
          TeamMemberConfig(
            id: 'builder',
            name: 'Builder',
            replicas: 2,
            responsibilities: 'Build things',
          ),
        ],
      );
      const member = TeamMemberConfig(
        id: 'builder-0',
        name: 'Builder #0',
        capabilities: {'builder'},
      );
      const binding = SessionMemberBinding(
        rosterMemberId: 'builder-0',
        typeId: 'builder',
        taskId: 'task-b0',
        cli: CliTool.claude,
      );
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        sessionTeam: 'team',
        members: const [binding],
        createdAt: 1,
      );

      final launchMember = memberForSessionConnect(
        session: session,
        team: liveTeam,
        member: member,
        memberBinding: binding,
        globalPresets: const [],
      );

      expect(launchMember.id, 'builder-0');
      expect(launchMember.name, 'Builder #0');
      expect(launchMember.responsibilities, 'Build things');
    },
  );
}
