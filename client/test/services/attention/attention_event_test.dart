import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/attention/attention_batch.dart';
import 'package:teampilot/services/attention/attention_cursor.dart';
import 'package:teampilot/services/attention/attention_event.dart';

void main() {
  test('AttentionEvent round-trips through JSON', () {
    final occurred = DateTime.utc(2026, 11, 14, 10, 30);
    final event = AttentionEvent(
      eventId: 'evt-1',
      authorityId: 'desk',
      epoch: 7,
      seq: 3,
      sessionId: 's1',
      memberId: 'dev',
      turnId: 'turn-1',
      workspaceId: 'ws1',
      kind: AttentionKind.idle,
      occurredAt: occurred,
      expiresAt: occurred.add(const Duration(days: 7)),
      title: 'Build finished',
      message: 'Ready',
      payload: const {'reason': 'turn.completed'},
    );

    final decoded = AttentionEvent.fromJson(event.toJson());

    expect(decoded, isNotNull);
    expect(decoded!.eventId, 'evt-1');
    expect(decoded.authorityId, 'desk');
    expect(decoded.epoch, 7);
    expect(decoded.seq, 3);
    expect(decoded.sessionId, 's1');
    expect(decoded.memberId, 'dev');
    expect(decoded.turnId, 'turn-1');
    expect(decoded.workspaceId, 'ws1');
    expect(decoded.kind, AttentionKind.idle);
    expect(decoded.occurredAt, occurred);
    expect(decoded.expiresAt, occurred.add(const Duration(days: 7)));
    expect(decoded.title, 'Build finished');
    expect(decoded.message, 'Ready');
    expect(decoded.payload, {'reason': 'turn.completed'});
  });

  test('AttentionEvent rejects missing identity or seq', () {
    expect(AttentionEvent.fromJson(const {}), isNull);
    expect(
      AttentionEvent.fromJson(const {
        'eventId': 'evt-1',
        'authorityId': 'desk',
        'sessionId': 's1',
        'kind': 'idle',
        'epoch': 7,
        'seq': 0,
      }),
      isNull,
    );
  });

  test('AttentionCursor advances only forward in the same epoch', () {
    const cursor = AttentionCursor(authorityId: 'desk', epoch: 7, seq: 3);
    final event = AttentionEvent(
      eventId: 'evt-4',
      authorityId: 'desk',
      epoch: 7,
      seq: 4,
      sessionId: 's1',
      memberId: 'dev',
      kind: AttentionKind.idle,
      occurredAt: DateTime.utc(2026, 11, 14),
      expiresAt: DateTime.utc(2026, 11, 21),
    );

    expect(cursor.advance(event).seq, 4);
    expect(cursor.advance(event).advance(event).seq, 4);
    expect(
      cursor
          .advance(
            AttentionEvent(
              eventId: 'evt-new-epoch',
              authorityId: 'desk',
              epoch: 8,
              seq: 1,
              sessionId: 's1',
              memberId: 'dev',
              kind: AttentionKind.idle,
              occurredAt: DateTime.utc(2026, 11, 14),
              expiresAt: DateTime.utc(2026, 11, 21),
            ),
          )
          .epoch,
      8,
    );
  });

  test('AttentionBatch round-trips through JSON', () {
    final occurred = DateTime.utc(2026, 11, 14);
    final batch = AttentionBatch(
      authorityId: 'desk',
      epoch: 7,
      fromSeq: 2,
      toSeq: 2,
      events: [
        AttentionEvent(
          eventId: 'evt-2',
          authorityId: 'desk',
          epoch: 7,
          seq: 2,
          sessionId: 's1',
          memberId: 'dev',
          kind: AttentionKind.idle,
          occurredAt: occurred,
          expiresAt: occurred.add(const Duration(days: 7)),
        ),
      ],
    );

    final decoded = AttentionBatch.fromJson(batch.toJson());

    expect(decoded, isNotNull);
    expect(decoded!.authorityId, 'desk');
    expect(decoded.epoch, 7);
    expect(decoded.fromSeq, 2);
    expect(decoded.toSeq, 2);
    expect(decoded.events.single.eventId, 'evt-2');
    expect(decoded.gap, isFalse);
  });
}
