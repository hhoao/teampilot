import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/find/find_bar_palette.dart';
import 'package:teampilot/widgets/find/find_bar_widgets.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      extensions: const [FindBarPalette.light],
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('FindBarPanel defaults to a stadium pill', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FindBarPanel(
          child: SizedBox(width: 200, height: FindField.kHeight),
        ),
      ),
    );

    final material = tester
        .widgetList<Material>(
          find.descendant(
            of: find.byType(FindBarPanel),
            matching: find.byType(Material),
          ),
        )
        .first;
    final shape = material.shape! as RoundedRectangleBorder;
    expect(
      shape.borderRadius,
      const BorderRadius.all(Radius.circular(FindBarPanel.kPillRadius)),
    );
  });

  testWidgets('FindBarPanel accepts the expanded card radius', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FindBarPanel(
          borderRadius: FindBarPanel.kCardRadius,
          child: SizedBox(width: 200, height: FindField.kHeight),
        ),
      ),
    );

    final material = tester
        .widgetList<Material>(
          find.descendant(
            of: find.byType(FindBarPanel),
            matching: find.byType(Material),
          ),
        )
        .first;
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(16));
  });

  testWidgets('FindBarPanel switches to the focus border', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _wrap(
        FindBarPanel(
          focusNode: focus,
          child: Focus(
            focusNode: focus,
            child: const SizedBox(width: 200, height: FindField.kHeight),
          ),
        ),
      ),
    );

    Color panelBorderColor() {
      final material = tester
          .widgetList<Material>(
            find.descendant(
              of: find.byType(FindBarPanel),
              matching: find.byType(Material),
            ),
          )
          .first;
      return (material.shape! as RoundedRectangleBorder).side.color;
    }

    expect(panelBorderColor(), FindBarPalette.light.panelBorder);
    focus.requestFocus();
    await tester.pump();
    expect(panelBorderColor(), FindBarPalette.light.focusBorder);
  });

  testWidgets('FindField shows a search icon and renders the hint', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      _wrap(
        FindField(
          controller: controller,
          focusNode: focus,
          hint: 'Search',
        ),
      ),
    );

    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
  });

  testWidgets('FindField standalone mode draws its own pill border', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      _wrap(
        FindField(
          controller: controller,
          focusNode: focus,
          hint: 'Search',
          standalone: true,
        ),
      ),
    );

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(FindField),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(
      decoration.borderRadius,
      const BorderRadius.all(Radius.circular(FindBarPanel.kPillRadius)),
    );
  });

  testWidgets('FindBarDivider is a hairline', (tester) async {
    await tester.pumpWidget(_wrap(const FindBarDivider()));
    final size = tester.getSize(find.byType(FindBarDivider));
    expect(size.height, 18);
  });
}
