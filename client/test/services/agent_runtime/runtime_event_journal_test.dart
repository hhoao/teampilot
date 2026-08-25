import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/agent_runtime/runtime_event_journal.dart';
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
}

RuntimeEventEnvelopeDraft _prompt(RuntimeSeatKey seat, String prompt) =>
    RuntimeEventEnvelopeDraft.promptSubmitted(
      seat: seat,
      cli: CliTool.codex,
      prompt: prompt,
      occurredAt: DateTime.utc(2026),
    );
