import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AiWorkflowTarget _workflowTarget() {
  return const AiWorkflowTarget(
    workflow: SubagentWorkflowInfo(
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
  required AiWorkflowCard card,
}) async {
  final theme = ThemeData(
    useMaterial3: true,
    extensions: [AiMessageTheme.test()],
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: AiToolSubagentActionsScope(
        actions: actions,
        child: Scaffold(body: card),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows run metadata and agent rows', (tester) async {
    await _pumpCard(
      tester,
      actions: const AiToolSubagentActions(),
      card: AiWorkflowCard(target: _workflowTarget()),
    );

    expect(find.byKey(AiWorkflowCard.cardKey), findsOneWidget);
    expect(find.text('migrate'), findsOneWidget);
    expect(find.text('DONE'), findsWidgets);
    expect(find.text('2 agents'), findsOneWidget);
    expect(find.text('all four sites migrated'), findsOneWidget);
    expect(find.text('implementer'), findsOneWidget);
    expect(find.text('reviewer'), findsOneWidget);
  });

  testWidgets('tapping an agent row opens the per-agent preview id', (
    tester,
  ) async {
    final opened = <String>[];
    await _pumpCard(
      tester,
      actions: AiToolSubagentActions(
        onOpenSubagent: (id) async => opened.add(id),
      ),
      card: AiWorkflowCard(target: _workflowTarget()),
    );

    await tester.tap(
      find.byKey(AiWorkflowCard.agentRowKey('wf_run1', 'agent-b')),
    );
    await tester.pumpAndSettle();

    expect(opened, ['wf_run1/agent-b']);
  });

  testWidgets('missing run shows the not-found label without rows', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      actions: const AiToolSubagentActions(),
      card: const AiWorkflowCard(target: AiWorkflowTarget()),
    );

    expect(find.byKey(AiWorkflowCard.cardKey), findsOneWidget);
    expect(
      find.text('Workflow run not found for this tool call.'),
      findsOneWidget,
    );
    expect(
      find.byKey(AiWorkflowCard.agentRowKey('wf_run1', 'agent-a')),
      findsNothing,
    );
  });
}
