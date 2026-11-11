import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/light_hover_row.dart';

void main() {
  Future<void> runOnDesktop(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Widget wrap(
    Widget child, {
    ColorScheme? scheme,
  }) =>
      MaterialApp(
        theme: scheme == null ? null : ThemeData(colorScheme: scheme),
        home: Scaffold(body: SizedBox(width: 300, height: 36, child: child)),
      );

  Color fillColor(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(LightHoverRow),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    return (box.decoration as BoxDecoration).color!;
  }

  Future<void> hoverRow(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(LightHoverRow)));
    await tester.pump();
  }

  testWidgets('omits the heavy TpHover layers', (tester) async {
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(const LightHoverRow(child: SizedBox.expand())),
      );
      for (final type in [
        Focus,
        Semantics,
        Stack,
        AnimatedContainer,
        TpHover,
      ]) {
        expect(
          find.descendant(
            of: find.byType(LightHoverRow),
            matching: find.byType(type),
          ),
          findsNothing,
          reason: '$type should not be in the lightweight row',
        );
      }
    });
  });

  testWidgets('hover tints the row over its background', (tester) async {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: Brightness.dark,
    );
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(
          LightHoverRow(
            backgroundColor: scheme.secondaryContainer,
            onTap: () {},
            child: const SizedBox.expand(),
          ),
          scheme: scheme,
        ),
      );
      expect(fillColor(tester), scheme.secondaryContainer);

      await hoverRow(tester);
      expect(
        fillColor(tester),
        Color.alphaBlend(
          TpHover.defaultHoverColor(
            tester.element(find.byType(LightHoverRow)),
          ),
          scheme.secondaryContainer,
        ),
      );
    });
  });

  testWidgets('transparent hoverColor keeps the resting fill', (tester) async {
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(
          const LightHoverRow(
            hoverColor: Colors.transparent,
            child: SizedBox.expand(),
          ),
        ),
      );
      await hoverRow(tester);
      // hoverEnabled=false passes Colors.transparent, so scrolling never
      // flashes a highlight while the pointer sits over a row.
      expect(fillColor(tester), Colors.transparent);
    });
  });

  testWidgets('addButtonSemantics marks navigation rows as buttons', (
    tester,
  ) async {
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(
          LightHoverRow(
            addButtonSemantics: true,
            onTap: () {},
            child: const SizedBox.expand(),
          ),
        ),
      );
      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(LightHoverRow),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.button, isTrue);
    });
  });

  testWidgets('trailing appears only while hovered', (tester) async {
    await runOnDesktop(tester, () async {
      var hoverChanges = <bool>[];
      await tester.pumpWidget(
        wrap(
          LightHoverRow(
            expandWidth: true,
            onHoverChanged: hoverChanges.add,
            trailing: const Text('actions'),
            child: const Text('row'),
          ),
        ),
      );
      expect(find.text('actions'), findsNothing);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();

      await gesture.moveTo(tester.getCenter(find.byType(LightHoverRow)));
      await tester.pump();
      expect(find.text('actions'), findsOneWidget);
      expect(hoverChanges, [true]);

      await gesture.moveTo(const Offset(1000, 1000));
      await tester.pump();
      expect(find.text('actions'), findsNothing);
      expect(hoverChanges, [true, false]);
    });
  });

  testWidgets('forceShowTrailing and forceHover keep the row active', (
    tester,
  ) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(
          LightHoverRow(
            forceShowTrailing: true,
            forceHover: true,
            hoverColor: scheme.primary,
            backgroundColor: scheme.surface,
            trailing: const Text('actions'),
            child: const Text('row'),
          ),
          scheme: scheme,
        ),
      );
      expect(find.text('actions'), findsOneWidget);
      expect(
        fillColor(tester),
        Color.alphaBlend(scheme.primary, scheme.surface),
        reason: 'an anchored menu keeps the hover fill visible',
      );
    });
  });

  testWidgets('disabled rows swallow taps and keep the resting fill', (
    tester,
  ) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    await runOnDesktop(tester, () async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          LightHoverRow(
            enabled: false,
            onTap: () => taps++,
            hoverColor: scheme.primary,
            backgroundColor: scheme.surface,
            child: const SizedBox.expand(),
          ),
          scheme: scheme,
        ),
      );
      await hoverRow(tester);
      expect(fillColor(tester), scheme.surface);

      await tester.tap(find.byType(LightHoverRow), warnIfMissed: false);
      expect(taps, 0);
    });
  });
}
