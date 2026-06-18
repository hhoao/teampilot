import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../support/post_frame_test_harness.dart';

class _FakeTerminalSession extends TerminalSession {
  _FakeTerminalSession({required super.executable});

  @override
  bool get isRunning => false;

  @override
  void dispose() {}
}

Future<bool> _mcpEndpointAcceptsHttp(Uri endpoint) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(endpoint);
    req.headers.set('content-type', 'application/json');
    req.headers.set('X-Member', 'team-lead');
    req.add(
      utf8.encode(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 0,
          'method': 'initialize',
        }),
      ),
    );
    final resp = await req.close();
    await resp.drain();
    return resp.statusCode == HttpStatus.ok;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('ChatCubit mixed team bus', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit cubit;
    late PostFrameTestHarness postFrame;

    const team = TeamProfile(
      id: 'team-mixed',
      name: 'Mixed',
      teamMode: TeamMode.mixed,
      members: [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'worker-1', name: 'developer'),
      ],
    );

    setUp(() async {
      HttpOverrides.global = null;
      tmp = await Directory.systemTemp.createTemp('chat_team_bus_');
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
      cubit = ChatCubit(
        executableResolver: () => 'true',
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                _FakeTerminalSession(executable: executable),
      );
    });

    tearDown(() async {
      await postFrame.flush();
      await drainPendingAsyncWork();
      await cubit.close();
      await drainPendingAsyncWork();
      await deleteTempDirBestEffort(tmp);
    });

    test('openSessionTab creates TeamBus and loopback MCP server', () async {
      final workspace = await repo.createWorkspace('/tmp');
      final session = await repo.createSession(
        workspace.workspaceId,
        sessionTeam: team.id,
        rosterMembers: team.members,
      );

      await cubit.openSessionTab(
        session,
        team: team,
        member: team.members.first,
        repo: repo,
        connectImmediately: false,
      );

      expect(cubit.hasTeamBusResources(session.sessionId), isTrue);
      final endpoint = cubit.teammateBusMcpEndpointForSession(
        session.sessionId,
      );
      expect(endpoint, isNotNull);
      expect(await _mcpEndpointAcceptsHttp(endpoint!), isTrue);
    });

    test('closeTab stops MCP server and clears bus resources', () async {
      final workspace = await repo.createWorkspace('/tmp');
      final session = await repo.createSession(
        workspace.workspaceId,
        sessionTeam: team.id,
        rosterMembers: team.members,
      );

      await cubit.openSessionTab(
        session,
        team: team,
        member: team.members.first,
        repo: repo,
        connectImmediately: false,
      );
      final endpoint = cubit.teammateBusMcpEndpointForSession(
        session.sessionId,
      )!;
      expect(cubit.state.tabs.length, 1);

      cubit.closeTab(0);
      await drainPendingAsyncWork();

      expect(cubit.hasTeamBusResources(session.sessionId), isFalse);
      expect(
        cubit.teammateBusMcpEndpointForSession(session.sessionId),
        isNull,
      );
      expect(await _mcpEndpointAcceptsHttp(endpoint), isFalse);
    });
  });
}
