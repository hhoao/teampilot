import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/attention/attention_batch.dart';
import 'package:teampilot/services/attention/attention_cursor_store.dart';
import 'package:teampilot/services/attention/attention_event.dart';
import 'package:teampilot/services/attention/attention_inbox.dart';

AttentionEvent _event({
  required int seq,
  String eventId = '',
  DateTime? occurredAt,
}) {
  final at = occurredAt ?? DateTime.utc(2026, 11, 14);
  return AttentionEvent(
    eventId: eventId.isEmpty ? 'evt-$seq' : eventId,
    authorityId: 'desk',
    epoch: 7,
    seq: seq,
    sessionId: 's1',
    memberId: 'dev',
    kind: AttentionKind.idle,
    occurredAt: at,
    expiresAt: at.add(const Duration(days: 7)),
  );
}

void main() {
  test('ingest deduplicates by eventId and advances the cursor', () async {
    final store = AttentionCursorStore();
    final inbox = AttentionInbox(store: store);
    final seen = <AttentionEvent>[];
    final sub = inbox.fresh.listen(seen.add);

    await inbox.ingest('local', [_event(seq: 1)]);
    await inbox.ingest('local', [_event(seq: 1), _event(seq: 2)]);
    await Future<void>.delayed(Duration.zero);

    expect(seen.map((event) => event.seq), [1, 2]);
    expect(inbox.cursorFor('local')?.seq, 2);
    await sub.cancel();
    await inbox.dispose();
  });

  test('out-of-order events still leave the cursor at the highest seq',
      () async {
    final inbox = AttentionInbox(store: AttentionCursorStore());
    final seen = <AttentionEvent>[];
    final sub = inbox.fresh.listen(seen.add);

    await inbox.ingest('local', [_event(seq: 3)]);
    await inbox.ingest('local', [_event(seq: 1), _event(seq: 2)]);
    await Future<void>.delayed(Duration.zero);

    // `fresh` is a live stream: seq 3 was already emitted before the late
    // batch arrived, so delivery keeps arrival order while the cursor still
    // lands on the highest seq.
    expect(seen.map((event) => event.seq), [3, 1, 2]);
    expect(inbox.cursorFor('local')?.seq, 3);
    await sub.cancel();
    await inbox.dispose();
  });

  test('expired events advance the cursor but do not notify', () async {
    final now = DateTime.utc(2026, 11, 14);
    final inbox = AttentionInbox(
      store: AttentionCursorStore(),
      clock: () => now.add(const Duration(days: 8)),
    );
    final seen = <AttentionEvent>[];
    final sub = inbox.fresh.listen(seen.add);

    await inbox.ingest('local', [_event(seq: 1, occurredAt: now)]);
    await Future<void>.delayed(Duration.zero);

    expect(seen, isEmpty);
    expect(inbox.cursorFor('local')?.seq, 1);
    await sub.cancel();
    await inbox.dispose();
  });

  test('skipGap advances the cursor past an unrecoverable range', () async {
    final inbox = AttentionInbox(store: AttentionCursorStore());
    await inbox.skipGap(
      'local',
      const AttentionBatch(
        authorityId: 'desk',
        epoch: 7,
        fromSeq: 3,
        toSeq: 3,
        events: [],
        gap: true,
      ),
    );

    expect(inbox.cursorFor('local')?.seq, 3);
  });

  test('cursor is retained across inbox instances', () async {
    final store = AttentionCursorStore();
    final first = AttentionInbox(store: store);
    await first.ingest('local', [_event(seq: 7)]);
    await first.dispose();

    final second = AttentionInbox(store: store);
    expect(second.cursorFor('local')?.seq, 7);
    await second.dispose();
  });

  test('clearCursor removes the home position', () async {
    final inbox = AttentionInbox(store: AttentionCursorStore());
    await inbox.ingest('local', [_event(seq: 2)]);
    await inbox.clearCursor('local');

    expect(inbox.cursorFor('local'), isNull);
    await inbox.dispose();
  });
}
