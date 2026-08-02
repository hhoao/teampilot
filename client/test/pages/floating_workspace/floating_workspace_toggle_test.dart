import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/floating_workspace/floating_workspace_toggle.dart';
import 'package:teampilot/theme/workspace_surface_layers.dart';

void main() {
  Widget wrap(FloatingWorkspaceCubit cubit, {ThemeData? theme}) {
    return MaterialApp(
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider.value(
        value: cubit,
        child: const Scaffold(
          body: Stack(children: [FloatingWorkspaceToggle()]),
        ),
      ),
    );
  }

  BoxDecoration pillDecoration(WidgetTester tester) {
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(const Key('floating_workspace_toggle')),
        matching: find.byType(AnimatedContainer),
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('hover lifts and switches fill toward accent', (tester) async {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);

    final theme = ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
    );
    await tester.pumpWidget(wrap(cubit, theme: theme));
    await tester.pump();

    final cs = theme.colorScheme;
    final idle = floatingWorkspaceToggleFill(
      colorScheme: cs,
      brightness: Brightness.light,
      hovered: false,
    );
    final hovered = floatingWorkspaceToggleFill(
      colorScheme: cs,
      brightness: Brightness.light,
      hovered: true,
    );
    expect(idle, cs.workspaceCard);
    expect(hovered, cs.workspaceInset);
    expect(hovered, isNot(idle));
    expect(pillDecoration(tester).color, idle);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('floating_workspace_toggle'))),
    );
    await tester.pumpAndSettle();

    expect(pillDecoration(tester).color, hovered);

    final slide = tester.widget<AnimatedSlide>(
      find.descendant(
        of: find.byKey(const Key('floating_workspace_toggle')),
        matching: find.byType(AnimatedSlide),
      ),
    );
    expect(slide.offset.dy, lessThan(0));
  });

  testWidgets('drag suppresses hover lift', (tester) async {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(wrap(cubit));
    await tester.pump();

    final toggle = find.byKey(const Key('floating_workspace_toggle'));
    final center = tester.getCenter(toggle);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(center);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.moveBy(const Offset(-20, -10));
    await tester.pump();

    final slide = tester.widget<AnimatedSlide>(
      find.descendant(of: toggle, matching: find.byType(AnimatedSlide)),
    );
    expect(slide.offset, Offset.zero);

    await gesture.up();
  });
}
