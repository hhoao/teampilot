import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

Future<void> _openContextMenu(WidgetTester tester) async {
  final chip = find.byType(WorkspaceShellTabChip);
  await tester.tap(chip, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('session tab menu shows pin and invokes onPin', (tester) async {
    var pinned = false;
    await tester.pumpWidget(
      _wrap(
        WorkspaceShellTabChip(
          title: 'Chat',
          active: true,
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
        WorkspaceShellTabChip(
          title: 'file.dart',
          active: true,
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
        WorkspaceShellTabChip(
          title: 'Chat',
          active: true,
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
