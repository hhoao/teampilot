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
}
