import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/pages/termux/work_environment_chooser_page.dart';

Future<Widget> _embeddedChooserHost(Widget child) async {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
      ),
      child: Material(child: child),
    ),
  );
}

void main() {
  testWidgets('embedded chooser has no AppBar', (tester) async {
    await tester.pumpWidget(
      await _embeddedChooserHost(
        const WorkEnvironmentChooserPage(embedded: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(Scaffold), findsNothing);
    expect(find.textContaining('Termux'), findsWidgets);
  });

  testWidgets('embedded chooser uses callbacks instead of Navigator.push',
      (tester) async {
    var termuxCalls = 0;
    var sshCalls = 0;
    await tester.pumpWidget(
      await _embeddedChooserHost(
        WorkEnvironmentChooserPage(
          embedded: true,
          onChooseTermux: () => termuxCalls++,
          onChooseSsh: () => sshCalls++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('On-device · Termux'));
    await tester.pumpAndSettle();
    expect(termuxCalls, 1);
    expect(sshCalls, 0);

    await tester.tap(find.text('Remote · SSH'));
    await tester.pumpAndSettle();
    expect(termuxCalls, 1);
    expect(sshCalls, 1);
  });
}
