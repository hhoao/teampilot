import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/agent_runtime/runtime_event_journal.dart';
import 'package:teampilot/services/io/filesystem.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  setUp(FileRuntimeEventJournal.debugResetSeatState);

  test('append assigns monotonically increasing sequences per seat', () async {
    final journal = MemoryRuntimeEventJournal();
    const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');
    final first = await journal.append(
      RuntimeEventEnvelopeDraft.promptSubmitted(
        seat: seat,
        cli: CliTool.codex,
        prompt: 'first',
        occurredAt: DateTime.utc(2026),
      ),
    );
    final second = await journal.append(
      RuntimeEventEnvelopeDraft.promptSubmitted(
        seat: seat,
        cli: CliTool.codex,
        prompt: 'second',
        occurredAt: DateTime.utc(2026),
      ),
    );

    expect([first.sequence, second.sequence], [1, 2]);
    expect(await journal.replay(seat).toList(), [first, second]);
  });

  test('sequences are independent for different seats', () async {
    final journal = MemoryRuntimeEventJournal();
    const a = RuntimeSeatKey(sessionId: 'session', memberId: 'a');
    const b = RuntimeSeatKey(sessionId: 'session', memberId: 'b');

    final first = await journal.append(
      RuntimeEventEnvelopeDraft.promptSubmitted(
        seat: a,
        cli: CliTool.codex,
        prompt: 'one',
        occurredAt: DateTime.utc(2026),
      ),
    );
    final second = await journal.append(
      RuntimeEventEnvelopeDraft.promptSubmitted(
        seat: b,
        cli: CliTool.codex,
        prompt: 'two',
        occurredAt: DateTime.utc(2026),
      ),
    );

    expect(first.sequence, 1);
    expect(second.sequence, 1);
  });

  test(
    'file journal persists seat events and continues their sequence',
    () async {
      final fs = InMemoryFilesystem();
      const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');
      final first = FileRuntimeEventJournal(
        journalRoot: '/runtime/events',
        fs: fs,
      );

      final one = await first.append(
        RuntimeEventEnvelopeDraft.promptSubmitted(
          seat: seat,
          cli: CliTool.codex,
          prompt: 'one',
          occurredAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        ),
      );

      final reopened = FileRuntimeEventJournal(
        journalRoot: '/runtime/events',
        fs: fs,
      );
      final two = await reopened.append(
        RuntimeEventEnvelopeDraft.promptSubmitted(
          seat: seat,
          cli: CliTool.codex,
          prompt: 'two',
          occurredAt: DateTime.utc(2026, 1, 2, 3, 4, 6),
        ),
      );

      expect(two.sequence, 2);
      final replayed = await reopened.replay(seat).toList();
      expect(
        (await reopened.replay(seat, afterSequence: 1).toList()).map(
          (event) => event.prompt,
        ),
        [two.prompt],
      );
      expect(replayed.map((event) => event.sequence), [
        one.sequence,
        two.sequence,
      ]);
      expect(replayed.map((event) => event.prompt), [one.prompt, two.prompt]);
    },
  );

  test('file journals sharing a seat do not reuse stale sequences', () async {
    final fs = InMemoryFilesystem();
    const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');
    final first = FileRuntimeEventJournal(
      journalRoot: '/runtime/events',
      fs: fs,
    );
    final second = FileRuntimeEventJournal(
      journalRoot: '/runtime/events',
      fs: fs,
    );

    final one = await first.append(_prompt(seat, 'one'));
    final two = await second.append(_prompt(seat, 'two'));
    final three = await first.append(_prompt(seat, 'three'));

    expect([one.sequence, two.sequence, three.sequence], [1, 2, 3]);
  });

  test(
    'independent filesystem views serialize concurrent persisted-seat appends',
    () async {
      final backing = InMemoryFilesystem();
      const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');
      final first = FileRuntimeEventJournal(
        journalRoot: '/runtime/events',
        fs: _FilesystemView(backing),
      );
      final second = FileRuntimeEventJournal(
        journalRoot: '/runtime/events',
        fs: _FilesystemView(backing),
      );

      final events = await Future.wait([
        first.append(_prompt(seat, 'one')),
        second.append(_prompt(seat, 'two')),
      ]);

      expect(events.map((event) => event.sequence).toSet(), {1, 2});
      expect(
        (await first.replay(seat).toList()).map((event) => event.sequence),
        [1, 2],
      );
    },
  );

  test('file journal partitions seats by sessionId directory', () async {
    final fs = InMemoryFilesystem();
    const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');
    const otherSeat = RuntimeSeatKey(sessionId: 'other', memberId: 'member');
    final journal = FileRuntimeEventJournal(
      journalRoot: '/runtime/events',
      fs: fs,
    );

    await journal.append(_prompt(seat, 'one'));
    await journal.append(_prompt(otherSeat, 'two'));

    final rootEntries = await fs.listDir('/runtime/events');
    expect(rootEntries.where((e) => !e.isDirectory), isEmpty);
    expect(
      await fs.listDir('/runtime/events/${_seg('session')}').then(
        (entries) => entries.map((e) => e.name),
      ),
      ['${_seg('member')}.jsonl'],
    );
    expect(await journal.seatsForSession('session'), {seat});
    expect(await journal.seatsForSession('other'), {otherSeat});
    expect(await journal.seatsForSession('missing'), isEmpty);
  });

  test('completed file-journal append releases its seat lock', () async {
    final journal = FileRuntimeEventJournal(
      journalRoot: '/runtime/events',
      fs: InMemoryFilesystem(),
    );
    const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');

    await journal.append(_prompt(seat, 'one'));

    expect(FileRuntimeEventJournal.activeSeatLockCount, 0);
  });

  test('warm append does not reread prior journal bytes', () async {
    final counting = _CountingFilesystem(InMemoryFilesystem());
    const seat = RuntimeSeatKey(sessionId: 'warm', memberId: 'member');
    final journal = FileRuntimeEventJournal(
      journalRoot: '/runtime/events-warm',
      fs: counting,
    );

    for (var i = 0; i < 20; i++) {
      await journal.append(_prompt(seat, 'event-$i'));
    }
    counting.reset();

    await journal.append(_prompt(seat, 'warm'));

    expect(counting.readStringCalls, 0);
    expect(counting.readBytesCalls, 0);
    expect(counting.rangeBytesRead, 0);
  });

  test('reopened journal tails last sequence without parsing the prefix', () async {
    final inner = InMemoryFilesystem();
    const seat = RuntimeSeatKey(sessionId: 'reopen', memberId: 'member');
    final first = FileRuntimeEventJournal(
      journalRoot: '/runtime/events-reopen',
      fs: inner,
    );
    for (var i = 0; i < 30; i++) {
      await first.append(_prompt(seat, 'event-$i'));
    }
    final path = _fileFor(inner, '/runtime/events-reopen', seat);
    final fileSize = (await inner.stat(path)).size!;

    FileRuntimeEventJournal.debugResetSeatState();
    final counting = _CountingFilesystem(inner);
    final reopened = FileRuntimeEventJournal(
      journalRoot: '/runtime/events-reopen',
      fs: counting,
    );
    final next = await reopened.append(_prompt(seat, 'after-reopen'));

    expect(next.sequence, 31);
    expect(counting.readStringCalls, 0);
    expect(counting.bytesRead, lessThan(fileSize));
    expect(counting.bytesRead, lessThan(8 * 1024));
  });

  test('seatsForSession does not read journal bodies', () async {
    final counting = _CountingFilesystem(InMemoryFilesystem());
    const seat = RuntimeSeatKey(sessionId: 'listed', memberId: 'member');
    final journal = FileRuntimeEventJournal(
      journalRoot: '/runtime/events-seats',
      fs: counting,
    );
    await journal.append(_prompt(seat, 'one'));
    counting.reset();

    expect(await journal.seatsForSession('listed'), {seat});
    expect(counting.readStringCalls, 0);
    expect(counting.readBytesCalls, 0);
    expect(counting.rangeBytesRead, 0);
  });

  test('replay afterSequence skips prefix bytes once offsets are warm', () async {
    final counting = _CountingFilesystem(InMemoryFilesystem());
    const seat = RuntimeSeatKey(sessionId: 'replay', memberId: 'member');
    final journal = FileRuntimeEventJournal(
      journalRoot: '/runtime/events-replay',
      fs: counting,
    );
    RuntimeEventEnvelope? last;
    for (var i = 0; i < 15; i++) {
      last = await journal.append(_prompt(seat, 'event-$i'));
    }
    counting.reset();

    final tail = await journal.replay(seat, afterSequence: 14).toList();

    expect(tail.map((event) => event.prompt), [last!.prompt]);
    expect(counting.readStringCalls, 0);
    expect(counting.bytesRead, lessThan(512));
  });

  test('unicode prompt keeps byte offsets aligned for the next append', () async {
    final counting = _CountingFilesystem(InMemoryFilesystem());
    const seat = RuntimeSeatKey(sessionId: 'unicode', memberId: '成员');
    final journal = FileRuntimeEventJournal(
      journalRoot: '/runtime/events-unicode',
      fs: counting,
    );

    await journal.append(_prompt(seat, '你好世界'));
    counting.reset();
    final second = await journal.append(_prompt(seat, '第二行'));

    expect(second.sequence, 2);
    expect(counting.readStringCalls, 0);
    expect(counting.rangeBytesRead, 0);
    expect(
      (await journal.replay(seat).toList()).map((event) => event.prompt),
      ['你好世界', '第二行'],
    );
  });

  test('partial trailing record is ignored when assigning the next sequence',
      () async {
    final fs = InMemoryFilesystem();
    const seat = RuntimeSeatKey(sessionId: 'partial', memberId: 'member');
    final journal = FileRuntimeEventJournal(
      journalRoot: '/runtime/events-partial',
      fs: fs,
    );
    final first = await journal.append(_prompt(seat, 'one'));
    final path = _fileFor(fs, '/runtime/events-partial', seat);
    await fs.appendBytes(path, utf8.encode('{"partial":true'));
    FileRuntimeEventJournal.debugResetSeatState();

    final reopened = FileRuntimeEventJournal(
      journalRoot: '/runtime/events-partial',
      fs: fs,
    );
    final next = await reopened.append(_prompt(seat, 'two'));

    expect(next.sequence, first.sequence + 1);
    expect(
      (await reopened.replay(seat).toList()).map((event) => event.prompt),
      [first.prompt, next.prompt],
    );
  });
}

