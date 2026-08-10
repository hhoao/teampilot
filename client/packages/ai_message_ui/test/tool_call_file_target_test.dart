import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestFileResolver implements AiToolFileTargetResolver {
  const _TestFileResolver();

  @override
  AiToolFileTarget? resolve(AiToolCallPart part) {
    final path = part.args?['file_path'] as String? ??
        part.args?['path'] as String?;
    if (path == null) return null;
    final offset = part.args?['offset'] as int?;
    final limit = part.args?['limit'] as int?;
    return AiToolFileTarget(
      path: path,
      startLine: offset,
      endLine: offset != null && limit != null ? offset + limit - 1 : null,
    );
  }
}

class _TestEditResolver implements AiEditToolTargetResolver {
  const _TestEditResolver();

  @override
  AiEditToolTarget? resolve(AiToolCallPart part) => null;
}

class _TestShellResolver implements AiShellToolTargetResolver {
  const _TestShellResolver();

  @override
  AiShellToolTarget? resolve(AiToolCallPart part) => null;
}

void main() {
  testWidgets('summary shows basename; tap opens; chevron expands', (
    tester,
  ) async {
    AiToolFileTarget? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolFileActionsScope(
          actions: AiToolFileActions(
            fileResolver: const _TestFileResolver(),
            editResolver: const _TestEditResolver(),
            shellResolver: const _TestShellResolver(),
            onOpenFile: (t) async => opened = t,
          ),
          child: const Scaffold(
            body: AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: '1',
                toolName: 'Read',
                args: {
                  'file_path': 'lib/ai_history_seat.dart',
                  'offset': 110,
                  'limit': 80,
                },
                result: 'ok',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('Read'), findsOneWidget);
    expect(find.textContaining('ai_history_seat.dart'), findsOneWidget);
    expect(find.textContaining('L110'), findsOneWidget);
    expect(find.textContaining('ok'), findsNothing);

    await tester.tap(find.textContaining('ai_history_seat.dart'));
    await tester.pumpAndSettle();
    expect(opened?.path, 'lib/ai_history_seat.dart');
    expect(opened?.startLine, 110);
    expect(find.textContaining('ok'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.textContaining('ok'), findsOneWidget);
  });

  testWidgets('Grep still shows Used tool chrome', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Grep',
              args: {'pattern': 'foo'},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Used tool:'), findsOneWidget);
  });

  testWidgets('summary without onOpenFile renders plain basename', (
    tester,
  ) async {
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
    expect(find.textContaining('foo.dart'), findsOneWidget);
    expect(find.textContaining('L'), findsNothing);
  });

  testWidgets('tap line range opens file when onOpenFile set', (tester) async {
    AiToolFileTarget? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolFileActionsScope(
          actions: AiToolFileActions(
            fileResolver: const _TestFileResolver(),
            editResolver: const _TestEditResolver(),
            shellResolver: const _TestShellResolver(),
            onOpenFile: (t) async => opened = t,
          ),
          child: const Scaffold(
            body: AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: '1',
                toolName: 'Read',
                args: {
                  'file_path': 'lib/foo.dart',
                  'offset': 5,
                  'limit': 3,
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.textContaining('L5-7'));
    await tester.pumpAndSettle();
    expect(opened?.path, 'lib/foo.dart');
    expect(opened?.startLine, 5);
    expect(opened?.endLine, 7);
  });
}
