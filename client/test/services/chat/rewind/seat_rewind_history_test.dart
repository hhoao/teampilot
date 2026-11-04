import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_history.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('seat-rewind-history-');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) {
      await tmpDir.delete(recursive: true);
    }
  });

  test('checkpoints list oldest first and map turn ids to commits', () async {
    final store = await _personalAcpStore(tmpDir.path);
    final first = await store.commitTurn(messageId: 'm1');
    final second = await store.commitTurn(messageId: 'm2');
    final third = await store.commitTurn(messageId: 'm3');

    final history = await readSeatRewindHistory(store: store);

    expect(history.orderedCommits, [first.commit, second.commit, third.commit]);
    expect(history.checkpointCommits, {
      'm1': first.commit,
      'm2': second.commit,
      'm3': third.commit,
    });
    expect(history.checkedOutCommit, third.commit);
    expect(history.checkedOutIndex, 3);
    expect(history.previousCommit, second.commit);
    expect(history.nextCommit, isNull);
  });

  test(
    'a restored commit reports its neighbours without moving the head',
    () async {
      final store = await _personalAcpStore(tmpDir.path);
      final first = await store.commitTurn(messageId: 'm1');
      final second = await store.commitTurn(messageId: 'm2');
      await store.restore(first.commit);

      final history = await readSeatRewindHistory(store: store);

      expect(history.checkedOutCommit, first.commit);
      expect(history.checkedOutIndex, 1);
      expect(history.previousCommit, isNull);
      expect(history.nextCommit, second.commit);
      expect(history.checkpointCommits['m2'], second.commit);
    },
  );

  test('an empty or missing repository has no checkpoints', () async {
    final store = SeatRewindStore(
      gitDir: '${tmpDir.path}/missing.git',
      workTree: tmpDir.path,
      target: const SeatRewindTarget(
        kind: SeatRewindKind.personalPty,
        tool: 'claude',
      ),
    );

    final history = await readSeatRewindHistory(store: store);

    expect(history.orderedCommits, isEmpty);
    expect(history.checkpointCommits, isEmpty);
    expect(history.checkedOutCommit, isNull);
    expect(history.checkedOutIndex, isNull);
    expect(history.previousCommit, isNull);
    expect(history.nextCommit, isNull);
  });
}

Future<SeatRewindStore> _personalAcpStore(String tmp) async {
  await Directory('$tmp/work/claude/projects').create(recursive: true);
  await File('$tmp/work/claude/projects/a.jsonl').writeAsString('one');
  await File('$tmp/work/acp-transcript.jsonl').writeAsString('[]');
  await File('$tmp/work/acp-session.json').writeAsString('{"v":1}');
  return SeatRewindStore(
    gitDir: '$tmp/repo.git',
    workTree: '$tmp/work',
    target: const SeatRewindTarget(
      kind: SeatRewindKind.personalAcp,
      tool: 'claude',
    ),
  );
}
