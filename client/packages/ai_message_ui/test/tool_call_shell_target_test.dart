import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestShellResolver implements AiShellToolTargetResolver {
  const _TestShellResolver();

  @override
  AiShellToolTarget? resolve(AiToolCallPart part) {
    final cmd = part.args?['command'] as String?;
    if (cmd == null) return null;
    return AiShellToolTarget(
      command: cmd,
      description: part.args?['description'] as String?,
    );
  }
}

class _TestFileResolver implements AiToolFileTargetResolver {
  const _TestFileResolver();

  @override
  AiToolFileTarget? resolve(AiToolCallPart part) {
    final path = part.args?['file_path'] as String?;
    if (path == null) return null;
    return AiToolFileTarget(path: path);
  }
}

class _NoopEditResolver implements AiEditToolTargetResolver {
  const _NoopEditResolver();

  @override
  AiEditToolTarget? resolve(AiToolCallPart part) => null;
}

Widget _wrapShell(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: AiToolFileActionsScope(
        actions: const AiToolFileActions(
          fileResolver: _TestFileResolver(),
          editResolver: _NoopEditResolver(),
          shellResolver: _TestShellResolver(),
        ),
        child: child,
      ),
    ),
  );
}

Finder _shellBodyFadeChevron() => find.descendant(
  of: find.byType(AiFadeExpandBody),
  matching: find.byKey(const ValueKey('ai-fade-expand-chevron')),
);

Finder _visibleShellText(String text) => find
    .descendant(
      of: find.byType(AiFadeExpandBody),
      matching: find.textContaining(text),
    )
    .hitTestable();

