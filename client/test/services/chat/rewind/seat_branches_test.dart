import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/rewind/seat_branches.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('seat-branches-');
    await Directory('${tmpDir.path}/work/claude/projects').create(
      recursive: true,
    );
    await File('${tmpDir.path}/work/claude/projects/a.jsonl').writeAsString(
      'one',
    );
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  test('siblings of the same parent become versions ordered by turn', () async {
    final store = _store(tmpDir.path);
    final root = await store.root();
    await store.commitTurn(messageId: 'a1', userMessageId: 'u1');
    await store.restore(root);
    await store.commitTurn(messageId: 'b1', userMessageId: 'u2');

    final branches = await readSeatBranches(store: store);

    expect(branches.turnOf('u1')!.count, 2);
    expect(branches.turnOf('u1')!.index, 1);
    expect(branches.turnOf('u2')!.index, 2);
    expect(branches.turnOf('u1')!.siblings, hasLength(2));
    expect(branches.turnOf('u1')!.next, branches.turnOf('u2')!.commit);
    expect(branches.turnOf('u2')!.previous, branches.turnOf('u1')!.commit);
  });

  test('a linear branch reports one version per turn', () async {
    final store = _store(tmpDir.path);
    await store.commitTurn(messageId: 'a1', userMessageId: 'u1');
    await store.commitTurn(messageId: 'a2', userMessageId: 'u2');

    final branches = await readSeatBranches(store: store);

    expect(branches.turnOf('u1')!.count, 1);
    expect(branches.turnOf('u1')!.previous, isNull);
    expect(branches.turnOf('u2')!.count, 1);
    expect(branches.checkedOutCommit, branches.turnOf('u2')!.commit);
  });

  test('turns written before the anchor are ignored', () async {
    final store = _store(tmpDir.path);
    await store.commitTurn(messageId: 'a1');

    final branches = await readSeatBranches(store: store);

    expect(branches.turns, isEmpty);
  });
}

SeatRewindStore _store(String tmp) => SeatRewindStore(
  gitDir: '$tmp/repo.git',
  workTree: '$tmp/work',
  target: const SeatRewindTarget(
    kind: SeatRewindKind.personalAcp,
    tool: 'claude',
  ),
);
