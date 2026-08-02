import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/settings/workspace_section_tab_bar.dart';

void main() {
  Widget wrap(Widget child) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    return MaterialApp(
      theme: ThemeData(colorScheme: scheme),
      home: TpTheme(
        data: TpThemeData.fromColorScheme(scheme, scale: 1),
        child: Scaffold(body: child),
      ),
    );
  }

  testWidgets('section tab bar selects and invokes onSelect', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      wrap(
        WorkspaceSectionTabBar(
          tabs: const ['Alpha', 'Beta'],
          selectedIndex: selected,
          onSelect: (i) => selected = i,
        ),
      ),
    );
    await tester.tap(find.text('Beta'));
    await tester.pump();
    expect(selected, 1);
  });
}
