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

  testWidgets('short user bubble shrinks; long bubble caps without matching width', (
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
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final longBubble = tester.getSize(
      find
          .ancestor(
            of: find.textContaining('much longer user message'),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );

    expect(shortBubble.width, lessThan(120));
    expect(longBubble.width, greaterThan(shortBubble.width + 80));
    // Cap at ~85% of 400 — must not force every bubble to that width.
    expect(shortBubble.width, lessThan(400 * 0.5));
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

    expect(find.textContaining('Used tool:'), findsOneWidget);
    expect(find.textContaining('ReadFile'), findsOneWidget);
    expect(find.textContaining('/tmp/x'), findsNothing);
    expect(find.textContaining('file contents'), findsNothing);

    await tester.tap(find.textContaining('Used tool:'));
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

    expect(find.textContaining('Used 3 tools'), findsOneWidget);
    expect(find.textContaining('Used tool:'), findsNothing);

    await tester.tap(find.textContaining('Used 3 tools'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Used tool:'), findsNWidgets(3));
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

    expect(find.textContaining('调用工具:'), findsOneWidget);
    await tester.tap(find.textContaining('调用工具:'));
    await tester.pumpAndSettle();
    expect(find.text('输出:'), findsOneWidget);
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

    expect(find.byType(AnimatedSize), findsOneWidget);
    await tester.tap(find.textContaining('Used tool:'));
    await tester.pumpAndSettle();
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

    final opacity = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(AiMessageActionBar),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(opacity.opacity, equals(0));
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

    final views = tester.widgetList<AiMessageView>(find.byType(AiMessageView)).toList();
    expect(views, hasLength(2));
    expect(views[0].actionBarReveal, AiActionBarReveal.hover);
    expect(views[1].actionBarReveal, AiActionBarReveal.always);
  });
}
