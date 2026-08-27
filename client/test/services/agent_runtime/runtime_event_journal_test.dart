import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/agent_runtime/runtime_event_journal.dart';
import 'package:teampilot/services/io/filesystem.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
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

class _FilesystemView implements Filesystem {
  _FilesystemView(this._delegate);

  final Filesystem _delegate;

  @override
  get pathContext => _delegate.pathContext;

  @override
  Future<String?> readString(String path) => _delegate.readString(path);

  @override
  Future<void> ensureDir(String path) => _delegate.ensureDir(path);

  @override
  Future<void> appendString(String path, String content) =>
      _delegate.appendString(path, content);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
