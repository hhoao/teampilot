import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/chat/conversation/history/ai_history_loader.dart';
import 'package:teampilot/services/chat/conversation/history/ai_history_locator.dart';
import 'package:teampilot/services/chat/conversation/history/history_parse_worker.dart';
import 'package:teampilot/services/chat/conversation/history/session_history_context.dart';
import 'package:teampilot/services/chat/conversation/history/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../support/fake_ai_history_registry.dart';
import '../support/post_frame_test_harness.dart';

void main() {
  late Map<String, List<AiMessage>> messagesBySession;
  late _ScriptedLocator locator;
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

  WorkspaceLaunchContext launchCtx(AppSession s) => WorkspaceLaunchContext(
    session: s,
    workspace: Workspace(
      workspaceId: s.workspaceId,
      folders: s.folders,
      createdAt: 0,
    ),
    usesPosixPaths: false,
  );

  List<AiMessage> markerMessages(String marker) => [
    AiMessage(
      id: 'm-$marker-0',
      role: AiRole.user,
      parts: [AiTextPart(text: 'marker-$marker')],
    ),
    AiMessage(
      id: 'm-$marker-1',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'reply-$marker')],
    ),
  ];

  bool messageHasText(AiMessage m, String needle) =>
      m.parts.any((p) => p is AiTextPart && p.text.contains(needle));

  AiHistoryLoader makeLoader({HistoryParseExecutor? parseExecutor}) {
    final fs = LocalFilesystem();
    return AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: '/tmp/ai-history-seat-isolation',
        cwd: '/tmp/ai-history-seat-isolation',
        appDataRoot: '/tmp/ai-history-seat-isolation',
        paths: AppPaths('/tmp/ai-history-seat-isolation'),
      ),
      locator: locator,
      registry: fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: _SessionMapAdapter(() => messagesBySession),
      ),
      resolveCacheToken: (_) async {
        // SoftReload reuses the loader token cache; fingerprint fixture
        // messages so in-memory transcript edits invalidate like mtime/size.
        final buf = StringBuffer();
        for (final e in messagesBySession.entries) {
          buf.write(e.key);
          buf.write(':');
          for (final m in e.value) {
            buf.write(m.id);
            buf.write('|');
          }
          buf.write(';');
        }
        return buf.toString();
      },
      parseExecutor: parseExecutor,
    );
  }

  setUp(() {
    setUpTestAppStorage();
    messagesBySession = {
      'sess-a': markerMessages('A'),
      'sess-b': markerMessages('B'),
    };
    locator = _ScriptedLocator();
    loader = makeLoader();
    cubit = AiHistoryCubit(loader: loader);
  });

  tearDown(() async {
    await cubit.close();
    tearDownTestAppStorage();
  });

  test('two seats keep independent runtimes after load', () async {
    locator.emitBundle = true;
    final sessionA = simpleSession(id: 'sess-a');
    final sessionB = simpleSession(id: 'sess-b');

    await cubit.load(
      session: sessionA,
      memberId: '',
      launchContext: launchCtx(sessionA),
    );
    await cubit.load(
      session: sessionB,
      memberId: '',
      launchContext: launchCtx(sessionB),
    );

    final seatA = cubit.ensureSeat(
      sessionId: sessionA.sessionId,
      selectedMemberId: '',
    );
    final seatB = cubit.ensureSeat(
      sessionId: sessionB.sessionId,
      selectedMemberId: '',
    );

    expect(identical(seatA.runtime, seatB.runtime), isFalse);
    expect(
      seatA.runtime.messages.any((m) => messageHasText(m, 'marker-A')),
      isTrue,
    );
    expect(
      seatB.runtime.messages.any((m) => messageHasText(m, 'marker-B')),
      isTrue,
    );
    expect(
      seatA.runtime.messages.any((m) => messageHasText(m, 'marker-B')),
      isFalse,
    );
  });

  test(
    'merged messages keep tool call categories after mailbox merge',
    () async {
      messagesBySession['sess-a'] = [
        AiMessage(
          id: 'm-tool',
          role: AiRole.assistant,
          parts: [AiToolCallPart(toolCallId: 't1', toolName: 'Bash')],
        ),
      ];
      locator.emitBundle = true;
      final session = simpleSession(id: 'sess-a');
      await cubit.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );
      final seat = cubit.ensureSeat(
        sessionId: session.sessionId,
        selectedMemberId: '',
      );

      final tool = seat.runtime.messages
          .expand((m) => m.parts)
          .whereType<AiToolCallPart>()
          .single;
      expect(tool.toolName, 'Bash');
      expect(tool.category, AiToolCallCategory.command);
    },
  );

  test('softReload seat A does not change seat B messages', () async {
    locator.emitBundle = true;
    final sessionA = simpleSession(id: 'sess-a');
    final sessionB = simpleSession(id: 'sess-b');

    await cubit.load(
      session: sessionA,
      memberId: '',
      launchContext: launchCtx(sessionA),
    );
    await cubit.load(
      session: sessionB,
      memberId: '',
      launchContext: launchCtx(sessionB),
    );

    final seatA = cubit.ensureSeat(
      sessionId: sessionA.sessionId,
      selectedMemberId: '',
    );
    final seatB = cubit.ensureSeat(
      sessionId: sessionB.sessionId,
      selectedMemberId: '',
    );
    final bIdsBefore = seatB.runtime.messages.map((m) => m.id).toList();

    messagesBySession['sess-a'] = [
      ...markerMessages('A'),
      const AiMessage(
        id: 'm-A-tip',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'extra-A-tip')],
      ),
    ];
    await seatA.softReload();

    expect(seatA.runtime.messages.any((m) => m.id == 'm-A-tip'), isTrue);
    expect(
      seatA.runtime.messages.any((m) => messageHasText(m, 'extra-A-tip')),
      isTrue,
    );
    expect(seatB.runtime.messages.map((m) => m.id).toList(), bIdsBefore);
  });

  test('seedPendingUser for B while A loaded applies on B load only', () async {
    locator.emitBundle = true;
    final sessionA = simpleSession(id: 'sess-a');
    final sessionB = simpleSession(id: 'sess-b');

    await cubit.load(
      session: sessionA,
      memberId: '',
      launchContext: launchCtx(sessionA),
    );
    final seatA = cubit.ensureSeat(
      sessionId: sessionA.sessionId,
      selectedMemberId: '',
    );

    cubit.seedPendingUser(
      sessionId: sessionB.sessionId,
      memberId: sessionB.sessionId, // shell id for simple
      text: 'hello-b',
    );
    expect(
      seatA.runtime.messages.any((m) => messageHasText(m, 'hello-b')),
      isFalse,
    );

    await cubit.load(
      session: sessionB,
      memberId: '',
      launchContext: launchCtx(sessionB),
    );
    final seatB = cubit.ensureSeat(
      sessionId: sessionB.sessionId,
      selectedMemberId: '',
    );
    expect(
      seatB.runtime.messages.any((m) => messageHasText(m, 'hello-b')),
      isTrue,
    );
  });

  test('disposeSeatsForSession removes seats and closes runtimes', () async {
    locator.emitBundle = true;
    final sessionA = simpleSession(id: 'sess-a');

    await cubit.load(
      session: sessionA,
      memberId: '',
      launchContext: launchCtx(sessionA),
    );
    final disposedSeat = cubit.seatOf(
      sessionId: sessionA.sessionId,
      selectedMemberId: '',
    );
    expect(disposedSeat, isNotNull);
    final disposedRuntime = disposedSeat!.runtime;

    cubit.disposeSeatsForSession(sessionA.sessionId);

    expect(
      cubit.seatOf(sessionId: sessionA.sessionId, selectedMemberId: ''),
      isNull,
    );

    final reseated = cubit.ensureSeat(
      sessionId: sessionA.sessionId,
      selectedMemberId: '',
    );
    expect(identical(reseated.runtime, disposedRuntime), isFalse);
  });

  test('disposeSeatsForSession drops pending seeds for that session', () async {
    locator.emitBundle = false;
    final sessionA = simpleSession(id: 'sess-a');

    cubit.seedPendingUser(
      sessionId: sessionA.sessionId,
      memberId: '',
      text: 'stale-seed-a',
    );
    cubit.disposeSeatsForSession(sessionA.sessionId);

    await cubit.load(
      session: sessionA,
      memberId: '',
      launchContext: launchCtx(sessionA),
    );
    final seatA = cubit.ensureSeat(
      sessionId: sessionA.sessionId,
      selectedMemberId: '',
    );
    expect(
      seatA.runtime.messages.any((m) => messageHasText(m, 'stale-seed-a')),
      isFalse,
    );
    expect(cubit.state.awaitingAssistant, isFalse);
  });

  test('softReloadIfSession refreshes every seat for the session', () async {
    locator.emitBundle = true;
    final session = simpleSession(id: 'sess-a');
    final launch = launchCtx(session);
    await cubit.load(session: session, memberId: '', launchContext: launch);
    final seat = cubit.ensureSeat(
      sessionId: session.sessionId,
      selectedMemberId: '',
    );
    expect(seat.state.status, AiHistoryViewStatus.ready);

    // Second open seat for same session (never loaded → empty).
    final idle = cubit.ensureSeat(
      sessionId: session.sessionId,
      selectedMemberId: 'ghost',
    );
    expect(idle.state.status, AiHistoryViewStatus.empty);

    messagesBySession['sess-a'] = markerMessages('A-stale');
    await cubit.softReloadIfSession(session.sessionId);

    expect(
      seat.runtime.messages.any((m) => messageHasText(m, 'marker-A-stale')),
      isTrue,
    );
    // Empty never-loaded seats have no _last* — invalidateAndReload no-ops,
    // but must not throw and must still visit the ready seat.
    expect(idle.state.status, AiHistoryViewStatus.empty);
  });

  test('late worker result cannot replace a newer seat generation', () async {
    locator.emitBundle = true;
    locator.emitLargeBundle = true;
    final executor = _QueuedHistoryParseExecutor();
    loader = makeLoader(parseExecutor: executor);
    final seat = AiHistorySeat(loader: loader);
    addTearDown(seat.close);
    final sessionA = simpleSession(id: 'sess-a');
    final sessionB = simpleSession(id: 'sess-b');

    final loadA = seat.load(
      session: sessionA,
      memberId: '',
      launchContext: launchCtx(sessionA),
    );
    await pumpEventQueue();
    final loadB = seat.load(
      session: sessionB,
      memberId: '',
      launchContext: launchCtx(sessionB),
    );
    await pumpEventQueue();
    expect(executor.requests, hasLength(2));

    executor.complete(0, 'old-result');
    await pumpEventQueue();
    expect(seat.runtime.messages, isEmpty);

    executor.complete(1, 'new-result');
    await Future.wait([loadA, loadB]);
    expect(seat.state.sessionId, sessionB.sessionId);
    expect(seat.runtime.messages.single.id, 'new-result');
  });

  test('worker failure keeps the existing transcript', () async {
    locator.emitBundle = true;
    final executor = _QueuedHistoryParseExecutor();
    loader = makeLoader(parseExecutor: executor);
    final seat = AiHistorySeat(loader: loader);
    addTearDown(seat.close);
    final session = simpleSession();

    await seat.load(
      session: session,
      memberId: '',
      launchContext: launchCtx(session),
    );
    expect(seat.runtime.messages.map((message) => message.id), [
      'm-A-0',
      'm-A-1',
    ]);

    locator.emitLargeBundle = true;
    final reload = seat.load(
      session: session,
      memberId: '',
      launchContext: launchCtx(session),
      force: true,
    );
    await pumpEventQueue();
    expect(executor.requests, hasLength(1));

    executor.fail(0, StateError('worker failed'));
    await reload;

    expect(seat.runtime.messages.map((message) => message.id), [
      'm-A-0',
      'm-A-1',
    ]);
  });
}

