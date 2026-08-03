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
  testWidgets('file tab menu shows copy path above close', (tester) async {
    await tester.pumpWidget(
      _wrap(
        WorkbenchStripTabChip(
          title: 'a.dart',
          active: true,
          kind: WorkbenchTabKind.file,
          tabId: '/ws/a.dart',
          filePath: '/ws/a.dart',
          workspaceRoot: '/ws',
          desktopShellActions: true,
          onTap: () {},
          onClose: () {},
          onCloseOthers: () {},
          onCloseRight: () {},
        ),
      ),
    );

    await _openContextMenu(tester);

    expect(find.text('Copy path'), findsOneWidget);
    expect(find.text('Copy relative path'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}
