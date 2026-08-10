import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/agent_permission_attention_banner.dart';
import 'package:teampilot/pages/chat/ask_user_question_card.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/agent_status/ask_user_question.dart';
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

  final answers = <Map<String, Object?>>[];
  final cancels = <Map<String, Object?>>[];
  AskUserAnswerResult answerResult = const AskUserAnswerOk();
  AskUserAnswerResult cancelResult = const AskUserAnswerOk();

  @override
  Future<AskUserAnswerResult> answerAskUserQuestion({
    required String sessionId,
    required String memberId,
    required int optionIndex,
    List<int>? optionIndices,
    String? askRequestId,
    List<List<String>>? answers,
    String? freeText,
    List<String?>? freeTexts,
  }) async {
    this.answers.add({
      'sessionId': sessionId,
      'memberId': memberId,
      'optionIndex': optionIndex,
      'optionIndices': optionIndices,
      'askRequestId': askRequestId,
      'answers': answers,
      'freeText': freeText,
      'freeTexts': freeTexts,
    });
    return answerResult;
  }

  @override
  Future<AskUserAnswerResult> cancelAskUserQuestion({
    required String sessionId,
    required String memberId,
    String? askRequestId,
  }) async {
    cancels.add({
      'sessionId': sessionId,
      'memberId': memberId,
      'askRequestId': askRequestId,
    });
    return cancelResult;
  }
}

AppSession _simpleSession({
  String id = 'sess-1',
  CliTool cli = CliTool.claude,
}) {
  return AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/tmp')],
    createdAt: 1,
    updatedAt: 1,
    cli: cli,
  );
}

Widget _tpApp({required Widget child}) {
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
      child: child,
    ),
  );
}

Widget _cardHarness({
  required ChatCubit chat,
  required AgentAttentionCubit attention,
  required AppSession session,
  required List<AgentAskUserQuestion> questions,
  String? askRequestId = 'toolu-1',
  bool supportsMultiSelectInChat = true,
  VoidCallback? onAnswerInTerminal,
}) {
  return _tpApp(
    child: MultiBlocProvider(
      providers: [
        BlocProvider<ChatCubit>.value(value: chat),
        BlocProvider<AgentAttentionCubit>.value(value: attention),
      ],
      child: Scaffold(
        body: AskUserQuestionCard(
          session: session,
          seatId: session.sessionId,
          questions: questions,
          askRequestId: askRequestId,
          supportsMultiSelectInChat: supportsMultiSelectInChat,
          onAnswerInTerminal: onAnswerInTerminal ?? () {},
        ),
      ),
    ),
  );
}

