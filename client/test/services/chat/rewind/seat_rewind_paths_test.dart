import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';

void main() {
  test('personal ACP includes the tool dir and both sidecars', () {
    const target = SeatRewindTarget(
      kind: SeatRewindKind.personalAcp,
      tool: 'claude',
    );
    expect(target.seatKey, 'personal');
    expect(target.includes('claude/projects/a.jsonl'), isTrue);
    expect(target.includes('acp-transcript.jsonl'), isTrue);
    expect(target.includes('acp-session.json'), isTrue);
    expect(target.includes('codex/sessions/x.jsonl'), isFalse);
    expect(target.isExcluded('claude/plugins/installed/a'), isTrue);
    expect(target.isExcluded('claude/skills/x'), isTrue);
    expect(target.isExcluded('claude/node_modules/y'), isTrue);
    expect(target.isExcluded('claude/cache/z'), isTrue);
    expect(target.isExcluded('claude/projects/a.jsonl'), isFalse);
  });

  test('mixed ACP prefixes stay under the member id', () {
    const target = SeatRewindTarget(
      kind: SeatRewindKind.mixedAcp,
      tool: 'claude',
      memberId: 'm1',
    );
    expect(target.seatKey, 'm1');
    expect(target.includes('m1/claude/projects/a.jsonl'), isTrue);
    expect(target.includes('acp-transcript-m1.jsonl'), isTrue);
    expect(target.includes('acp-session-m1.json'), isTrue);
    expect(target.includes('claude/projects/a.jsonl'), isFalse);
    expect(target.includes('acp-transcript.jsonl'), isFalse);
  });

  test('PTY seats have no ACP sidecars', () {
    const personal = SeatRewindTarget(
      kind: SeatRewindKind.personalPty,
      tool: 'codex',
    );
    const mixed = SeatRewindTarget(
      kind: SeatRewindKind.mixedPty,
      tool: 'codex',
      memberId: 'm1',
    );
    expect(personal.includes('codex/sessions/rollout.jsonl'), isTrue);
    expect(personal.includes('acp-session.json'), isFalse);
    expect(mixed.includes('m1/codex/sessions/rollout.jsonl'), isTrue);
    expect(mixed.includes('acp-session-m1.json'), isFalse);
  });
}
