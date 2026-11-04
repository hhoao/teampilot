import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('rewind-');
    final tmp = tmpDir.path;
    await Directory('$tmp/work/claude/projects').create(recursive: true);
    await Directory('$tmp/work/claude/plugins').create(recursive: true);
    await Directory('$tmp/work/other').create(recursive: true);
    await File('$tmp/work/claude/projects/a.jsonl').writeAsString('one');
    final outside = await Directory('$tmp/outside').create();
    await Link('$tmp/work/claude/plugins/link').create(outside.path);
    await File('$tmp/work/acp-transcript.jsonl').writeAsString('[]');
    await File(
      '$tmp/work/acp-session.json',
    ).writeAsString('{"v":1,"sessionId":"s1"}');
    await File('$tmp/work/other/secret.txt').writeAsString('nope');
  });

  tearDown(() async {
    if (!tmpDir.existsSync()) return;
    try {
      await tmpDir.delete(recursive: true);
    } on FileSystemException {
      // A test may leave an unreadable directory behind.
    }
  });

  test(
    'commit stores one seat and skips symlink, cache names, and siblings',
    () async {
      final tmp = tmpDir.path;
      final store = SeatRewindStore(
        gitDir: '$tmp/repo.git',
        workTree: '$tmp/work',
        target: const SeatRewindTarget(
          kind: SeatRewindKind.personalAcp,
          tool: 'claude',
        ),
      );
      final checkpoint = await store.commitTurn(
        messageId: 'm1',
        nativeSessionId: null,
      );
      final names = await _lsTree(store, checkpoint.commit);
      expect(
        names,
        containsAll([
          'claude/projects/a.jsonl',
          'acp-transcript.jsonl',
          'acp-session.json',
        ]),
      );
      expect(
        names.any((n) => n.contains('plugins') || n == 'other/secret.txt'),
        isFalse,
      );
      expect(await store.checkedOut(), checkpoint.commit);
      expect((await store.checkpoints()).single.messageId, 'm1');
      expect(
        await store.showFile(checkpoint.commit, 'claude/projects/a.jsonl'),
        'one',
      );
    },
  );

  test('an unreadable seat directory is skipped, not fatal', () async {
    final tmp = tmpDir.path;
    final locked = Directory('$tmp/work/claude/locked');
    await locked.create();
    await File('${locked.path}/x.jsonl').writeAsString('x');
    final chmod = await Process.run('chmod', ['000', locked.path]);
    if (chmod.exitCode != 0) return;
    addTearDown(() => Process.run('chmod', ['755', locked.path]));
    bool readable;
    try {
      locked.listSync();
      readable = true;
    } on FileSystemException {
      readable = false;
    }
    // Root ignores the mode; there is nothing to assert on such a host.
    if (readable) return;

    final store = SeatRewindStore(
      gitDir: '$tmp/repo.git',
      workTree: '$tmp/work',
      target: const SeatRewindTarget(
        kind: SeatRewindKind.personalAcp,
        tool: 'claude',
      ),
    );
    final checkpoint = await store.commitTurn(messageId: 'm1');
    final names = await _lsTree(store, checkpoint.commit);

    expect(names, contains('claude/projects/a.jsonl'));
    expect(names, isNot(contains('claude/locked/x.jsonl')));
  });

  test('commitTurn drops a seat file deleted from the work tree', () async {
    final tmp = tmpDir.path;
    final store = SeatRewindStore(
      gitDir: '$tmp/repo.git',
      workTree: '$tmp/work',
      target: const SeatRewindTarget(
        kind: SeatRewindKind.personalAcp,
        tool: 'claude',
      ),
    );
    await store.commitTurn(messageId: 'm1');
    await File('$tmp/work/claude/projects/a.jsonl').delete();
    final second = await store.commitTurn(messageId: 'm2');
    expect(
      await _lsTree(store, second.commit),
      isNot(contains('claude/projects/a.jsonl')),
    );
  });

  test(
    'restore replaces seat bytes, deletes extras, and keeps the sibling',
    () async {
      final tmp = tmpDir.path;
      final work = '$tmp/work';
      final store = SeatRewindStore(
        gitDir: '$tmp/repo.git',
        workTree: work,
        target: const SeatRewindTarget(
          kind: SeatRewindKind.personalAcp,
          tool: 'claude',
        ),
      );
      final first = await store.commitTurn(messageId: 'm1');
      await File('$work/claude/projects/a.jsonl').writeAsString('two');
      await File('$work/claude/projects/extra.txt').writeAsString('x');
      await store.commitTurn(messageId: 'm2');
      await store.restore(first.commit);
      expect(await File('$work/claude/projects/a.jsonl').readAsString(), 'one');
      expect(File('$work/claude/projects/extra.txt').existsSync(), isFalse);
      expect(await File('$work/other/secret.txt').readAsString(), 'nope');
      expect(await store.checkedOut(), first.commit);
    },
  );

  test('failed restore puts the previous tree back', () async {
    final tmp = tmpDir.path;
    final work = '$tmp/work';
    const target = SeatRewindTarget(
      kind: SeatRewindKind.personalAcp,
      tool: 'claude',
    );
    final store = SeatRewindStore(
      gitDir: '$tmp/repo.git',
      workTree: work,
      target: target,
    );
    final first = await store.commitTurn(messageId: 'm1');
    await File('$work/claude/projects/a.jsonl').writeAsString('two');
    final second = await store.commitTurn(messageId: 'm2');
    final which = await Process.run('which', ['git']);
    final realGit = (which.stdout as String).trim();
    final scriptPath = '$tmp/git-fail-checkout';
    await File(scriptPath).writeAsString('''
#!/bin/sh
prev=""
for arg in "\$@"; do
  if [ "\$prev" = "checkout" ] && [ "\$arg" = "${first.commit}" ]; then
    exit 1
  fi
  prev="\$arg"
done
exec "$realGit" "\$@"
''');
    await Process.run('chmod', ['+x', scriptPath]);
    final failing = SeatRewindStore(
      gitDir: store.gitDir,
      workTree: store.workTree,
      target: target,
      gitExecutable: scriptPath,
    );
    await expectLater(
      failing.restore(first.commit),
      throwsA(isA<StateError>()),
    );
    expect(await File('$work/claude/projects/a.jsonl').readAsString(), 'two');
    expect(await failing.checkedOut(), second.commit);
  });

  test(
    'forkAt copies the selected commit into a personal dest layout',
    () async {
      final tmp = tmpDir.path;
      await Directory('$tmp/work/m1/claude/projects').create(recursive: true);
      await File('$tmp/work/m1/claude/projects/a.jsonl').writeAsString('one');
      await File('$tmp/work/acp-session-m1.json').writeAsString('{"v":1}');
      final store = SeatRewindStore(
        gitDir: '$tmp/repo.git',
        workTree: '$tmp/work',
        target: const SeatRewindTarget(
          kind: SeatRewindKind.mixedAcp,
          tool: 'claude',
          memberId: 'm1',
        ),
      );
      final first = await store.commitTurn(messageId: 'm1');
      await File('$tmp/work/m1/claude/projects/a.jsonl').writeAsString('two');
      final second = await store.commitTurn(messageId: 'm2');
      final dest = await store.forkAt(
        commit: first.commit,
        destGitDir: '$tmp/dest.git',
        destWorkTree: '$tmp/dest-work',
        destTarget: const SeatRewindTarget(
          kind: SeatRewindKind.personalAcp,
          tool: 'claude',
        ),
      );
      final live = await Process.run(dest.gitExecutable, [
        '--git-dir',
        dest.gitDir,
        'rev-parse',
        'refs/rewind/live',
      ]);
      expect((live.stdout as String).trim(), first.commit);
      expect(
        await File('$tmp/dest-work/claude/projects/a.jsonl').readAsString(),
        'one',
      );
      expect(File('$tmp/dest-work/acp-session.json').existsSync(), isTrue);
      expect(File('$tmp/dest-work/acp-session-m1.json').existsSync(), isFalse);
      final listed = await Process.run(dest.gitExecutable, [
        '--git-dir',
        dest.gitDir,
        'rev-list',
        '--all',
      ]);
      expect(listed.stdout as String, isNot(contains(second.commit)));
      expect(
        await File('$tmp/work/m1/claude/projects/a.jsonl').readAsString(),
        'two',
      );
    },
  );

  test(
    'restore and showFile map mixed commit paths onto a personal dest',
    () async {
      final tmp = tmpDir.path;
      await Directory('$tmp/work/m1/claude/projects').create(recursive: true);
      await File('$tmp/work/m1/claude/projects/a.jsonl').writeAsString('one');
      await File('$tmp/work/acp-session-m1.json').writeAsString('{"v":1}');
      final store = SeatRewindStore(
        gitDir: '$tmp/repo.git',
        workTree: '$tmp/work',
        target: const SeatRewindTarget(
          kind: SeatRewindKind.mixedAcp,
          tool: 'claude',
          memberId: 'm1',
        ),
      );
      final first = await store.commitTurn(messageId: 'm1');
      await File('$tmp/work/m1/claude/projects/a.jsonl').writeAsString('two');
      final second = await store.commitTurn(messageId: 'm2');
      final dest = await store.forkAt(
        commit: second.commit,
        destGitDir: '$tmp/dest.git',
        destWorkTree: '$tmp/dest-work',
        destTarget: const SeatRewindTarget(
          kind: SeatRewindKind.personalAcp,
          tool: 'claude',
        ),
      );
      expect(
        await File('$tmp/dest-work/claude/projects/a.jsonl').readAsString(),
        'two',
      );
      await dest.restore(first.commit);
      expect(
        await File('$tmp/dest-work/claude/projects/a.jsonl').readAsString(),
        'one',
      );
      expect(File('$tmp/dest-work/acp-session.json').existsSync(), isTrue);
      expect(File('$tmp/dest-work/acp-session-m1.json').existsSync(), isFalse);
      expect(
        await File('$tmp/work/m1/claude/projects/a.jsonl').readAsString(),
        'two',
      );
      expect(await dest.checkedOut(), first.commit);
      expect(
        await dest.showFile(first.commit, 'claude/projects/a.jsonl'),
        'one',
      );
    },
  );

  test('a turn records its user message above the root commit', () async {
    final tmp = tmpDir.path;
    final store = SeatRewindStore(
      gitDir: '$tmp/repo.git',
      workTree: '$tmp/work',
      target: const SeatRewindTarget(
        kind: SeatRewindKind.personalAcp,
        tool: 'claude',
      ),
    );

    final first = await store.commitTurn(
      messageId: 'a1',
      userMessageId: 'u1',
      nativeSessionId: 's1',
    );
    final second = await store.commitTurn(
      messageId: 'a2',
      userMessageId: 'u2',
    );

    expect(first.userMessageId, 'u1');
    expect(first.messageId, 'a1');
    expect(first.nativeSessionId, 's1');
    expect(first.turnAt, greaterThan(0));
    expect(first.parentCommit, await store.root());
    expect(second.parentCommit, first.commit);
    expect(await store.branchTip(first.commit), second.commit);
    expect(await store.branchTip(second.commit), second.commit);
  });

  test('a second turn from the same parent is a sibling', () async {
    final tmp = tmpDir.path;
    final store = SeatRewindStore(
      gitDir: '$tmp/repo.git',
      workTree: '$tmp/work',
      target: const SeatRewindTarget(
        kind: SeatRewindKind.personalAcp,
        tool: 'claude',
      ),
    );
    final root = await store.root();
    final versionOne = await store.commitTurn(
      messageId: 'a1',
      userMessageId: 'u1',
    );
    await store.restore(root);
    final versionTwo = await store.commitTurn(
      messageId: 'b1',
      userMessageId: 'u2',
    );

    expect(versionOne.parentCommit, root);
    expect(versionTwo.parentCommit, root);
    expect(await store.branchTip(versionOne.commit), versionOne.commit);
    expect(await store.checkedOut(), versionTwo.commit);
  });

  test('a reopened store parses the turn anchor from the commit body', () async {
    final tmp = tmpDir.path;
    final writer = SeatRewindStore(
      gitDir: '$tmp/repo.git',
      workTree: '$tmp/work',
      target: const SeatRewindTarget(
        kind: SeatRewindKind.personalAcp,
        tool: 'claude',
      ),
    );
    await writer.commitTurn(messageId: 'a1', userMessageId: 'u1');

    // A fresh store instance has no in-memory record; only the commit body.
    final reader = SeatRewindStore(
      gitDir: '$tmp/repo.git',
      workTree: '$tmp/work',
      target: const SeatRewindTarget(
        kind: SeatRewindKind.personalAcp,
        tool: 'claude',
      ),
    );
    final parsed = (await reader.checkpoints()).single;

    expect(parsed.userMessageId, 'u1');
    expect(parsed.messageId, 'a1');
    expect(parsed.turnAt, greaterThan(0));
  });

  test('a commit written before the anchor parses with empty defaults', () async {
    final tmp = tmpDir.path;
    final gitDir = '$tmp/repo.git';
    final store = SeatRewindStore(
      gitDir: gitDir,
      workTree: '$tmp/work',
      target: const SeatRewindTarget(
        kind: SeatRewindKind.personalAcp,
        tool: 'claude',
      ),
    );
    // Seed a tree, then write a commit body in the pre-anchor shape.
    await store.commitTurn(messageId: 'a1');
    final tree = (await Process.run('git', [
      '--git-dir',
      gitDir,
      '--work-tree',
      '$tmp/work',
      'write-tree',
    ])).stdout as String;
    const identity = {
      'GIT_AUTHOR_NAME': 'TeamPilot',
      'GIT_AUTHOR_EMAIL': 'teampilot@localhost',
      'GIT_COMMITTER_NAME': 'TeamPilot',
      'GIT_COMMITTER_EMAIL': 'teampilot@localhost',
    };
    final legacy = (await Process.run('git', [
      '--git-dir',
      gitDir,
      'commit-tree',
      tree.trim(),
      '-m',
      'checkpoint\n\nTurn-Message: a-legacy\nNative-Session: ',
    ], environment: identity)).stdout as String;
    await Process.run('git', [
      '--git-dir',
      gitDir,
      'update-ref',
      'refs/rewind/keep/a-legacy',
      legacy.trim(),
    ]);

    final parsed = (await store.checkpoints())
        .singleWhere((turn) => turn.messageId == 'a-legacy');

    expect(parsed.userMessageId, isEmpty);
    expect(parsed.turnAt, 0);
  });
}

Future<List<String>> _lsTree(SeatRewindStore store, String commit) async {
  final result = await Process.run(store.gitExecutable, [
    '--git-dir',
    store.gitDir,
    'ls-tree',
    '-r',
    '--name-only',
    commit,
  ]);
  return const LineSplitter()
      .convert(result.stdout as String)
      .where((line) => line.isNotEmpty)
      .toList();
}
