import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/cursor_title_attention.dart';

void main() {
  group('detectCursorTitleAttention', () {
    test('bare Cursor Agent native title is a no-op', () {
      expect(detectCursorTitleAttention('Cursor Agent'), isNull);
      expect(detectCursorTitleAttention('cursor agent'), isNull);
      expect(detectCursorTitleAttention('  Cursor Agent  '), isNull);
    });

    test('synthesized action-required title is waiting', () {
      expect(
        detectCursorTitleAttention('Cursor - action required'),
        AgentSeatAttention.waiting,
      );
    });

    test('matches permission and waiting keywords', () {
      expect(
        detectCursorTitleAttention('Cursor - permission needed'),
        AgentSeatAttention.waiting,
      );
      expect(
        detectCursorTitleAttention('Cursor waiting for you'),
        AgentSeatAttention.waiting,
      );
    });

    test('non-matching titles are not waiting', () {
      expect(detectCursorTitleAttention('Cursor ready'), isNull);
      expect(detectCursorTitleAttention(''), isNull);
    });
  });
}
