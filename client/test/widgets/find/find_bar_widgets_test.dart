import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
        FindField(controller: controller, focusNode: focus, hint: 'Search'),
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

  testWidgets('FindField opts out of the themed input fill', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: const [FindBarPalette.light],
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: Colors.grey,
          ),
        ),
        home: Scaffold(
          body: Center(
            child: FindBarPanel(
              child: FindField(
                controller: controller,
                focusNode: focus,
                hint: 'Search',
              ),
            ),
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.filled, isFalse);
  });

  testWidgets('FindField spaces inline toggles apart', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    FindToggleButton toggle(String asset) => FindToggleButton(
      iconAsset: asset,
      tooltip: asset,
      checked: false,
      onTap: () {},
    );

    await tester.pumpWidget(
      _wrap(
        FindBarPanel(
          child: FindField(
            controller: controller,
            focusNode: focus,
            hint: 'Search',
            toggles: [
              toggle(FindBarIcons.caseSensitive),
              toggle(FindBarIcons.wholeWord),
            ],
          ),
        ),
      ),
    );

    final first = tester.getCenter(find.byType(FindToggleButton).at(0));
    final second = tester.getCenter(find.byType(FindToggleButton).at(1));
    expect(
      second.dx - first.dx,
      greaterThanOrEqualTo(FindToggleButton.kSize + 6),
    );
  });

  testWidgets('FindToggleButton highlights its glyph on hover', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      _wrap(
        FindToggleButton(
          iconAsset: FindBarIcons.caseSensitive,
          tooltip: 'Case sensitive',
          checked: false,
          onTap: () {},
        ),
      ),
    );

    ColorFilter? glyphFilter() =>
        tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter;

    expect(
      glyphFilter(),
      ColorFilter.mode(FindBarPalette.light.icon, BlendMode.srcIn),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(FindToggleButton)));
    await tester.pumpAndSettle();

    expect(
      glyphFilter(),
      ColorFilter.mode(FindBarPalette.light.text, BlendMode.srcIn),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('FindField puts the clear button before the toggles', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'alpha');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      _wrap(
        FindField(
          controller: controller,
          focusNode: focus,
          hint: 'Search',
          showClear: true,
          onClear: () {},
          toggles: [
            FindToggleButton(
              iconAsset: FindBarIcons.caseSensitive,
              tooltip: 'Case sensitive',
              checked: false,
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    final clear = tester.getCenter(find.byIcon(Icons.close));
    final toggle = tester.getCenter(find.byType(FindToggleButton));
    expect(clear.dx, lessThan(toggle.dx));
  });

  testWidgets('FindField clear button highlights its glyph on hover', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final controller = TextEditingController(text: 'alpha');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      _wrap(
        FindField(
          controller: controller,
          focusNode: focus,
          hint: 'Search',
          showClear: true,
          onClear: () {},
        ),
      ),
    );

    Color? glyphColor() => tester.widget<Icon>(find.byIcon(Icons.close)).color;

    expect(glyphColor(), FindBarPalette.light.icon);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byIcon(Icons.close)));
    await tester.pumpAndSettle();

    expect(glyphColor(), FindBarPalette.light.text);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('FindBarDivider is a hairline', (tester) async {
    await tester.pumpWidget(_wrap(const FindBarDivider()));
    final size = tester.getSize(find.byType(FindBarDivider));
    expect(size.height, 18);
  });
}
