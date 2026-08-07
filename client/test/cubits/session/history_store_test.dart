import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/history_store.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/fake_ai_history_registry.dart';
import '../../support/post_frame_test_harness.dart';

class _HolderAdapter implements AiTranscriptAdapter {
  _HolderAdapter(this.messages);

  final List<AiMessage> Function() messages;

  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async =>
      List.of(messages());
}

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
  late HistoryStore store;

  AppSession session() => AppSession(
    sessionId: 's1',
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
    holderMessages = messages(1);
    cacheToken = 'token-1';
    locator = _ScriptedLocator()..emitBundle = true;
    final fs = LocalFilesystem();
    store = HistoryStore(
      loader: AiHistoryLoader(
        contextBuilder: const SessionHistoryContextBuilder(),
        resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
          target: RuntimeTarget.local(),
          filesystem: fs,
          home: '/tmp/history-store',
          cwd: '/tmp/history-store',
          appDataRoot: '/tmp/history-store',
          paths: AppPaths('/tmp/history-store'),
        ),
        locator: locator,
        registry: fakeAiHistoryRegistry(
          cli: CliTool.claude,
          adapter: _HolderAdapter(() => holderMessages),
        ),
        resolveCacheToken: (_) async => cacheToken,
      ),
    );
  });

  tearDown(() async {
    await store.close();
    tearDownTestAppStorage();
  });

  test('memberSeat is per (session, member) and stable', () {
    final a = store.memberSeat(sessionId: 's1', memberId: '');
    final a2 = store.memberSeat(sessionId: 's1', memberId: '');
    final b = store.memberSeat(sessionId: 's1', memberId: 'member-x');
    expect(identical(a, a2), isTrue);
    expect(identical(a, b), isFalse);
  });

  test('disposeSeats closes seats for a session', () async {
    final seat = store.memberSeat(sessionId: 's1', memberId: '');
    expect(seat.isClosed, isFalse);
    await store.disposeSeats('s1');
    expect(seat.isClosed, isTrue);
  });

  test('seedPendingUser is consumed when the seat loads', () async {
    final seat = store.memberSeat(sessionId: 's1', memberId: '');
    store.seedPendingUser(sessionId: 's1', memberId: '', text: 'hello');
    // Fresh seat buffers the seed (its sessionId is null until first load).
    expect(seat.hasOptimisticPending, isFalse);

    await seat.load(
      session: session(),
      memberId: '',
      launchContext: ctx(session()),
    );

    expect(seat.hasOptimisticPending, isTrue);
  });

  test('cancelSeedPendingUser removes a buffered seed before load', () async {
    final seat = store.memberSeat(sessionId: 's1', memberId: '');
    store.seedPendingUser(sessionId: 's1', memberId: '', text: 'hello');
    store.cancelSeedPendingUser(sessionId: 's1', text: 'hello');

    await seat.load(
      session: session(),
      memberId: '',
      launchContext: ctx(session()),
    );

    expect(seat.hasOptimisticPending, isFalse);
  });
}
