import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/services/install/job_log_store.dart';

import '../../support/in_memory_filesystem.dart';

const _key = InstallJobKey(
  kind: InstallJobKind.cliExecutable,
  target: 'claude:remote',
);

void main() {
  group('JobLogStore tokens', () {
    test('sanitizes unsafe characters and stays deterministic', () {
      final store = JobLogStore(appDataRoot: '/tp', fs: InMemoryFilesystem());
      final token = store.tokenFor(_key);
      expect(token, matches(RegExp(r'^[A-Za-z0-9._-]+$')));
      expect(store.tokenFor(_key), token);
      expect(token, contains('claude_remote'));
    });

    test('different keys get different tokens', () {
      final store = JobLogStore(appDataRoot: '/tp', fs: InMemoryFilesystem());
      const other = InstallJobKey(
        kind: InstallJobKind.cliExecutable,
        target: 'codex',
      );
      expect(store.tokenFor(_key), isNot(store.tokenFor(other)));
    });
  });

  group('JobLogStore writing', () {
    test(
      'writes header and lines in order and closes the live stream',
      () async {
        final fs = InMemoryFilesystem();
        final store = JobLogStore(appDataRoot: '/tp', fs: fs);
        final token = store.tokenFor(_key);
        final writer = store.begin(key: _key, title: 'Install Claude');
        final events = <String>[];
        final sub = store.follow(token).listen(events.add);

        writer.line('first');
        writer.line('second');
        await writer.close();
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(store.isLive(token), isFalse);
        expect(events.length, 3);
        expect(events[0], startsWith('[start]'));
        expect(events[1], 'first');
        expect(events[2], 'second');

        final file = p.join('/tp', 'logs', 'install-jobs', '$token.log');
        final onDisk = utf8.decode(fs.byteFiles[file]!);
        expect(onDisk.split('\n')[1], 'first');
        expect(await store.read(token), isNotEmpty);
      },
    );

    test(
      'strips ANSI escapes and keeps the last carriage-return render',
      () async {
        final fs = InMemoryFilesystem();
        final store = JobLogStore(appDataRoot: '/tp', fs: fs);
        final token = store.tokenFor(_key);
        final writer = store.begin(key: _key, title: 't');
        writer.line('\u001b[32m50%\u001b[0m progress');
        writer.line('10%\rdone');
        await writer.close();

        final lines = await store.read(token);
        expect(lines[1], '50% progress');
        expect(lines[2], 'done');
        expect(lines.join('\n'), isNot(contains('\u001b')));
      },
    );

    test('caps a single line at 4096 characters', () async {
      final fs = InMemoryFilesystem();
      final store = JobLogStore(appDataRoot: '/tp', fs: fs);
      final token = store.tokenFor(_key);
      final writer = store.begin(key: _key, title: 't');
      writer.line('x' * 10000);
      await writer.close();

      final lines = await store.read(token);
      expect(lines[1].length, 4096);
    });

    test('ring buffer keeps the newest 2000 lines', () async {
      final fs = InMemoryFilesystem();
      final store = JobLogStore(appDataRoot: '/tp', fs: fs);
      final token = store.tokenFor(_key);
      final writer = store.begin(key: _key, title: 't');
      for (var i = 0; i < 2100; i++) {
        writer.line('line $i');
      }
      final replayed = <String>[];
      final sub = store.follow(token).listen(replayed.add);
      await writer.close();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      // The file keeps every line; the live replay is the 2000-line ring.
      expect(replayed.length, 2000);
      expect(replayed.first, 'line 100');
      expect(replayed.last, 'line 2099');
      expect((await store.read(token)).length, 2101);
    });

    test('a second begin for the same key replaces the previous run', () async {
      final fs = InMemoryFilesystem();
      final store = JobLogStore(appDataRoot: '/tp', fs: fs);

      final first = store.begin(key: _key, title: 'first run');
      first.line('old line');
      await first.close();

      final second = store.begin(key: _key, title: 'second run');
      second.line('new line');
      await second.close();

      final lines = await store.read(store.tokenFor(_key));
      expect(lines.where((l) => l.startsWith('[start]')).length, 1);
      expect(lines, contains('new line'));
      expect(lines, isNot(contains('old line')));
    });

    test('returns empty for an unknown token', () async {
      final store = JobLogStore(appDataRoot: '/tp', fs: InMemoryFilesystem());
      expect(await store.read('missing'), isEmpty);
      expect(store.isLive('missing'), isFalse);
      expect(await store.follow('missing').toList(), isEmpty);
    });
  });

  group('JobLogStore purge', () {
    late Directory root;
    late JobLogStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('job-log-test-');
      store = JobLogStore(appDataRoot: root.path);
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    test('removes files older than 7 days', () async {
      final dir = Directory(p.join(root.path, 'logs', 'install-jobs'))
        ..createSync(recursive: true);
      final old = File(p.join(dir.path, 'old.log'))
        ..writeAsStringSync('[start]\n')
        ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 8)));
      final fresh = File(p.join(dir.path, 'fresh.log'))
        ..writeAsStringSync('[start]\n');

      await store.purge();

      expect(old.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });

    test('keeps at most 20 newest files', () async {
      final dir = Directory(p.join(root.path, 'logs', 'install-jobs'))
        ..createSync(recursive: true);
      final files = <File>[];
      for (var i = 0; i < 25; i++) {
        final file = File(p.join(dir.path, 'job$i.log'))
          ..writeAsStringSync('[start]\n')
          ..setLastModifiedSync(DateTime.now().subtract(Duration(minutes: i)));
        files.add(file);
      }

      await store.purge();

      final remaining = dir.listSync().whereType<File>().toList();
      expect(remaining.length, 20);
      expect(File(p.join(dir.path, 'job0.log')).existsSync(), isTrue);
      expect(File(p.join(dir.path, 'job24.log')).existsSync(), isFalse);
    });
  });
}
