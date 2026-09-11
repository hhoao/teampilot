import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/workbench/workbench_group_lock_button.dart';

Widget _localizedHost(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('lock button exposes state-specific icon and callback', (
    tester,
  ) async {
    var toggles = 0;
    await tester.pumpWidget(
      _localizedHost(
        WorkbenchGroupLockButton(locked: false, onToggle: () => toggles++),
      ),
    );
    expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);
    await tester.tap(find.byType(WorkbenchGroupLockButton));
    expect(toggles, 1);

    await tester.pumpWidget(
      _localizedHost(
        WorkbenchGroupLockButton(locked: true, onToggle: () => toggles++),
      ),
    );
    expect(find.byIcon(Icons.lock_outlined), findsOneWidget);
  });

  testWidgets('lock button is disabled when no callback is provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localizedHost(
        const WorkbenchGroupLockButton(locked: false, onToggle: null),
      ),
    );

    expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);
    final hover = tester.widget<TpHover>(find.byType(TpHover));
    expect(hover.enabled, isFalse);
    expect(hover.onTap, isNull);
    await tester.tap(find.byType(WorkbenchGroupLockButton));
    expect(tester.takeException(), isNull);
  });
}
