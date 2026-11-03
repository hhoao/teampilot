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
    if (tmpDir.existsSync()) {
      await tmpDir.delete(recursive: true);
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
