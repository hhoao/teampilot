import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/svg_view_mode_store.dart';

void main() {
  test('defaults to preview and is per-path in-session', () {
    final store = SvgViewModeStore();
    addTearDown(store.dispose);

    expect(store.modeFor('/a/x.svg'), SvgViewMode.preview);

    var notifications = 0;
    store.addListener(() => notifications++);

    store.setMode('/a/x.svg', SvgViewMode.edit);
    expect(store.modeFor('/a/x.svg'), SvgViewMode.edit);
    expect(notifications, 1);

    // Same mode again: no redundant notification.
    store.setMode('/a/x.svg', SvgViewMode.edit);
    expect(notifications, 1);

    // Other paths keep the default.
    expect(store.modeFor('/a/y.svg'), SvgViewMode.preview);
  });
}
