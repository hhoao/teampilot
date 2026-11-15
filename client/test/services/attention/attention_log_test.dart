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

  test('an event is on disk before appended fires', () async {
    final fs = InMemoryFilesystem();
    const path = '/tp/attention/log-7.jsonl';
    final log = await AttentionLog.open(
      authorityId: 'desk',
      epoch: 7,
      fs: fs,
      path: path,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );
    final onDisk = <String?>[];
    final sub = log.appended.listen((event) => onDisk.add(fs.files[path]));

    final event = await log.append(
      sessionId: 's1',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    await Future<void>.delayed(Duration.zero);

    expect(onDisk, hasLength(1));
    expect(onDisk.single, contains(event.eventId));

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

  test(
    'a failed existing-log read fails open without changing disk; retry '
    'loads and continues the sequence',
    () async {
      final fs = _FlakyReadFilesystem();
      const path = '/tp/attention/log-7.jsonl';
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
      await first.close();
      final before = fs.files[path];

      fs.failRead = true;
      await expectLater(
        AttentionLog.open(
          authorityId: 'desk',
          epoch: 7,
          fs: fs,
          path: path,
          clock: () => DateTime.utc(2026, 11, 14),
          eventId: () => 'evt-${logSeq++}',
        ),
        throwsA(isA<StateError>()),
      );
      expect(fs.files[path], before);

      fs.failRead = false;
      final reopened = await AttentionLog.open(
        authorityId: 'desk',
        epoch: 7,
        fs: fs,
        path: path,
        clock: () => DateTime.utc(2026, 11, 14),
        eventId: () => 'evt-${logSeq++}',
      );
      final next = await reopened.append(
        sessionId: 's2',
        memberId: 'dev',
        kind: AttentionKind.idle,
      );
      expect(next.seq, 2);
      await reopened.close();
    },
  );

  test('a failed append still emits and the next append reconciles it',
      () async {
    final fs = _FlakyFilesystem();
    const path = '/tp/attention/log-7.jsonl';
    final log = await AttentionLog.open(
      authorityId: 'desk',
      epoch: 7,
      fs: fs,
      path: path,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );
    final seen = <AttentionEvent>[];
    final sub = log.appended.listen(seen.add);

    fs.fail = true;
    final first = await log.append(
      sessionId: 's1',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    await Future<void>.delayed(Duration.zero);
    expect(seen.map((event) => event.eventId), [first.eventId]);
    expect(fs.files[path] ?? '', isNot(contains(first.eventId)));

    fs.fail = false;
    final second = await log.append(
      sessionId: 's2',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );

    final content = fs.files[path] ?? '';
    expect(content, contains(first.eventId));
    expect(content, contains(second.eventId));

    await sub.cancel();
    await log.close();
  });

  test('concurrent appends keep call order', () async {
    final log = AttentionLog(
      authorityId: 'desk',
      epoch: 7,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );

    final events = await Future.wait([
      for (var i = 0; i < 20; i++)
        log.append(
          sessionId: 's$i',
          memberId: 'dev',
          kind: AttentionKind.idle,
        ),
    ]);

    expect(
      events.map((event) => event.seq),
      [for (var i = 1; i <= 20; i++) i],
    );
    expect(
      events.map((event) => event.sessionId),
      [for (var i = 0; i < 20; i++) 's$i'],
    );
    expect(log.latestSeq, 20);
    await log.close();
  });

  test('an append queued before close still runs; later appends fail',
      () async {
    final log = AttentionLog(
      authorityId: 'desk',
      epoch: 7,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );

    final queued = log.append(
      sessionId: 's1',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    final closed = log.close();
    await expectLater(
      log.append(
        sessionId: 's2',
        memberId: 'dev',
        kind: AttentionKind.idle,
      ),
      throwsStateError,
    );

    expect((await queued).seq, 1);
    await closed;
  });
}

var logSeq = 0;

/// An [InMemoryFilesystem] whose writes can be made to fail on demand.
final class _FlakyFilesystem extends InMemoryFilesystem {
  bool fail = false;

  @override
  Future<void> appendString(String path, String content) async {
    if (fail) throw StateError('append failed');
    return super.appendString(path, content);
  }

  @override
  Future<void> atomicWrite(String path, String content) async {
    if (fail) throw StateError('atomic write failed');
    return super.atomicWrite(path, content);
  }
}

/// An [InMemoryFilesystem] whose reads can be made to fail on demand.
final class _FlakyReadFilesystem extends InMemoryFilesystem {
  bool failRead = false;

  @override
  Future<String?> readString(String path) async {
    if (failRead) throw StateError('read failed');
    return super.readString(path);
  }
}
