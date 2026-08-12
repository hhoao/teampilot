import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/opencode_permission_card.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/terminal/ask_user_question_answer_service.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );

  final replies = <Map<String, Object?>>[];
  AskUserAnswerResult replyResult = const AskUserAnswerOk();

  @override
  Future<AskUserAnswerResult> answerPermissionRequest({
    required String sessionId,
    required String memberId,
    String? permissionRequestId,
    required String reply,
  }) async {
    replies.add({
      'sessionId': sessionId,
      'memberId': memberId,
      'permissionRequestId': permissionRequestId,
      'reply': reply,
    });
    return replyResult;
  }
}

AppSession _simpleSession({String id = 'sess-1'}) {
  return AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/tmp')],
    createdAt: 1,
    updatedAt: 1,
  );
}

Widget _harness({
  required ChatCubit chat,
  required AgentAttentionCubit attention,
  required AgentPermissionRequest request,
  required String sessionId,
}) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ChatCubit>.value(value: chat),
          BlocProvider<AgentAttentionCubit>.value(value: attention),
        ],
        child: Scaffold(
          body: OpenCodePermissionCard(
            session: _simpleSession(id: sessionId),
            seatId: sessionId,
            request: request,
            askRequestId: request.id,
            onAnswerInTerminal: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('renders permission description with allow / reject buttons', (
    tester,
  ) async {
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    final attention = AgentAttentionCubit(pruneInterval: null);
    addTearDown(attention.close);

    const request = AgentPermissionRequest(
      id: 'perm-1',
      description: 'Run `npm install`',
      always: ['npm install'],
    );
    await tester.pumpWidget(
      _harness(
        chat: chat,
        attention: attention,
        request: request,
        sessionId: 'sess-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.opencodePermissionCard), findsOneWidget);
    expect(find.textContaining('npm install'), findsWidgets);
    expect(find.text('Allow once'), findsOneWidget);
    expect(find.text('Always allow'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('Allow once replies "once" with the permission request id', (
    tester,
  ) async {
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    final attention = AgentAttentionCubit(pruneInterval: null);
    addTearDown(attention.close);

    const request = AgentPermissionRequest(
      id: 'perm-1',
      description: 'Run `npm install`',
    );
    await tester.pumpWidget(
      _harness(
        chat: chat,
        attention: attention,
        request: request,
        sessionId: 'sess-1',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.opencodePermissionAllowOnceButton));
    await tester.pumpAndSettle();

    expect(chat.replies, hasLength(1));
    expect(chat.replies.single, {
      'sessionId': 'sess-1',
      'memberId': 'sess-1',
      'permissionRequestId': 'perm-1',
      'reply': 'once',
    });
  });

  testWidgets('Always allow replies "always"', (tester) async {
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    final attention = AgentAttentionCubit(pruneInterval: null);
    addTearDown(attention.close);

    const request = AgentPermissionRequest(
      id: 'perm-1',
      description: 'Run `npm install`',
      always: ['npm install'],
    );
    await tester.pumpWidget(
      _harness(
        chat: chat,
        attention: attention,
        request: request,
        sessionId: 'sess-1',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.opencodePermissionAlwaysButton));
    await tester.pumpAndSettle();

    expect(chat.replies.single['reply'], 'always');
  });

  testWidgets('Always allow hidden when the tool has no always options', (
    tester,
  ) async {
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    final attention = AgentAttentionCubit(pruneInterval: null);
    addTearDown(attention.close);

    const request = AgentPermissionRequest(
      id: 'perm-1',
      description: 'Run `npm install`',
    );
    await tester.pumpWidget(
      _harness(
        chat: chat,
        attention: attention,
        request: request,
        sessionId: 'sess-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.opencodePermissionAlwaysButton), findsNothing);
    expect(find.byKey(AppKeys.opencodePermissionAllowOnceButton), findsOneWidget);
    expect(find.byKey(AppKeys.opencodePermissionRejectButton), findsOneWidget);
  });

  testWidgets('Reject replies "reject"', (tester) async {
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    final attention = AgentAttentionCubit(pruneInterval: null);
    addTearDown(attention.close);

    const request = AgentPermissionRequest(
      id: 'perm-1',
      description: 'Run `npm install`',
      always: ['npm install'],
    );
    await tester.pumpWidget(
      _harness(
        chat: chat,
        attention: attention,
        request: request,
        sessionId: 'sess-1',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.opencodePermissionRejectButton));
    await tester.pumpAndSettle();

    expect(chat.replies.single['reply'], 'reject');
  });

  testWidgets('failed reply shows inline error', (tester) async {
    final chat = _RecordingChatCubit()..replyResult = const AskUserAnswerFailed(
      'unsupported',
    );
    addTearDown(chat.close);
    final attention = AgentAttentionCubit(pruneInterval: null);
    addTearDown(attention.close);

    const request = AgentPermissionRequest(
      id: 'perm-1',
      description: 'Run `npm install`',
      always: ['npm install'],
    );
    await tester.pumpWidget(
      _harness(
        chat: chat,
        attention: attention,
        request: request,
        sessionId: 'sess-1',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.opencodePermissionAllowOnceButton));
    await tester.pumpAndSettle();

    expect(
      find.byKey(AppKeys.opencodePermissionInlineError),
      findsOneWidget,
    );
  });
}
