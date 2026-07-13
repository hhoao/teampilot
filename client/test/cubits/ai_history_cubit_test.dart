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
