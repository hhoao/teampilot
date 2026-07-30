import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/repositories/layout_repository.dart';
import 'package:teampilot/services/floating_workspace/floating_workspace_persistence.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('hydrateFromLayout applies saved geometry when fields are set', () {
    final layout = LayoutCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(layout.close);
    addTearDown(floating.close);

    layout.emit(
      layout.state.copyWith(
        preferences: const LayoutPreferences(
          floatingPanelLeft: 100,
          floatingPanelTop: 120,
          floatingPanelWidth: 640,
          floatingPanelHeight: 400,
          floatingToggleDx: -16,
          floatingToggleDy: -20,
          floatingMaximized: true,
        ),
      ),
    );

    FloatingWorkspacePersistence(layout: layout, floating: floating)
        .hydrateFromLayout();

    expect(floating.state.panelBounds, const Rect.fromLTWH(100, 120, 640, 400));
    expect(floating.state.toggleOffset, const Offset(-16, -20));
    expect(floating.state.isMaximized, isTrue);
  });

  test('hydrateFromLayout keeps cubit defaults when prefs fields are null', () {
    final layout = LayoutCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(layout.close);
    addTearDown(floating.close);

    FloatingWorkspacePersistence(layout: layout, floating: floating)
        .hydrateFromLayout();

    expect(floating.state.panelBounds, const Rect.fromLTWH(80, 80, 720, 480));
    expect(floating.state.toggleOffset, const Offset(-24, -24));
    expect(floating.state.isMaximized, isFalse);
  });

  test('bind persists geometry changes to layout preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final layout = LayoutCubit(repository: LayoutRepository(prefs));
    final floating = FloatingWorkspaceCubit();
    addTearDown(layout.close);
    addTearDown(floating.close);

    final persistence = FloatingWorkspacePersistence(
      layout: layout,
      floating: floating,
    );
    addTearDown(persistence.dispose);
    persistence.bind();

    floating.setPanelBounds(const Rect.fromLTWH(40, 50, 600, 360));
    floating.setToggleOffset(const Offset(-12, -18));
    floating.setMaximized(true);
    await Future<void>.delayed(Duration.zero);

    expect(layout.state.preferences.floatingPanelLeft, 40);
    expect(layout.state.preferences.floatingPanelTop, 50);
    expect(layout.state.preferences.floatingPanelWidth, 600);
    expect(layout.state.preferences.floatingPanelHeight, 360);
    expect(layout.state.preferences.floatingToggleDx, -12);
    expect(layout.state.preferences.floatingToggleDy, -18);
    expect(layout.state.preferences.floatingMaximized, isTrue);

    final reloaded = await LayoutRepository(prefs).load();
    expect(reloaded.floatingPanelLeft, 40);
    expect(reloaded.floatingPanelTop, 50);
    expect(reloaded.floatingPanelWidth, 600);
    expect(reloaded.floatingPanelHeight, 360);
    expect(reloaded.floatingToggleDx, -12);
    expect(reloaded.floatingToggleDy, -18);
    expect(reloaded.floatingMaximized, isTrue);
  });

  test('hydrateFromLayout does not trigger bind save storms', () async {
    final layout = LayoutCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(layout.close);
    addTearDown(floating.close);

    layout.emit(
      layout.state.copyWith(
        preferences: const LayoutPreferences(
          floatingPanelLeft: 80,
          floatingPanelTop: 80,
          floatingPanelWidth: 720,
          floatingPanelHeight: 480,
          floatingToggleDx: -24,
          floatingToggleDy: -24,
        ),
      ),
    );

    final persistence = FloatingWorkspacePersistence(
      layout: layout,
      floating: floating,
    );
    addTearDown(persistence.dispose);
    persistence.bind();
    persistence.hydrateFromLayout();
    await Future<void>.delayed(Duration.zero);

    expect(layout.state.preferences.floatingPanelLeft, 80);
    expect(layout.state.preferences.floatingPanelTop, 80);
    expect(layout.state.preferences.floatingPanelWidth, 720);
    expect(layout.state.preferences.floatingPanelHeight, 480);
    expect(layout.state.preferences.floatingToggleDx, -24);
    expect(layout.state.preferences.floatingToggleDy, -24);
  });
}
