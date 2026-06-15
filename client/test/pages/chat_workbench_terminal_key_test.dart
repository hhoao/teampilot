import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/chat_workbench_terminal.dart';

void main() {
  group('chatWorkbenchTerminalViewKey', () {
    test('running key is stable and independent of session identity', () {
      // Two different running sessions must yield the SAME key so the
      // AnimatedSwitcher reuses the TerminalView element (engine swap) instead
      // of remounting it and rebuilding the glyph cache.
      final a = chatWorkbenchTerminalViewKey(loading: false, running: true);
      final b = chatWorkbenchTerminalViewKey(loading: false, running: true);
      expect(a, equals(b));
    });

    test('loading, running, and placeholder keys are distinct', () {
      final loading = chatWorkbenchTerminalViewKey(loading: true, running: false);
      final running = chatWorkbenchTerminalViewKey(loading: false, running: true);
      final placeholder =
          chatWorkbenchTerminalViewKey(loading: false, running: false);
      expect(loading, isNot(equals(running)));
      expect(running, isNot(equals(placeholder)));
      expect(loading, isNot(equals(placeholder)));
    });

    test('loading takes precedence over running', () {
      final loading = chatWorkbenchTerminalViewKey(loading: true, running: true);
      final running = chatWorkbenchTerminalViewKey(loading: false, running: true);
      expect(loading, isNot(equals(running)));
    });
  });
}
