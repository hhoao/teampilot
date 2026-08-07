import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory root;
  late LocalFilesystem fs;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('teampilot_local_fs_');
    fs = LocalFilesystem(pathContext: p.context);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('rename moves a file', () async {
    final from = p.join(root.path, 'a.txt');
    final to = p.join(root.path, 'b.txt');
    await fs.writeString(from, 'hello');

    await fs.rename(from, to);

    expect(await File(from).exists(), isFalse);
    expect(await fs.readString(to), 'hello');
  });

  test('rename moves a directory tree', () async {
    final from = p.join(root.path, 'repo');
    final to = p.join(root.path, 'repo.bak');
    await fs.ensureDir(p.join(from, 'files', 'skill-a'));
    await fs.writeString(p.join(from, 'meta.json'), '{}');
    await fs.writeBytes(p.join(from, 'files', 'skill-a', 'SKILL.md'), [
      1,
      2,
      3,
    ]);

    await fs.rename(from, to);

    expect(await Directory(from).exists(), isFalse);
    expect((await fs.stat(p.join(to, 'meta.json'))).isFile, isTrue);
    expect(
      (await fs.stat(p.join(to, 'files', 'skill-a', 'SKILL.md'))).isFile,
      isTrue,
    );
  });

  test('ensureDir is a no-op when path is an existing symlink', () async {
    final target = p.join(root.path, 'target');
    final link = p.join(root.path, 'link');
    await fs.ensureDir(target);
    await Link(link).create(target);

    await expectLater(fs.ensureDir(link), completes);
    expect(Link(link).existsSync(), isTrue);
  });

  test(
    'listDir reports a symlink/junction to a directory as a directory',
    () async {
      final target = p.join(root.path, 'installed', 'brainstorming');
      await fs.ensureDir(target);
      final container = p.join(root.path, 'skills');
      await fs.ensureDir(container);
      await fs.createSymlink(
        target: target,
        linkPath: p.join(container, 'brainstorming'),
      );

      final entries = await fs.listDir(container);

      expect(entries, hasLength(1));
      expect(entries.single.name, 'brainstorming');
      expect(entries.single.isDirectory, isTrue);
    },
  );

  test('rename replaces an existing destination directory', () async {
    final from = p.join(root.path, 'next');
    final to = p.join(root.path, 'current');
    await fs.ensureDir(p.join(to, 'old'));
    await fs.writeString(p.join(to, 'old', 'stale.txt'), 'stale');
    await fs.writeString(p.join(from, 'fresh.txt'), 'fresh');

    await fs.rename(from, to);

    expect(await Directory(from).exists(), isFalse);
    expect(await fs.readString(p.join(to, 'fresh.txt')), 'fresh');
    expect(await File(p.join(to, 'old', 'stale.txt')).exists(), isFalse);
  });

  test(
    'atomicWrite survives concurrent removeRecursive of its parent dir',
    () async {
      // Mirrors session launch: multiple members flush manifests that
      // removeRecursive(plugins) then write .teampilot-member-plugins-stamp.json.
      final dir = p.join(root.path, 'plugins');
      final stamp = p.join(dir, '.teampilot-member-plugins-stamp.json');
      await fs.ensureDir(dir);

      final ops = <Future<void>>[
        for (var i = 0; i < 24; i++) ...[
          () async {
            await fs.removeRecursive(dir);
            await fs.ensureDir(dir);
          }(),
          fs.atomicWrite(stamp, '{"i":$i}'),
        ],
      ];
      await Future.wait(ops);

      expect((await fs.stat(dir)).isDirectory, isTrue);
      final text = await fs.readString(stamp);
      expect(text, isNotNull);
      expect(text, contains('"i":'));
    },
  );

  group('copyTree / copyFile preserve executable bit', () {
    Future<int> modeBits(String path) async {
      final mode = (await File(path).stat()).mode;
      return mode & 0x49; // any exec bit
    }

    test('copyTree keeps an executable file executable and others not',
        () async {
      if (Platform.isWindows) {
        return; // POSIX exec bits are meaningless on Windows
      }
      final src = p.join(root.path, 'src');
      final dest = p.join(root.path, 'dst');
      final hook = p.join(src, 'hooks', 'run-hook.cmd');
      final plain = p.join(src, 'SKILL.md');
      await fs.ensureDir(p.join(src, 'hooks'));
      await fs.writeString(hook, '#!/usr/bin/env bash\n');
      await fs.writeString(plain, 'content');
      await Process.run('chmod', ['+x', hook]);

      await fs.copyTree(source: src, destination: dest);

      expect(await modeBits(p.join(dest, 'hooks', 'run-hook.cmd')),
          isNot(equals(0)));
      expect(await modeBits(p.join(dest, 'SKILL.md')), equals(0));
    });

    test('copyFile keeps an executable file executable and others not', () async {
      if (Platform.isWindows) {
        return; // POSIX exec bits are meaningless on Windows
      }
      final hook = p.join(root.path, 'hook.sh');
      final plain = p.join(root.path, 'plain.txt');
      await fs.writeString(hook, '#!/usr/bin/env bash\n');
      await fs.writeString(plain, 'content');
      await Process.run('chmod', ['+x', hook]);

      await fs.copyFile(hook, p.join(root.path, 'hook-copy.sh'));
      await fs.copyFile(plain, p.join(root.path, 'plain-copy.txt'));

      expect(await modeBits(p.join(root.path, 'hook-copy.sh')), isNot(equals(0)));
      expect(await modeBits(p.join(root.path, 'plain-copy.txt')), equals(0));
    });
  });
}
