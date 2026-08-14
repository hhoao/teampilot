import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/html_view_mode_store.dart';

void main() {
  test('defaults to edit for unknown paths', () {
    final store = HtmlViewModeStore();
    expect(store.modeFor('/a.html'), HtmlViewMode.edit);
  });

  test('remembers per-path modes', () {
    final store = HtmlViewModeStore();
    store.setMode('/a.html', HtmlViewMode.preview);
    store.setMode('/b.html', HtmlViewMode.edit);
    expect(store.modeFor('/a.html'), HtmlViewMode.preview);
    expect(store.modeFor('/b.html'), HtmlViewMode.edit);
    expect(store.modeFor('/c.html'), HtmlViewMode.edit);
  });

  test('setMode with same value does not notify', () {
    final store = HtmlViewModeStore();
    var notified = 0;
    store.addListener(() => notified++);
    store.setMode('/a.html', HtmlViewMode.preview);
    store.setMode('/a.html', HtmlViewMode.preview);
    expect(notified, 1);
  });
}
