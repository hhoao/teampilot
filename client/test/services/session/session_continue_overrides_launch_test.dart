import 'package:teampilot/models/launch_security_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/preset_resolver.dart';
import 'package:teampilot/services/launch/session_runtime_plan.dart';
import 'package:teampilot/services/session/session_continue_overrides_apply.dart';

/// Mirrors [SessionLifecycleService._memberWithPreset] for unit tests.
TeamMemberConfig _memberWithPreset(TeamMemberConfig member, CliPreset? preset) {
  if (preset == null) return member;
  return member.copyWith(
    provider: preset.provider.trim().isNotEmpty
        ? preset.provider.trim()
        : member.provider,
    model: preset.model.trim().isNotEmpty ? preset.model.trim() : member.model,
    effort: preset.effort.trim().isNotEmpty
        ? preset.effort.trim()
        : member.effort,
    cli: preset.cli,
    updateCli: true,
  );
}

/// Same merge order as `_buildShellLaunchContextFromPlan` / staging finalize.
TeamMemberConfig resolveShellLaunchMember({
  required AppSession session,
  required SessionRuntimePlan runtimePlan,
  CliPreset? preset,
}) {
  final isSimple = runtimePlan.mode == SessionRuntimeMode.simple;
  return finalizeSessionLaunchMember(
    session: session,
    baseMember: runtimePlan.member,
    memberId: isSimple ? session.sessionId : runtimePlan.memberId,
    isSimple: isSimple,
    preset: preset,
    withPreset: _memberWithPreset,
  );
}

