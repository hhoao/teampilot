import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/session/session_preset_follow_sync.dart';

void main() {
  Future<({SessionRepository repo, AppSession session})> createSession({
    String sessionTeam = '',
    SessionContinueOverrides? continueOverrides,
  }) async {
    final temp = await Directory.systemTemp.createTemp('follow_sync_');
    addTearDown(() => temp.delete(recursive: true));
    final repo = SessionRepository(rootDir: temp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/w')]);
    final session = (await repo.createSession(
      workspace.workspaceId,
      sessionTeam: sessionTeam,
      rosterMembers: sessionTeam.isEmpty
          ? const []
          : const [TeamMemberConfig(id: 'builder-0', name: 'Builder')],
      memberClis: sessionTeam.isEmpty
          ? const {}
          : const {'builder-0': CliTool.cursor},
      provider: 'old-account',
      model: 'old-model',
      effort: 'low',
      continueOverrides: continueOverrides,
    )).session;
    return (repo: repo, session: session);
  }

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

  test('persists patched simple launch identity', () async {
    final (:repo, :session) = await createSession();
    final patched = session.copyWith(
      provider: 'new-account',
      model: 'composer-2.5',
      effort: 'high',
    );

    await persistFollowedSession(repo: repo, patched: patched, isSimple: true);

    final disk = (await repo.loadSessions()).single;
    expect(disk.provider, 'new-account');
    expect(disk.model, 'composer-2.5');
    expect(disk.effort, 'high');
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

  test('persists patched team continue overrides', () async {
    const overrides = SessionContinueOverrides(
      memberOverrides: {
        'builder-0': SessionMemberContinueOverride(
          presetId: 'p-cursor',
          provider: 'old-account',
          model: 'old-model',
          effort: 'low',
        ),
      },
    );
    final (:repo, :session) = await createSession(
      sessionTeam: 'team',
      continueOverrides: overrides,
    );
    final patched = session.copyWith(
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

    await persistFollowedSession(repo: repo, patched: patched, isSimple: false);

    expect(
      (await repo.loadSessions()).single.continueOverrides,
      patched.continueOverrides,
    );
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
