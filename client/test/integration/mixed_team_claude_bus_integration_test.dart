@Tags(['integration'])
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../support/post_frame_test_harness.dart';
import 'support/mixed_team_integration_harness.dart';

void main() {
  setUp(() {
    HttpOverrides.global = null;
    setUpTestAppStorage();
  });
  tearDown(tearDownTestAppStorage);

  test('two Claude members exchange ping/pong via ChatCubit launch path', () async {
    if (!MixedTeamIntegrationHarness.nativePtyAvailable) {
      markTestSkipped('Requires libflutter_pty.so');
      return;
    }
    final claudePath = MixedTeamIntegrationHarness.resolveClaudePath();
    if (claudePath == null) {
      markTestSkipped('claude not on PATH');
      return;
    }

    final harness = MixedTeamIntegrationHarness(claudePath: claudePath);
    final postFrame = PostFrameTestHarness();
    AppSession? session;
    try {
      await harness.startMockServer();
      await harness.writeMockProviders();
      final repo = SessionRepository();
      final cubit = harness.createCubit(postFrame: postFrame);
      harness.cubit = cubit;

      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: AppStorage.cwd),
      ]);
      session = await repo.createSession(
        workspace.workspaceId,
        sessionTeam: kItMixedClaudeTeam.id,
        rosterMembers: kItMixedClaudeTeam.members,
      );

      await cubit.openSessionTab(
        session,
        team: kItMixedClaudeTeam,
        member: kLeadMember,
        repo: repo,
        connectImmediately: true,
      );
      await postFrame.flush();
      await harness.waitUntilMembersReady(
        cubit,
        [kLeadMember.id, kWorkerMember.id],
      );
      await harness.kickoffMembers(cubit, postFrame: postFrame);
      await harness.waitForPingPong(
        workspaceId: session.workspaceId,
        sessionId: session.sessionId,
      );

      expect(cubit.hasTeamBusResources(session.sessionId), isTrue);
    } catch (e, st) {
      await harness.dumpFailureArtifacts(
        workspaceId: session?.workspaceId,
        sessionId: session?.sessionId,
      );
      Error.throwWithStackTrace(e, st);
    } finally {
      await harness.dispose();
      await postFrame.flush();
      await drainPendingAsyncWork();
      // Let Claude PTY children release config dir handles before tearDown.
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  });
}
