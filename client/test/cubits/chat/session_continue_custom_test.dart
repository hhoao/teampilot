import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('ChatCubit.setSessionContinueCustom', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit cubit;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('chat_continue_custom_');
      repo = SessionRepository(rootDir: tmp.path);
      cubit = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
      );
    });

    tearDown(() async {
      await cubit.close();
      await deleteTempDirBestEffort(tmp);
    });

    test(
      'setSessionContinueCustom clears presetId and updates provider/model/effort',
      () async {
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/w'),
        ]);
        final session = await repo.createSession(
          workspace.workspaceId,
          cli: CliTool.cursor,
          provider: 'anthropic',
          model: 'claude-sonnet',
          effort: 'high',
          presetId: 'p1',
        );
        await cubit.loadWorkspaceData(repo);

        final ok = await cubit.setSessionContinueCustom(
          sessionId: session.sessionId,
          provider: 'openai',
          model: 'gpt-4o',
          effort: 'medium',
        );

        expect(ok, isTrue);
        final memory = cubit.state.sessions.single;
        expect(memory.presetId, '');
        expect(memory.provider, 'openai');
        expect(memory.model, 'gpt-4o');
        expect(memory.effort, 'medium');
        expect(memory.cli, CliTool.cursor);

        final disk = (await repo.loadSessions()).single;
        expect(disk.presetId, '');
        expect(disk.provider, 'openai');
        expect(disk.model, 'gpt-4o');
        expect(disk.effort, 'medium');
        expect(disk.cli, CliTool.cursor);
      },
    );

    test('returns false for team sessions', () async {
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/w'),
      ]);
      final session = await repo.createSession(
        workspace.workspaceId,
        sessionTeam: 'team-1',
        rosterMembers: const [
          TeamMemberConfig(id: 'builder-0', name: 'Builder'),
        ],
        memberClis: const {'builder-0': CliTool.claude},
      );
      await cubit.loadWorkspaceData(repo);

      final ok = await cubit.setSessionContinueCustom(
        sessionId: session.sessionId,
        provider: 'openai',
        model: 'gpt-4o',
        effort: 'medium',
      );

      expect(ok, isFalse);
      final memory = cubit.state.sessions.single;
      expect(memory.sessionTeam, 'team-1');
      expect(memory.provider, '');
      expect(memory.model, '');
      expect(memory.effort, '');

      final disk = (await repo.loadSessions()).single;
      expect(disk.sessionTeam, 'team-1');
      expect(disk.provider, '');
      expect(disk.model, '');
      expect(disk.effort, '');
    });

    test('returns false when session missing', () async {
      final ok = await cubit.setSessionContinueCustom(
        sessionId: 'missing',
        provider: 'openai',
        model: 'gpt-4o',
        effort: 'medium',
      );

      expect(ok, isFalse);
    });
  });
}
