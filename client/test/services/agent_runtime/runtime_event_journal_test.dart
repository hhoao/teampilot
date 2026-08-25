import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/agent_runtime/runtime_event_journal.dart';

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
}
