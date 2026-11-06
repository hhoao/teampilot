import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildLiveChain(List<AiMessagePart> parts, {bool autoExpand = true}) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AiChainOfThoughtView(parts: parts, autoExpand: autoExpand),
        ),
      ),
    );
  }

  testWidgets('Cot trigger does not overflow in a narrow parent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 80,
            child: AiChainOfThoughtView(
              parts: [AiReasoningPart(text: 'secret plan')],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('Cot expand keeps nested reasoning/tools collapsed by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: [
                AiReasoningPart(text: 'secret plan'),
                AiToolCallPart(
                  toolCallId: 'c1',
                  toolName: 'shell_command',
                  result: 'ok',
                ),
                AiTextPart(text: 'all done'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('secret plan'), findsNothing);
    expect(find.text('all done'), findsOneWidget);

    await tester.tap(find.textContaining('Thinking process'));
    await tester.pumpAndSettle();

    // Nested rows visible as triggers, payloads still hidden.
    expect(find.text('Reasoning'), findsOneWidget);
    expect(find.textContaining('shell_command'), findsOneWidget);
    expect(find.textContaining('secret plan'), findsNothing);
    expect(find.textContaining('ok'), findsNothing);

    await tester.tap(find.text('Reasoning'));
    await tester.pumpAndSettle();
    expect(find.textContaining('secret plan'), findsOneWidget);

    await tester.tap(find.textContaining('shell_command'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ok'), findsOneWidget);
  });

  testWidgets('theme cotExpand*OnOpen auto-expands nested kinds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            AiMessageTheme.test(
              cotExpandReasoningOnOpen: true,
              cotExpandToolsOnOpen: true,
            ),
          ],
        ),
        home: const Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: [
                AiReasoningPart(text: 'secret plan'),
                AiToolCallPart(
                  toolCallId: 'c1',
                  toolName: 'shell_command',
                  result: 'ok',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.textContaining('Thinking process'));
    await tester.pumpAndSettle();

    expect(find.textContaining('secret plan'), findsOneWidget);
    expect(find.textContaining('ok'), findsOneWidget);
  });

  testWidgets('theme cotExpandReasoningOnOpen expands reasoning only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [AiMessageTheme.test(cotExpandReasoningOnOpen: true)],
        ),
        home: const Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: [
                AiReasoningPart(text: 'secret plan'),
                AiToolCallPart(
                  toolCallId: 'c1',
                  toolName: 'shell_command',
                  result: 'ok',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.textContaining('Thinking process'));
    await tester.pumpAndSettle();

    expect(find.textContaining('secret plan'), findsOneWidget);
    expect(find.textContaining('ok'), findsNothing);
  });

  testWidgets(
    'multi-tool Cot keeps tool payloads collapsed until each row is tapped',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiMessageView(
              message: AiMessage(
                id: 'a1',
                role: AiRole.assistant,
                parts: [
                  AiToolCallPart(
                    toolCallId: 'c1',
                    toolName: 'Read',
                    result: 'file-a',
                  ),
                  AiToolCallPart(
                    toolCallId: 'c2',
                    toolName: 'Grep',
                    result: 'file-b',
                  ),
                  const AiTextPart(text: 'summary'),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.textContaining('Thinking process'));
      await tester.pumpAndSettle();

      expect(find.textContaining('file-a'), findsNothing);
      expect(find.textContaining('file-b'), findsNothing);
      expect(find.textContaining('Used 2 tools'), findsNothing);

      await tester.tap(find.textContaining('Read'));
      await tester.pumpAndSettle();
      expect(find.textContaining('file-a'), findsOneWidget);
      expect(find.textContaining('file-b'), findsNothing);

      await tester.tap(find.textContaining('Grep'));
      await tester.pumpAndSettle();
      expect(find.textContaining('file-b'), findsOneWidget);
    },
  );

  testWidgets('R/T-only turn is a single Cot with no trailing text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: [
                AiReasoningPart(text: 'only think'),
                AiToolCallPart(toolCallId: 'c1', toolName: 'Shell'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Thinking process'), findsOneWidget);
    expect(find.textContaining('only think'), findsNothing);
  });

  testWidgets(
    'Cot trigger summarizes unique files, searches, commands, diffs',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiToolFileActionsScope(
              actions: AiToolFileActions(
                fileResolver: _SummaryFileResolver(),
                editResolver: _SummaryEditResolver(),
                shellResolver: const _NoopShellResolver(),
              ),
              child: AiMessageView(
                message: AiMessage(
                  id: 'a1',
                  role: AiRole.assistant,
                  parts: [
                    const AiReasoningPart(text: 'secret plan'),
                    AiToolCallPart(
                      toolCallId: 'e1',
                      toolName: 'Edit',
                      category: AiToolCallCategory.edit,
                      args: {'path': 'a.dart'},
                    ),
                    AiToolCallPart(
                      toolCallId: 'e2',
                      toolName: 'Edit',
                      category: AiToolCallCategory.edit,
                      args: {'path': 'b.dart'},
                    ),
                    AiToolCallPart(
                      toolCallId: 'r1',
                      toolName: 'Read',
                      category: AiToolCallCategory.read,
                      args: {'path': 'c.dart'},
                    ),
                    AiToolCallPart(
                      toolCallId: 'g1',
                      toolName: 'Grep',
                      category: AiToolCallCategory.read,
                      args: {'path': 'c.dart'},
                    ),
                    const AiToolCallPart(
                      toolCallId: 'c1',
                      toolName: 'Bash',
                      category: AiToolCallCategory.command,
                    ),
                    const AiTextPart(text: 'all done'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.textContaining(
          'Edited 2 files, explored 1 file, 1 search, ran 1 command',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('+15'), findsOneWidget);
      expect(find.textContaining('-3'), findsOneWidget);
      expect(find.textContaining('secret plan'), findsNothing);
      expect(find.text('all done'), findsOneWidget);

      await tester.tap(find.textContaining('Edited 2 files, explored 1 file'));
      await tester.pumpAndSettle();
      expect(find.text('Reasoning'), findsOneWidget);
      expect(find.textContaining('secret plan'), findsNothing);
    },
  );

  testWidgets('live reasoning follows streamed text to the bottom', (
    tester,
  ) async {
    final lines = [for (var i = 0; i < 80; i++) 'reasoning line $i'].join('\n');

    Widget build(String text) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: AiReasoningPartView(
              part: AiReasoningPart(text: text),
              initiallyExpanded: true,
              autoFollow: true,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(lines));
    await tester.pumpAndSettle();

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.pumpWidget(build('$lines\nnewest reasoning line'));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
    expect(position.pixels, closeTo(position.maxScrollExtent, 1));
  });

  testWidgets('reasoning body folds when streaming stops', (tester) async {
    Widget build({required bool live}) {
      return MaterialApp(
        home: Scaffold(
          body: AiReasoningPartView(
            part: const AiReasoningPart(text: 'live thought'),
            initiallyExpanded: live,
            autoFollow: live,
          ),
        ),
      );
    }

    await tester.pumpWidget(build(live: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('live thought'), findsOneWidget);

    await tester.pumpWidget(build(live: false));
    await tester.pumpAndSettle();

    expect(find.text('Reasoning'), findsOneWidget);
    expect(find.textContaining('live thought'), findsNothing);
  });

  testWidgets('reasoning body expands when it becomes the live target', (
    tester,
  ) async {
    Widget build({required bool live}) {
      return MaterialApp(
        home: Scaffold(
          body: AiReasoningPartView(
            part: const AiReasoningPart(text: 'live thought'),
            initiallyExpanded: live,
            autoFollow: live,
          ),
        ),
      );
    }

    await tester.pumpWidget(build(live: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('live thought'), findsNothing);

    await tester.pumpWidget(build(live: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('live thought'), findsOneWidget);
  });

  testWidgets('Cot trigger keeps steps phrase when stats hook is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiChainOfThoughtView(
            parts: [AiReasoningPart(text: 'thought')],
            toolCallCount: 3,
          ),
        ),
      ),
    );

    expect(find.textContaining('Thinking process · 1 steps'), findsOneWidget);
    expect(find.textContaining('tool calls'), findsNothing);
  });

  testWidgets('Cot trigger uses stats hook when toolCallCount is positive', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageStringsScope(
            strings: const AiMessageStrings(
              formatThinkingProcessStats: _statsLabel,
            ),
            child: AiChainOfThoughtView(
              parts: const [AiReasoningPart(text: 'thought')],
              toolCallCount: 3,
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining('Thinking process · 1 steps · 3 tool calls'),
      findsOneWidget,
    );
  });

  testWidgets('Cot trigger falls back to steps when toolCallCount is zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageStringsScope(
            strings: const AiMessageStrings(
              formatThinkingProcessStats: _statsLabel,
            ),
            child: AiChainOfThoughtView(
              parts: const [AiReasoningPart(text: 'thought')],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Thinking process · 1 steps'), findsOneWidget);
    expect(find.textContaining('tool calls'), findsNothing);
  });

  testWidgets('Cot trigger prefers summary over stats hook', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageStringsScope(
            strings: const AiMessageStrings(
              formatThinkingProcessStats: _statsLabel,
            ),
            child: AiChainOfThoughtView(
              parts: const [
                AiReasoningPart(text: 'thought'),
                AiToolCallPart(
                  toolCallId: 'e1',
                  toolName: 'Edit',
                  category: AiToolCallCategory.edit,
                ),
              ],
              toolCallCount: 3,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Edited 1 file'), findsOneWidget);
    expect(find.textContaining('tool calls'), findsNothing);
  });

  testWidgets('Cot stats refresh without resetting manual open state', (
    tester,
  ) async {
    Widget build(int count) => MaterialApp(
      theme: ThemeData(
        extensions: [AiMessageTheme.test(cotExpandReasoningOnOpen: true)],
      ),
      home: Scaffold(
        body: AiMessageStringsScope(
          strings: const AiMessageStrings(
            formatThinkingProcessStats: _statsLabel,
          ),
          child: AiChainOfThoughtView(
            parts: const [AiReasoningPart(text: 'thought')],
            toolCallCount: count,
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(1));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Thinking process'));
    await tester.pumpAndSettle();
    expect(find.textContaining('thought'), findsOneWidget);

    await tester.pumpWidget(build(3));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 steps · 3 tool calls'), findsOneWidget);
    expect(find.textContaining('thought'), findsOneWidget);
  });
}

class _SummaryFileResolver implements AiToolFileTargetResolver {
  @override
  AiToolFileTarget? resolve(AiToolCallPart part) {
    final path = part.args?['path'] as String?;
    if (path == null) return null;
    return AiToolFileTarget(path: path);
  }
}

class _SummaryEditResolver implements AiEditToolTargetResolver {
  @override
  AiEditToolTarget? resolve(AiToolCallPart part) {
    final path = part.args?['path'] as String?;
    if (path == null) return null;
    return AiEditToolTarget(
      hunk: AiEditHunk(
        path: path,
        lines: const [],
        addedCount: path == 'a.dart' ? 10 : 5,
        removedCount: path == 'a.dart' ? 2 : 1,
      ),
    );
  }
}

class _NoopShellResolver implements AiShellToolTargetResolver {
  const _NoopShellResolver();

  @override
  AiShellToolTarget? resolve(AiToolCallPart part) => null;
}

String _statsLabel(int steps, int toolCalls) =>
    'Thinking process · $steps steps · $toolCalls tool calls';
