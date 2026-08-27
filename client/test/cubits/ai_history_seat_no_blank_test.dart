import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_seat.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/failed_message_store.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../support/fake_ai_history_registry.dart';
import '../support/in_memory_filesystem.dart';
import '../support/post_frame_test_harness.dart';

/// Adapter returning whatever the mutable [messages] closure holds at parse
/// time, so tests can grow the transcript between loads.
class _HolderAdapter implements AiTranscriptAdapter {
  _HolderAdapter(this.messages);

  final List<AiMessage> Function() messages;

  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async =>
      List.of(messages());
}

/// Locator that hands back a canned bundle when [emitBundle] is true.
class _ScriptedLocator extends AiHistoryLocator {
  bool emitBundle = false;

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) async {
    if (!emitBundle) return null;
    return const AiTranscriptBundle(
      adapterId: 'claude',
      fragments: [AiTranscriptFragment(name: 'canned.jsonl', bytes: [])],
    );
  }
}

void main() {
  late _ScriptedLocator locator;
  late List<AiMessage> holderMessages;
  late String cacheToken;
  late AiHistoryLoader loader;
  late AiHistorySeat seat;

  void bumpCacheToken() => cacheToken =
      'token-${cacheToken.hashCode.abs()}-${holderMessages.length}';

  AppSession session() => AppSession(
    sessionId: 'sess-a',
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work/project')],
    cli: CliTool.claude,
    createdAt: 1,
  );

  WorkspaceLaunchContext ctx(AppSession s) => WorkspaceLaunchContext(
    session: s,
    workspace: Workspace(
      workspaceId: s.workspaceId,
      folders: s.folders,
      createdAt: 0,
    ),
  );

  List<AiMessage> messages(int count) => [
    for (var i = 0; i < count; i++)
      AiMessage(
        id: 'm-$i',
        role: AiRole.user,
        parts: [AiTextPart(text: 'msg-$i')],
      ),
  ];

  setUp(() {
    setUpTestAppStorage();
    holderMessages = const [];
    cacheToken = 'token-1';
    locator = _ScriptedLocator()..emitBundle = true;
    final fs = LocalFilesystem();
    loader = AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: '/tmp/history-seat-no-blank',
        cwd: '/tmp/history-seat-no-blank',
        appDataRoot: '/tmp/history-seat-no-blank',
        paths: AppPaths('/tmp/history-seat-no-blank'),
      ),
      locator: locator,
      registry: fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: _HolderAdapter(() => holderMessages),
      ),
      resolveCacheToken: (_) async => cacheToken,
    );
    seat = AiHistorySeat(loader: loader);
  });

  tearDown(() async {
    await seat.close();
    tearDownTestAppStorage();
  });

  test(
    're-load for the same seat keeps content and goes refreshing, never blank',
    () async {
      holderMessages = messages(2);
      await seat.load(
        session: session(),
        memberId: '',
        launchContext: ctx(session()),
      );

      expect(seat.state.status, AiHistoryViewStatus.ready);
      expect(seat.runtime.messages, hasLength(2));

      // Transcript grows; a re-load (token bump) must NOT blank the list.
      holderMessages = messages(3);
      bumpCacheToken();
      final reloading = seat.load(
        session: session(),
        memberId: '',
        launchContext: ctx(session()),
      );
      expect(
        seat.runtime.messages,
        hasLength(2),
        reason: 'no-blank: cached list survives',
      );
      expect(seat.state.status, AiHistoryViewStatus.refreshing);
      await reloading;
      expect(seat.state.status, AiHistoryViewStatus.ready);
      expect(seat.runtime.messages, hasLength(3));
    },
  );

  test('hydrates stale sending as failed without latching awaiting', () async {
    holderMessages = messages(1);
    final current = session();
    await seat.load(
      session: current,
      memberId: '',
      launchContext: ctx(current),
    );
    final store = FailedMessageStore(
      fs: InMemoryFilesystem(),
      rootPath: '/teampilot',
    );
    final record = FailedMessageRecord(
      id: 'pending:restart',
      text: 'survives restart',
      createdAt: DateTime.utc(2026),
      status: FailedMessageStatus.sending,
    );
    await store.save(current.workspaceId, current.sessionId, record);

    await seat.hydratePendingUsers(
      store: store,
      workspaceId: current.workspaceId,
      sessionId: current.sessionId,
    );

    expect(
      seat.runtime.messages.map((message) => message.id),
      containsAll(['m-0', record.id]),
    );
    expect(seat.state.awaitingAssistant, isFalse);
    expect(
      seat.pendingDeliveryStatusFor(record.id),
      FailedMessageStatus.failed,
    );
    expect(
      (await store.load(current.workspaceId, current.sessionId)).single.status,
      FailedMessageStatus.failed,
    );
  });

  test(
    'later CLI confirmation never consumes hydrated failed record',
    () async {
      holderMessages = messages(1);
      final current = session();
      await seat.load(
        session: current,
        memberId: '',
        launchContext: ctx(current),
      );
      final store = FailedMessageStore(
        fs: InMemoryFilesystem(),
        rootPath: '/teampilot',
      );
      final failed = FailedMessageRecord(
        id: 'pending:failed',
        text: 'failed first',
        createdAt: DateTime.utc(2026),
        status: FailedMessageStatus.failed,
      );
      await store.save(current.workspaceId, current.sessionId, failed);
      await seat.hydratePendingUsers(
        store: store,
        workspaceId: current.workspaceId,
        sessionId: current.sessionId,
      );

      holderMessages = messages(2);
      bumpCacheToken();
      await seat.softReload();

      expect(
        seat.runtime.messages.map((message) => message.id),
        contains(failed.id),
      );
      expect(
        await store.load(current.workspaceId, current.sessionId),
        contains(failed),
      );
    },
  );

  test(
    'first load with no content emits loading (initialLoading path)',
    () async {
      holderMessages = const [];
      final future = seat.load(
        session: session(),
        memberId: '',
        launchContext: ctx(session()),
      );
      expect(seat.state.status, AiHistoryViewStatus.loading);
      await future;
      expect(seat.state.status, AiHistoryViewStatus.empty);
    },
  );

  test('loadOlder keeps runtime content and never blanks', () async {
    holderMessages = messages(40);
    bumpCacheToken();
    await seat.load(session: session(), memberId: '', launchContext: ctx(session()));
    expect(seat.runtime.messages, isNotEmpty);
    final before = List<AiMessage>.from(seat.runtime.messages);
    expect(seat.runtime.status, isNot(AiThreadStatus.loading));

    await seat.loadOlder();

    expect(seat.runtime.status, isNot(AiThreadStatus.loading));
    expect(seat.runtime.messages, isNotEmpty);
    expect(seat.runtime.messages.first.id, isNot(before.first.id));
    expect(seat.runtime.messages.last.id, before.last.id);
    expect(seat.state.status, AiHistoryViewStatus.ready);
  });

  group('revealMessage', () {
    test(
      'expands the visible window to include a not-yet-loaded index',
      () async {
        holderMessages = messages(40);
        bumpCacheToken();
        await seat.load(
          session: session(),
          memberId: '',
          launchContext: ctx(session()),
        );

        // Initial window covers only the tail (kSessionHistoryInitialTurns).
        // The thread renders runtime.messages; loadedMessages is the full
        // transcript regardless of the window.
        final beforeIds = seat.runtime.messages.map((m) => m.id).toList();
        expect(beforeIds.length, lessThan(40));
        expect(beforeIds, isNot(contains('m-5')));

        seat.revealMessage(5);
        final afterIds = seat.runtime.messages.map((m) => m.id).toList();
        expect(afterIds.length, greaterThan(beforeIds.length));
        expect(afterIds.first, 'm-5');
        expect(afterIds, contains('m-5'));

        // Full loaded transcript is unchanged — reveal only widens the window.
        expect(seat.loadedMessages.length, 40);
        expect(seat.loadedMessages.first.id, 'm-0');
        expect(seat.loadedMessages[5].id, 'm-5');

        // Content before the revealed index stays hidden, so hasOlder is true.
        expect(seat.state.hasOlder, isTrue);
      },
    );

    test('no-op when the index is already visible', () async {
      holderMessages = messages(10);
      bumpCacheToken();
      await seat.load(
        session: session(),
        memberId: '',
        launchContext: ctx(session()),
      );

      final before = seat.runtime.messages.length;
      seat.revealMessage(0);
      expect(seat.runtime.messages.length, before);
    });

    test('ignores out-of-range indices', () async {
      holderMessages = messages(10);
      bumpCacheToken();
      await seat.load(
        session: session(),
        memberId: '',
        launchContext: ctx(session()),
      );

      final before = seat.runtime.messages.length;
      seat.revealMessage(-1);
      seat.revealMessage(100);
      expect(seat.runtime.messages.length, before);
    });
  });
}
