import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/settings/settings_dialog_pane_host.dart';

void main() {
  testWidgets('SettingsDialogPaneHost builds only visited panes', (tester) async {
    var builtPanes = <int>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsDialogPaneHost(
            paneCount: 3,
            selectedIndex: 0,
            builder: (context, index) {
              builtPanes.add(index);
              return Text('pane-$index');
            },
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(builtPanes, {0});
    expect(find.text('pane-0'), findsOneWidget);
    expect(find.text('pane-1'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsDialogPaneHost(
            paneCount: 3,
            selectedIndex: 1,
            builder: (context, index) {
              builtPanes.add(index);
              return Text('pane-$index');
            },
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(builtPanes, {0, 1});
    expect(find.text('pane-1'), findsOneWidget);
    expect(find.text('pane-0'), findsNothing);
  });
}
