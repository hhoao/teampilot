import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/session/session_history_pagination.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  late _ScriptedLocator locator;
  late List<AiMessage> holderMessages;
  late AiHistoryLoader loader;
  late AiHistoryCubit cubit;

  AppSession simpleSession({String id = 'sess-a'}) => AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work/project')],
    cli: CliTool.claude,
    createdAt: 1,
    updatedAt: 1,
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
    final layout = RuntimeLayout(
      teampilotRoot: '/tmp/ai-history-cubit',
      fs: fs,
    );
    loader = AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      fs: () => fs,
      layout: () => layout,
      appDataRoot: () => '/tmp/ai-history-cubit',
      locator: locator,
      adapters: {
        CliTool.claude: _HolderAdapter(() => holderMessages),
      },
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

    final done = cubit.load(session: simpleSession(), memberId: '');
    expect(cubit.state.status, AiHistoryViewStatus.loading);
    expect(cubit.runtime.status, AiThreadStatus.loading);
    await done;

    expect(cubit.state.status, AiHistoryViewStatus.ready);
    expect(cubit.state.totalMessageCount, 2);
    expect(cubit.state.hasOlder, isFalse);
    expect(cubit.runtime.messages, hasLength(2));
    expect(cubit.runtime.status, AiThreadStatus.idle);
  });

  test('empty load sets runtime empty', () async {
    locator.emitBundle = false;
    await cubit.load(session: simpleSession(), memberId: '');
    expect(cubit.state.status, AiHistoryViewStatus.empty);
    expect(cubit.runtime.status, AiThreadStatus.empty);
    expect(cubit.runtime.messages, isEmpty);
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
    );
    final secondLoad = cubit.load(
      session: simpleSession(id: 's2'),
      memberId: '',
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
    expect(cubit.runtime.messages.single.id, 'second');

    holderMessages = [
      const AiMessage(
        id: 'first',
        role: AiRole.user,
        parts: [AiTextPart(text: 'first')],
      ),
    ];
    first.complete(_dummyBundle());
    await firstLoad;

    expect(cubit.state.sessionId, 's2');
    expect(cubit.runtime.messages.single.id, 'second');
  });

  test('windows to recent messages and loadOlder expands slice', () async {
    holderMessages = messages(50);
    locator.emitBundle = true;

    await cubit.load(session: simpleSession(), memberId: '');
    expect(cubit.state.totalMessageCount, 50);
    expect(cubit.runtime.messages, hasLength(kSessionHistoryInitialTurns));
    expect(cubit.runtime.messages.first.id, 'm-20');
    expect(cubit.runtime.messages.last.id, 'm-49');
    expect(cubit.state.hasOlder, isTrue);

    cubit.loadOlder();
    expect(cubit.runtime.messages, hasLength(50));
    expect(cubit.state.hasOlder, isFalse);
    expect(cubit.state.isLoadingOlder, isFalse);
  });

  test('error sets runtime error', () async {
    locator.error = StateError('boom');
    await cubit.load(session: simpleSession(), memberId: '');
    expect(cubit.state.status, AiHistoryViewStatus.error);
    expect(cubit.state.errorMessage, contains('boom'));
    expect(cubit.runtime.status, AiThreadStatus.error);
  });

  test('softReload grows visibleCount by tip delta and preserves start', () async {
    holderMessages = messages(40);
    locator.emitBundle = true;

    await cubit.load(session: simpleSession(), memberId: '');
    expect(cubit.runtime.messages, hasLength(kSessionHistoryInitialTurns));
    expect(cubit.runtime.messages.first.id, 'm-10');

    cubit.loadOlder();
    expect(cubit.state.totalMessageCount, 40);
    expect(cubit.runtime.messages, hasLength(40));
    expect(cubit.runtime.messages.first.id, 'm-0');

    holderMessages = messages(42);
    await cubit.softReload();

    expect(cubit.state.totalMessageCount, 42);
    expect(cubit.runtime.messages, hasLength(42));
    expect(cubit.runtime.messages.first.id, 'm-0');
    expect(cubit.runtime.messages.last.id, 'm-41');
    expect(cubit.state.hasOlder, isFalse);
  });

  test('softReload does not emit loading when already ready', () async {
    holderMessages = messages(2);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '');
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
    await cubit.load(session: simpleSession(), memberId: '');
    cubit.loadOlder();
    expect(cubit.runtime.messages, hasLength(40));

    holderMessages = messages(25);
    await cubit.softReload();

    expect(cubit.state.totalMessageCount, 25);
    expect(cubit.runtime.messages, hasLength(25));
    expect(cubit.runtime.messages.first.id, 'm-0');
    expect(cubit.runtime.messages.last.id, 'm-24');
  });

  test('pending user merges then drops on matching tip user text', () async {
    holderMessages = messages(2);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '');

    cubit.enqueuePendingUser('hello   world');
    expect(cubit.state.awaitingAssistant, isTrue);
    expect(cubit.runtime.messages, hasLength(3));
    expect(cubit.runtime.messages.last.id, startsWith('pending:'));
    expect(
      (cubit.runtime.messages.last.parts.single as AiTextPart).text,
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
      cubit.runtime.messages.where((m) => m.id.startsWith('pending:')),
      isEmpty,
    );
    expect(cubit.runtime.messages.last.id, 'u-hello');
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
    expect(cubit.runtime.messages.last.id, 'u-hello');

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
    expect(cubit.runtime.messages.last.id, 'u-hello');

    // Still working after hold: reveal tip, keep Running.
    await Future<void>.delayed(
      AiHistoryCubit.tipHoldAfterAssistant + const Duration(milliseconds: 50),
    );
    expect(cubit.state.awaitingAssistant, isTrue);
    expect(cubit.hasHeldAssistantTip, isFalse);
    expect(cubit.runtime.messages.last.id, 'a-2');

    cubit.flushHeldTip(endAwaiting: true);
    expect(cubit.state.awaitingAssistant, isFalse);
  });

  test('held assistant tip flushes immediately on idle endAwaiting', () async {
    holderMessages = messages(1);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '');

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
    expect(cubit.runtime.messages.last.id, 'u-1');

    cubit.flushHeldTip(endAwaiting: true);
    expect(cubit.hasHeldAssistantTip, isFalse);
    expect(cubit.state.awaitingAssistant, isFalse);
    expect(cubit.runtime.messages.last.id, 'a-1');
  });

  test('multi pending drops independently by normalized text', () async {
    holderMessages = messages(1);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '');

    cubit.enqueuePendingUser('a');
    cubit.enqueuePendingUser('b');
    expect(
      cubit.runtime.messages.where((m) => m.id.startsWith('pending:')),
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

    final pendings = cubit.runtime.messages
        .where((m) => m.id.startsWith('pending:'))
        .toList();
    expect(pendings, hasLength(1));
    expect((pendings.single.parts.single as AiTextPart).text, 'b');
  });

  test('enqueuePendingUser on empty promotes to ready with pending tip', () async {
    locator.emitBundle = false;
    await cubit.load(session: simpleSession(), memberId: '');
    expect(cubit.state.status, AiHistoryViewStatus.empty);

    cubit.enqueuePendingUser('continue me');

    expect(cubit.state.status, AiHistoryViewStatus.ready);
    expect(cubit.runtime.messages, hasLength(1));
    expect(cubit.runtime.messages.single.id, startsWith('pending:'));
    expect(
      (cubit.runtime.messages.single.parts.single as AiTextPart).text,
      'continue me',
    );
  });

  test('softReloadOrLoad soft-reloads when already ready for same seat', () async {
    holderMessages = messages(2);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '');
    expect(cubit.state.status, AiHistoryViewStatus.ready);

    final statuses = <AiHistoryViewStatus>[];
    final sub = cubit.stream.listen((s) => statuses.add(s.status));

    holderMessages = messages(3);
    await cubit.softReloadOrLoad(
      session: simpleSession(),
      memberId: '',
    );
    await sub.cancel();

    expect(statuses, isNot(contains(AiHistoryViewStatus.loading)));
    expect(cubit.state.status, AiHistoryViewStatus.ready);
    expect(cubit.state.totalMessageCount, 3);
  });

  test('softReloadIfSession soft-reloads when ready for session', () async {
    holderMessages = messages(2);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '');
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
    await cubit.load(session: simpleSession(), memberId: '');

    final delayed = Completer<AiTranscriptBundle?>();
    locator.queue.add(delayed.future);

    final soft = cubit.softReload();
    cubit.clear();
    expect(cubit.state.status, AiHistoryViewStatus.empty);

    holderMessages = messages(5);
    delayed.complete(_dummyBundle());
    await soft;

    expect(cubit.state.status, AiHistoryViewStatus.empty);
    expect(cubit.runtime.messages, isEmpty);
    expect(cubit.state.totalMessageCount, 0);
  });
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