Widget _bannerHarness({
  required ChatCubit chat,
  required AgentAttentionCubit attention,
  required AppSession session,
}) {
  return _tpApp(
    child: MultiBlocProvider(
      providers: [
        BlocProvider<ChatCubit>.value(value: chat),
        BlocProvider<AgentAttentionCubit>.value(value: attention),
      ],
      child: Scaffold(
        body: AgentPermissionAttentionBanner(
          session: session,
          selectedMemberId: '',
        ),
      ),
    ),
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  const singleQuestion = AgentAskUserQuestion(
    question: 'Pick color?',
    header: 'Color',
    options: [
      AgentAskUserOption(label: 'Red'),
      AgentAskUserOption(label: 'Blue'),
    ],
  );

  const multiQuestions = [
    AgentAskUserQuestion(
      question: 'Pick color?',
      header: 'Color',
      options: [
        AgentAskUserOption(label: 'Red'),
        AgentAskUserOption(label: 'Blue'),
      ],
    ),
    AgentAskUserQuestion(
      question: 'Pick size?',
      header: 'Size',
      options: [
        AgentAskUserOption(label: 'S'),
        AgentAskUserOption(label: 'L'),
      ],
    ),
  ];

  group('AskUserQuestionCard', () {
    testWidgets('select option + submit sends answers', (tester) async {
      final session = _simpleSession();
      final chat = _RecordingChatCubit();
      addTearDown(chat.close);
      final attention = AgentAttentionCubit(pruneInterval: null);
      addTearDown(attention.close);

      await tester.pumpWidget(
        _cardHarness(
          chat: chat,
          attention: attention,
          session: session,
          questions: const [singleQuestion],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(AppKeys.askUserQuestionCard), findsOneWidget);
      expect(find.text('Pick color?'), findsOneWidget);
      expect(find.text('Enter your answer…'), findsOneWidget);

      final continueBtn = find.byKey(AppKeys.askUserQuestionContinueButton);
      expect(continueBtn, findsOneWidget);
      expect(tester.widget<TpButton>(continueBtn).onPressed, isNull);

      await tester.tap(
        find.byKey(
          AppKeys.askUserQuestionOptionAt(questionIndex: 0, optionIndex: 1),
        ),
      );
      await tester.pumpAndSettle();

      final submit = find.byKey(AppKeys.askUserQuestionSubmitButton);
      expect(submit, findsOneWidget);
      expect(tester.widget<TpButton>(submit).onPressed, isNotNull);

      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(chat.answers, hasLength(1));
      expect(chat.answers.single['answers'], [
        ['Blue'],
      ]);
      expect(chat.answers.single['optionIndex'], 1);
      expect(chat.answers.single['askRequestId'], 'toolu-1');
    });

    testWidgets('custom answer submits free text', (tester) async {
      final session = _simpleSession();
      final chat = _RecordingChatCubit();
      addTearDown(chat.close);
      final attention = AgentAttentionCubit(pruneInterval: null);
      addTearDown(attention.close);

      await tester.pumpWidget(
        _cardHarness(
          chat: chat,
          attention: attention,
          session: session,
          questions: const [singleQuestion],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(
          AppKeys.askUserQuestionOptionAt(questionIndex: 0, optionIndex: 2),
        ),
        'Custom purple',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(AppKeys.askUserQuestionSubmitButton));
      await tester.pumpAndSettle();

      expect(chat.answers, hasLength(1));
      expect(chat.answers.single['answers'], [
        ['Custom purple'],
      ]);
      expect(chat.answers.single['freeText'], 'Custom purple');
    });

    testWidgets('multi-question pager + submit all answers', (tester) async {
      final session = _simpleSession();
      final chat = _RecordingChatCubit();
      addTearDown(chat.close);
      final attention = AgentAttentionCubit(pruneInterval: null);
      addTearDown(attention.close);

      await tester.pumpWidget(
        _cardHarness(
          chat: chat,
          attention: attention,
          session: session,
          questions: multiQuestions,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('Pick color?'), findsOneWidget);
      expect(find.text('Pick size?'), findsNothing);

      await tester.tap(
        find.byKey(
          AppKeys.askUserQuestionOptionAt(questionIndex: 0, optionIndex: 0),
        ),
      );
      await tester.pumpAndSettle();

      // Single-select auto-advances to the next question.
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('Pick size?'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      // Current page unanswered — Continue still enabled so users can skip.
      expect(
        tester
            .widget<TpButton>(
              find.byKey(AppKeys.askUserQuestionContinueButton),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(
        find.byKey(
          AppKeys.askUserQuestionOptionAt(questionIndex: 1, optionIndex: 1),
        ),
      );
      await tester.pumpAndSettle();

      final submit = find.byKey(AppKeys.askUserQuestionSubmitButton);
      expect(submit, findsOneWidget);
      expect(tester.widget<TpButton>(submit).onPressed, isNotNull);
      expect(
        tester.widget<TpButton>(submit).variant,
        TpButtonVariant.primary,
      );

      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(chat.answers.single['answers'], [
        ['Red'],
        ['L'],
      ]);
      expect(chat.answers.single['optionIndices'], [0, 1]);
    });

    testWidgets('answered page shows Continue back to incomplete', (
      tester,
    ) async {
      final session = _simpleSession();
      final chat = _RecordingChatCubit();
      addTearDown(chat.close);
      final attention = AgentAttentionCubit(pruneInterval: null);
      addTearDown(attention.close);

      await tester.pumpWidget(
        _cardHarness(
          chat: chat,
          attention: attention,
          session: session,
          questions: multiQuestions,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          AppKeys.askUserQuestionOptionAt(questionIndex: 0, optionIndex: 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);

      // Jump back to the already-answered first question.
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      final continueBtn = find.byKey(AppKeys.askUserQuestionContinueButton);
      expect(tester.widget<TpButton>(continueBtn).onPressed, isNotNull);

      await tester.tap(continueBtn);
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('Pick size?'), findsOneWidget);
    });

    testWidgets('Ignore cancels ask', (tester) async {
      final session = _simpleSession();
      final chat = _RecordingChatCubit();
      addTearDown(chat.close);
      final attention = AgentAttentionCubit(pruneInterval: null);
      addTearDown(attention.close);

      await tester.pumpWidget(
        _cardHarness(
          chat: chat,
          attention: attention,
          session: session,
          questions: const [singleQuestion],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ignore'));
      await tester.pumpAndSettle();

      expect(chat.cancels, hasLength(1));
      expect(chat.cancels.single['askRequestId'], 'toolu-1');
    });

    testWidgets('failed answer shows inline error', (tester) async {
      final session = _simpleSession();
      final chat = _RecordingChatCubit()
        ..answerResult = const AskUserAnswerFailed('terminal_disconnected');
      addTearDown(chat.close);
      final attention = AgentAttentionCubit(pruneInterval: null);
      addTearDown(attention.close);

      await tester.pumpWidget(
        _cardHarness(
          chat: chat,
          attention: attention,
          session: session,
          questions: const [singleQuestion],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          AppKeys.askUserQuestionOptionAt(questionIndex: 0, optionIndex: 0),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AppKeys.askUserQuestionSubmitButton));
      await tester.pumpAndSettle();

      expect(find.byKey(AppKeys.askUserQuestionInlineError), findsOneWidget);
    });
  });

  group('AgentPermissionAttentionBanner ask card', () {
    testWidgets('shows ask card instead of terminal banner', (tester) async {
      final session = _simpleSession();
      final chat = _RecordingChatCubit();
      addTearDown(chat.close);
      chat.tabStore.setActiveWorkspaceId(session.workspaceId);
      chat.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(
            id: session.sessionId,
            title: 'Chat',
            subtitle: 'simple',
          ),
          cliTeamName: '',
          workbenchView: SessionWorkbenchView.chat,
        ),
      );

      final attention = AgentAttentionCubit(pruneInterval: null);
      addTearDown(attention.close);
      attention.applyEvent(
        sessionId: session.sessionId,
        memberId: session.sessionId,
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PreToolUse',
          toolName: 'AskUserQuestion',
          toolUseId: 'toolu-1',
          askRequestId: 'toolu-1',
          askUserQuestions: [singleQuestion],
        ),
        skipPermissions: false,
      );

      await tester.pumpWidget(
        _bannerHarness(chat: chat, attention: attention, session: session),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(AppKeys.askUserQuestionCard), findsOneWidget);
      expect(find.byKey(AppKeys.agentPermissionAttentionBanner), findsNothing);
      expect(
        AgentPermissionAttentionBanner.isSelectedSeatAskCard(
          attention: attention,
          session: session,
          selectedMemberId: '',
          seatCli: CliTool.claude,
        ),
        isTrue,
      );
    });

    testWidgets('Cursor seat keeps terminal confirmation banner', (
      tester,
    ) async {
      final session = _simpleSession(cli: CliTool.cursor);
      final chat = _RecordingChatCubit();
      addTearDown(chat.close);
      chat.tabStore.setActiveWorkspaceId(session.workspaceId);
      chat.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(
            id: session.sessionId,
            title: 'Chat',
            subtitle: 'simple',
          ),
          cliTeamName: '',
          workbenchView: SessionWorkbenchView.chat,
        ),
      );

      final attention = AgentAttentionCubit(pruneInterval: null);
      addTearDown(attention.close);
      attention.applyEvent(
        sessionId: session.sessionId,
        memberId: session.sessionId,
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PreToolUse',
          toolName: 'AskUserQuestion',
          toolUseId: 'toolu-1',
          askRequestId: 'toolu-1',
          askUserQuestions: [singleQuestion],
        ),
        skipPermissions: false,
      );

      await tester.pumpWidget(
        _bannerHarness(chat: chat, attention: attention, session: session),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(AppKeys.askUserQuestionCard), findsNothing);
      expect(find.byKey(AppKeys.agentPermissionAttentionBanner), findsOneWidget);
      expect(
        AgentPermissionAttentionBanner.isSelectedSeatAskCard(
          attention: attention,
          session: session,
          selectedMemberId: '',
          seatCli: CliTool.cursor,
        ),
        isFalse,
      );
    });
  });
}
