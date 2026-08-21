import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_placement.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/repositories/layout_repository.dart';
import 'package:teampilot/services/floating_workspace/floating_workspace_persistence.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('hydrateFromLayout applies inset placement when fields are set', () {
    final layout = LayoutCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(layout.close);
    addTearDown(floating.close);

    layout.emit(
      layout.state.copyWith(
        preferences: const LayoutPreferences(
          floatingPanelWidth: 640,
          floatingPanelHeight: 400,
          floatingPanelRightInset: 32,
          floatingPanelBottomInset: 48,
          floatingToggleDx: -16,
          floatingToggleDy: -20,
          floatingMaximized: true,
        ),
      ),
    );

    FloatingWorkspacePersistence(layout: layout, floating: floating)
        .hydrateFromLayout();

    expect(
      floating.state.panelPlacement,
      const FloatingPanelPlacement(
        width: 640,
        height: 400,
        rightInset: 32,
        bottomInset: 48,
      ),
    );
    expect(floating.state.toggleOffset, const Offset(-16, -20));
    expect(floating.state.isMaximized, isTrue);
  });

  test('hydrateFromLayout keeps unset placement when prefs fields are null', () {
    final layout = LayoutCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(layout.close);
    addTearDown(floating.close);

    FloatingWorkspacePersistence(layout: layout, floating: floating)
        .hydrateFromLayout();

    expect(floating.state.panelPlacement, isNull);
    expect(floating.state.legacyAbsoluteBounds, isNull);
    expect(floating.state.toggleOffset, const Offset(-24, -72));
    expect(floating.state.isMaximized, isFalse);
  });

  test('hydrateFromLayout keeps legacy absolute for first-layout convert', () {
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
        ),
      ),
    );

    FloatingWorkspacePersistence(layout: layout, floating: floating)
        .hydrateFromLayout();

    expect(floating.state.panelPlacement, isNull);
    expect(
      floating.state.legacyAbsoluteBounds,
      const Rect.fromLTWH(100, 120, 640, 400),
    );
  });

  test('bind persists inset geometry changes to layout preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final layout = LayoutCubit(repository: LayoutRepository(prefs));
    final floating = FloatingWorkspaceCubit();
    addTearDown(layout.close);
    addTearDown(floating.close);

    final persistence = FloatingWorkspacePersistence(
      layout: layout,
      floating: floating,
      persistDebounce: const Duration(milliseconds: 10),
    );
    addTearDown(persistence.dispose);
    persistence.bind();

    floating.setPanelRect(
      const Rect.fromLTWH(40, 50, 600, 360),
      const Size(1400, 900),
    );
    floating.setToggleOffset(const Offset(-12, -18));
    floating.setMaximized(true);
    await waitUntil(
      () => layout.state.preferences.floatingPanelWidth != null,
    );

    final p = floating.state.panelPlacement!;
    expect(layout.state.preferences.floatingPanelWidth, p.width);
    expect(layout.state.preferences.floatingPanelHeight, p.height);
    expect(layout.state.preferences.floatingPanelRightInset, p.rightInset);
    expect(layout.state.preferences.floatingPanelBottomInset, p.bottomInset);
    expect(layout.state.preferences.floatingToggleDx, -12);
    expect(layout.state.preferences.floatingToggleDy, -18);
    expect(layout.state.preferences.floatingMaximized, isTrue);

    final reloaded = await LayoutRepository(prefs).load();
    expect(reloaded.floatingPanelWidth, p.width);
    expect(reloaded.floatingPanelHeight, p.height);
    expect(reloaded.floatingPanelRightInset, p.rightInset);
    expect(reloaded.floatingPanelBottomInset, p.bottomInset);
  });

  test('hydrateFromLayout does not trigger bind save storms', () async {
    final layout = LayoutCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(layout.close);
    addTearDown(floating.close);

    layout.emit(
      layout.state.copyWith(
        preferences: const LayoutPreferences(
          floatingPanelWidth: 720,
          floatingPanelHeight: 480,
          floatingPanelRightInset: 24,
          floatingPanelBottomInset: 76,
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

    expect(layout.state.preferences.floatingPanelRightInset, 24);
    expect(layout.state.preferences.floatingPanelBottomInset, 76);
  });
}
