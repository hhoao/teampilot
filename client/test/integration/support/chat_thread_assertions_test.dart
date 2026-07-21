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
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/terminal/pending_user_message.dart';

import '../../support/post_frame_test_harness.dart';
import 'chat_thread_assertions.dart';

void main() {
  late _ScriptedLocator locator;
  late List<AiMessage> holderMessages;
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
  );

  setUp(() {
    setUpTestAppStorage();
    holderMessages = const [];
    locator = _ScriptedLocator();
    final fs = LocalFilesystem();
    final loader = AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: '/tmp/chat-thread-assertions',
        cwd: '/tmp/chat-thread-assertions',
        appDataRoot: '/tmp/chat-thread-assertions',
        paths: AppPaths('/tmp/chat-thread-assertions'),
      ),
      locator: locator,
      adapters: {
        CliTool.claude: _HolderAdapter(() => holderMessages),
      },
    );
    cubit = AiHistoryCubit(loader: loader);
  });

  tearDown(() async {
    await cubit.close();
    tearDownTestAppStorage();
  });

  test('expectUserBubble finds optimistic pending user text', () {
    cubit.enqueuePendingUser('hello operator');
    expectUserBubble(cubit, 'hello operator');
  });

  test('expectUserBubble finds sticky mailbox user text', () {
    cubit.appendStickyLocalUser(id: 'mailbox:mail-1', text: 'mailbox follow-up');
    expectUserBubble(cubit, 'mailbox follow-up');
  });

  test('expectAssistantMarkers requires ≥3 and finds each marker', () async {
    locator.emitBundle = true;
    holderMessages = [
      const AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'prefix MARK_A1')],
      ),
      const AiMessage(
        id: 'a2',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'MARK_A2 mid')],
      ),
      const AiMessage(
        id: 'a3',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'tail MARK_A3')],
      ),
    ];
    await cubit.load(
      session: simpleSession(),
      memberId: '',
      launchContext: launchCtx(simpleSession()),
    );

    expectAssistantMarkers(cubit, const ['MARK_A1', 'MARK_A2', 'MARK_A3']);
  });

  test('expectAssistantMarkers rejects fewer than 3 markers', () async {
    locator.emitBundle = true;
    holderMessages = [
      const AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'MARK_A1')],
      ),
      const AiMessage(
        id: 'a2',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'MARK_A2')],
      ),
    ];
    await cubit.load(
      session: simpleSession(),
      memberId: '',
      launchContext: launchCtx(simpleSession()),
    );

    expect(
      () => expectAssistantMarkers(cubit, const ['MARK_A1', 'MARK_A2']),
      throwsA(isA<TestFailure>()),
    );
  });

  test('expectMailboxQueuedThenSticky checks Queued snapshot and sticky id', () {
    const mailId = 'mail-42';
    const text = 'please handle this';
    final queued = [
      const PendingUserMessage(id: mailId, content: text),
    ];
    cubit.appendStickyLocalUser(id: 'mailbox:$mailId', text: text);

    expectMailboxQueuedThenSticky(
      queuedSnapshot: queued,
      history: cubit,
      text: text,
      mailId: mailId,
    );
  });

  test('dumpThread includes roles and text for failure messages', () {
    cubit.enqueuePendingUser('pending-line');
    cubit.appendStickyLocalUser(id: 'mailbox:m1', text: 'sticky-line');
    final dump = dumpThread(cubit);
    expect(dump, contains('pending-line'));
    expect(dump, contains('sticky-line'));
    expect(dump, contains('user'));
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

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) async {
    if (!emitBundle) return null;
    return _dummyBundle();
  }
}
