import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/session_history_review_submit.dart';

void main() {
  group('shouldSwitchToTerminalAfterHistorySubmit', () {
    test('false preference keeps History (default)', () {
      expect(shouldSwitchToTerminalAfterHistorySubmit(false), isFalse);
    });

    test('true preference switches to Terminal', () {
      expect(shouldSwitchToTerminalAfterHistorySubmit(true), isTrue);
    });
  });
}