RuntimeEventEnvelopeDraft _prompt(RuntimeSeatKey seat, String prompt) =>
    RuntimeEventEnvelopeDraft.promptSubmitted(
      seat: seat,
      cli: CliTool.codex,
      prompt: prompt,
      occurredAt: DateTime.utc(2026),
    );

String _seg(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

String _fileFor(Filesystem fs, String journalRoot, RuntimeSeatKey seat) =>
    fs.pathContext.join(
      journalRoot,
      _seg(seat.sessionId),
      '${_seg(seat.memberId)}.jsonl',
    );

class _CountingFilesystem implements Filesystem {
  _CountingFilesystem(this._inner);

  final Filesystem _inner;
  int readStringCalls = 0;
  int readBytesCalls = 0;
  int rangeBytesRead = 0;

  int get bytesRead => rangeBytesRead;

  void reset() {
    readStringCalls = 0;
    readBytesCalls = 0;
    rangeBytesRead = 0;
  }

  @override
  get pathContext => _inner.pathContext;

  @override
  Future<String?> readString(String path) async {
    readStringCalls++;
    return _inner.readString(path);
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    readBytesCalls++;
    final bytes = await _inner.readBytes(path);
    if (bytes != null) rangeBytesRead += bytes.length;
    return bytes;
  }

  @override
  Future<List<int>?> readBytesRange(
    String path,
    int offset,
    int length,
  ) async {
    final bytes = await _inner.readBytesRange(path, offset, length);
    if (bytes != null) rangeBytesRead += bytes.length;
    return bytes;
  }

  @override
  Future<void> ensureDir(String path) => _inner.ensureDir(path);

  @override
  Future<void> appendString(String path, String content) =>
      _inner.appendString(path, content);

  @override
  Future<void> appendBytes(String path, List<int> bytes) =>
      _inner.appendBytes(path, bytes);

  @override
  Future<FsStat> stat(String path) => _inner.stat(path);

  @override
  Future<void> writeString(String path, String content) =>
      _inner.writeString(path, content);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      _inner.writeBytes(path, bytes);

  @override
  Future<void> atomicWrite(String path, String content) =>
      _inner.atomicWrite(path, content);

  @override
  Future<List<FsDirEntry>> listDir(String path) => _inner.listDir(path);

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) =>
      _inner.listDirRecursive(path);

  @override
  Future<void> removeRecursive(String path) => _inner.removeRecursive(path);

  @override
  Future<void> rename(String from, String to) => _inner.rename(from, to);

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) => _inner.createSymlink(target: target, linkPath: linkPath);

  @override
  Future<String?> readSymlinkTarget(String linkPath) =>
      _inner.readSymlinkTarget(linkPath);

  @override
  Future<String?> resolveSymlink(String path) => _inner.resolveSymlink(path);

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) => _inner.copyTree(source: source, destination: destination);

  @override
  Future<void> copyFile(String source, String destination) =>
      _inner.copyFile(source, destination);

  @override
  Future<String> createTempDir({String? prefix, String? parent}) =>
      _inner.createTempDir(prefix: prefix, parent: parent);
}

