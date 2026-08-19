import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/cubits/chat/session_data_store.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/launch/session_prompt_metadata_sync.dart';

void main() {
  late _FakeHost host;
  late _FakeRepo repo;
  late int nowMs;
  late SessionPromptMetadataSync sync;

  AppSession session({
    String id = 'sess-1',
    int updatedAt = 1,
    String display = '',
  }) {
    return AppSession(
      sessionId: id,
      workspaceId: 'ws-1',
      display: display,
      createdAt: 1,
      updatedAt: updatedAt,
    );
  }

  setUp(() {
    repo = _FakeRepo();
    host = _FakeHost(repo);
    nowMs = 10_000;
    host.state = ChatState(sessions: [session()]);
    sync = SessionPromptMetadataSync(
      host: host,
      state: () => host.state,
      nowMs: () => nowMs,
    );
  });

  test('applyFirstPromptTitle renames empty display from landing prompt', () async {
    await sync.applyFirstPromptTitle('sess-1', '  fix the landing title  ');

    expect(host.renames, [('sess-1', 'fix the landing title')]);
  });

  test('applyFirstPromptTitle skips when display already set', () async {
    host.state = ChatState(sessions: [session(display: 'Manual title')]);

    await sync.applyFirstPromptTitle('sess-1', 'should not win');

    expect(host.renames, isEmpty);
  });

  test('applyFirstPromptTitle skips blank prompts', () async {
    await sync.applyFirstPromptTitle('sess-1', '   \n  ');

    expect(host.renames, isEmpty);
  });

  test('touchOnUserActivity bumps updatedAt and persists', () async {
    sync.touchOnUserActivity('sess-1');
    await Future<void>.value();

    expect(host.state.sessions.single.updatedAt, 10_000);
    expect(repo.touched, ['sess-1']);
  });

  test('touchOnUserActivity skips local sessions', () async {
    host.state = ChatState(sessions: [session(id: 'local-1')]);

    sync.touchOnUserActivity('local-1');
    await Future<void>.value();

    expect(host.state.sessions.single.updatedAt, 1);
    expect(repo.touched, isEmpty);
  });

  test('touchOnUserActivity debounces to once per 5 seconds', () async {
    sync.touchOnUserActivity('sess-1');
    nowMs = 14_999;
    sync.touchOnUserActivity('sess-1');
    await Future<void>.value();

    expect(repo.touched, ['sess-1']);
    expect(host.state.sessions.single.updatedAt, 10_000);

    nowMs = 15_000;
    sync.touchOnUserActivity('sess-1');
    await Future<void>.value();

    expect(repo.touched, ['sess-1', 'sess-1']);
    expect(host.state.sessions.single.updatedAt, 15_000);
  });

  test('autoTouchOnEveryPrompt uses the same activity touch', () async {
    final onLine = sync.autoTouchOnEveryPrompt('sess-1');
    expect(onLine, isNotNull);
    onLine!('hello');
    await Future<void>.value();

    expect(host.state.sessions.single.updatedAt, 10_000);
    expect(repo.touched, ['sess-1']);
  });
}

class _FakeRepo extends Fake implements SessionRepository {
  final touched = <String>[];

  @override
  Future<AppSession?> touchSession(String sessionId) async {
    touched.add(sessionId);
    return AppSession(
      sessionId: sessionId,
      workspaceId: 'ws-1',
      createdAt: 1,
      updatedAt: 99,
    );
  }
}

class _FakeHost implements SessionLaunchHost {
  _FakeHost(this._repo);

  @override
  ChatState state = const ChatState();

  @override
  ChatDataSnapshot stateSnapshot() => ChatDataSnapshot(
        workspaces: state.workspaces,
        sessions: state.sessions,
        visibleWorkspaces: state.visibleWorkspaces,
        visibleSessions: state.visibleSessions,
      );

  final renames = <(String, String)>[];
  final _FakeRepo _repo;

  @override
  bool get isClosed => false;

  @override
  SessionRepository? get sessionRepository => _repo;

  @override
  void applyState(ChatState next) => state = next;

  @override
  void replaceSessionSnapshot(AppSession session) {
    state = state.copyWith(
      sessions: [
        for (final s in state.sessions)
          if (s.sessionId == session.sessionId) session else s,
      ],
    );
  }

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
