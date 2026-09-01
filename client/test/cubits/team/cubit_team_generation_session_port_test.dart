import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/team/cubit_team_generation_session_port.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/failed_message_store.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/fake_ai_history_registry.dart';
import '../../support/post_frame_test_harness.dart';

class _FakeAdapter implements AiTranscriptAdapter {
  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async => const [];
}

AiHistoryLoader _stubLoader() => AiHistoryLoader(
  contextBuilder: const SessionHistoryContextBuilder(),
  resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
    target: RuntimeTarget.local(),
    filesystem: LocalFilesystem(),
    home: '/tmp/team-generation-port',
    cwd: '/tmp/team-generation-port',
    appDataRoot: '/tmp/team-generation-port',
    paths: AppPaths('/tmp/team-generation-port'),
  ),
  registry: fakeAiHistoryRegistry(cli: CliTool.claude, adapter: _FakeAdapter()),
);

class _SessionRepository extends Fake implements SessionRepository {
  _SessionRepository(this.session);

  final AppSession session;

  @override
  Future<AppSession?> findById(String sessionId) async =>
      sessionId == session.sessionId ? session : null;
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'history seed fails when ChatCubit cannot persist a pending record',
    () async {
      final chatCubit = testChatCubit(executableResolver: () => 'true');
      addTearDown(chatCubit.close);
      final port = CubitTeamGenerationSessionPort(
        chatCubit: chatCubit,
        workbenchCubit: WorkbenchCubit(),
        sessionRepository: _SessionRepository(
          AppSession(sessionId: 'builder', workspaceId: 'ws', createdAt: 1),
        ),
      );

      await expectLater(
        port.persistHistoryPending(
          'builder',
          'builder',
          'Build the team',
          deliveryId: 'teamgen-kickoff-123',
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'generation history seed preserves leading and trailing prompt whitespace',
    () async {
      const sessionId = 'generated-lead';
      const originalPrompt = '  plan the release\n  ';
      final chatCubit = testChatCubit(executableResolver: () => 'true');
      chatCubit.historyLoader = _stubLoader();
      addTearDown(chatCubit.close);
      final port = CubitTeamGenerationSessionPort(
        chatCubit: chatCubit,
        workbenchCubit: WorkbenchCubit(),
        sessionRepository: _SessionRepository(
          AppSession(
            sessionId: sessionId,
            workspaceId: 'ws',
            createdAt: 1,
            sessionTeam: 'generated-team',
          ),
        ),
      );

      await port.persistHistoryPending(
        sessionId,
        'team-lead',
        originalPrompt,
        deliveryId: 'teamgen-prompt-123',
      );

      final records = await FailedMessageStore(
        fs: AppStorage.fs,
        rootPath: AppStorage.appDataRoot,
      ).load('ws', sessionId);
      expect(records.single.text, originalPrompt);
    },
  );
}
