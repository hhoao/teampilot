import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_seat.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/subagent_side_resolver.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../support/fake_ai_history_registry.dart';
import '../support/post_frame_test_harness.dart';

/// Adapter returning whatever the mutable [messages] closure holds at parse
/// time (parent transcript is deliberately frozen across reloads).
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
  bool emitBundle = true;

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

/// Side resolver whose transcript content and fingerprint are both mutable —
/// mimics a running sub-agent appending its own jsonl while the parent stays
/// frozen.
class _MutableSideResolver implements SubagentSideResolver {
  _MutableSideResolver({
    required this.messages,
    required this.token,
  });

  final List<AiMessage> Function() messages;
  final String Function() token;
  bool failResolve = false;

  @override
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
    DateTime? toolCallAt,
  }) async {
    if (failResolve) return null;
    return SubagentSideResolveResult(
      messages: List.of(messages()),
      handle: const SubagentFileHandle('/side/agent-1.jsonl'),
    );
  }

  @override
  Future<String?> fingerprint({
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
  }) async => token();
}

void main() {
  late List<AiMessage> holderMessages;
  late List<AiMessage> sideMessages;
  late String sideToken;
  late String cacheToken;
  late _MutableSideResolver sideResolver;
  late AiHistoryLoader loader;
  late AiHistorySeat seat;

  AppSession session() => AppSession(
    sessionId: 'sess-a',
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work/project')],
    cli: CliTool.claude,
    createdAt: 1,
  );

  WorkspaceLaunchContext ctx() => WorkspaceLaunchContext(
    session: session(),
    workspace: Workspace(
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: '/work/project')],
      createdAt: 0,
    ),
  );

  List<AiMessage> parentWithAgentCall() => [
    AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: const [
        AiToolCallPart(
          toolCallId: 'toolu_agent',
          toolName: 'Agent',
          args: {'description': 'explore'},
          status: AiToolCallStatus.incomplete,
        ),
      ],
    ),
  ];

  List<AiMessage> side(int count) => [
    for (var i = 0; i < count; i++)
      AiMessage(
        id: 's-$i',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'progress $i')],
      ),
  ];

  setUp(() {
    setUpTestAppStorage();
    holderMessages = parentWithAgentCall();
    sideMessages = side(1);
    sideToken = 'fp-1';
    cacheToken = 'token-1';
    sideResolver = _MutableSideResolver(
      messages: () => sideMessages,
      token: () => sideToken,
    );
    final fs = LocalFilesystem();
    loader = AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: '/tmp/history-seat-side',
        cwd: '/tmp/history-seat-side',
        appDataRoot: '/tmp/history-seat-side',
        paths: AppPaths('/tmp/history-seat-side'),
      ),
      locator: _ScriptedLocator(),
      registry: fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: _HolderAdapter(() => holderMessages),
        subagentSideResolver: sideResolver,
        subagentToolNames: const {'agent'},
      ),
      resolveCacheToken: (_) async => cacheToken,
    );
    seat = AiHistorySeat(loader: loader);
  });

  tearDown(() async {
    await seat.close();
    tearDownTestAppStorage();
  });

  test('side-only growth on an unchanged parent bumps the attachment epoch',
      () async {
    await seat.load(
      session: session(),
      memberId: '',
      launchContext: ctx(),
    );
    expect(seat.state.status, AiHistoryViewStatus.ready);
    await seat.loadSubagentAttachment('toolu_agent');
    expect(
      seat.subagentAttachments['toolu_agent']!.messages,
      hasLength(1),
    );
    final epochBefore = seat.state.subagentAttachmentEpoch;

    // Running sub-agent appends its own transcript; parent + cache token stay
    // frozen. softReload must pick up the grown attachment and bump the epoch
    // so the preview overlay rebuilds.
    sideMessages = side(2);
    sideToken = 'fp-2';
    await seat.softReload();

    expect(seat.state.subagentAttachmentEpoch, epochBefore + 1);
    expect(
      seat.subagentAttachments['toolu_agent']!.messages,
      hasLength(2),
    );

    // Nothing changed → no epoch churn.
    final epochStable = seat.state.subagentAttachmentEpoch;
    await seat.softReload();
    expect(seat.state.subagentAttachmentEpoch, epochStable);
  });

  test(
    'load refresh after side dirty keeps materialized seat attachments',
    () async {
      await seat.load(
        session: session(),
        memberId: '',
        launchContext: ctx(),
      );
      await seat.loadSubagentAttachment('toolu_agent');
      expect(
        seat.subagentAttachments['toolu_agent']!.messages,
        hasLength(1),
      );

      sideMessages = side(2);
      sideToken = 'fp-2';
      await seat.softReload();
      expect(
        seat.subagentAttachments['toolu_agent']!.messages,
        hasLength(2),
      );

      // Parent token still frozen. A subsequent seat.load refresh must not
      // replace seat-owned lazy previews with the loader's empty map.
      await seat.load(
        session: session(),
        memberId: '',
        launchContext: ctx(),
      );
      expect(
        seat.subagentAttachments['toolu_agent']!.messages,
        hasLength(2),
      );
    },
  );

  test(
    'failed side resolve during dirty softReload keeps prior preview',
    () async {
      await seat.load(
        session: session(),
        memberId: '',
        launchContext: ctx(),
      );
      await seat.loadSubagentAttachment('toolu_agent');
      final prior = seat.subagentAttachments['toolu_agent']!;
      expect(prior.messages, hasLength(1));

      sideToken = 'fp-2';
      sideResolver.failResolve = true;
      await seat.softReload();

      expect(
        seat.subagentAttachments['toolu_agent'],
        same(prior),
      );
      expect(
        seat.subagentAttachments['toolu_agent']!.messages,
        hasLength(1),
      );
    },
  );
}
