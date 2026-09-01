import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/team/cubit_team_generation_session_port.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/repositories/session_repository.dart';

import '../../support/post_frame_test_harness.dart';

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
}
