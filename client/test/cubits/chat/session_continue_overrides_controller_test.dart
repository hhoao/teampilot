import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/session_continue_overrides_controller.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';

void main() {
  const controller = SessionContinueOverridesController();

  AppSession _simpleSession() {
    return AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/w')],
      cli: CliTool.claude,
      provider: 'anthropic',
      model: 'claude-sonnet',
      effort: 'high',
      presetId: 'preset-a',
      createdAt: 1,
      updatedAt: 1,
    );
  }

  CliPreset _claudePreset({String id = 'preset-b'}) {
    return CliPreset(
      id: id,
      name: 'Beta',
      cli: CliTool.claude,
      provider: 'openai',
      model: 'gpt-4o',
      effort: 'medium',
      createdAt: 0,
      updatedAt: 0,
    );
  }

  group('patchPermission', () {
    test('writes session-level permission for Simple', () {
      final patched = controller.patchPermission(
        session: _simpleSession(),
        dangerouslySkipPermissions: true,
      );

      expect(
        patched.continueOverrides.dangerouslySkipPermissions,
        isTrue,
      );
      expect(patched.continueOverrides.memberOverrides, isEmpty);
    });

    test('writes per-member permission without touching other members', () {
      final session = _simpleSession().copyWith(
        sessionTeam: 'team-1',
        continueOverrides: const SessionContinueOverrides(
          memberOverrides: {
            'builder-0': SessionMemberContinueOverride(
              presetId: 'preset-a',
              provider: 'anthropic',
              model: 'claude-sonnet',
            ),
            'reviewer-0': SessionMemberContinueOverride(
              dangerouslySkipPermissions: true,
            ),
          },
        ),
      );

      final patched = controller.patchPermission(
        session: session,
        dangerouslySkipPermissions: false,
        memberId: 'builder-0',
      );

      expect(
        patched.continueOverrides.memberOverrides['builder-0']
            ?.dangerouslySkipPermissions,
        isFalse,
      );
      expect(
        patched.continueOverrides.memberOverrides['builder-0']?.presetId,
        'preset-a',
      );
      expect(
        patched.continueOverrides.memberOverrides['reviewer-0']
            ?.dangerouslySkipPermissions,
        isTrue,
      );
    });
  });

  group('patchPreset', () {
    test('same-CLI preset updates Simple identity fields', () {
      final patched = controller.patchPreset(
        session: _simpleSession(),
        preset: _claudePreset(),
        lockedCli: CliTool.claude,
      );

      expect(patched, isNotNull);
      expect(patched!.presetId, 'preset-b');
      expect(patched.provider, 'openai');
      expect(patched.model, 'gpt-4o');
      expect(patched.effort, 'medium');
    });

    test('cross-CLI preset is rejected', () {
      final patched = controller.patchPreset(
        session: _simpleSession(),
        preset: _claudePreset().copyWith(cli: CliTool.codex),
        lockedCli: CliTool.claude,
      );

      expect(patched, isNull);
    });

    test('team member preset expands override without touching other members', () {
      final session = _simpleSession().copyWith(
        sessionTeam: 'team-1',
        continueOverrides: const SessionContinueOverrides(
          memberOverrides: {
            'reviewer-0': SessionMemberContinueOverride(
              presetId: 'keep-me',
              provider: 'anthropic',
              model: 'claude-opus',
            ),
          },
        ),
      );

      final patched = controller.patchPreset(
        session: session,
        preset: _claudePreset(),
        memberId: 'builder-0',
        lockedCli: CliTool.claude,
      );

      expect(patched, isNotNull);
      final builder = patched!.continueOverrides.memberOverrides['builder-0'];
      expect(builder?.presetId, 'preset-b');
      expect(builder?.provider, 'openai');
      expect(builder?.model, 'gpt-4o');
      expect(builder?.effort, 'medium');
      expect(
        patched.continueOverrides.memberOverrides['reviewer-0']?.presetId,
        'keep-me',
      );
    });
  });
}
