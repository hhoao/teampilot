import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/layout_cubit.dart';

void main() {
  test('openMobileWorkspaceDrawer defaults to chat', () async {
    final cubit = LayoutCubit();
    addTearDown(cubit.close);
    // Pretend prefs loaded
    await cubit.setSidebarVisible(false);
    await cubit.setRightToolsVisible(false);

    cubit.openMobileWorkspaceDrawer();

    expect(cubit.state.mobileDrawerMode, MobileDrawerMode.chat);
    expect(cubit.state.preferences.sidebarVisible, isTrue);
    expect(cubit.state.preferences.rightToolsVisible, isFalse);
  });

  test('setMobileDrawerMode tools flips intents without losing mode memory on close', () async {
    final cubit = LayoutCubit();
    addTearDown(cubit.close);
    cubit.openMobileWorkspaceDrawer();
    await cubit.setMobileDrawerMode(MobileDrawerMode.tools, composeLanding: false);

    expect(cubit.state.mobileDrawerMode, MobileDrawerMode.tools);
    expect(cubit.state.preferences.rightToolsVisible, isTrue);

    cubit.closeMobileWorkspaceDrawer(composeLanding: false);
    expect(cubit.state.preferences.sidebarVisible, isFalse);
    expect(cubit.state.preferences.rightToolsVisible, isFalse);
    expect(cubit.state.mobileDrawerMode, MobileDrawerMode.tools);

    cubit.openMobileWorkspaceDrawer(composeLanding: false);
    expect(cubit.state.mobileDrawerMode, MobileDrawerMode.tools);
    expect(cubit.state.preferences.rightToolsVisible, isTrue);
  });

  test('setMobileDrawerMode never emits both sides false while switching', () async {
    final cubit = LayoutCubit();
    addTearDown(cubit.close);
    cubit.openMobileWorkspaceDrawer();
    await cubit.setMobileDrawerMode(MobileDrawerMode.chat, composeLanding: false);

    final states = <LayoutState>[];
    final sub = cubit.stream.listen(states.add);
    addTearDown(sub.cancel);

    await cubit.setMobileDrawerMode(MobileDrawerMode.tools, composeLanding: false);

    for (final s in states) {
      expect(
        s.preferences.sidebarVisible || s.preferences.rightToolsVisible,
        isTrue,
        reason: 'Drawer should not flash closed during mode switch',
      );
    }
  });

  test('setMobileDrawerMode tools with composeLanding sets landing override', () async {
    final cubit = LayoutCubit();
    addTearDown(cubit.close);
    cubit.openMobileWorkspaceDrawer(composeLanding: true);
    await cubit.setMobileDrawerMode(MobileDrawerMode.tools, composeLanding: true);

    expect(cubit.state.landingRightToolsOverride, isTrue);
  });

  test('legacy setSidebarVisible(true) syncs mobileDrawerMode to chat', () async {
    final cubit = LayoutCubit();
    addTearDown(cubit.close);
    await cubit.setMobileDrawerMode(MobileDrawerMode.tools);
    await cubit.setSidebarVisible(false);
    await cubit.setRightToolsVisible(false);

    await cubit.setSidebarVisible(true);

    expect(cubit.state.mobileDrawerMode, MobileDrawerMode.chat);
    cubit.openMobileWorkspaceDrawer();
    expect(cubit.state.preferences.sidebarVisible, isTrue);
    expect(cubit.state.preferences.rightToolsVisible, isFalse);
  });

  test('legacy setRightToolsVisible(true) syncs mobileDrawerMode to tools', () async {
    final cubit = LayoutCubit();
    addTearDown(cubit.close);
    await cubit.setMobileDrawerMode(MobileDrawerMode.chat);
    await cubit.setSidebarVisible(false);
    await cubit.setRightToolsVisible(false);

    await cubit.setRightToolsVisible(true);

    expect(cubit.state.mobileDrawerMode, MobileDrawerMode.tools);
    cubit.openMobileWorkspaceDrawer();
    expect(cubit.state.preferences.rightToolsVisible, isTrue);
  });

  test('legacy intents: tools wins when both sides become visible', () async {
    final cubit = LayoutCubit();
    addTearDown(cubit.close);
    await cubit.setRightToolsVisible(false);

    await cubit.setSidebarVisible(true);
    expect(cubit.state.mobileDrawerMode, MobileDrawerMode.chat);

    await cubit.setRightToolsVisible(true);
    expect(cubit.state.mobileDrawerMode, MobileDrawerMode.tools);
  });
}
