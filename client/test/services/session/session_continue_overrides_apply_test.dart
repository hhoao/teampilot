import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/session_continue_overrides_apply.dart';

void main() {
  test('permission: member > session > launchDefault', () {
    expect(
      resolveContinueSkipPermissions(
        sessionLevel: true,
        memberLevel: false,
        launchDefault: true,
      ),
      isFalse,
    );
    expect(
      resolveContinueSkipPermissions(
        sessionLevel: true,
        memberLevel: null,
        launchDefault: false,
      ),
      isTrue,
    );
    expect(
      resolveContinueSkipPermissions(
        sessionLevel: null,
        memberLevel: null,
        launchDefault: true,
      ),
      isTrue,
    );
  });

  test('team merge applies provider/model/effort/preset and permission; CLI unchanged', () {
    const base = TeamMemberConfig(
      id: 'builder-0',
      name: 'Builder',
      cli: CliTool.claude,
      provider: 'old',
      model: 'old-m',
      dangerouslySkipPermissions: true,
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team',
      createdAt: 1,
      continueOverrides: const SessionContinueOverrides(
        dangerouslySkipPermissions: true,
        memberOverrides: {
          'builder-0': SessionMemberContinueOverride(
            presetId: 'p1',
            provider: 'new',
            model: 'new-m',
            effort: 'high',
            dangerouslySkipPermissions: false,
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
    expect(out.dangerouslySkipPermissions, isFalse);
  });

  test('simple merge applies session-level permission; keeps base provider/model/cli', () {
    const base = TeamMemberConfig(
      id: 's1',
      name: 'Simple',
      cli: CliTool.codex,
      provider: 'openai',
      model: 'gpt',
      dangerouslySkipPermissions: true,
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      cli: CliTool.codex,
      provider: 'openai',
      model: 'gpt',
      createdAt: 1,
      continueOverrides: const SessionContinueOverrides(
        dangerouslySkipPermissions: false,
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
    expect(out.dangerouslySkipPermissions, isFalse);
  });

  test('other member overrides do not affect this member', () {
    const base = TeamMemberConfig(
      id: 'builder-0',
      name: 'Builder',
      cli: CliTool.claude,
      provider: 'keep',
      model: 'keep-m',
      dangerouslySkipPermissions: true,
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
            dangerouslySkipPermissions: false,
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
    expect(out.dangerouslySkipPermissions, isTrue);
  });

  test('team merge with only presetId sets activePresetId for launch expand', () {
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
  });
}