void main() {
  const preset = CliPreset(
    id: 'p-template',
    name: 'Template',
    cli: CliTool.claude,
    provider: 'preset-provider',
    model: 'preset-model',
    effort: 'low',
    createdAt: 1,
    updatedAt: 1,
  );

  test('shell launch member: continue overrides win over template preset '
      '(provider + permission)', () {
    const base = TeamMemberConfig(
      id: 'builder-0',
      name: 'Builder',
      cli: CliTool.claude,
      provider: 'base-provider',
      model: 'base-model',
      launchSecurityPolicy: LaunchSecurityPolicy.cliDefault,
      activePresetId: 'p-template',
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team',
      createdAt: 1,
      continueOverrides: const SessionContinueOverrides(
        launchSecurityPolicy: LaunchSecurityPolicyOverride.fullAccess,
        memberOverrides: {
          'builder-0': SessionMemberContinueOverride(
            provider: 'override-provider',
            model: 'override-model',
            launchSecurityPolicy: LaunchSecurityPolicyOverride.fullAccess,
          ),
        },
      ),
    );
    final plan = SessionRuntimePlan(
      mode: SessionRuntimeMode.team,
      workspaceId: 'w1',
      sessionId: 's1',
      memberId: 'builder-0',
      expertKey: 'builder',
      teamId: 'team',
      presetId: 'p-template',
      runtimeBundle: const ConfigBundle(),
      member: base,
    );

    final shellMember = resolveShellLaunchMember(
      session: session,
      runtimePlan: plan,
      preset: preset,
    );

    // Fail if only an unused field were updated: shell member must carry
    // override provider + permission (what CliLaunchContext.member uses).
    expect(shellMember.provider, 'override-provider');
    expect(shellMember.model, 'override-model');
    expect(shellMember.launchSecurityPolicy.requiresDangerousExecution, isTrue);
    expect(shellMember.cli, CliTool.claude);

    // Preset alone would have won without finalize-last:
    final presetOnly = _memberWithPreset(base, preset);
    expect(presetOnly.provider, 'preset-provider');
    expect(presetOnly.provider, isNot(shellMember.provider));
  });

  test(
    'finalize then memberForLaunch keeps continue provider (team staging)',
    () {
      const base = TeamMemberConfig(
        id: 'builder-0',
        name: 'Builder',
        cli: CliTool.claude,
        provider: 'base-provider',
        model: 'base-model',
        launchSecurityPolicy: LaunchSecurityPolicy.cliDefault,
        activePresetId: 'p-template',
      );
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        sessionTeam: 'team',
        createdAt: 1,
        continueOverrides: const SessionContinueOverrides(
          memberOverrides: {
            'builder-0': SessionMemberContinueOverride(
              presetId: 'p-template',
              provider: 'override-provider',
              model: 'override-model',
              launchSecurityPolicy: LaunchSecurityPolicyOverride.fullAccess,
            ),
          },
        ),
      );

      final finalized = finalizeSessionLaunchMember(
        session: session,
        baseMember: base,
        memberId: 'builder-0',
        isSimple: false,
        preset: preset,
        withPreset: _memberWithPreset,
      );
      expect(finalized.provider, 'override-provider');
      expect(finalized.activePresetId, isNull);

      final team = TeamProfile(
        id: 'team',
        name: 'Team',
        cli: CliTool.claude,
        members: [base],
      );
      // Same path as stageTeamLaunch after orchestrator finalize.
      final staged = memberForLaunch(
        team: team,
        member: finalized,
        globalPresets: const [preset],
      );

      expect(staged.provider, 'override-provider');
      expect(staged.model, 'override-model');
      expect(staged.launchSecurityPolicy.requiresDangerousExecution, isTrue);

      // Old bug: leaving activePresetId set made memberForLaunch expand the
      // template preset and wipe continue provider/model.
      final buggy = memberForLaunch(
        team: team,
        member: finalized.copyWith(
          activePresetId: 'p-template',
          updateActivePresetId: true,
        ),
        globalPresets: const [preset],
      );
      expect(buggy.provider, 'preset-provider');
      expect(buggy.provider, isNot(staged.provider));
    },
  );

  test(
    'orchestrator then shell double-finalize still keeps overrides last',
    () {
      const base = TeamMemberConfig(
        id: 'builder-0',
        name: 'Builder',
        cli: CliTool.claude,
        provider: 'base',
        model: 'base-m',
        launchSecurityPolicy: LaunchSecurityPolicy.cliDefault,
      );
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        sessionTeam: 'team',
        createdAt: 1,
        continueOverrides: const SessionContinueOverrides(
          memberOverrides: {
            'builder-0': SessionMemberContinueOverride(
              provider: 'from-continue',
              launchSecurityPolicy: LaunchSecurityPolicyOverride.fullAccess,
            ),
          },
        ),
      );

      // Staging path (orchestrator):
      final staged = finalizeSessionLaunchMember(
        session: session,
        baseMember: base,
        memberId: 'builder-0',
        isSimple: false,
        preset: preset,
        withPreset: _memberWithPreset,
      );
      expect(staged.provider, 'from-continue');
      expect(staged.launchSecurityPolicy.requiresDangerousExecution, isTrue);

      // Shell path re-applies preset on already-finalized plan.member, then
      // overrides again — must not let preset wipe continue provider.
      final shellMember = resolveShellLaunchMember(
        session: session,
        runtimePlan: SessionRuntimePlan(
          mode: SessionRuntimeMode.team,
          workspaceId: 'w1',
          sessionId: 's1',
          memberId: 'builder-0',
          expertKey: 'builder',
          runtimeBundle: const ConfigBundle(),
          member: staged,
        ),
        preset: preset,
      );
      expect(shellMember.provider, 'from-continue');
      expect(
        shellMember.launchSecurityPolicy.requiresDangerousExecution,
        isTrue,
      );
    },
  );

  test('simple finalize applies session-level permission false', () {
    const base = TeamMemberConfig(
      id: 's1',
      name: 'Simple',
      cli: CliTool.codex,
      provider: 'openai',
      model: 'gpt',
      launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      cli: CliTool.codex,
      provider: 'openai',
      model: 'gpt',
      createdAt: 1,
      continueOverrides: const SessionContinueOverrides(
        launchSecurityPolicy: LaunchSecurityPolicyOverride.cliDefault,
      ),
    );

    final shellMember = resolveShellLaunchMember(
      session: session,
      runtimePlan: SessionRuntimePlan(
        mode: SessionRuntimeMode.simple,
        workspaceId: 'w1',
        sessionId: 's1',
        memberId: 's1',
        expertKey: 'default',
        runtimeBundle: const ConfigBundle(),
        member: base,
      ),
    );

    expect(
      shellMember.launchSecurityPolicy.requiresDangerousExecution,
      isFalse,
    );
    expect(shellMember.provider, 'openai');
    expect(shellMember.model, 'gpt');
    expect(shellMember.cli, CliTool.codex);
  });

  test('plan.copyWith replaces member used for staging', () {
    const base = TeamMemberConfig(
      id: 'builder-0',
      name: 'Builder',
      cli: CliTool.claude,
      provider: 'old',
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team',
      createdAt: 1,
      continueOverrides: const SessionContinueOverrides(
        memberOverrides: {
          'builder-0': SessionMemberContinueOverride(provider: 'staged'),
        },
      ),
    );
    final plan = SessionRuntimePlan(
      mode: SessionRuntimeMode.team,
      workspaceId: 'w1',
      sessionId: 's1',
      memberId: 'builder-0',
      expertKey: 'builder',
      runtimeBundle: const ConfigBundle(),
      member: base,
    );
    final finalized = finalizeSessionLaunchMember(
      session: session,
      baseMember: plan.member,
      memberId: 'builder-0',
      isSimple: false,
      preset: preset,
      withPreset: _memberWithPreset,
    );
    final stagedPlan = plan.copyWith(member: finalized);
    expect(stagedPlan.member.provider, 'staged');
    expect(identical(stagedPlan.member, finalized), isTrue);
  });
}
