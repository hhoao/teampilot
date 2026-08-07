import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/workflow_card.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

AiSubagentAttachment _workflowAttachment() {
  return AiSubagentAttachment(
    toolCallId: 'call_00_wf',
    messages: const [],
    source: AiSubagentAttachmentSource.sideTranscript,
    title: 'migrate',
    handle: const SubagentFileHandle('/runs/wf_run1'),
    workflow: const SubagentWorkflowInfo(
      runId: 'wf_run1',
      workflowName: 'migrate',
      status: 'DONE',
      phases: ['Implement', 'Review'],
      agentCount: 2,
      summary: 'all four sites migrated',
      duration: Duration(seconds: 160),
      agents: [
        SubagentWorkflowAgent(
          agentId: 'agent-a',
          role: 'implementer',
          status: 'DONE',
          messages: [],
          handle: SubagentFileHandle('/runs/wf_run1/agent-agent-a.jsonl'),
        ),
        SubagentWorkflowAgent(
          agentId: 'agent-b',
          role: 'reviewer',
          status: 'approved',
          messages: [],
          handle: SubagentFileHandle('/runs/wf_run1/agent-agent-b.jsonl'),
        ),
      ],
    ),
  );
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required AiToolSubagentActions actions,
  required WorkflowCard card,
}) async {
  final theme = ThemeData(useMaterial3: true);
  await tester.pumpWidget(
    MaterialApp(
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
        child: AiToolSubagentActionsScope(
          actions: actions,
          child: Scaffold(body: card),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const part = AiToolCallPart(
    toolCallId: 'call_00_wf',
    toolName: 'Workflow',
    args: {'script': 'export const meta = {};'},
  );

  testWidgets('shows run metadata and agent rows', (tester) async {
    await _pumpCard(
      tester,
      actions: const AiToolSubagentActions(),
      card: WorkflowCard(part: part, attachment: _workflowAttachment()),
    );

    expect(find.byKey(AppKeys.workflowCard), findsOneWidget);
    expect(find.text('migrate'), findsOneWidget);
    expect(find.text('DONE'), findsWidgets);
    expect(find.text('2 agents'), findsOneWidget);
    expect(find.text('all four sites migrated'), findsOneWidget);
    expect(find.text('implementer'), findsOneWidget);
    expect(find.text('reviewer'), findsOneWidget);
  });

  testWidgets('tapping an agent row opens the per-agent preview id',
      (tester) async {
    final opened = <String>[];
    await _pumpCard(
      tester,
      actions: AiToolSubagentActions(
        onOpenSubagent: (id) async => opened.add(id),
      ),
      card: WorkflowCard(part: part, attachment: _workflowAttachment()),
    );

    await tester.tap(
      find.byKey(AppKeys.workflowAgentRow('wf_run1', 'agent-b')),
    );
    await tester.pumpAndSettle();

    expect(opened, ['wf_run1/agent-b']);
  });

  testWidgets('missing run shows the not-found label without rows',
      (tester) async {
    await _pumpCard(
      tester,
      actions: const AiToolSubagentActions(),
      card: WorkflowCard(part: part, attachment: null),
    );

    expect(find.byKey(AppKeys.workflowCard), findsOneWidget);
    expect(find.text('Workflow run not found for this tool call.'), findsOneWidget);
    expect(find.byKey(AppKeys.workflowAgentRow('wf_run1', 'agent-a')),
        findsNothing);
  });
}