AiTranscriptBundle _bundleForSession(String sessionId, {bool large = false}) =>
    AiTranscriptBundle(
      adapterId: 'claude',
      fragments: [
        AiTranscriptFragment(
          name: 'canned.jsonl',
          bytes: large ? List<int>.filled(256 * 1024, 32) : const [],
        ),
      ],
      hints: {'sessionId': sessionId},
    );

class _SessionMapAdapter implements AiTranscriptAdapter {
  _SessionMapAdapter(this._messagesBySession);

  final Map<String, List<AiMessage>> Function() _messagesBySession;

  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    final sessionId = bundle.hints['sessionId'] ?? '';
    return List.of(_messagesBySession()[sessionId] ?? const []);
  }
}

class _ScriptedLocator extends AiHistoryLocator {
  bool emitBundle = false;
  bool emitLargeBundle = false;
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
    final sessionId = ctx.sessionId?.trim() ?? '';
    return _bundleForSession(sessionId, large: emitLargeBundle);
  }
}

final class _QueuedHistoryParseExecutor implements HistoryParseExecutor {
  final requests = <Completer<HistoryParseResult>>[];

  @override
  Future<HistoryParseResult> parse({
    required String adapterId,
    required AiTranscriptBundle bundle,
    String? workerEnricherId,
    String? sourceToken,
    String? rootTranscriptPath,
  }) {
    final request = Completer<HistoryParseResult>();
    requests.add(request);
    return request.future;
  }

  void complete(int index, String id) {
    requests[index].complete(
      HistoryParseResult(
        messages: [
          AiMessage(
            id: id,
            role: AiRole.assistant,
            parts: [AiTextPart(text: id)],
          ),
        ],
      ),
    );
  }

  void fail(int index, Object error) {
    requests[index].completeError(error);
  }

  @override
  Future<void> dispose() async {}
}
