import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/pages/home_workspace/workspaces_tab.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: TpTheme(
        data: TpThemeData.fromColorScheme(
          ColorScheme.fromSeed(seedColor: Colors.blue),
          scale: 1.0,
        ),
        child: Scaffold(body: child),
      ),
    );
  }

  testWidgets('border encloses padded icon, not a tight icon-only box', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        WorkspacesIconChip(icon: Icons.sort_rounded, onTap: () {}),
      ),
    );

    final icon = find.byIcon(Icons.sort_rounded);
    expect(icon, findsOneWidget);

    final bordered = find.ancestor(
      of: icon,
      matching: find.byWidgetPredicate((widget) {
        if (widget is! DecoratedBox) return false;
        final decoration = widget.decoration;
        return decoration is BoxDecoration && decoration.border != null;
      }),
    );
    expect(bordered, findsWidgets);

    final box = tester.widget<DecoratedBox>(bordered.first);
    expect(
      box.child,
      isNot(isA<Icon>()),
      reason: 'padding must sit inside the border, not outside it',
    );

    final iconSize = tester.getSize(icon);
    final borderSize = tester.getSize(bordered.first);
    expect(borderSize.width, greaterThan(iconSize.width + 8));
    expect(borderSize.height, greaterThan(iconSize.height + 8));
  });
}
