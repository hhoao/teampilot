import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import '../support/in_memory_filesystem.dart';

void main() {
  Future<({SessionRepository repo, AppSession session})> simpleSession() async {
    final tmp = await Directory.systemTemp.createTemp('fs_continue_overrides_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(
      rootDir: tmp.path,
      storage: fakeHomeStorage(),
    );
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/w')]);
    final session = (await repo.createSession(
      workspace.workspaceId,
      cli: CliTool.claude,
      provider: 'anthropic',
      model: 'claude-sonnet',
      effort: 'high',
      presetId: 'preset-a',
    )).session;
    return (repo: repo, session: session);
  }

  test('updateContinueOverrides round-trips on disk', () async {
    final (:repo, :session) = await simpleSession();
    const overrides = SessionContinueOverrides(
      memberOverrides: {
        'team-lead': SessionMemberContinueOverride(
          provider: 'openai',
          model: 'gpt-4',
        ),
      },
    );

    await repo.updateContinueOverrides(session.sessionId, overrides);

    final disk = (await repo.loadSessions()).single;
    expect(disk.continueOverrides, overrides);
  });

  test(
    'updateSimpleLaunchIdentity updates fields without clearing continueOverrides',
    () async {
      final (:repo, :session) = await simpleSession();
      const overrides = SessionContinueOverrides(
        memberOverrides: {
          'team-lead': SessionMemberContinueOverride(provider: 'openai'),
        },
      );
      await repo.updateContinueOverrides(session.sessionId, overrides);

      await repo.updateSimpleLaunchIdentity(
        session.sessionId,
        presetId: 'preset-b',
        provider: 'openai',
        model: 'gpt-4o',
        effort: 'medium',
      );

      final disk = (await repo.loadSessions()).single;
      expect(disk.presetId, 'preset-b');
      expect(disk.provider, 'openai');
      expect(disk.model, 'gpt-4o');
      expect(disk.effort, 'medium');
      expect(disk.continueOverrides, overrides);
    },
  );

  test('createSession persists optional continueOverrides', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_continue_overrides_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(
      rootDir: tmp.path,
      storage: fakeHomeStorage(),
    );
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/w')]);
    const overrides = SessionContinueOverrides(
      memberOverrides: {
        'team-lead': SessionMemberContinueOverride(provider: 'openai'),
      },
    );
    final session = (await repo.createSession(
      workspace.workspaceId,
      continueOverrides: overrides,
    )).session;

    expect(session.continueOverrides, overrides);
    expect((await repo.loadSessions()).single.continueOverrides, overrides);
  });

  test('updateContinueOverrides no-ops for unknown sessionId', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_continue_overrides_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(
      rootDir: tmp.path,
      storage: fakeHomeStorage(),
    );

    await repo.updateContinueOverrides(
      'unknown-session-id',
      const SessionContinueOverrides(),
    );

    expect(await repo.loadSessions(), isEmpty);
  });

  test('updateSimpleLaunchIdentity no-ops for unknown sessionId', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_continue_overrides_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(
      rootDir: tmp.path,
      storage: fakeHomeStorage(),
    );

    await repo.updateSimpleLaunchIdentity(
      'unknown-session-id',
      presetId: 'x',
      provider: 'y',
      model: 'z',
      effort: 'low',
    );

    expect(await repo.loadSessions(), isEmpty);
  });
}
