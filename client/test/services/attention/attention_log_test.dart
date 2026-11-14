import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/attention/attention_cursor.dart';
import 'package:teampilot/services/attention/attention_event.dart';
import 'package:teampilot/services/attention/attention_log.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  setUp(() => logSeq = 0);

  test('append assigns monotonic seq and emits after the write', () async {
    final log = AttentionLog(
      authorityId: 'desk',
      epoch: 7,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );
    final seen = <AttentionEvent>[];
    final sub = log.appended.listen(seen.add);

    final first = await log.append(
      sessionId: 's1',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    final second = await log.append(
      sessionId: 's1',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    await Future<void>.delayed(Duration.zero);

    expect(first.seq, 1);
    expect(second.seq, 2);
    expect(first.eventId, 'evt-0');
    expect(second.eventId, 'evt-1');
    expect(seen.map((event) => event.seq), [1, 2]);
    expect(log.latestSeq, 2);
    expect(log.earliestSeq, 1);

    await sub.cancel();
    await log.close();
  });

  test('slice returns only events after the cursor', () async {
    final log = AttentionLog(
      authorityId: 'desk',
      epoch: 7,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );
    for (var i = 0; i < 3; i++) {
      await log.append(
        sessionId: 's$i',
        memberId: 'dev',
        kind: AttentionKind.idle,
      );
    }

    final batch = log.slice(
      cursor: const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 1),
      limit: 1,
    );

    expect(batch.events.single.seq, 2);
    expect(batch.fromSeq, 2);
    expect(batch.toSeq, 2);
    expect(batch.gap, isFalse);
    await log.close();
  });

  test('slice reports a gap when the cursor is before the retained window',
      () async {
    final log = AttentionLog(
      authorityId: 'desk',
      epoch: 7,
      maxEvents: 2,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );
    for (var i = 0; i < 3; i++) {
      await log.append(
        sessionId: 's$i',
        memberId: 'dev',
        kind: AttentionKind.idle,
      );
    }

    final batch = log.slice(
      cursor: const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 0),
    );

    expect(batch.gap, isTrue);
    expect(batch.events.map((event) => event.seq), [2, 3]);
    expect(batch.toSeq, 3);
    await log.close();
  });

  test('file-backed log reloads events and continues the sequence', () async {
    final fs = InMemoryFilesystem();
    final path = '/tp/attention/log-7.jsonl';
    final first = await AttentionLog.open(
      authorityId: 'desk',
      epoch: 7,
      fs: fs,
      path: path,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );
    await first.append(
      sessionId: 's1',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    await first.append(
      sessionId: 's2',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    await first.close();

    final second = await AttentionLog.open(
      authorityId: 'desk',
      epoch: 7,
      fs: fs,
      path: path,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );

    expect(second.events.map((event) => event.seq), [1, 2]);
    expect(second.latestSeq, 2);
    final third = await second.append(
      sessionId: 's3',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    expect(third.seq, 3);
    await second.close();
  });

  test('corrupt lines are skipped', () async {
    final fs = InMemoryFilesystem();
    final path = '/tp/attention/log-7.jsonl';
    fs.files[path] = 'not json\n';
    final log = await AttentionLog.open(
      authorityId: 'desk',
      epoch: 7,
      fs: fs,
      path: path,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );

    expect(log.events, isEmpty);
    expect(log.latestSeq, 0);
    final event = await log.append(
      sessionId: 's1',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    expect(event.seq, 1);
    await log.close();
  });
}

var logSeq = 0;
