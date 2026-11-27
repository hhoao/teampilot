import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/attention/attention_batch.dart';
import 'package:teampilot/services/attention/attention_cursor.dart';
import 'package:teampilot/services/attention/attention_cursor_store.dart';
import 'package:teampilot/services/attention/attention_event.dart';
import 'package:teampilot/services/attention/attention_inbox.dart';

import '../../support/in_memory_filesystem.dart';

/// [InMemoryFilesystem] whose atomic writes throw while [failWrite] is set.
final class _FlakyWriteFilesystem extends InMemoryFilesystem {
  bool failWrite = false;

  @override
  Future<void> atomicWrite(String path, String content) async {
    if (failWrite) throw StateError('write failed for $path');
    return super.atomicWrite(path, content);
  }
}

final _now = DateTime.utc(2026, 11, 14);

AttentionEvent _event({
  required int seq,
  String eventId = '',
  DateTime? occurredAt,
}) {
  final at = occurredAt ?? _now;
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

/// An inbox whose clock matches [_event]'s occurrence time, so freshness is
/// decided by the test data instead of the wall clock.
AttentionInbox _inbox({
  AttentionCursorStore? store,
  DateTime Function()? clock,
}) => AttentionInbox(
  store: store ?? AttentionCursorStore(),
  clock: clock ?? () => _now,
);

void main() {
  test('ingest deduplicates by eventId and advances the cursor', () async {
    final store = AttentionCursorStore();
    final inbox = _inbox(store: store);
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

  test(
    'out-of-order events still leave the cursor at the highest seq',
    () async {
      final inbox = _inbox(store: AttentionCursorStore());
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
    },
  );

  test('an evicted duplicate at or below the cursor is suppressed', () async {
    final store = AttentionCursorStore(maxSeenEventIds: 1);
    final inbox = _inbox(store: store);
    final seen = <AttentionEvent>[];
    final sub = inbox.fresh.listen(seen.add);

    await inbox.ingest('local', [_event(seq: 1)]);
    await inbox.ingest('local', [_event(seq: 2)]);
    await inbox.ingest('local', [_event(seq: 1)]);
    await Future<void>.delayed(Duration.zero);

    expect(seen.map((event) => event.seq), [1, 2]);
    expect(inbox.cursorFor('local')?.seq, 2);
    await sub.cancel();
    await inbox.dispose();
  });

  test('expired events advance the cursor but do not notify', () async {
    final now = DateTime.utc(2026, 11, 14);
    final inbox = _inbox(clock: () => now.add(const Duration(days: 8)));
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
    final inbox = _inbox(store: AttentionCursorStore());
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

  test('skipGap does not rewind an older-epoch cursor', () async {
    final store = AttentionCursorStore();
    final inbox = _inbox(store: store);
    final seen = <AttentionEvent>[];
    final sub = inbox.fresh.listen(seen.add);

    await store.remember(
      'local',
      const AttentionCursor(authorityId: 'desk', epoch: 8, seq: 5),
      const [],
    );
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
    await Future<void>.delayed(Duration.zero);

    expect(inbox.cursorFor('local')?.epoch, 8);
    expect(inbox.cursorFor('local')?.seq, 5);
    expect(seen, isEmpty);
    await sub.cancel();
    await inbox.dispose();
  });

  test(
    'a failed cursor save produces no fresh emission and leaves the previous '
    'cursor advertised',
    () async {
      final fs = _FlakyWriteFilesystem();
      final store = AttentionCursorStore(
        fs: fs,
        path: '/tp/attention/cursors.json',
      );
      await store.load();
      expect(
        await store.remember(
          'local',
          const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 1),
          const [],
        ),
        isTrue,
      );

      final inbox = _inbox(store: store);
      final seen = <AttentionEvent>[];
      final sub = inbox.fresh.listen(seen.add);
      fs.failWrite = true;

      await expectLater(
        inbox.ingest('local', [_event(seq: 2)]),
        throwsA(isA<AttentionPersistenceException>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen, isEmpty);
      expect(inbox.cursorFor('local')?.seq, 1);
      await sub.cancel();
      await inbox.dispose();
    },
  );

  test('cursor is retained across inbox instances', () async {
    final store = AttentionCursorStore();
    final first = _inbox(store: store);
    await first.ingest('local', [_event(seq: 7)]);
    await first.dispose();

    final second = _inbox(store: store);
    expect(second.cursorFor('local')?.seq, 7);
    await second.dispose();
  });

  test('clearCursor removes the home position', () async {
    final inbox = _inbox(store: AttentionCursorStore());
    await inbox.ingest('local', [_event(seq: 2)]);
    await inbox.clearCursor('local');

    expect(inbox.cursorFor('local'), isNull);
    await inbox.dispose();
  });
}
