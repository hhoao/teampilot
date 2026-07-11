import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/layout_preferences.dart';

void main() {
  test('fromJson ignores legacy tool layout keys', () {
    final prefs = LayoutPreferences.fromJson(const {
      'toolPlacement': 'bottom',
      'toolsArrangement': 'stacked',
      'bottomToolsHeight': 300,
      'membersSplit': 0.5,
    });
    expect(prefs.rightToolsWidth, LayoutPreferences.defaultRightToolsWidth);
    expect(prefs.membersVisible, isTrue);
    expect(prefs.fileTreeVisible, isTrue);
  });

  test('sidebarVisible defaults true and round-trips', () {
    expect(const LayoutPreferences().sidebarVisible, isTrue);
    final parsed = LayoutPreferences.fromJson(const {'sidebarVisible': false});
    expect(parsed.sidebarVisible, isFalse);
    expect(parsed.toJson()['sidebarVisible'], isFalse);
  });

  test('workspace panes keep large sizes and only clamp mins', () {
    final prefs = LayoutPreferences.fromJson(const {
      'sidebarWidth': 900,
      'rightToolsWidth': 800,
      'workspaceTerminalHeight': 700,
    });
    expect(prefs.sidebarWidth, 900);
    expect(prefs.rightToolsWidth, 800);
    expect(prefs.workspaceTerminalHeight, 700);

    final clamped = const LayoutPreferences().copyWith(
      sidebarWidth: 10,
      rightToolsWidth: 10,
      workspaceTerminalHeight: 10,
    );
    expect(clamped.sidebarWidth, LayoutPreferences.minSidebarWidth);
    expect(clamped.rightToolsWidth, LayoutPreferences.minRightToolsWidth);
    expect(
      clamped.workspaceTerminalHeight,
      LayoutPreferences.minWorkspaceTerminalHeight,
    );
  });
}
