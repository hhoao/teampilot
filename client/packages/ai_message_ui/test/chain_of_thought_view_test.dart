import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpActivityUi(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  await tester.pump();
}

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
    await pumpActivityUi(tester);

    // Nested rows visible as triggers, payloads still hidden.
    expect(find.text('Thought'), findsOneWidget);
    expect(find.textContaining('shell_command'), findsOneWidget);
    expect(find.textContaining('secret plan'), findsNothing);
    expect(find.textContaining('ok'), findsNothing);

    await tester.tap(find.text('Thought'));
    await pumpActivityUi(tester);
    expect(find.textContaining('secret plan'), findsOneWidget);

    await tester.tap(find.textContaining('shell_command'));
    await pumpActivityUi(tester);
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
    await pumpActivityUi(tester);

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
    await pumpActivityUi(tester);

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
      await pumpActivityUi(tester);

      expect(find.textContaining('file-a'), findsNothing);
      expect(find.textContaining('file-b'), findsNothing);
      expect(find.textContaining('Used 2 tools'), findsNothing);

      await tester.tap(find.textContaining('Read'));
      await pumpActivityUi(tester);
      expect(find.textContaining('file-a'), findsOneWidget);
      expect(find.textContaining('file-b'), findsNothing);

      await tester.tap(find.textContaining('Grep'));
      await pumpActivityUi(tester);
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
      await pumpActivityUi(tester);
      expect(find.text('Thought'), findsOneWidget);
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
    await pumpActivityUi(tester);

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.pumpWidget(build('$lines\nnewest reasoning line'));
    await pumpActivityUi(tester);

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
    await pumpActivityUi(tester);
    expect(find.textContaining('live thought'), findsOneWidget);

    await tester.pumpWidget(build(live: false));
    await pumpActivityUi(tester);

    expect(find.text('Thought'), findsOneWidget);
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
    await pumpActivityUi(tester);
    expect(find.textContaining('live thought'), findsNothing);

    await tester.pumpWidget(build(live: true));
    await pumpActivityUi(tester);
    expect(find.textContaining('live thought'), findsOneWidget);
  });

  testWidgets('Cot trigger keeps steps phrase when stats hook is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiChainOfThoughtView(
            parts: [
              AiReasoningPart(text: 'thought'),
              AiToolCallPart(toolCallId: 'c1', toolName: 'Tool'),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('Thinking process · 2 steps'), findsOneWidget);
    expect(find.textContaining('tool calls'), findsNothing);
  });

  testWidgets('Cot trigger uses stats hook when the chain has tool calls', (
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
              parts: const [
                AiReasoningPart(text: 'thought'),
                AiToolCallPart(toolCallId: 'c1', toolName: 'Tool'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining('Thinking process · 2 steps · 1 tool calls'),
      findsOneWidget,
    );
  });

  testWidgets('Cot trigger falls back to steps when the chain has no tools', (
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
            parts: [
              const AiReasoningPart(text: 'thought'),
              for (var i = 0; i < count; i++)
                AiToolCallPart(toolCallId: 'c$i', toolName: 'Tool'),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(1));
    await pumpActivityUi(tester);
    await tester.tap(find.textContaining('Thinking process'));
    await pumpActivityUi(tester);
    expect(find.textContaining('2 steps · 1 tool calls'), findsOneWidget);
    expect(find.textContaining('thought'), findsOneWidget);

    await tester.pumpWidget(build(3));
    await pumpActivityUi(tester);
    expect(find.textContaining('4 steps · 3 tool calls'), findsOneWidget);
    expect(find.textContaining('thought'), findsOneWidget);
  });

  testWidgets('live Cot opens only the last reasoning part', (tester) async {
    await tester.pumpWidget(
      buildLiveChain(const [
        AiReasoningPart(text: 'first thought'),
        AiReasoningPart(text: 'second thought'),
        AiReasoningPart(text: 'third thought'),
      ]),
    );
    await pumpActivityUi(tester);

    expect(find.textContaining('first thought'), findsNothing);
    expect(find.textContaining('second thought'), findsNothing);
    expect(find.textContaining('third thought'), findsOneWidget);
    expect(find.text('Thought'), findsNWidgets(2));
    expect(find.text('Thinking'), findsOneWidget);
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
    await pumpActivityUi(tester);

    expect(find.textContaining('first thought'), findsNothing);
    expect(find.text('Thought'), findsOneWidget);
  });

  testWidgets('live Cot folds the previous reasoning when a new one arrives', (
    tester,
  ) async {
    const first = AiReasoningPart(text: 'first thought');
    const second = AiReasoningPart(text: 'second thought');
    const third = AiReasoningPart(text: 'third thought');

    await tester.pumpWidget(buildLiveChain(const [first, second]));
    await pumpActivityUi(tester);
    expect(find.textContaining('second thought'), findsOneWidget);

    await tester.pumpWidget(buildLiveChain(const [first, second, third]));
    await pumpActivityUi(tester);

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
    await pumpActivityUi(tester);

    // Manually open the already-finished first block.
    await tester.tap(find.text('Thought').first);
    await pumpActivityUi(tester);
    expect(find.textContaining('first thought'), findsOneWidget);

    await tester.pumpWidget(buildLiveChain(const [first, second, third]));
    await pumpActivityUi(tester);

    expect(find.textContaining('first thought'), findsOneWidget);
    expect(find.textContaining('third thought'), findsOneWidget);
  });

  testWidgets('all reasoning folds when live auto-expand ends', (tester) async {
    const parts = [
      AiReasoningPart(text: 'first thought'),
      AiReasoningPart(text: 'second thought'),
    ];

    await tester.pumpWidget(buildLiveChain(parts));
    await pumpActivityUi(tester);
    // Only the active (last) reasoning body is open during live streaming.
    expect(find.textContaining('first thought'), findsNothing);
    expect(find.textContaining('second thought'), findsOneWidget);

    await tester.pumpWidget(buildLiveChain(parts, autoExpand: false));
    await pumpActivityUi(tester);

    expect(find.textContaining('Thinking process'), findsOneWidget);
    expect(find.textContaining('first thought'), findsNothing);
    expect(find.textContaining('second thought'), findsNothing);
  });
  testWidgets('Cot uses a bordered leading chevron and colors expansion', (
    tester,
  ) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: const Scaffold(
          body: AiChainOfThoughtView(parts: [AiReasoningPart(text: 'thought')]),
        ),
      ),
    );

    final closedChevron = tester.widget<Icon>(find.byIcon(Icons.chevron_right));
    expect(closedChevron.color, scheme.onSurfaceVariant);
    final button = find.byKey(const ValueKey('ai-activity-chevron'));
    expect(button, findsOneWidget);
    expect(tester.getSize(button), const Size(24, 24));
    expect(
      tester.getTopLeft(button).dx,
      tester.getTopLeft(find.byType(AiChainOfThoughtView)).dx,
    );
    final decoration =
        tester.widget<Container>(button).decoration! as BoxDecoration;
    expect(decoration.color, scheme.surfaceContainerLow);
    expect(decoration.border, Border.all(color: scheme.outlineVariant));
    expect(decoration.borderRadius, BorderRadius.circular(7));
    expect(
      tester.getTopLeft(find.byIcon(Icons.chevron_right)).dx,
      lessThan(tester.getTopLeft(find.textContaining('Thinking process')).dx),
    );

    await tester.tap(find.textContaining('Thinking process'));
    await pumpActivityUi(tester);

    final openChevron = tester.widget<Icon>(find.byIcon(Icons.expand_more));
    expect(openChevron.color, scheme.primary);
    expect(
      tester
              .getTopLeft(
                find.byKey(const ValueKey('ai-reasoning-status-icon')),
              )
              .dx -
          tester.getTopLeft(button).dx,
      closeTo(32, 0.1),
      reason: 'nested activity must be indented from the chain header',
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('ai-reasoning-status-icon')))
          .dx,
      lessThan(tester.getTopLeft(find.text('Thought')).dx),
    );

    await tester.tap(find.text('Thought'));
    await pumpActivityUi(tester);
    expect(
      tester
          .widgetList<Icon>(find.byIcon(Icons.expand_more))
          .every((icon) => icon.color == scheme.primary),
      isTrue,
    );
  });

  testWidgets('reasoning and tool status icons share a center line', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiChainOfThoughtView(
            parts: [
              AiReasoningPart(text: 'finished thought'),
              AiToolCallPart(
                toolCallId: 'read',
                toolName: 'Read',
                status: AiToolCallStatus.complete,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('Thinking process'));
    await pumpActivityUi(tester);

    final reasoningIcon = find.descendant(
      of: find.byType(AiReasoningPartView),
      matching: find.byIcon(Icons.check_circle_outline),
    );
    final toolIcon = find.descendant(
      of: find.byType(AiToolCallPartView),
      matching: find.byIcon(Icons.check_circle_outline),
    );
    expect(reasoningIcon, findsOneWidget);
    expect(toolIcon, findsOneWidget);
    expect(
      tester.getCenter(reasoningIcon).dx,
      closeTo(tester.getCenter(toolIcon).dx, 0.01),
    );
    expect(
      tester.getTopLeft(find.text('Thought')).dx,
      closeTo(tester.getTopLeft(find.textContaining('Read')).dx, 0.01),
    );
  });

  testWidgets('outline indentation guide aligns with the Cot trigger', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiChainOfThoughtView(
            parts: [
              AiReasoningPart(text: 'first thought'),
              AiReasoningPart(text: 'second thought'),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('Thinking process'));
    await pumpActivityUi(tester);

    final guide = find.byKey(
      const ValueKey('ai-activity-outline-indent-guide'),
    );
    expect(guide, findsOneWidget);
    final guideRect = tester.getRect(guide);
    expect(guideRect.width, 1);
    expect(
      guideRect.center.dx,
      closeTo(tester.getRect(find.byIcon(Icons.expand_more)).center.dx, 0.01),
      reason: 'the indentation guide must align with the Cot trigger icon',
    );
    expect(
      guideRect.right,
      lessThanOrEqualTo(
        tester
            .getRect(
              find.byKey(const ValueKey('ai-reasoning-status-icon')).first,
            )
            .left,
      ),
    );
    expect(
      guideRect.top,
      lessThanOrEqualTo(tester.getRect(find.text('Thought').first).top),
    );
    expect(
      guideRect.bottom,
      greaterThanOrEqualTo(tester.getRect(find.text('Thought').last).bottom),
    );
    for (final element in find.byType(Icon).evaluate()) {
      expect(
        guideRect.overlaps(tester.getRect(find.byWidget(element.widget))),
        isFalse,
      );
    }
  });

  testWidgets(
    'nested reasoning and tool bodies keep separate visible scrollbars',
    (tester) async {
      final reasoning = List.generate(
        40,
        (i) => 'reasoning line $i',
      ).join('\n');
      final output = List.generate(80, (i) => 'tool output line $i').join('\n');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            platform: TargetPlatform.linux,
            extensions: [
              AiMessageTheme.test(
                cotExpandReasoningOnOpen: true,
                cotExpandToolsOnOpen: true,
              ),
            ],
          ),
          home: Scaffold(
            body: AiChainOfThoughtView(
              parts: [
                AiReasoningPart(text: reasoning),
                AiToolCallPart(
                  toolCallId: 'shell',
                  toolName: 'Bash',
                  category: AiToolCallCategory.command,
                  args: const {'command': 'run checks'},
                  result: output,
                  status: AiToolCallStatus.complete,
                ),
                for (var i = 0; i < 10; i++)
                  AiToolCallPart(toolCallId: 'tool-$i', toolName: 'Read $i'),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.chevron_right));
      await pumpActivityUi(tester);

      expect(find.byType(Scrollbar), findsNWidgets(3));
      final reasoningScrollbar = find.descendant(
        of: find.byType(AiReasoningPartView),
        matching: find.byType(Scrollbar),
      );
      expect(reasoningScrollbar, findsOneWidget);
      expect(
        tester.widget<Scrollbar>(reasoningScrollbar).thumbVisibility,
        isTrue,
      );
      final scrollables = find.byType(Scrollable);
      expect(scrollables, findsNWidgets(3));
      final outlineRight = tester.getRect(find.byType(Scrollbar).first).right;
      for (var i = 1; i < 3; i++) {
        final inner = scrollables.at(i);
        expect(
          outlineRight - tester.getRect(inner).right,
          greaterThanOrEqualTo(16),
          reason: 'inner scrollbars must stay in their own gutter',
        );
        final position = tester.state<ScrollableState>(inner).position;
        expect(position.maxScrollExtent, greaterThan(0));
        await tester.ensureVisible(inner);
        await tester.drag(inner, const Offset(0, -80));
        await pumpActivityUi(tester);
        expect(position.pixels, greaterThan(0));
      }
    },
  );

  testWidgets('expanded Cot bounds long activity in a scrollable outline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiChainOfThoughtView(
            parts: [
              for (var i = 0; i < 50; i++)
                AiToolCallPart(
                  toolCallId: 'c$i',
                  toolName: 'Tool $i',
                  status: AiToolCallStatus.complete,
                ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('Thinking process'));
    await pumpActivityUi(tester);

    final scrollable = find.byType(Scrollable);
    expect(scrollable, findsOneWidget);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(tester.getSize(scrollable).height, lessThanOrEqualTo(384));

    await tester.drag(scrollable, const Offset(0, -240));
    await pumpActivityUi(tester);
    expect(position.pixels, greaterThan(0));
  });

  testWidgets('live Cot follows new activity to the outline bottom', (
    tester,
  ) async {
    Widget build(int count) => MaterialApp(
      home: Scaffold(
        body: AiChainOfThoughtView(
          autoExpand: true,
          parts: [
            for (var i = 0; i < count; i++)
              AiToolCallPart(toolCallId: 'c$i', toolName: 'Tool $i'),
          ],
        ),
      ),
    );

    await tester.pumpWidget(build(40));
    await pumpActivityUi(tester);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, closeTo(position.maxScrollExtent, 1));

    await tester.pumpWidget(build(45));
    await pumpActivityUi(tester);
    expect(position.pixels, closeTo(position.maxScrollExtent, 1));
  });

  testWidgets('live Cot stops following while the reader scrolls up', (
    tester,
  ) async {
    Widget build(int count) => MaterialApp(
      home: Scaffold(
        body: AiChainOfThoughtView(
          autoExpand: true,
          parts: [
            for (var i = 0; i < count; i++)
              AiToolCallPart(toolCallId: 'c$i', toolName: 'Tool $i'),
          ],
        ),
      ),
    );

    await tester.pumpWidget(build(40));
    await pumpActivityUi(tester);
    final scrollable = find.byType(Scrollable);
    final position = tester.state<ScrollableState>(scrollable).position;
    await tester.drag(scrollable, const Offset(0, 160));
    await pumpActivityUi(tester);
    final readOffset = position.pixels;
    expect(position.maxScrollExtent - readOffset, greaterThan(20));

    await tester.pumpWidget(build(45));
    await pumpActivityUi(tester);
    expect(position.pixels, closeTo(readOffset, 1));
  });

  testWidgets('tool status icons use success, error and running colors', (
    tester,
  ) async {
    const successColor = Color(0xFF248A5A);
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: scheme,
          extensions: [AiMessageTheme.test(toolSuccessColor: successColor)],
        ),
        home: const Scaffold(
          body: Column(
            children: [
              AiToolCallPartView(
                part: AiToolCallPart(
                  toolCallId: 'success',
                  toolName: 'Read',
                  status: AiToolCallStatus.complete,
                ),
              ),
              AiToolCallPartView(
                part: AiToolCallPart(
                  toolCallId: 'failure',
                  toolName: 'Read',
                  status: AiToolCallStatus.complete,
                  isError: true,
                ),
              ),
              AiToolCallPartView(
                part: AiToolCallPart(
                  toolCallId: 'running',
                  toolName: 'Read',
                  status: AiToolCallStatus.running,
                ),
              ),
              AiToolCallPartView(
                part: AiToolCallPart(
                  toolCallId: 'cancelled',
                  toolName: 'Read',
                  status: AiToolCallStatus.cancelled,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.widget<Icon>(find.byIcon(Icons.check_circle_outline)).color,
      successColor,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.error_outline)).color,
      scheme.error,
    );
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color,
      scheme.primary,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.cancel_outlined)).color,
      scheme.error,
    );
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
