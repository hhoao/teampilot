import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/chat/acp_ask_card.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

/// All-stub [AcpSessionRuntimeApi] (same shape as the cubit test fake).
///
/// The cubit's start()/close() plumbing awaits stream futures that only
/// complete on the real event loop, so cubit lifecycle calls run inside
/// [WidgetTester.runAsync] (this SDK's testWidgets fake-async zone never
/// advances plain `Future.delayed(Duration.zero)` chains).
class _FakeAcpRuntime implements AcpSessionRuntimeApi {
  final permissionsController =
      StreamController<AgentPermissionRequest>.broadcast();

  AcpAskHoldReply? lastAsk;
  bool cancelled = false;

  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
    List<acpd.McpServer> mcpServers = const [],
    LaunchSecurityPolicy permissionPolicy = LaunchSecurityPolicy.fullAccess,
  }) async {}

  @override
  void setPermissionPolicy(LaunchSecurityPolicy policy) {}

  @override
  bool get isStarted => true;

  @override
  String get sessionId => 'acp-session-1';

  @override
  Future<void> prompt(String text) async {}

  @override
  Stream<AcpSessionUpdate> get updates => const Stream.empty();

  @override
  Stream<AgentPermissionRequest> get permissionRequests =>
      permissionsController.stream;

  @override
  Stream<AcpPendingClientRequest> get clientRequests => const Stream.empty();

  @override
  AcpAuthNotice? get lastAuthNotice => null;

  @override
  Future<int>? get agentProcessExitCode => null;

  @override
  Future<AgentPermissionReplyKind?> answerPermission(
    AgentPermissionReplyKind reply, {
    AgentPermissionAlwaysOption? always,
  }) async => reply;

  @override
  Future<void> answerAsk(AcpAskHoldReply reply) async {
    lastAsk = reply;
  }

  @override
  Future<void> answerPlan(AcpPlanHoldReply reply) async {}

  @override
  void cancel() => cancelled = true;

  @override
  Future<void> close() async {}
}

const _questions = [
  AiAskUserQuestion(
    question: 'Pick a color?',
    options: [
      AiAskUserOption(label: 'Red'),
      AiAskUserOption(label: 'Blue'),
    ],
  ),
];

Widget _harness(AcpChatRuntimeCubit cubit) {
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
      child: Scaffold(
        body: AcpAskCard(runtime: cubit, questions: _questions),
      ),
    ),
  );
}

void main() {
  late _FakeAcpRuntime runtime;
  late AcpChatRuntimeCubit cubit;

  setUp(() {
    runtime = _FakeAcpRuntime();
    cubit = AcpChatRuntimeCubit(
      runtime: runtime,
      sessionId: 's1',
      tool: CliTool.gemini,
    );
  });

  tearDown(() async {
    await cubit.close();
    await runtime.permissionsController.close();
  });

  Future<void> startRuntime(WidgetTester tester) async {
    await tester.runAsync(() async {
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
    });
  }

  testWidgets('selecting an option then submit answers the ask hold', (
    tester,
  ) async {
    await startRuntime(tester);

    await tester.pumpWidget(_harness(cubit));
    await tester.pumpAndSettle();

    expect(find.byKey(AiAskUserQuestionCard.cardKey), findsOneWidget);

    await tester.tap(
      find.byKey(
        AiAskUserQuestionCard.optionKey(questionIndex: 0, optionIndex: 1),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiAskUserQuestionCard.submitButtonKey));
    await tester.pumpAndSettle();

    expect(runtime.lastAsk?.skipped, isFalse);
    expect(runtime.lastAsk?.cancelled, isFalse);
    expect(runtime.lastAsk?.submission?.optionIndices, [1]);
    expect(runtime.lastAsk?.submission?.answers, [
      ['Blue'],
    ]);
  });

  testWidgets('ignore control skips the ask hold', (tester) async {
    await startRuntime(tester);

    await tester.pumpWidget(_harness(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ignore'));
    await tester.pumpAndSettle();

    expect(runtime.lastAsk?.skipped, isTrue);
    expect(runtime.lastAsk?.submission, isNull);
  });
}