class _FilesystemView implements Filesystem {
  _FilesystemView(this._delegate);

  final Filesystem _delegate;

  @override
  get pathContext => _delegate.pathContext;

  @override
  Future<FsStat> stat(String path) => _delegate.stat(path);

  @override
  Future<String?> readString(String path) => _delegate.readString(path);

  @override
  Future<List<int>?> readBytes(String path) => _delegate.readBytes(path);

  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) =>
      _delegate.readBytesRange(path, offset, length);

  @override
  Future<void> ensureDir(String path) => _delegate.ensureDir(path);

  @override
  Future<void> appendString(String path, String content) =>
      _delegate.appendString(path, content);

  @override
  Future<void> appendBytes(String path, List<int> bytes) =>
      _delegate.appendBytes(path, bytes);

  @override
  Future<void> writeString(String path, String content) =>
      _delegate.writeString(path, content);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      _delegate.writeBytes(path, bytes);

  @override
  Future<void> atomicWrite(String path, String content) =>
      _delegate.atomicWrite(path, content);

  @override
  Future<List<FsDirEntry>> listDir(String path) => _delegate.listDir(path);

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) =>
      _delegate.listDirRecursive(path);

  @override
  Future<void> removeRecursive(String path) => _delegate.removeRecursive(path);

  @override
  Future<void> rename(String from, String to) => _delegate.rename(from, to);

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) => _delegate.createSymlink(target: target, linkPath: linkPath);

  @override
  Future<String?> readSymlinkTarget(String linkPath) =>
      _delegate.readSymlinkTarget(linkPath);

  @override
  Future<String?> resolveSymlink(String path) =>
      _delegate.resolveSymlink(path);

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) => _delegate.copyTree(source: source, destination: destination);

  @override
  Future<void> copyFile(String source, String destination) =>
      _delegate.copyFile(source, destination);

  @override
  Future<String> createTempDir({String? prefix, String? parent}) =>
      _delegate.createTempDir(prefix: prefix, parent: parent);
}
