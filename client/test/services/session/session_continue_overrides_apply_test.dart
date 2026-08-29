import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/session_continue_overrides_apply.dart';

void main() {
  test('security policy overrides merge member > session > launchDefault', () {
    expect(
      resolveContinueSecurityPolicy(
        sessionLevel: const LaunchSecurityPolicyOverride(
          approval: LaunchApprovalPolicy.ask,
        ),
        memberLevel: const LaunchSecurityPolicyOverride(
          sandbox: LaunchSandboxPolicy.readOnly,
        ),
        launchDefault: LaunchSecurityPolicy.fullAccess,
      ),
      const LaunchSecurityPolicy(
        approval: LaunchApprovalPolicy.ask,
        sandbox: LaunchSandboxPolicy.readOnly,
        hookTrust: LaunchHookTrustPolicy.bypass,
      ),
    );
    expect(
      resolveContinueSecurityPolicy(
        sessionLevel: const LaunchSecurityPolicyOverride(
          approval: LaunchApprovalPolicy.ask,
        ),
        launchDefault: const LaunchSecurityPolicy(
          sandbox: LaunchSandboxPolicy.workspaceWrite,
        ),
      ),
      const LaunchSecurityPolicy(
        approval: LaunchApprovalPolicy.ask,
        sandbox: LaunchSandboxPolicy.workspaceWrite,
      ),
    );
    expect(
      resolveContinueSecurityPolicy(
        launchDefault: const LaunchSecurityPolicy(
          hookTrust: LaunchHookTrustPolicy.trustedOnly,
        ),
      ),
      const LaunchSecurityPolicy(hookTrust: LaunchHookTrustPolicy.trustedOnly),
    );
  });

  test(
    'team deleted-preset without livePreset stamps snapshot and policy; CLI unchanged',
    () {
      const base = TeamMemberConfig(
        id: 'builder-0',
        name: 'Builder',
        cli: CliTool.claude,
        provider: 'old',
        model: 'old-m',
        launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
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
              presetId: 'p1',
              provider: 'new',
              model: 'new-m',
              effort: 'high',
              launchSecurityPolicy: LaunchSecurityPolicyOverride.cliDefault,
            ),
          },
        ),
      );
      final out = applySessionContinueOverrides(
        baseMember: base,
        session: session,
        memberId: 'builder-0',
        isSimple: false,
      );
      expect(out.cli, CliTool.claude);
      expect(out.provider, 'new');
      expect(out.model, 'new-m');
      expect(out.effort, 'high');
      // Concrete fields clear activePresetId so memberForLaunch cannot re-expand
      // a template preset over continue provider/model (presetId stays on override).
      expect(out.activePresetId, isNull);
      expect(out.launchSecurityPolicy.requiresDangerousExecution, isFalse);
    },
  );

  test(
    'team follow with live preset keeps withPreset fields and activePresetId',
    () {
      const live = CliPreset(
        id: 'p1',
        name: 'Live',
        cli: CliTool.claude,
        provider: 'live-provider',
        model: 'live-model',
        effort: 'low',
        createdAt: 1,
        updatedAt: 2,
      );
      const base = TeamMemberConfig(
        id: 'builder-0',
        name: 'Builder',
        cli: CliTool.claude,
        provider: 'live-provider',
        model: 'live-model',
        effort: 'low',
        launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
      );
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        sessionTeam: 'team',
        createdAt: 1,
        continueOverrides: const SessionContinueOverrides(
          memberOverrides: {
            'builder-0': SessionMemberContinueOverride(
              presetId: 'p1',
              provider: 'stale-provider',
              model: 'stale-model',
              effort: 'high',
            ),
          },
        ),
      );
      final out = applySessionContinueOverrides(
        baseMember: base,
        session: session,
        memberId: 'builder-0',
        isSimple: false,
        livePreset: live,
      );
      expect(out.provider, 'live-provider');
      expect(out.model, 'live-model');
      expect(out.effort, 'low');
      expect(out.activePresetId, 'p1');
      expect(out.cli, CliTool.claude);
    },
  );

  test('team follow CLI mismatch still stamps snapshot', () {
    const live = CliPreset(
      id: 'p1',
      name: 'Live',
      cli: CliTool.cursor,
      provider: 'cursor-account',
      model: 'composer-2.5',
      createdAt: 1,
      updatedAt: 2,
    );
    const base = TeamMemberConfig(
      id: 'builder-0',
      name: 'Builder',
      cli: CliTool.claude,
      provider: 'keep',
      model: 'keep-m',
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team',
      createdAt: 1,
      continueOverrides: const SessionContinueOverrides(
        memberOverrides: {
          'builder-0': SessionMemberContinueOverride(
            presetId: 'p1',
            provider: 'snap',
            model: 'snap-m',
          ),
        },
      ),
    );
    final out = applySessionContinueOverrides(
      baseMember: base,
      session: session,
      memberId: 'builder-0',
      isSimple: false,
      livePreset: live,
    );
    expect(out.provider, 'snap');
    expect(out.model, 'snap-m');
    expect(out.activePresetId, isNull);
    expect(out.cli, CliTool.claude);
  });

  test(
    'simple merge applies session-level policy; keeps base provider/model/cli',
    () {
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
      final out = applySessionContinueOverrides(
        baseMember: base,
        session: session,
        memberId: 's1',
        isSimple: true,
      );
      expect(out.cli, CliTool.codex);
      expect(out.provider, 'openai');
      expect(out.model, 'gpt');
      expect(out.launchSecurityPolicy.requiresDangerousExecution, isFalse);
    },
  );

  test('simple finalize sets member.id to session.sessionId for X-Member', () {
    const base = TeamMemberConfig(
      id: 'expert-pack-slug',
      name: 'Simple',
      cli: CliTool.claude,
    );
    final session = AppSession(
      sessionId: 'sess-abc',
      workspaceId: 'w1',
      cli: CliTool.claude,
      createdAt: 1,
    );
    final out = finalizeSessionLaunchMember(
      session: session,
      baseMember: base,
      memberId: session.sessionId,
      isSimple: true,
    );
    expect(out.id, session.sessionId);
    expect(out.id, isNot('expert-pack-slug'));
  });

  test('other member overrides do not affect this member', () {
    const base = TeamMemberConfig(
      id: 'builder-0',
      name: 'Builder',
      cli: CliTool.claude,
      provider: 'keep',
      model: 'keep-m',
      launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team',
      createdAt: 1,
      continueOverrides: const SessionContinueOverrides(
        memberOverrides: {
          'other': SessionMemberContinueOverride(
            provider: 'x',
            model: 'y',
            launchSecurityPolicy: LaunchSecurityPolicyOverride.cliDefault,
          ),
        },
      ),
    );
    final out = applySessionContinueOverrides(
      baseMember: base,
      session: session,
      memberId: 'builder-0',
      isSimple: false,
    );
    expect(out.provider, 'keep');
    expect(out.model, 'keep-m');
    expect(out.launchSecurityPolicy.requiresDangerousExecution, isTrue);
  });

  test(
    'team merge with only presetId sets activePresetId for launch expand',
    () {
      const base = TeamMemberConfig(
        id: 'builder-0',
        name: 'Builder',
        cli: CliTool.claude,
        provider: 'keep',
        model: 'keep-m',
      );
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        sessionTeam: 'team',
        createdAt: 1,
        continueOverrides: const SessionContinueOverrides(
          memberOverrides: {
            'builder-0': SessionMemberContinueOverride(presetId: 'p-only'),
          },
        ),
      );
      final out = applySessionContinueOverrides(
        baseMember: base,
        session: session,
        memberId: 'builder-0',
        isSimple: false,
      );
      expect(out.activePresetId, 'p-only');
      expect(out.provider, 'keep');
      expect(out.model, 'keep-m');
    },
  );
}
