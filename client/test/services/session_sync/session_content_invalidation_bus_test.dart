import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session_sync/session_content_invalidation_bus.dart';

void main() {
  test('publishes the session id and member id', () async {
    final future = SessionContentInvalidationBus.stream.first;
    SessionContentInvalidationBus.publish(sessionId: ' s1 ', memberId: 'dev');

    final event = await future;

    expect(event.sessionId, 's1');
    expect(event.memberId, 'dev');
  });

  test('ignores empty session ids', () async {
    final events = <SessionContentInvalidation>[];
    final sub = SessionContentInvalidationBus.stream.listen(events.add);
    SessionContentInvalidationBus.publish(sessionId: '   ');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();

    expect(events, isEmpty);
  });
}
