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
    await fs.writeBytes(p.join(from, 'files', 'skill-a', 'SKILL.md'), [1, 2, 3]);

    await fs.rename(from, to);

    expect(await Directory(from).exists(), isFalse);
    expect((await fs.stat(p.join(to, 'meta.json'))).isFile, isTrue);
    expect((await fs.stat(p.join(to, 'files', 'skill-a', 'SKILL.md'))).isFile, isTrue);
  });

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
}
