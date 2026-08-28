import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/cubits/ai_history_seat.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/pages/chat/session_history_thread.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/subagent_side_resolver.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/fake_ai_history_registry.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  late Map<String, List<AiMessage>> messagesBySession;
  late _ScriptedLocator locator;
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

  List<AiMessage> markerMessages(String marker) => [
    AiMessage(
      id: 'm-$marker-0',
      role: AiRole.user,
      parts: [AiTextPart(text: 'marker-$marker')],
    ),
  ];

  setUp(() {
    setUpTestAppStorage();
    messagesBySession = {
      'sess-a': markerMessages('A'),
      'sess-b': markerMessages('B'),
    };
    locator = _ScriptedLocator()..emitBundle = true;
    final fs = LocalFilesystem();
    final loader = AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: '/tmp/ai-history-multi-seat-widget',
        cwd: '/tmp/ai-history-multi-seat-widget',
        appDataRoot: '/tmp/ai-history-multi-seat-widget',
        paths: AppPaths('/tmp/ai-history-multi-seat-widget'),
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
    );
    cubit = AiHistoryCubit(loader: loader);
  });

  tearDown(() async {
    await cubit.close();
    tearDownTestAppStorage();
  });

  testWidgets(
    'softReload seat A updates only that SessionHistoryThread',
    (tester) async {
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

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: ThemeData(extensions: [AiMessageTheme.test()]),
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 400,
                    child: SessionHistoryThread(
                      key: const ValueKey('thread-a'),
                      runtime: seatA.runtime,
                      hasOlder: false,
                      isLoadingOlder: false,
                    ),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 400,
                    child: SessionHistoryThread(
                      key: const ValueKey('thread-b'),
                      runtime: seatB.runtime,
                      hasOlder: false,
                      isLoadingOlder: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('marker-A'), findsOneWidget);
      expect(find.text('marker-B'), findsOneWidget);
      expect(find.text('extra-A-tip'), findsNothing);

      messagesBySession['sess-a'] = [
        ...markerMessages('A'),
        const AiMessage(
          id: 'm-A-tip',
          role: AiRole.assistant,
          parts: [AiTextPart(text: 'extra-A-tip')],
        ),
      ];
      await seatA.softReload();
      await tester.pumpAndSettle();

      expect(find.text('extra-A-tip'), findsOneWidget);
      expect(find.text('marker-A'), findsOneWidget);
      expect(find.text('marker-B'), findsOneWidget);
      expect(find.textContaining('extra-B'), findsNothing);
    },
  );

  test(
    'loadSubagentAttachment only resolves the requested running id',
    () async {
      final resolver = _CountingSideResolver();
      final session = simpleSession();
      final agentMessages = [
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: [
            const AiToolCallPart(
              toolCallId: 'toolu_run',
              toolName: 'Agent',
              args: {'description': 'running'},
              status: AiToolCallStatus.incomplete,
            ),
            const AiToolCallPart(
              toolCallId: 'toolu_done',
              toolName: 'Agent',
              args: {'description': 'done'},
              result: 'finished',
            ),
          ],
        ),
      ];
      messagesBySession['sess-a'] = agentMessages;

      final fs = LocalFilesystem();
      final loader = AiHistoryLoader(
        contextBuilder: const SessionHistoryContextBuilder(),
        resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
          target: RuntimeTarget.local(),
          filesystem: fs,
          home: '/tmp/ai-history-multi-seat-lazy',
          cwd: '/tmp/ai-history-multi-seat-lazy',
          appDataRoot: '/tmp/ai-history-multi-seat-lazy',
          paths: AppPaths('/tmp/ai-history-multi-seat-lazy'),
        ),
        locator: locator,
        registry: fakeAiHistoryRegistry(
          cli: CliTool.claude,
          adapter: _SessionMapAdapter(() => messagesBySession),
          subagentSideResolver: resolver,
          subagentToolNames: const {'agent', 'task'},
        ),
        resolveCacheToken: (_) async => 'token-1',
      );
      final seat = AiHistorySeat(loader: loader);
      await seat.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );
      expect(seat.subagentAttachments, isEmpty);
      expect(resolver.resolveCount, 0);

      final attachment = await seat.loadSubagentAttachment('toolu_run');
      expect(attachment, isNotNull);
      expect(resolver.resolveCount, 1);
      expect(seat.subagentAttachments.keys, ['toolu_run']);
    },
  );
}

AiTranscriptBundle _bundleForSession(String sessionId) => AiTranscriptBundle(
  adapterId: 'claude',
  fragments: const [
    AiTranscriptFragment(name: 'canned.jsonl', bytes: []),
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

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) async {
    if (!emitBundle) return null;
    final sessionId = ctx.sessionId?.trim() ?? '';
    return _bundleForSession(sessionId);
  }
}

class _CountingSideResolver implements SubagentSideResolver {
  int resolveCount = 0;

  @override
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
    DateTime? toolCallAt,
  }) async {
    resolveCount++;
    return SubagentSideResolveResult(
      messages: [
        AiMessage(
          id: 'side-${part.toolCallId}',
          role: AiRole.assistant,
          parts: [AiTextPart(text: part.toolCallId)],
        ),
      ],
      handle: SubagentFileHandle('/side/${part.toolCallId}.jsonl'),
    );
  }

  @override
  Future<String?> fingerprint({
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
  }) async =>
      null;
}
