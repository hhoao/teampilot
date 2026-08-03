import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        ColorScheme.fromSeed(seedColor: Colors.blue),
        scale: 1.0,
      ),
      child: Scaffold(body: child),
    ),
  );
}

Future<void> _openContextMenu(WidgetTester tester) async {
  final chip = find.byType(WorkbenchStripTabChip);
  await tester.tap(chip, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('session tab menu shows pin and invokes onPin', (tester) async {
    var pinned = false;
    await tester.pumpWidget(
      _wrap(
        WorkbenchStripTabChip(
          title: 'Chat',
          active: true,
          kind: WorkbenchTabKind.session,
          tabId: 'chat-1',
          pinnable: true,
          pinned: false,
          onTap: () {},
          onClose: () {},
          onPin: () => pinned = true,
        ),
      ),
    );

    await _openContextMenu(tester);

    expect(find.text('Pin conversation'), findsOneWidget);
    await tester.tap(find.text('Pin conversation'));
    await tester.pumpAndSettle();
    expect(pinned, isTrue);
  });

  testWidgets('unpinnable tab menu omits pin', (tester) async {
    await tester.pumpWidget(
      _wrap(
        WorkbenchStripTabChip(
          title: 'file.dart',
          active: true,
          kind: WorkbenchTabKind.file,
          tabId: '/ws/file.dart',
          onTap: () {},
          onClose: () {},
        ),
      ),
    );

    await _openContextMenu(tester);

    expect(find.text('Pin conversation'), findsNothing);
    expect(find.text('Unpin conversation'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('pinned session tab menu shows unpin', (tester) async {
    await tester.pumpWidget(
      _wrap(
        WorkbenchStripTabChip(
          title: 'Chat',
          active: true,
          kind: WorkbenchTabKind.session,
          tabId: 'chat-1',
          pinnable: true,
          pinned: true,
          onTap: () {},
          onClose: () {},
          onPin: () {},
        ),
      ),
    );

    await _openContextMenu(tester);

    expect(find.text('Unpin conversation'), findsOneWidget);
    expect(find.text('Pin conversation'), findsNothing);
  });
}
