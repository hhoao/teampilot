import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_seat.dart';
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
import 'package:teampilot/utils/logging/logger.dart';

import '../support/fake_ai_history_registry.dart';
import '../support/post_frame_test_harness.dart';

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

AiToolCallPart _tool(String callId, {Object? result, String name = 'question'}) {
  return AiToolCallPart(
    toolCallId: callId,
    toolName: name,
    status:
        result == null ? AiToolCallStatus.incomplete : AiToolCallStatus.complete,
    result: result,
  );
}

void main() {
  late _ScriptedLocator locator;
  late List<AiMessage> holderMessages;
  late String cacheToken;
  late AiHistoryLoader loader;
  late AiHistorySeat seat;

  void bumpCacheToken() =>
      cacheToken = 'token-${cacheToken.hashCode.abs()}-${holderMessages.length}';

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
        home: '/tmp/history-seat-dedup',
        cwd: '/tmp/history-seat-dedup',
        appDataRoot: '/tmp/history-seat-dedup',
        paths: AppPaths('/tmp/history-seat-dedup'),
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

  test('duplicate assistant pair in the live list publishes only the winner',
      () async {
    holderMessages = [
      AiMessage(
        id: 'u1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'question?')],
      ),
      AiMessage(
        id: 'asst-pending',
        role: AiRole.assistant,
        parts: [
          const AiTextPart(text: "I've traced the full back-navigation path"),
          _tool('call_q1'),
        ],
      ),
      AiMessage(
        id: 'asst-completed',
        role: AiRole.assistant,
        parts: [
          const AiTextPart(text: "I've traced the full back-navigation path"),
          _tool('call_q1', result: '{"answers":[]}'),
        ],
      ),
    ];
    await seat.load(session: session(), memberId: '', launchContext: ctx(session()));

    expect(seat.runtime.messages, hasLength(2));
    expect(
      seat.runtime.messages.map((m) => m.id),
      ['u1', 'asst-completed'],
      reason: '同文本 pending/completed 双份只发布 completed 版',
    );
  });

  test('duplicate pair logs [ai-history] duplicate-messages once per fingerprint',
      () async {
    final before = await AppLogger.instance.getPendingLogLines();
    holderMessages = [
      AiMessage(
        id: 'u1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'question?')],
      ),
      AiMessage(
        id: 'asst-pending',
        role: AiRole.assistant,
        parts: [
          const AiTextPart(text: 'same prose'),
          _tool('call_q1'),
        ],
      ),
      AiMessage(
        id: 'asst-completed',
        role: AiRole.assistant,
        parts: [
          const AiTextPart(text: 'same prose'),
          _tool('call_q1', result: 'answer'),
        ],
      ),
    ];
    await seat.load(session: session(), memberId: '', launchContext: ctx(session()));

    var lines = await AppLogger.instance.getPendingLogLines();
    final firstLogs = lines.skip(before.length).where(
      (l) => l.contains('[ai-history] duplicate-messages'),
    );
    expect(firstLogs, hasLength(1), reason: '去重触发必须打日志');

    // 同指纹再次出现（soft reload 同列表）→ 不再打。
    bumpCacheToken();
    await seat.softReload();
    lines = await AppLogger.instance.getPendingLogLines();
    final secondLogs = lines.skip(before.length).where(
      (l) => l.contains('[ai-history] duplicate-messages'),
    );
    expect(secondLogs, hasLength(1), reason: '相同重复指纹防刷屏，只打一次');
  });
}
