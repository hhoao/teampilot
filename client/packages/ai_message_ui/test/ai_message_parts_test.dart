import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('user message aligns end; assistant aligns start', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AiMessageView(
                message: AiMessage(
                  id: 'u1',
                  role: AiRole.user,
                  parts: const [AiTextPart(text: 'hello user')],
                ),
              ),
              AiMessageView(
                message: AiMessage(
                  id: 'a1',
                  role: AiRole.assistant,
                  parts: const [AiTextPart(text: 'hello assistant')],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final userAlign = tester.widget<Align>(
      find
          .ancestor(
            of: find.textContaining('hello user'),
            matching: find.byType(Align),
          )
          .first,
    );
    final assistantAlign = tester.widget<Align>(
      find
          .ancestor(
            of: find.textContaining('hello assistant'),
            matching: find.byType(Align),
          )
          .first,
    );

    expect(userAlign.alignment, Alignment.centerRight);
    expect(assistantAlign.alignment, Alignment.centerLeft);
  });

  testWidgets('short user bubble shrinks to content; long caps at 85%', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AiMessageView(
                  message: AiMessage(
                    id: 'short',
                    role: AiRole.user,
                    parts: const [AiTextPart(text: 'hi')],
                  ),
                ),
                AiMessageView(
                  message: AiMessage(
                    id: 'long',
                    role: AiRole.user,
                    parts: const [
                      AiTextPart(
                        text:
                            'this is a much longer user message that should wrap '
                            'inside the max bubble width instead of shrinking',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final shortBubble = tester.getSize(
      find
          .ancestor(
            of: find.text('hi'),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    final longBubble = tester.getSize(
      find
          .ancestor(
            of: find.textContaining('much longer user message'),
            matching: find.byType(ColoredBox),
          )
          .first,
    );

    expect(shortBubble.width, lessThan(80));
    expect(shortBubble.width, lessThan(longBubble.width));
    // Action bar reserves 80px, so cap is min(85%, thread − reserve) = 320 here.
    expect(longBubble.width, closeTo(320, 8));
    expect(longBubble.width, lessThanOrEqualTo(400 * 0.85 + 1));
  });

  testWidgets('tool fallback shows Used tool label; tap expands args/result', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: const [
                AiToolCallPart(
                  toolCallId: 'tc1',
                  toolName: 'ReadFile',
                  args: {'path': '/tmp/x'},
                  result: 'file contents',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Thinking process'), findsOneWidget);
    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('ReadFile'), findsNothing);
    expect(find.textContaining('/tmp/x'), findsNothing);
    expect(find.textContaining('file contents'), findsNothing);

    await tester.tap(find.textContaining('Thinking process'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('ReadFile'), findsOneWidget);
    expect(find.textContaining('x'), findsOneWidget);
    expect(find.text('Result:'), findsNothing);
    expect(find.textContaining('file contents'), findsNothing);

    await tester.tap(find.textContaining('ReadFile'));
    await tester.pumpAndSettle();

    expect(find.textContaining('/tmp/x'), findsOneWidget);
    expect(find.text('Result:'), findsOneWidget);
    expect(find.textContaining('file contents'), findsOneWidget);
  });

  testWidgets('consecutive tools render as a collapsible group', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: const [
                AiToolCallPart(toolCallId: '1', toolName: 'Read'),
                AiToolCallPart(toolCallId: '2', toolName: 'Grep'),
                AiToolCallPart(toolCallId: '3', toolName: 'Shell'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Thinking process · 3 steps'), findsOneWidget);
    expect(find.textContaining('Used 3 tools'), findsNothing);
    expect(find.textContaining('Used tool:'), findsNothing);

    await tester.tap(find.textContaining('Thinking process'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Used tool:'), findsNWidgets(3));
    expect(find.textContaining('Used 3 tools'), findsNothing);
    expect(find.textContaining('Read'), findsWidgets);
  });

  testWidgets('text part renders markdown without raw markers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: const [AiTextPart(text: 'say **bold** please')],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('bold'), findsWidgets);
    expect(find.textContaining('**bold**'), findsNothing);
  });

  testWidgets('injected strings localize tool labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiMessageStringsScope(
          strings: const AiMessageStrings(
            usedTool: '调用工具',
            result: '输出',
          ),
          child: Scaffold(
            body: AiMessageView(
              message: AiMessage(
                id: 'a1',
                role: AiRole.assistant,
                parts: const [
                  AiToolCallPart(
                    toolCallId: '1',
                    toolName: 'Bash',
                    args: {'command': 'ls'},
                    result: 'ok',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Thinking process'), findsOneWidget);
    expect(find.textContaining('调用工具:'), findsNothing);
    expect(find.textContaining('ls'), findsNothing);

    await tester.tap(find.textContaining('Thinking process'));
    await tester.pumpAndSettle();

    expect(find.textContaining('调用工具:'), findsNothing);
    // Header summary + mini panel both show the command when no description.
    expect(find.textContaining('ls'), findsWidgets);
    expect(find.text('输出:'), findsNothing);
    // Collapsed shell mini panel already shows $ and result (no further tap needed).
    expect(find.textContaining(r'$'), findsWidgets);
    // Fade-expand keeps full output in tree for measurement.
    expect(find.textContaining('ok'), findsAtLeastNWidgets(1));
  });

  testWidgets('tool expand uses AnimatedSize; long args soft-wrap', (
    tester,
  ) async {
    final long = 'x' * 400;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: '1',
                toolName: 'Echo',
                argsText: long,
                result: 'ok',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AnimatedSize), findsNothing);
    await tester.tap(find.textContaining('Used tool:'));
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedSize), findsOneWidget);
    expect(find.textContaining('xxx'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('action bar hover reveal starts fully hidden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            actionBarReveal: AiActionBarReveal.hover,
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: const [AiTextPart(text: 'hello')],
            ),
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(AiMessageActionBar),
        matching: find.byIcon(Icons.copy_rounded),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(AiMessageActionBar),
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );
  });

  testWidgets('AiThread last message uses always reveal; earlier uses hover', (
    tester,
  ) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages([
        AiMessage(
          id: '1',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'first')],
        ),
        AiMessage(
          id: '2',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'last')],
        ),
      ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiThread(
            runtime: store,
            loadingBuilder: (_) => const SizedBox.shrink(),
            emptyBuilder: (_) => const SizedBox.shrink(),
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstView = tester.widget<AiMessageView>(
      find.ancestor(
        of: find.text('first'),
        matching: find.byType(AiMessageView),
      ),
    );
    final lastView = tester.widget<AiMessageView>(
      find.ancestor(
        of: find.text('last'),
        matching: find.byType(AiMessageView),
      ),
    );
    expect(firstView.actionBarReveal, AiActionBarReveal.hover);
    expect(lastView.actionBarReveal, AiActionBarReveal.always);
  });

  testWidgets('tip thinking auto-expands chain and inner reasoning', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            chainOfThoughtAutoExpand: true,
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: const [
                AiReasoningPart(text: 'first step'),
                AiReasoningPart(text: 'second step'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Thinking process · 2 steps'), findsOneWidget);
    // Inner reasoning steps are open — their content is visible.
    expect(find.textContaining('first step'), findsOneWidget);
    expect(find.textContaining('second step'), findsOneWidget);
  });

  testWidgets('non-tip thinking stays collapsed by default', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: const [AiReasoningPart(text: 'hidden thinking')],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Thinking process · 1 steps'), findsOneWidget);
    expect(find.textContaining('hidden thinking'), findsNothing);
  });

  testWidgets('auto-expanded thinking collapses once non-thinking arrives', (
    tester,
  ) async {
    Future<void> pump({
      required bool autoExpand,
      required List<AiMessagePart> parts,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiMessageView(
              chainOfThoughtAutoExpand: autoExpand,
              message: AiMessage(
                id: 'a1',
                role: AiRole.assistant,
                parts: parts,
              ),
            ),
          ),
        ),
      );
    }

    await pump(
      autoExpand: true,
      parts: const [AiReasoningPart(text: 'live thinking')],
    );
    expect(find.textContaining('live thinking'), findsOneWidget);

    await pump(
      autoExpand: false,
      parts: const [
        AiReasoningPart(text: 'live thinking'),
        AiTextPart(text: 'the answer'),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('the answer'), findsOneWidget);
    expect(find.textContaining('live thinking'), findsNothing);
  });

  testWidgets('AiThread auto-expands only the last all-thinking message', (
    tester,
  ) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages([
        AiMessage(
          id: '1',
          role: AiRole.assistant,
          parts: const [AiReasoningPart(text: 'old reasoning')],
        ),
        AiMessage(
          id: '2',
          role: AiRole.assistant,
          parts: const [AiReasoningPart(text: 'tip reasoning')],
        ),
      ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiThread(
            runtime: store,
            loadingBuilder: (_) => const SizedBox.shrink(),
            emptyBuilder: (_) => const SizedBox.shrink(),
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('tip reasoning'), findsOneWidget);
    expect(find.textContaining('old reasoning'), findsNothing);
  });
}
