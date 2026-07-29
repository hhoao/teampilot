import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/session/session_history_pagination.dart';
import 'package:teampilot/services/team_bus/persistence/bus_message_log.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import '../support/fake_ai_history_registry.dart';
import '../support/post_frame_test_harness.dart';

void main() {
  late _ScriptedLocator locator;
  late List<AiMessage> holderMessages;
  late AiHistoryLoader loader;
  late AiHistoryCubit cubit;

  ExternalStoreAiThreadRuntime seatRuntime({
    String sessionId = 'sess-a',
    String memberId = '',
  }) =>
      cubit.ensureSeat(sessionId: sessionId, selectedMemberId: memberId).runtime;

  AppSession simpleSession({String id = 'sess-a'}) => AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work/project')],
    cli: CliTool.claude,
    createdAt: 1,
    updatedAt: 1,
  );


  WorkspaceLaunchContext launchCtx(AppSession s) => WorkspaceLaunchContext(
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
    locator = _ScriptedLocator();
    final fs = LocalFilesystem();
    loader = AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: '/tmp/ai-history-cubit',
        cwd: '/tmp/ai-history-cubit',
        appDataRoot: '/tmp/ai-history-cubit',
        paths: AppPaths('/tmp/ai-history-cubit'),
      ),
      locator: locator,
      registry: fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: _HolderAdapter(() => holderMessages),
      ),
      resolveCacheToken: (_) async => 'token',
    );
    cubit = AiHistoryCubit(loader: loader);
  });

  tearDown(() async {
    await cubit.close();
    tearDownTestAppStorage();
  });

  test('load emits loading then ready and sets runtime messages', () async {
    holderMessages = messages(2);
    locator.emitBundle = true;

    final done = cubit.load(session: simpleSession(), memberId: '', launchContext: launchCtx(simpleSession()));
    expect(cubit.state.status, AiHistoryViewStatus.loading);
    expect(seatRuntime().status, AiThreadStatus.loading);
    await done;

    expect(cubit.state.status, AiHistoryViewStatus.ready);
    expect(cubit.state.totalMessageCount, 2);
    expect(cubit.state.hasOlder, isFalse);
    expect(seatRuntime().messages, hasLength(2));
    expect(seatRuntime().status, AiThreadStatus.idle);
  });

  test('empty load sets runtime empty', () async {
    locator.emitBundle = false;
    await cubit.load(session: simpleSession(), memberId: '', launchContext: launchCtx(simpleSession()));
    expect(cubit.state.status, AiHistoryViewStatus.empty);
    expect(seatRuntime().status, AiThreadStatus.empty);
    expect(seatRuntime().messages, isEmpty);
  });

  test('ignores stale generation when a newer load finishes first', () async {
    final first = Completer<AiTranscriptBundle?>();
    final second = Completer<AiTranscriptBundle?>();
    locator.queue
      ..add(first.future)
      ..add(second.future);

    final firstLoad = cubit.load(
      session: simpleSession(id: 's1'),
      memberId: '',
      launchContext: launchCtx(simpleSession(id: 's1')),
    );
    final secondLoad = cubit.load(
      session: simpleSession(id: 's2'),
      memberId: '',
      launchContext: launchCtx(simpleSession(id: 's2')),
    );

    holderMessages = [
      const AiMessage(
        id: 'second',
        role: AiRole.user,
        parts: [AiTextPart(text: 'second')],
      ),
    ];
    second.complete(_dummyBundle());
    await secondLoad;
    expect(cubit.state.sessionId, 's2');
    expect(seatRuntime(sessionId: 's2').messages.single.id, 'second');

    holderMessages = [
      const AiMessage(
        id: 'first',
        role: AiRole.user,
        parts: [AiTextPart(text: 'first')],
      ),
    ];
    first.complete(_dummyBundle());
    await firstLoad;

    // Focused facade state stays on s2; seat s1 may finish independently.
    expect(cubit.state.sessionId, 's2');
    expect(seatRuntime(sessionId: 's2').messages.single.id, 'second');
  });

  test('windows to recent messages and loadOlder expands slice', () async {
    holderMessages = messages(50);
    locator.emitBundle = true;

    await cubit.load(session: simpleSession(), memberId: '', launchContext: launchCtx(simpleSession()));
    expect(cubit.state.totalMessageCount, 50);
    expect(seatRuntime().messages, hasLength(kSessionHistoryInitialTurns));
    expect(seatRuntime().messages.first.id, 'm-20');
    expect(seatRuntime().messages.last.id, 'm-49');
    expect(cubit.state.hasOlder, isTrue);

    cubit.loadOlder();
    expect(seatRuntime().messages, hasLength(50));
    expect(cubit.state.hasOlder, isFalse);
    expect(cubit.state.isLoadingOlder, isFalse);
  });

  test('error sets runtime error', () async {
    locator.error = StateError('boom');
    await cubit.load(session: simpleSession(), memberId: '', launchContext: launchCtx(simpleSession()));
    expect(cubit.state.status, AiHistoryViewStatus.error);
    expect(cubit.state.errorMessage, contains('boom'));
    expect(seatRuntime().status, AiThreadStatus.error);
  });

  test('softReload grows visibleCount by tip delta and preserves start', () async {
    holderMessages = messages(40);
    locator.emitBundle = true;

    await cubit.load(session: simpleSession(), memberId: '', launchContext: launchCtx(simpleSession()));
    expect(seatRuntime().messages, hasLength(kSessionHistoryInitialTurns));
    expect(seatRuntime().messages.first.id, 'm-10');

    cubit.loadOlder();
    expect(cubit.state.totalMessageCount, 40);
    expect(seatRuntime().messages, hasLength(40));
    expect(seatRuntime().messages.first.id, 'm-0');

    holderMessages = messages(42);
    await cubit.softReload();

    expect(cubit.state.totalMessageCount, 42);
    expect(seatRuntime().messages, hasLength(42));
    expect(seatRuntime().messages.first.id, 'm-0');
    expect(seatRuntime().messages.last.id, 'm-41');
    expect(cubit.state.hasOlder, isFalse);
  });

  test('softReload does not emit loading when already ready', () async {
    holderMessages = messages(2);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '', launchContext: launchCtx(simpleSession()));
    expect(cubit.state.status, AiHistoryViewStatus.ready);

    final statuses = <AiHistoryViewStatus>[];
    final sub = cubit.stream.listen((s) => statuses.add(s.status));

    holderMessages = messages(3);
    await cubit.softReload();
    await sub.cancel();

    expect(statuses, isNot(contains(AiHistoryViewStatus.loading)));
    expect(cubit.state.status, AiHistoryViewStatus.ready);
    expect(cubit.state.totalMessageCount, 3);
  });

  test('softReload truncate clamps visibleCount', () async {
    holderMessages = messages(40);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '', launchContext: launchCtx(simpleSession()));
    cubit.loadOlder();
    expect(seatRuntime().messages, hasLength(40));

    holderMessages = messages(25);
    await cubit.softReload();

    expect(cubit.state.totalMessageCount, 25);
    expect(seatRuntime().messages, hasLength(25));
    expect(seatRuntime().messages.first.id, 'm-0');
    expect(seatRuntime().messages.last.id, 'm-24');
  });

  test('pending user merges then drops on matching tip user text', () async {
    holderMessages = messages(2);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '', launchContext: launchCtx(simpleSession()));

    cubit.enqueuePendingUser('hello   world');
    expect(cubit.state.awaitingAssistant, isTrue);
    expect(seatRuntime().messages, hasLength(3));
    expect(seatRuntime().messages.last.id, startsWith('pending:'));
    expect(
      (seatRuntime().messages.last.parts.single as AiTextPart).text,
      'hello   world',
    );

    holderMessages = [
      ...messages(2),
      const AiMessage(
        id: 'u-hello',
        role: AiRole.user,
        parts: [AiTextPart(text: 'hello world')],
      ),
    ];
    await cubit.softReload();

    expect(
      seatRuntime().messages.where((m) => m.id.startsWith('pending:')),
      isEmpty,
    );
    expect(seatRuntime().messages.last.id, 'u-hello');
    // Pending flushed but tip is still user — keep awaiting until assistant tip.
    expect(cubit.state.awaitingAssistant, isTrue);

    holderMessages = [
      ...holderMessages,
      const AiMessage(
        id: 'a-1',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'hi')],
      ),
    ];
    await cubit.softReload();
    expect(cubit.state.awaitingAssistant, isTrue);
    // Assistant tip is held for idleAfter-aligned window.
    expect(cubit.hasHeldAssistantTip, isTrue);
    expect(seatRuntime().messages.last.id, 'u-hello');

    holderMessages = [
      ...holderMessages,
      const AiMessage(
        id: 'a-2',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'more')],
      ),
    ];
    await cubit.softReload();
    expect(cubit.state.awaitingAssistant, isTrue);
    expect(cubit.hasHeldAssistantTip, isTrue);
    expect(seatRuntime().messages.last.id, 'u-hello');

    // Still working after hold: reveal tip, keep Running.
    await Future<void>.delayed(
      AiHistoryCubit.tipHoldAfterAssistant + const Duration(milliseconds: 50),
    );
    expect(cubit.state.awaitingAssistant, isTrue);
    expect(cubit.hasHeldAssistantTip, isFalse);
    expect(seatRuntime().messages.last.id, 'a-2');

    cubit.flushHeldTip(endAwaiting: true);
    expect(cubit.state.awaitingAssistant, isFalse);
  });

  test(
    'softReload after idle clear does not revive awaiting via leftover pending',
    () async {
      // Turn ended (sidebar working cleared) while optimistic pending is still
      // unmatched — softReload must not force Running chrome back on.
      holderMessages = messages(2);
      locator.emitBundle = true;
      await cubit.load(
        session: simpleSession(),
        memberId: '',
        launchContext: launchCtx(simpleSession()),
      );

      cubit.enqueuePendingUser('stop me');
      expect(cubit.state.awaitingAssistant, isTrue);

      cubit.flushHeldTip(endAwaiting: true);
      expect(cubit.state.awaitingAssistant, isFalse);
      expect(
        seatRuntime().messages.where((m) => m.id.startsWith('pending:')),
        isNotEmpty,
      );

      await cubit.softReload();

      expect(cubit.state.awaitingAssistant, isFalse);
      expect(
        seatRuntime().messages.where((m) => m.id.startsWith('pending:')),
        isNotEmpty,
      );
    },
  );

  test('read mailbox mail merged via timeline survives softReload', () async {
    holderMessages = messages(2);
    locator.emitBundle = true;

    var mailboxRecords = <LoggedMessage>[];
    await cubit.close();
    cubit = AiHistoryCubit(
      loader: loader,
      loadMailboxRecords: (sessionId, memberId) async => mailboxRecords,
    );

    await cubit.load(
      session: simpleSession(),
      memberId: '',
      launchContext: launchCtx(simpleSession()),
    );

    mailboxRecords = [
      LoggedMessage(
        seq: 0,
        message: const TeamMessage(
          id: 'mail-1',
          from: TeamBus.userSenderId,
          to: 'dev',
          content: 'follow up',
        ),
        createdAt: 3000,
        read: true,
      ),
    ];
    await cubit.refreshMailboxTimeline();
    expect(cubit.state.awaitingAssistant, isFalse);
    expect(seatRuntime().messages, hasLength(3));
    expect(seatRuntime().messages.last.id, 'mailbox:mail-1');

    holderMessages = [
      ...messages(2),
      const AiMessage(
        id: 'a-new',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'working')],
      ),
    ];
    await cubit.softReload();

    expect(seatRuntime().messages.map((m) => m.id).toList(), [
      'm-0',
      'm-1',
      'a-new',
      'mailbox:mail-1',
    ]);
  });

  test('held assistant tip flushes immediately on idle endAwaiting', () async {
    holderMessages = messages(1);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '', launchContext: launchCtx(simpleSession()));

    cubit.enqueuePendingUser('hello');
    holderMessages = [
      ...messages(1),
      const AiMessage(
        id: 'u-1',
        role: AiRole.user,
        parts: [AiTextPart(text: 'hello')],
      ),
      const AiMessage(
        id: 'a-1',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'hi')],
      ),
    ];
    await cubit.softReload();
    expect(cubit.hasHeldAssistantTip, isTrue);
    expect(seatRuntime().messages.last.id, 'u-1');

    cubit.flushHeldTip(endAwaiting: true);
    expect(cubit.hasHeldAssistantTip, isFalse);
    expect(cubit.state.awaitingAssistant, isFalse);
    expect(seatRuntime().messages.last.id, 'a-1');
  });

  test('multi pending drops independently by normalized text', () async {
    holderMessages = messages(1);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '', launchContext: launchCtx(simpleSession()));

    cubit.enqueuePendingUser('a');
    cubit.enqueuePendingUser('b');
    expect(
      seatRuntime().messages.where((m) => m.id.startsWith('pending:')),
      hasLength(2),
    );

    holderMessages = [
      const AiMessage(
        id: 'u-a',
        role: AiRole.user,
        parts: [AiTextPart(text: 'a')],
      ),
    ];
    await cubit.softReload();

    final pendings = seatRuntime().messages
        .where((m) => m.id.startsWith('pending:'))
        .toList();
    expect(pendings, hasLength(1));
    expect((pendings.single.parts.single as AiTextPart).text, 'b');
  });

  test('enqueuePendingUser on empty promotes to ready with pending tip', () async {
    locator.emitBundle = false;
    await cubit.load(session: simpleSession(), memberId: '', launchContext: launchCtx(simpleSession()));
    expect(cubit.state.status, AiHistoryViewStatus.empty);

    cubit.enqueuePendingUser('continue me');

    expect(cubit.state.status, AiHistoryViewStatus.ready);
    expect(seatRuntime().messages, hasLength(1));
    expect(seatRuntime().messages.single.id, startsWith('pending:'));
    expect(
      (seatRuntime().messages.single.parts.single as AiTextPart).text,
      'continue me',
    );
  });

  test('seedPendingUser applies immediately when already on seat', () async {
    locator.emitBundle = false;
    await cubit.load(
      session: simpleSession(),
      memberId: '',
      launchContext: launchCtx(simpleSession()),
    );

    cubit.seedPendingUser(
      sessionId: 'sess-a',
      memberId: '',
      text: 'from landing',
    );

    expect(cubit.state.awaitingAssistant, isTrue);
    expect(cubit.state.status, AiHistoryViewStatus.ready);
    expect(
      (seatRuntime().messages.single.parts.single as AiTextPart).text,
      'from landing',
    );
  });

  test('seedPendingUser survives seat load clearPendings', () async {
    locator.emitBundle = false;
    await cubit.load(
      session: simpleSession(id: 'old'),
      memberId: '',
      launchContext: launchCtx(simpleSession(id: 'old')),
    );

    cubit.seedPendingUser(
      sessionId: 'sess-a',
      memberId: '',
      text: 'landing prompt',
    );
    expect(cubit.state.awaitingAssistant, isFalse);

    await cubit.load(
      session: simpleSession(),
      memberId: '',
      launchContext: launchCtx(simpleSession()),
    );

    expect(cubit.state.awaitingAssistant, isTrue);
    expect(cubit.state.status, AiHistoryViewStatus.ready);
    expect(
      (seatRuntime().messages.single.parts.single as AiTextPart).text,
      'landing prompt',
    );
  });

  test('enqueuePendingUser during loading promotes to ready', () async {
    locator.emitBundle = false;
    final loadFuture = cubit.load(
      session: simpleSession(),
      memberId: '',
      launchContext: launchCtx(simpleSession()),
    );
    // Mid-load: seat already set, status still loading.
    expect(cubit.state.status, AiHistoryViewStatus.loading);
    expect(cubit.state.sessionId, 'sess-a');

    cubit.seedPendingUser(
      sessionId: 'sess-a',
      memberId: '',
      text: 'eager landing',
    );

    expect(cubit.state.status, AiHistoryViewStatus.ready);
    expect(cubit.state.awaitingAssistant, isTrue);
    expect(
      (seatRuntime().messages.single.parts.single as AiTextPart).text,
      'eager landing',
    );

    await loadFuture;
    expect(cubit.state.status, AiHistoryViewStatus.ready);
    expect(cubit.state.awaitingAssistant, isTrue);
    expect(
      (seatRuntime().messages.single.parts.single as AiTextPart).text,
      'eager landing',
    );
  });

  test('cancelSeedPendingUser drops stored seed and matching pending', () async {
    locator.emitBundle = false;
    cubit.seedPendingUser(
      sessionId: 'sess-a',
      memberId: '',
      text: 'will fail',
    );
    cubit.cancelSeedPendingUser(sessionId: 'sess-a', text: 'will fail');

    await cubit.load(
      session: simpleSession(),
      memberId: '',
      launchContext: launchCtx(simpleSession()),
    );

    expect(cubit.state.awaitingAssistant, isFalse);
    expect(cubit.state.status, AiHistoryViewStatus.empty);
    expect(seatRuntime().messages, isEmpty);
  });

  test(
    'softReloadOrLoad keeps pending-only first bubble when transcript still missing',
    () async {
      locator.emitBundle = false;
      await cubit.load(
        session: simpleSession(),
        memberId: '',
        launchContext: launchCtx(simpleSession()),
      );
      cubit.enqueuePendingUser('能不能做个番茄钟');
      expect(cubit.state.status, AiHistoryViewStatus.ready);
      expect(cubit.state.awaitingAssistant, isTrue);

      // Remount / switch-back path — transcript still not locatable.
      await cubit.softReloadOrLoad(
        session: simpleSession(),
        memberId: '',
        launchContext: launchCtx(simpleSession()),
      );

      expect(cubit.state.status, AiHistoryViewStatus.ready);
      expect(cubit.state.awaitingAssistant, isTrue);
      expect(
        (seatRuntime().messages.single.parts.single as AiTextPart).text,
        '能不能做个番茄钟',
      );
    },
  );

  test('softReloadOrLoad soft-reloads when already ready for same seat', () async {
    holderMessages = messages(2);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '', launchContext: launchCtx(simpleSession()));
    expect(cubit.state.status, AiHistoryViewStatus.ready);

    final statuses = <AiHistoryViewStatus>[];
    final sub = cubit.stream.listen((s) => statuses.add(s.status));

    holderMessages = messages(3);
    await cubit.softReloadOrLoad(
      session: simpleSession(),
      memberId: '',
      launchContext: launchCtx(simpleSession()),
    );
    await sub.cancel();

    expect(statuses, isNot(contains(AiHistoryViewStatus.loading)));
    expect(cubit.state.status, AiHistoryViewStatus.ready);
    expect(cubit.state.totalMessageCount, 3);
  });

  test('softReloadIfSession soft-reloads when ready for session', () async {
    holderMessages = messages(2);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '', launchContext: launchCtx(simpleSession()));
    expect(cubit.state.status, AiHistoryViewStatus.ready);

    final statuses = <AiHistoryViewStatus>[];
    final sub = cubit.stream.listen((s) => statuses.add(s.status));

    holderMessages = messages(4);
    await cubit.softReloadIfSession('sess-a');
    await sub.cancel();

    expect(statuses, isNot(contains(AiHistoryViewStatus.loading)));
    expect(cubit.state.status, AiHistoryViewStatus.ready);
    expect(cubit.state.totalMessageCount, 4);
  });

  test('softReload no-ops after seat clear / generation bump', () async {
    holderMessages = messages(2);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '', launchContext: launchCtx(simpleSession()));

    final delayed = Completer<AiTranscriptBundle?>();
    locator.queue.add(delayed.future);

    final soft = cubit.softReload();
    cubit.clear();
    expect(cubit.state.status, AiHistoryViewStatus.empty);

    holderMessages = messages(5);
    delayed.complete(_dummyBundle());
    await soft;

    expect(cubit.state.status, AiHistoryViewStatus.empty);
    expect(
      cubit.seatOf(sessionId: 'sess-a', selectedMemberId: ''),
      isNull,
    );
    expect(cubit.state.totalMessageCount, 0);
  });

  test(
    'mailbox: read user mail merges between CLI messages by createdAt',
    () async {
      holderMessages = [
        AiMessage(
          id: 'u-1',
          role: AiRole.user,
          parts: const [AiTextPart(text: 'cli user')],
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
        AiMessage(
          id: 'a-1',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'cli assistant')],
          createdAt: DateTime.fromMillisecondsSinceEpoch(3000),
        ),
      ];
      locator.emitBundle = true;

      await cubit.close();
      cubit = AiHistoryCubit(
        loader: loader,
        loadMailboxRecords: (sessionId, memberId) async => [
          LoggedMessage(
            seq: 0,
            message: const TeamMessage(
              id: 'mail-1',
              from: TeamBus.userSenderId,
              to: 'dev',
              content: 'mailbox user',
            ),
            createdAt: 2000,
            read: true,
          ),
        ],
      );

      await cubit.load(
        session: simpleSession(),
        memberId: '',
        launchContext: launchCtx(simpleSession()),
      );

      final ids = seatRuntime().messages.map((m) => m.id).toList();
      expect(ids, ['u-1', 'mailbox:mail-1', 'a-1']);
      final mailboxMsg = seatRuntime().messages[1];
      expect(mailboxMsg.id, startsWith('mailbox:'));
      expect(mailboxMsg.deliveryChannel, 'mailbox');
    },
  );

  test('mailbox: unread mail does not appear in runtime messages', () async {
    holderMessages = [
      AiMessage(
        id: 'u-1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'cli user')],
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ),
    ];
    locator.emitBundle = true;

    await cubit.close();
    cubit = AiHistoryCubit(
      loader: loader,
      loadMailboxRecords: (sessionId, memberId) async => [
        LoggedMessage(
          seq: 0,
          message: const TeamMessage(
            id: 'mail-unread',
            from: TeamBus.userSenderId,
            to: 'dev',
            content: 'queued text',
          ),
          createdAt: 2000,
          read: false,
        ),
      ],
    );

    await cubit.load(
      session: simpleSession(),
      memberId: '',
      launchContext: launchCtx(simpleSession()),
    );

    final ids = seatRuntime().messages.map((m) => m.id).toList();
    expect(ids, ['u-1']);
    expect(ids.any((id) => id.contains('mail-unread')), isFalse);
  });

  test(
    'refreshMailboxTimeline merges a newly read mailbox mail after consume',
    () async {
      holderMessages = [
        AiMessage(
          id: 'u-1',
          role: AiRole.user,
          parts: const [AiTextPart(text: 'cli user')],
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      ];
      locator.emitBundle = true;

      var mailboxRecords = <LoggedMessage>[];
      await cubit.close();
      cubit = AiHistoryCubit(
        loader: loader,
        loadMailboxRecords: (sessionId, memberId) async => mailboxRecords,
      );

      await cubit.load(
        session: simpleSession(),
        memberId: '',
        launchContext: launchCtx(simpleSession()),
      );
      expect(seatRuntime().messages.map((m) => m.id).toList(), ['u-1']);

      // Simulate SessionChatView's onConsumed: the Queued strip observed the
      // mail is no longer unread and asks History to refresh the merge —
      // no CLI reload involved.
      mailboxRecords = [
        LoggedMessage(
          seq: 0,
          message: const TeamMessage(
            id: 'mail-1',
            from: TeamBus.userSenderId,
            to: 'dev',
            content: 'mailbox user',
          ),
          createdAt: 2000,
          read: true,
        ),
      ];

      await cubit.refreshMailboxTimeline();

      final ids = seatRuntime().messages.map((m) => m.id).toList();
      expect(ids, ['u-1', 'mailbox:mail-1']);
      final mailboxMsg = seatRuntime().messages.last;
      expect(mailboxMsg.deliveryChannel, 'mailbox');
    },
  );

  test(
    'refreshMailboxTimeline degrades to CLI-only when the mailbox loader '
    'throws',
    () async {
      holderMessages = messages(2);
      locator.emitBundle = true;

      await cubit.close();
      cubit = AiHistoryCubit(
        loader: loader,
        loadMailboxRecords: (sessionId, memberId) async =>
            throw StateError('mailbox boom'),
      );

      await cubit.load(
        session: simpleSession(),
        memberId: '',
        launchContext: launchCtx(simpleSession()),
      );
      expect(seatRuntime().messages.map((m) => m.id).toList(), [
        'm-0',
        'm-1',
      ]);

      await cubit.refreshMailboxTimeline();

      expect(seatRuntime().messages.map((m) => m.id).toList(), [
        'm-0',
        'm-1',
      ]);
    },
  );

  test(
    'softReload with a transient empty CLI parse keeps prior CLI history '
    'and still merges a new read mailbox message (no wipe)',
    () async {
      holderMessages = messages(5);
      locator.emitBundle = true;

      var mailboxRecords = <LoggedMessage>[];
      await cubit.close();
      cubit = AiHistoryCubit(
        loader: loader,
        loadMailboxRecords: (sessionId, memberId) async => mailboxRecords,
      );

      await cubit.load(
        session: simpleSession(),
        memberId: '',
        launchContext: launchCtx(simpleSession()),
      );
      expect(seatRuntime().messages, hasLength(5));

      // Transient empty CLI parse (e.g. locate() briefly finds no bundle)
      // while the mailbox now has a NEW read message not yet in the timeline.
      holderMessages = const [];
      locator.emitBundle = false;
      mailboxRecords = [
        LoggedMessage(
          seq: 0,
          message: const TeamMessage(
            id: 'mail-1',
            from: TeamBus.userSenderId,
            to: 'dev',
            content: 'mailbox user',
          ),
          createdAt: 6000,
          read: true,
        ),
      ];

      await cubit.softReload();

      final ids = seatRuntime().messages.map((m) => m.id).toList();
      expect(ids, containsAll(['m-0', 'm-1', 'm-2', 'm-3', 'm-4']));
      expect(ids, contains('mailbox:mail-1'));
    },
  );

  test(
    'mailbox bubble survives seat reopen from mailbox loader',
    () async {
      holderMessages = messages(2);
      locator.emitBundle = true;

      var mailboxRecords = <LoggedMessage>[];
      await cubit.close();
      cubit = AiHistoryCubit(
        loader: loader,
        loadMailboxRecords: (sessionId, memberId) async => mailboxRecords,
      );

      final session = simpleSession();
      await cubit.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );
      expect(seatRuntime().messages.map((m) => m.id).toList(), [
        'm-0',
        'm-1',
      ]);

      mailboxRecords = [
        LoggedMessage(
          seq: 0,
          message: const TeamMessage(
            id: 'mail-1',
            from: TeamBus.userSenderId,
            to: 'dev',
            content: 'mailbox follow-up',
          ),
          createdAt: 3000,
          read: true,
        ),
      ];
      await cubit.refreshMailboxTimeline();
      expect(seatRuntime().messages.last.id, 'mailbox:mail-1');
      expect(seatRuntime().messages.last.deliveryChannel, 'mailbox');

      cubit.clearPendings();
      await cubit.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );

      final mailboxMsg = seatRuntime().messages.firstWhere(
        (m) => m.id == 'mailbox:mail-1',
      );
      expect(mailboxMsg.deliveryChannel, 'mailbox');
      expect(
        (mailboxMsg.parts.single as AiTextPart).text,
        'mailbox follow-up',
      );

      // Switch away then reopen same seat — rebuilds from log, not sticky.
      await cubit.load(
        session: simpleSession(id: 'other'),
        memberId: '',
        launchContext: launchCtx(simpleSession(id: 'other')),
      );
      await cubit.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );

      final reopened = seatRuntime().messages.firstWhere(
        (m) => m.id == 'mailbox:mail-1',
      );
      expect(reopened.deliveryChannel, 'mailbox');
    },
  );

  test(
    'mailbox: loader throwing degrades to CLI-only history',
    () async {
      holderMessages = messages(2);
      locator.emitBundle = true;

      await cubit.close();
      cubit = AiHistoryCubit(
        loader: loader,
        loadMailboxRecords: (sessionId, memberId) async =>
            throw StateError('mailbox boom'),
      );

      await cubit.load(
        session: simpleSession(),
        memberId: '',
        launchContext: launchCtx(simpleSession()),
      );

      expect(cubit.state.status, AiHistoryViewStatus.ready);
      expect(seatRuntime().messages.map((m) => m.id).toList(), [
        'm-0',
        'm-1',
      ]);
    },
  );
}

AiTranscriptBundle _dummyBundle() => const AiTranscriptBundle(
  adapterId: 'claude',
  fragments: [
    AiTranscriptFragment(name: 'canned.jsonl', bytes: []),
  ],
);

class _HolderAdapter implements AiTranscriptAdapter {
  _HolderAdapter(this._messages);

  final List<AiMessage> Function() _messages;

  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async =>
      List.of(_messages());
}

class _ScriptedLocator extends AiHistoryLocator {
  bool emitBundle = false;
  Object? error;
  final queue = <Future<AiTranscriptBundle?>>[];

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) async {
    if (error != null) throw error!;
    if (queue.isNotEmpty) return queue.removeAt(0);
    if (!emitBundle) return null;
    return _dummyBundle();
  }
}
