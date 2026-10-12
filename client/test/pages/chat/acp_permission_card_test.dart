import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/chat/acp_permission_card.dart';
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

  ({AgentPermissionReplyKind kind, AgentPermissionAlwaysOption? always})?
  lastAnswer;
  bool cancelled = false;

  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
    List<acpd.McpServer> mcpServers = const [],
  }) async {}

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
  }) async {
    lastAnswer = (kind: reply, always: always);
    return reply;
  }

  @override
  Future<void> answerAsk(AcpAskHoldReply reply) async {}

  @override
  Future<void> answerPlan(AcpPlanHoldReply reply) async {}

  @override
  void cancel() => cancelled = true;

  @override
  Future<void> close() async {}
}

const _request = AgentPermissionRequest(
  id: 'perm-1',
  description: 'Run `npm install`',
  always: [AgentPermissionAlwaysOption(label: 'Bash', payload: 'opt-9')],
);

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
        body: AcpPermissionCard(runtime: cubit, pendingPermission: _request),
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

  Future<void> holdPermission(WidgetTester tester) async {
    await tester.runAsync(() async {
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      runtime.permissionsController.add(_request);
      await Future<void>.delayed(Duration.zero);
    });
    expect(cubit.state.pendingPermission, _request);
  }

  testWidgets('card renders description and always options', (tester) async {
    await holdPermission(tester);

    await tester.pumpWidget(_harness(cubit));
    await tester.pumpAndSettle();

    expect(find.byKey(AiPermissionCard.cardKey), findsOneWidget);
    expect(find.textContaining('npm install'), findsOneWidget);
    expect(find.text('Always allow Bash'), findsOneWidget);
  });

  testWidgets('allow once reply delegates to answerPermission', (tester) async {
    await holdPermission(tester);

    await tester.pumpWidget(_harness(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPermissionCard.allowOnceButtonKey));
    await tester.pumpAndSettle();

    expect(runtime.lastAnswer?.kind, AgentPermissionReplyKind.allowOnce);
    expect(runtime.lastAnswer?.always, isNull);
    // The hold cleared — the host unmounts the card.
    expect(cubit.state.pendingPermission, isNull);
  });

  testWidgets('always reply forwards the selected option payload', (
    tester,
  ) async {
    await holdPermission(tester);

    await tester.pumpWidget(_harness(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPermissionCard.alwaysButtonKey));
    await tester.pumpAndSettle();

    expect(runtime.lastAnswer?.kind, AgentPermissionReplyKind.always);
    expect(runtime.lastAnswer?.always?.payload, 'opt-9');
  });

  testWidgets('reject reply delegates with the reject kind', (tester) async {
    await holdPermission(tester);

    await tester.pumpWidget(_harness(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPermissionCard.rejectButtonKey));
    await tester.pumpAndSettle();

    expect(runtime.lastAnswer?.kind, AgentPermissionReplyKind.reject);
  });

  testWidgets('header cancel action cancels the turn', (tester) async {
    await holdPermission(tester);

    await tester.pumpWidget(_harness(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.terminal_rounded));
    await tester.pumpAndSettle();

    expect(runtime.cancelled, isTrue);
  });
}
