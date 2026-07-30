import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/floating_workspace/floating_workspace_empty.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SizedBox(width: 400, height: 300, child: child)),
    );
  }

  testWidgets('shows three rows including minimize', (tester) async {
    await tester.pumpWidget(
      wrap(
        FloatingWorkspaceEmpty(
          rows: const [
            FloatingWorkspaceEmptyRow(
              id: 'newTerminal',
              icon: Icons.terminal_outlined,
              label: '新 Terminal',
            ),
            FloatingWorkspaceEmptyRow(
              id: 'openFile',
              icon: Icons.insert_drive_file_outlined,
              label: '打开文件',
            ),
            FloatingWorkspaceEmptyRow(
              id: 'minimize',
              icon: Icons.remove,
              label: '最小化',
            ),
          ],
          onActivate: (_) {},
        ),
      ),
    );

    expect(find.text('新 Terminal'), findsOneWidget);
    expect(find.text('打开文件'), findsOneWidget);
    expect(find.text('最小化'), findsOneWidget);
  });

  testWidgets('tap new terminal invokes callback', (tester) async {
    String? activated;
    await tester.pumpWidget(
      wrap(
        FloatingWorkspaceEmpty(
          rows: const [
            FloatingWorkspaceEmptyRow(
              id: 'newTerminal',
              icon: Icons.terminal_outlined,
              label: '新 Terminal',
            ),
            FloatingWorkspaceEmptyRow(
              id: 'openFile',
              icon: Icons.insert_drive_file_outlined,
              label: '打开文件',
            ),
            FloatingWorkspaceEmptyRow(
              id: 'minimize',
              icon: Icons.remove,
              label: '最小化',
            ),
          ],
          onActivate: (id) => activated = id,
        ),
      ),
    );

    await tester.tap(find.text('新 Terminal'));
    await tester.pump();
    expect(activated, 'newTerminal');
  });

  testWidgets('arrow keys and Enter select and activate', (tester) async {
    String? activated;
    await tester.pumpWidget(
      wrap(
        FloatingWorkspaceEmpty(
          autofocus: true,
          rows: const [
            FloatingWorkspaceEmptyRow(
              id: 'newTerminal',
              icon: Icons.terminal_outlined,
              label: '新 Terminal',
            ),
            FloatingWorkspaceEmptyRow(
              id: 'openFile',
              icon: Icons.insert_drive_file_outlined,
              label: '打开文件',
            ),
            FloatingWorkspaceEmptyRow(
              id: 'minimize',
              icon: Icons.remove,
              label: '最小化',
            ),
          ],
          onActivate: (id) => activated = id,
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(activated, 'openFile');
  });
}
