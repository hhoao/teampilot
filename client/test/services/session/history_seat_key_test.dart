import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/history_seat_key.dart';

void main() {
  test('simple empty member uses sessionId as shell segment', () {
    expect(
      historySeatKey(sessionId: 's1', selectedMemberId: ''),
      's1|s1',
    );
    expect(
      shellMemberIdForHistory(sessionId: 's1', selectedMemberId: '  '),
      's1',
    );
  });

  test('team member uses trimmed member id', () {
    expect(
      historySeatKey(sessionId: 's1', selectedMemberId: ' lead '),
      's1|lead',
    );
  });

  group('isHistorySeatHot', () {
    test('warm seat: inactive route and member not running stops live refresh',
        () {
      // SessionChatView uses this gate before start / after routeActive flips:
      // !isHistorySeatHot → await _liveRefresh?.stop().
      expect(
        isHistorySeatHot(routeActive: false, isMemberRunning: false),
        isFalse,
      );
    });

    test('hot when route is active even if member idle', () {
      expect(
        isHistorySeatHot(routeActive: true, isMemberRunning: false),
        isTrue,
      );
    });

    test('hot when member PTY running even if route inactive', () {
      expect(
        isHistorySeatHot(routeActive: false, isMemberRunning: true),
        isTrue,
      );
    });
  });
}
