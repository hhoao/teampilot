import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('ChatCubit continue override APIs', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit cubit;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('chat_continue_overrides_');
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

    CliPreset claudePreset({String id = 'preset-b'}) {
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

    test(
      'setSessionContinuePreset persists same-CLI Simple identity',
      () async {
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/w'),
        ]);
        final session = (await repo.createSession(
          workspace.workspaceId,
          cli: CliTool.claude,
          provider: 'anthropic',
          model: 'claude-sonnet',
          effort: 'high',
          presetId: 'preset-a',
        )).session;
        await cubit.loadWorkspaceData(repo);

        final ok = await cubit.setSessionContinuePreset(
          sessionId: session.sessionId,
          preset: claudePreset(),
          lockedCli: CliTool.claude,
        );

        expect(ok, isTrue);
        final memory = cubit.state.sessions.single;
        expect(memory.presetId, 'preset-b');
        expect(memory.provider, 'openai');
        expect(memory.model, 'gpt-4o');

        final disk = (await repo.loadSessions()).single;
        expect(disk.presetId, 'preset-b');
        expect(disk.provider, 'openai');
        expect(disk.model, 'gpt-4o');
      },
    );

    test('setSessionContinuePreset rejects cross-CLI preset', () async {
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/w'),
      ]);
      final session = (await repo.createSession(
        workspace.workspaceId,
        cli: CliTool.claude,
        presetId: 'preset-a',
      )).session;
      await cubit.loadWorkspaceData(repo);

      final ok = await cubit.setSessionContinuePreset(
        sessionId: session.sessionId,
        preset: claudePreset().copyWith(cli: CliTool.codex),
        lockedCli: CliTool.claude,
      );

      expect(ok, isFalse);
      expect(cubit.state.sessions.single.presetId, 'preset-a');
      expect((await repo.loadSessions()).single.presetId, 'preset-a');
    });

    test('setSessionContinuePreset isolates team member overrides', () async {
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/w'),
      ]);
      final session = (await repo.createSession(
        workspace.workspaceId,
        sessionTeam: 'team-1',
        rosterMembers: const [
          TeamMemberConfig(id: 'builder-0', name: 'Builder'),
          TeamMemberConfig(id: 'reviewer-0', name: 'Reviewer'),
        ],
        continueOverrides: const SessionContinueOverrides(
          memberOverrides: {
            'reviewer-0': SessionMemberContinueOverride(
              presetId: 'keep-me',
              provider: 'anthropic',
              model: 'claude-opus',
            ),
          },
        ),

        memberClis: const {
          'builder-0': CliTool.claude,
          'reviewer-0': CliTool.claude,
        },
      )).session;
      await cubit.loadWorkspaceData(repo);

      final ok = await cubit.setSessionContinuePreset(
        sessionId: session.sessionId,
        preset: claudePreset(),
        memberId: 'builder-0',
        lockedCli: CliTool.claude,
      );

      expect(ok, isTrue);
      final memory = cubit.state.sessions.single.continueOverrides;
      expect(memory.memberOverrides['builder-0']?.presetId, 'preset-b');
      expect(memory.memberOverrides['reviewer-0']?.presetId, 'keep-me');

      final disk = (await repo.loadSessions()).single.continueOverrides;
      expect(disk.memberOverrides['builder-0']?.presetId, 'preset-b');
      expect(disk.memberOverrides['reviewer-0']?.presetId, 'keep-me');
    });

    test('setSessionContinuePermission persists session-level bool', () async {
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/w'),
      ]);
      final session = (await repo.createSession(workspace.workspaceId)).session;
      await cubit.loadWorkspaceData(repo);

      final ok = await cubit.setSessionContinuePermission(
        sessionId: session.sessionId,
        dangerouslySkipPermissions: true,
      );

      expect(ok, isTrue);
      expect(
        cubit
            .state
            .sessions
            .single
            .continueOverrides
            .dangerouslySkipPermissions,
        isTrue,
      );
      expect(
        (await repo.loadSessions())
            .single
            .continueOverrides
            .dangerouslySkipPermissions,
        isTrue,
      );
    });

    test(
      'setSessionContinuePermission returns false when session missing',
      () async {
        final ok = await cubit.setSessionContinuePermission(
          sessionId: 'missing',
          dangerouslySkipPermissions: true,
        );

        expect(ok, isFalse);
      },
    );
  });
}
