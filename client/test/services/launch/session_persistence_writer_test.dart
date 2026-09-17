import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/session_data_store.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/launch/session/session_persistence_writer.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/session/shell_launch_spec.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late _FakeRepoPort repository;
  late _RecordingSnapshots snapshots;
  late _FakeChatState chatState;
  late _FakeTabs tabs;
  late _FakeEnvironment environment;
  late SessionDataStore dataStore;

  SessionPersistenceWriter build() => SessionPersistenceWriter(
    repository: repository,
    snapshots: snapshots,
    chatState: chatState,
    tabs: tabs,
    environment: environment,
    dataStore: dataStore,
  );

  ChatTab makeTab({String id = 'sess-1'}) => ChatTab(
    info: ChatTabInfo(id: id, title: 'T', subtitle: ''),
    cliTeamName: 'team-cli',
    workspaceId: 'ws-1',
  );

  AppSession makeSession({
    String id = 'sess-1',
    AppSessionLaunchState launchState = AppSessionLaunchState.created,
    List<TeamMemberConfig> members = const [],
  }) => AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    createdAt: 1,
    updatedAt: 1,
    launchState: launchState,
    members: [
      for (final m in members)
        SessionMemberBinding(
          rosterMemberId: m.id,
          taskId: m.id,
          cli: m.cli,
        ),
    ],
  );

  LaunchPlan makePlan({String? nativeId, String? tool}) => LaunchPlan(
    env: const {},
    resume: false,
    taskId: 'task',
    cliTeamName: 'team-cli',
    memberConfigDir: '',
    resolvedRoots: const [],
    nativeSessionIdToPersist: nativeId,
    toolValue: tool,
  );

  setUp(() {
    repository = _FakeRepoPort();
    snapshots = _RecordingSnapshots();
    chatState = _FakeChatState();
    tabs = _FakeTabs();
    environment = _FakeEnvironment();
    dataStore = SessionDataStore(storage: fakeHomeStorage());
  });

  group('persistSessionStarted', () {
    test('marks launched, syncs the tab cache, and emits a snapshot',
        () async {
      final session = makeSession();
      final tab = makeTab()..persistedSession = session;
      tabs.tabStore
        ..setActiveWorkspaceId('ws-1')
        ..registerSession(tab);
      chatState.state = ChatState(sessions: [session]);

      await build().persistSessionStarted('sess-1');

      expect(repository.repo.launched, ['sess-1']);
      expect(
        tab.persistedSession!.launchState,
        AppSessionLaunchState.started,
      );
      expect(snapshots.emitted, hasLength(1));
      expect(
        snapshots.emitted.single.sessions.single.launchState,
        AppSessionLaunchState.started,
      );
    });

    test('is a no-op when no repository is available', () async {
      repository.hasRepository = false;
      chatState.state = ChatState(sessions: [makeSession()]);

      await build().persistSessionStarted('sess-1');

      expect(repository.repo.launched, isEmpty);
      expect(snapshots.emitted, isEmpty);
    });
  });

  group('persistNativeSessionId', () {
    test('skips local- sessions without touching the repository', () async {
      final session = makeSession(id: 'local-1');
      final tab = makeTab(id: 'local-1')..persistedSession = session;

      await build().persistNativeSessionId(
        tab: tab,
        session: session,
        binding: null,
        plan: makePlan(nativeId: 'native-1', tool: 'claude'),
      );

      expect(repository.repo.nativeIds, isEmpty);
    });

    test('skips when native id or tool is missing', () async {
      final session = makeSession();
      final tab = makeTab()..persistedSession = session;

      await build().persistNativeSessionId(
        tab: tab,
        session: session,
        binding: null,
        plan: makePlan(nativeId: '', tool: 'claude'),
      );
      await build().persistNativeSessionId(
        tab: tab,
        session: session,
        binding: null,
        plan: makePlan(nativeId: 'native-1', tool: null),
      );

      expect(repository.repo.nativeIds, isEmpty);
      expect(snapshots.emitted, isEmpty);
    });

    test('records the native id and applies it to the bound member', () async {
      const member = TeamMemberConfig(id: 'm1', name: 'M1');
      final session = makeSession(members: const [member]);
      final tab = makeTab()..persistedSession = session;
      chatState.state = ChatState(sessions: [session]);

      await build().persistNativeSessionId(
        tab: tab,
        session: session,
        binding: const SessionMemberBinding(
          rosterMemberId: 'm1',
          taskId: 'task-1',
          cli: CliTool.claude,
        ),
        plan: makePlan(nativeId: 'native-1', tool: 'claude'),
      );

      expect(repository.repo.nativeIds, [
        ('sess-1', 'claude', 'native-1', 'm1'),
      ]);
      expect(
        tab.persistedSession!.members.single.nativeSessionIds['claude'],
        'native-1',
      );
      expect(snapshots.emitted, hasLength(1));
    });
  });

  group('syncFollowedPresetOnConnect', () {
    test('returns the session unchanged when nothing is stale', () async {
      final session = makeSession();
      final tab = makeTab()..persistedSession = session;
      chatState.state = ChatState(sessions: [session]);

      final result = await build().syncFollowedPresetOnConnect(
        session: session,
        tab: tab,
        isPersonal: true,
        memberId: 'm1',
      );

      expect(identical(result, session), isTrue);
      expect(snapshots.replacements, isEmpty);
    });
  });
}

// --- fakes ---

class _FakeRepo implements SessionRepository {
  final List<String> launched = [];
  final List<(String, String, String, String?)> nativeIds = [];

  @override
  Future<void> markSessionLaunched(String sessionId) async {
    launched.add(sessionId);
  }

  @override
  Future<void> recordNativeSessionId(
    String sessionId, {
    required String tool,
    required String nativeId,
    String? rosterMemberId,
  }) async {
    nativeIds.add((sessionId, tool, nativeId, rosterMemberId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRepoPort implements SessionRepositoryPort {
  final _FakeRepo repo = _FakeRepo();
  bool hasRepository = true;

  @override
  SessionRepository? get sessionRepository => hasRepository ? repo : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingSnapshots implements SessionSnapshotPort {
  final List<ChatDataSnapshot> emitted = [];
  final List<AppSession> replacements = [];

  @override
  void emitSnapshot(ChatDataSnapshot snapshot) => emitted.add(snapshot);

  @override
  void replaceSessionSnapshot(AppSession session) =>
      replacements.add(session);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeChatState implements ChatStatePort {
  @override
  ChatState state = ChatState();

  @override
  bool isClosed = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeTabs implements TabPort {
  @override
  final ChatTabStore tabStore = ChatTabStore(storage: fakeHomeStorage());

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeEnvironment implements LaunchEnvironmentPort {
  @override
  final SessionLifecycleService lifecycle = SessionLifecycleService(
    storage: fakeHomeStorage(),
    loadPresets: () => const [],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
