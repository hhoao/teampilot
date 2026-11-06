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

  testWidgets('live Cot opens only the last reasoning part', (tester) async {
    await tester.pumpWidget(
      buildLiveChain(const [
        AiReasoningPart(text: 'first thought'),
        AiReasoningPart(text: 'second thought'),
        AiReasoningPart(text: 'third thought'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('first thought'), findsNothing);
    expect(find.textContaining('second thought'), findsNothing);
    expect(find.textContaining('third thought'), findsOneWidget);
    expect(find.text('Reasoning'), findsNWidgets(3));
  });

  testWidgets('live Cot folds all reasoning when a tool call is the tail', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLiveChain(const [
        AiReasoningPart(text: 'first thought'),
        AiToolCallPart(toolCallId: 'c1', toolName: 'Read'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('first thought'), findsNothing);
    expect(find.text('Reasoning'), findsOneWidget);
  });

  testWidgets('live Cot folds the previous reasoning when a new one arrives', (
    tester,
  ) async {
    const first = AiReasoningPart(text: 'first thought');
    const second = AiReasoningPart(text: 'second thought');
    const third = AiReasoningPart(text: 'third thought');

    await tester.pumpWidget(buildLiveChain(const [first, second]));
    await tester.pumpAndSettle();
    expect(find.textContaining('second thought'), findsOneWidget);

    await tester.pumpWidget(buildLiveChain(const [first, second, third]));
    await tester.pumpAndSettle();

    expect(find.textContaining('second thought'), findsNothing);
    expect(find.textContaining('third thought'), findsOneWidget);
  });

  testWidgets('manually opened finished reasoning survives a new live part', (
    tester,
  ) async {
    const first = AiReasoningPart(text: 'first thought');
    const second = AiReasoningPart(text: 'second thought');
    const third = AiReasoningPart(text: 'third thought');

    await tester.pumpWidget(buildLiveChain(const [first, second]));
    await tester.pumpAndSettle();

    // Manually open the already-finished first block.
    await tester.tap(find.text('Reasoning').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('first thought'), findsOneWidget);

    await tester.pumpWidget(buildLiveChain(const [first, second, third]));
    await tester.pumpAndSettle();

    expect(find.textContaining('first thought'), findsOneWidget);
    expect(find.textContaining('third thought'), findsOneWidget);
  });

  testWidgets('all reasoning folds when live auto-expand ends', (tester) async {
    const parts = [
      AiReasoningPart(text: 'first thought'),
      AiReasoningPart(text: 'second thought'),
    ];

    await tester.pumpWidget(buildLiveChain(parts));
    await tester.pumpAndSettle();
    // Only the active (last) reasoning body is open during live streaming.
    expect(find.textContaining('first thought'), findsNothing);
    expect(find.textContaining('second thought'), findsOneWidget);

    await tester.pumpWidget(buildLiveChain(parts, autoExpand: false));
    await tester.pumpAndSettle();

    expect(find.textContaining('Thinking process'), findsOneWidget);
    expect(find.textContaining('first thought'), findsNothing);
    expect(find.textContaining('second thought'), findsNothing);
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
