import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/session_preset_follow_sync.dart';

void main() {
  const cursorPreset = CliPreset(
    id: 'p-cursor',
    name: 'Cursor',
    cli: CliTool.cursor,
    provider: 'new-account',
    model: 'composer-2.5',
    effort: 'high',
    createdAt: 1,
    updatedAt: 9,
  );

  test('simple stale following session is patched', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      cli: CliTool.cursor,
      presetId: 'p-cursor',
      provider: 'old-account',
      model: 'old-model',
      effort: 'low',
      createdAt: 1,
    );
    final patched = staleFollowingSimpleSession(
      session: session,
      presets: const [cursorPreset],
    );
    expect(patched, isNotNull);
    expect(patched!.provider, 'new-account');
    expect(patched.model, 'composer-2.5');
    expect(patched.effort, 'high');
    expect(patched.presetId, 'p-cursor');
    expect(patched.cli, CliTool.cursor);
  });

  test('simple matching fields returns null', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      cli: CliTool.cursor,
      presetId: 'p-cursor',
      provider: 'new-account',
      model: 'composer-2.5',
      effort: 'high',
      createdAt: 1,
    );
    expect(
      staleFollowingSimpleSession(
        session: session,
        presets: const [cursorPreset],
      ),
      isNull,
    );
  });

  test('simple detached (empty presetId) returns null', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      cli: CliTool.cursor,
      provider: 'old-account',
      model: 'old-model',
      createdAt: 1,
    );
    expect(
      staleFollowingSimpleSession(
        session: session,
        presets: const [cursorPreset],
      ),
      isNull,
    );
  });

  test('team stale following member override is patched', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team',
      createdAt: 1,
      continueOverrides: const SessionContinueOverrides(
        memberOverrides: {
          'builder-0': SessionMemberContinueOverride(
            presetId: 'p-cursor',
            provider: 'old-account',
            model: 'old-model',
            effort: 'low',
          ),
        },
      ),
    );
    final patched = staleFollowingTeamSession(
      session: session,
      memberId: 'builder-0',
      presets: const [cursorPreset],
      lockedCli: CliTool.cursor,
    );
    expect(patched, isNotNull);
    final override = patched!.continueOverrides.memberOverrides['builder-0']!;
    expect(override.presetId, 'p-cursor');
    expect(override.provider, 'new-account');
    expect(override.model, 'composer-2.5');
    expect(override.effort, 'high');
  });

  test('team matching override returns null', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team',
      createdAt: 1,
      continueOverrides: const SessionContinueOverrides(
        memberOverrides: {
          'builder-0': SessionMemberContinueOverride(
            presetId: 'p-cursor',
            provider: 'new-account',
            model: 'composer-2.5',
            effort: 'high',
          ),
        },
      ),
    );
    expect(
      staleFollowingTeamSession(
        session: session,
        memberId: 'builder-0',
        presets: const [cursorPreset],
        lockedCli: CliTool.cursor,
      ),
      isNull,
    );
  });
}
