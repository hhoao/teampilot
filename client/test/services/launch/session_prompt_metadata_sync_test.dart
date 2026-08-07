import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/launch/session_prompt_metadata_sync.dart';

void main() {
  late _FakeHost host;
  late SessionPromptMetadataSync sync;

  setUp(() {
    host = _FakeHost();
    sync = SessionPromptMetadataSync(host: host, state: () => host.state);
  });

  test('applyFirstPromptTitle renames empty display from landing prompt', () async {
    host.state = ChatState(
      sessions: [
        AppSession(
          sessionId: 'sess-1',
          workspaceId: 'ws-1',
          createdAt: 1,
        ),
      ],
    );

    await sync.applyFirstPromptTitle('sess-1', '  fix the landing title  ');

    expect(host.renames, [('sess-1', 'fix the landing title')]);
  });

  test('applyFirstPromptTitle skips when display already set', () async {
    host.state = ChatState(
      sessions: [
        AppSession(
          sessionId: 'sess-1',
          workspaceId: 'ws-1',
          display: 'Manual title',
          createdAt: 1,
        ),
      ],
    );

    await sync.applyFirstPromptTitle('sess-1', 'should not win');

    expect(host.renames, isEmpty);
  });

  test('applyFirstPromptTitle skips blank prompts', () async {
    host.state = ChatState(
      sessions: [
        AppSession(
          sessionId: 'sess-1',
          workspaceId: 'ws-1',
          createdAt: 1,
        ),
      ],
    );

    await sync.applyFirstPromptTitle('sess-1', '   \n  ');

    expect(host.renames, isEmpty);
  });
}

class _FakeRepo extends Fake implements SessionRepository {}

class _FakeHost implements SessionLaunchHost {
  @override
  ChatState state = const ChatState();
  final renames = <(String, String)>[];
  final _repo = _FakeRepo();

  @override
  bool get isClosed => false;

  @override
  SessionRepository? get sessionRepository => _repo;

  @override
  Future<void> renameSession(
    SessionRepository repo,
    String sessionId,
    String newName,
  ) async {
    renames.add((sessionId, newName));
  }

  @override
  bool isSessionConnecting(String sessionId) => false;

  @override
  bool get hasConnectingSession => false;

  @override
  void setMaterializingInFlight(bool value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) return null;
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}
