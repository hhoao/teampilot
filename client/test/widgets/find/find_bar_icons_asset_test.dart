import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/find/find_bar_widgets.dart';

/// Guards the find-widget SVG icons against being dropped from the asset
/// bundle again: `assets/icons/svg/` is a separate pubspec asset entry (the
/// `assets/icons/` directory entry is not recursive), so a missing entry here
/// silently renders empty icons instead of failing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all find-widget svg icons are bundled and non-empty', () async {
    const icons = [
      FindBarIcons.caseSensitive,
      FindBarIcons.wholeWord,
      FindBarIcons.regexp,
      FindBarIcons.upperCase,
      FindBarIcons.replace,
      FindBarIcons.replaceAll,
    ];
    for (final path in icons) {
      final data = await rootBundle.load(path);
      expect(
        data.lengthInBytes,
        greaterThan(0),
        reason: '$path missing or empty in the asset bundle',
      );
    }
  });
}