void main() {
  testWidgets('Bash shows shell summary; collapsed shows \$ command + output', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapShell(
        const AiToolCallPartView(
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
    );

    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('Check worktree git state'), findsOneWidget);
    expect(find.textContaining('git status --short'), findsAtLeastNWidgets(1));
    expect(find.textContaining('M client/lib/a.dart'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Result:'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(find.textContaining('\$'), findsWidgets);
    expect(find.textContaining('git status --short'), findsAtLeastNWidgets(1));
    expect(find.textContaining('M client/lib/a.dart'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Result:'), findsNothing);
    // Must not dump JSON args panel.
    expect(find.textContaining('"command"'), findsNothing);
  });

  testWidgets('collapsed fade keeps full output in tree', (tester) async {
    final result = List.generate(7, (i) => 'line${i + 1}').join('\n');

    await tester.pumpWidget(
      _wrapShell(
        AiToolCallPartView(
          part: AiToolCallPart(
            toolCallId: '1',
            toolName: 'Bash',
            args: {'command': 'seq 7'},
            result: result,
            status: AiToolCallStatus.complete,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('line1'), findsAtLeastNWidgets(1));
    expect(find.textContaining('line5'), findsAtLeastNWidgets(1));
    expect(find.textContaining('line6'), findsAtLeastNWidgets(1));
    expect(find.textContaining('line7'), findsAtLeastNWidgets(1));
    expect(find.byIcon(Icons.expand_less), findsNothing);
  });

  testWidgets('tap mini panel toggles full output', (tester) async {
    final result = List.generate(7, (i) => 'line${i + 1}').join('\n');

    await tester.pumpWidget(
      _wrapShell(
        AiToolCallPartView(
          part: AiToolCallPart(
            toolCallId: '1',
            toolName: 'Bash',
            args: {'command': 'seq 7'},
            result: result,
            status: AiToolCallStatus.complete,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('line6'), findsAtLeastNWidgets(1));
    expect(find.byIcon(Icons.expand_less), findsNothing);
    await tester.tap(_visibleShellText('line3'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.expand_less), findsWidgets);
    expect(find.textContaining('line7'), findsAtLeastNWidgets(1));
  });

  testWidgets('body fade chevron tap toggles expand once', (tester) async {
    final result = List.generate(7, (i) => 'line${i + 1}').join('\n');

    await tester.pumpWidget(
      _wrapShell(
        AiToolCallPartView(
          part: AiToolCallPart(
            toolCallId: '1',
            toolName: 'Bash',
            args: {'command': 'seq 7'},
            result: result,
            status: AiToolCallStatus.complete,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_shellBodyFadeChevron(), findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsNothing);
    await tester.tap(_shellBodyFadeChevron());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.expand_less), findsWidgets);
    await tester.tap(_shellBodyFadeChevron());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.expand_less), findsNothing);
  });

  testWidgets('initiallyExpanded shows full output immediately', (
    tester,
  ) async {
    final result = List.generate(7, (i) => 'line${i + 1}').join('\n');

    await tester.pumpWidget(
      _wrapShell(
        AiToolCallPartView(
          initiallyExpanded: true,
          part: AiToolCallPart(
            toolCallId: '1',
            toolName: 'Bash',
            args: {'command': 'seq 7'},
            result: result,
            status: AiToolCallStatus.complete,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('line6'), findsAtLeastNWidgets(1));
    expect(find.textContaining('line7'), findsAtLeastNWidgets(1));
    expect(find.byIcon(Icons.expand_less), findsWidgets);
  });

  testWidgets('expanded shell output is not in SelectionContainer.disabled', (
    tester,
  ) async {
    final result = List.generate(7, (i) => 'line${i + 1}').join('\n');

    await tester.pumpWidget(
      _wrapShell(
        SelectionArea(
          child: AiToolCallPartView(
            initiallyExpanded: true,
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Bash',
              args: {'command': 'seq 7'},
              result: result,
              status: AiToolCallStatus.complete,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final outputFinder = find.textContaining('line7');
    expect(outputFinder, findsAtLeastNWidgets(1));
    expect(
      find.ancestor(
        of: outputFinder.last,
        matching: find.byWidgetPredicate(
          (w) =>
              w is SelectionContainer &&
              w.delegate == SelectionContainer.disabled,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('shell without description uses truncated command in header', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapShell(
        const AiToolCallPartView(
          part: AiToolCallPart(
            toolCallId: '1',
            toolName: 'Shell',
            args: {'command': 'ls -la'},
          ),
        ),
      ),
    );
    expect(find.textContaining('ls -la'), findsWidgets);
    expect(find.textContaining('Used tool:'), findsNothing);
  });

  testWidgets('shell name without command stays legacy', (tester) async {
    await tester.pumpWidget(
      _wrapShell(
        const AiToolCallPartView(
          part: AiToolCallPart(
            toolCallId: '1',
            toolName: 'Bash',
            args: {'description': 'no command'},
          ),
        ),
      ),
    );
    expect(find.textContaining('Used tool:'), findsOneWidget);
  });

  testWidgets('Read still uses file summary chrome', (tester) async {
    await tester.pumpWidget(
      _wrapShell(
        const AiToolCallPartView(
          part: AiToolCallPart(
            toolCallId: '1',
            toolName: 'Read',
            args: {'file_path': 'lib/foo.dart'},
          ),
        ),
      ),
    );
    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('foo.dart'), findsOneWidget);
  });

  testWidgets('expanded huge shell output is capped so layout stays bounded', (
    tester,
  ) async {
    // > 50 KB output — expanded body must be capped with a marker, not laid
    // out in full.
    final result = List.generate(1500, (i) => 'line$i-${'x' * 40}').join('\n');
    await tester.pumpWidget(
      _wrapShell(
        AiToolCallPartView(
          initiallyExpanded: true,
          part: AiToolCallPart(
            toolCallId: '1',
            toolName: 'Bash',
            args: {'command': 'make test'},
            result: result,
            status: AiToolCallStatus.complete,
          ),
        ),
      ),
    );

    expect(find.textContaining(kAiToolPanelTruncationMarker), findsOneWidget);
    // The capped-away tail is not mounted.
    expect(find.textContaining('line1499-'), findsNothing);
    // The head is still visible.
    expect(find.textContaining('line0-'), findsOneWidget);
  });

  testWidgets(
    'collapsed huge shell output mounts a short preview not 50k chars',
    (tester) async {
      final result = List.generate(
        1500,
        (i) => 'line$i-${'x' * 40}',
      ).join('\n');
      await tester.pumpWidget(
        _wrapShell(
          AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Bash',
              args: {'command': 'make test'},
              result: result,
              status: AiToolCallStatus.complete,
            ),
          ),
        ),
      );

      expect(find.textContaining('line0-'), findsOneWidget);
      expect(find.textContaining('line6-'), findsNothing);
      expect(find.textContaining('line1499-'), findsNothing);
      expect(find.textContaining(kAiToolPanelTruncationMarker), findsNothing);

      await tester.tap(_shellBodyFadeChevron());
      await tester.pumpAndSettle();
      expect(find.textContaining(kAiToolPanelTruncationMarker), findsOneWidget);
      expect(find.textContaining('line0-'), findsOneWidget);
      expect(find.textContaining('line1499-'), findsNothing);
    },
  );
}
