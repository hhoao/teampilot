import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TaskResolver implements AiTaskToolResolver {
  @override
  AiTaskToolTarget? resolve(AiToolCallPart part) {
    if (part.toolName.toLowerCase() != 'taskcreate') return null;
    return AiTaskCreateTarget(
      toolLabel: part.toolName,
      subject: 'from-resolver',
    );
  }
}

void main() {
  testWidgets('part view renders specialized card from resolver', (
    tester,
  ) async {
    final theme = ThemeData(
      useMaterial3: true,
      extensions: [AiMessageTheme.test()],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AiSpecialToolActionsScope(
            actions: AiSpecialToolActions(taskResolver: _TaskResolver()),
            child: const AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: 'c',
                toolName: 'TaskCreate',
                args: {'subject': 'ignored-by-card'},
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      find.textContaining('from-resolver', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Used tool', findRichText: true), findsNothing);
  });
}
