import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/layout_preferences.dart';

void main() {
  test('defaults toolsArrangement to tabs', () {
    expect(const LayoutPreferences().toolsArrangement, ToolsArrangement.tabs);
    expect(
      LayoutPreferences.fromJson(const {}).toolsArrangement,
      ToolsArrangement.tabs,
    );
  });

  test('still honors a persisted stacked preference', () {
    expect(
      LayoutPreferences.fromJson(const {'toolsArrangement': 'stacked'})
          .toolsArrangement,
      ToolsArrangement.stacked,
    );
  });
}
