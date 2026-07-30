import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _editBodyFadeChevron() => find.descendant(
      of: find.byType(AiFadeExpandBody),
      matching: find.byKey(const ValueKey('ai-fade-expand-chevron')),
    );

Finder _visibleDiffText(String text) => find
    .descendant(
      of: find.byType(AiFadeExpandBody),
      matching: find.textContaining(text),
    )
    .hitTestable();

void main() {
  testWidgets('StrReplace shows basename + badge + mini-diff (not Used tool)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'StrReplace',
              args: {
                'file_path': 'lib/tp_sidebar_provider.dart',
                'old_string': 'final double mobileBreakpoint;',
                'new_string':
                    'final double mobileBreakpoint;\nfinal bool edgeOpenEnabled;',
                'start_line': 40,
              },
              result: 'ok',
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('tp_sidebar_provider.dart'), findsOneWidget);
    expect(find.textContaining('+'), findsWidgets);
    expect(find.textContaining('edgeOpenEnabled'), findsAtLeastNWidgets(1));
    expect(find.textContaining('ok'), findsNothing);
  });

  testWidgets('tap diff line does not toggle expand', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'StrReplace',
              args: {
                'file_path': 'lib/a.dart',
                'old_string': 'l1\nl2\nl3\nl4\nl5\nl6',
                'new_string': 'l1\nl2\nl3\nl4\nl5\nlate-line',
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Collapsed is on-demand preview — late-line not mounted yet.
    expect(find.textContaining('late-line'), findsNothing);
    expect(find.byIcon(Icons.expand_less), findsNothing);
    await tester.tap(_visibleDiffText('l3'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.expand_less), findsNothing);
  });

  testWidgets('tap basename opens file and does not toggle expand', (
    tester,
  ) async {
    AiToolFileTarget? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolFileActionsScope(
          actions: AiToolFileActions(onOpenFile: (t) async => opened = t),
          child: const Scaffold(
            body: AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: '1',
                toolName: 'StrReplace',
                args: {
                  'file_path': 'lib/a.dart',
                  'old_string': 'l1\nl2\nl3\nl4\nl5\nl6',
                  'new_string': 'l1\nl2\nl3\nl4\nl5\nlate-line',
                  'start_line': 1,
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('late-line'), findsNothing);
    expect(find.byIcon(Icons.expand_less), findsNothing);
    await tester.tap(find.textContaining('a.dart'));
    await tester.pumpAndSettle();
    expect(opened?.path, 'lib/a.dart');
    expect(find.byIcon(Icons.expand_less), findsNothing);
  });

  testWidgets('tap line gutter opens file and does not toggle expand', (
    tester,
  ) async {
    AiToolFileTarget? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolFileActionsScope(
          actions: AiToolFileActions(onOpenFile: (t) async => opened = t),
          child: const Scaffold(
            body: AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: '1',
                toolName: 'StrReplace',
                args: {
                  'file_path': 'lib/a.dart',
                  'old_string': 'l1\nl2\nl3\nl4\nl5\nl6',
                  'new_string': 'l1\nl2\nl3\nl4\nl5\nlate-line',
                  'start_line': 1,
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('late-line'), findsNothing);
    expect(find.byIcon(Icons.expand_less), findsNothing);
    await tester.tap(
      find
          .descendant(
            of: find.byType(AiFadeExpandBody),
            matching: find.text('3'),
          )
          .hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(opened, isNotNull);
    expect(find.byIcon(Icons.expand_less), findsNothing);
  });

  testWidgets('expand grows same region; no Result: label or args JSON', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'StrReplace',
              args: {
                'file_path': 'lib/a.dart',
                'old_string': 'l1\nl2\nl3\nl4\nl5\nl6',
                'new_string': 'l1\nl2\nl3\nl4\nl5\nlate-line',
              },
              result: 'ok',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('late-line'), findsNothing);
    expect(find.byIcon(Icons.expand_less), findsNothing);
    await tester.tap(_editBodyFadeChevron());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.expand_less), findsWidgets);
    expect(find.textContaining('late-line'), findsOneWidget);
    expect(find.textContaining('Result:'), findsNothing);
    expect(find.textContaining('old_string'), findsNothing);
  });

  testWidgets('body fade chevron tap toggles expand once', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'StrReplace',
              args: {
                'file_path': 'lib/a.dart',
                'old_string': 'l1\nl2\nl3\nl4\nl5\nl6',
                'new_string': 'l1\nl2\nl3\nl4\nl5\nlate-line',
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_editBodyFadeChevron(), findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsNothing);
    await tester.tap(_editBodyFadeChevron());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.expand_less), findsWidgets);
    expect(find.textContaining('late-line'), findsOneWidget);
    await tester.tap(_editBodyFadeChevron());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.expand_less), findsNothing);
    expect(find.textContaining('late-line'), findsNothing);
  });

  testWidgets('expanded long single-line add shows full text', (tester) async {
    const marker = 'UNIQUE_EXPAND_MARKER_TAIL';
    final longLine = '${'x' * 80}$marker';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            initiallyExpanded: true,
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'StrReplace',
              args: {
                'file_path': 'lib/a.dart',
                'old_string': 'short',
                'new_string': longLine,
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.textContaining(marker), findsAtLeastNWidgets(1));
  });

  testWidgets('tap basename opens file with endLine', (tester) async {
    AiToolFileTarget? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolFileActionsScope(
          actions: AiToolFileActions(
            onOpenFile: (t) async => opened = t,
          ),
          child: const Scaffold(
            body: AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: '1',
                toolName: 'StrReplace',
                args: {
                  'file_path': 'lib/a.dart',
                  'old_string': 'x',
                  'new_string': 'y',
                  'start_line': 10,
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('a.dart'));
    await tester.pumpAndSettle();
    expect(opened?.path, 'lib/a.dart');
    expect(opened?.startLine, 10);
    expect(opened?.endLine, 11);
  });

  testWidgets(
    'enricher with leading context still shows add line in collapsed preview',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AiToolFileActionsScope(
            actions: AiToolFileActions(
              enrichEditContext: (hunk) async => AiEditHunk(
                path: hunk.path,
                addedCount: 1,
                removedCount: 0,
                startLine: 1,
                lines: [
                  const AiEditLine(
                    kind: AiEditLineKind.context,
                    text: 'ctx1',
                    lineNumber: 1,
                  ),
                  const AiEditLine(
                    kind: AiEditLineKind.context,
                    text: 'ctx2',
                    lineNumber: 2,
                  ),
                  const AiEditLine(
                    kind: AiEditLineKind.context,
                    text: 'ctx3',
                    lineNumber: 3,
                  ),
                  const AiEditLine(
                    kind: AiEditLineKind.context,
                    text: 'ctx4',
                    lineNumber: 4,
                  ),
                  const AiEditLine(
                    kind: AiEditLineKind.context,
                    text: 'ctx5',
                    lineNumber: 5,
                  ),
                  const AiEditLine(
                    kind: AiEditLineKind.context,
                    text: 'ctx6',
                    lineNumber: 6,
                  ),
                  const AiEditLine(
                    kind: AiEditLineKind.add,
                    text: 'added-line',
                    lineNumber: 7,
                  ),
                ],
              ),
            ),
            child: const Scaffold(
              body: AiToolCallPartView(
                part: AiToolCallPart(
                  toolCallId: '1',
                  toolName: 'StrReplace',
                  args: {
                    'file_path': 'lib/a.dart',
                    'old_string': 'x',
                    'new_string': 'y',
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      // Preview prefers change window — added-line visible; early ctx may be omitted.
      expect(find.textContaining('added-line'), findsOneWidget);
      expect(find.textContaining('ctx1'), findsNothing);
    },
  );

  testWidgets('enricher throw keeps original hunk visible', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolFileActionsScope(
          actions: AiToolFileActions(
            enrichEditContext: (_) async => throw StateError('enrich failed'),
          ),
          child: const Scaffold(
            body: AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: '1',
                toolName: 'StrReplace',
                args: {
                  'file_path': 'lib/a.dart',
                  'old_string': 'original-old',
                  'new_string': 'original-new',
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.textContaining('original-old'), findsAtLeastNWidgets(1));
    expect(find.textContaining('original-new'), findsAtLeastNWidgets(1));
  });

  testWidgets('enrichEditContext success updates line numbers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolFileActionsScope(
          actions: AiToolFileActions(
            enrichEditContext: (hunk) async => AiEditHunk(
              path: hunk.path,
              addedCount: hunk.addedCount,
              removedCount: hunk.removedCount,
              startLine: 40,
              lines: [
                const AiEditLine(
                  kind: AiEditLineKind.context,
                  text: 'before',
                  lineNumber: 40,
                ),
                const AiEditLine(
                  kind: AiEditLineKind.add,
                  text: 'added',
                  lineNumber: 41,
                ),
              ],
            ),
          ),
          child: const Scaffold(
            body: AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: '1',
                toolName: 'StrReplace',
                args: {
                  'file_path': 'lib/a.dart',
                  'old_string': 'x',
                  'new_string': 'y',
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('40'), findsWidgets);
    expect(find.textContaining('before'), findsAtLeastNWidgets(1));
  });

  testWidgets('Read still uses summary chrome', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Read',
              args: {'file_path': 'lib/foo.dart'},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('Read'), findsOneWidget);
    expect(find.textContaining('foo.dart'), findsOneWidget);
    expect(find.byIcon(Icons.terminal), findsNothing);
  });

  testWidgets('Bash with command still uses shell chrome, not edit card', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Bash',
              args: {
                'command': 'git status --short',
                'description': 'Check worktree git state',
              },
              result: ' M client/lib/a.dart',
              status: AiToolCallStatus.complete,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('Check worktree git state'), findsOneWidget);
    expect(find.textContaining('git status --short'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Result:'), findsNothing);
    expect(find.byIcon(Icons.terminal), findsOneWidget);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(find.textContaining('\$'), findsWidgets);
    expect(find.textContaining('git status --short'), findsAtLeastNWidgets(1));
    expect(find.textContaining('M client/lib/a.dart'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Result:'), findsNothing);
    expect(find.textContaining('"command"'), findsNothing);
  });
}
