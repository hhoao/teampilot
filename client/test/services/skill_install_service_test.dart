import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';
import 'package:teampilot/services/skill/skill_install_service.dart';
import 'package:teampilot/services/skill/skill_manifest_service.dart';

void main() {
  late Directory tmp;
  late SkillManifestService manifest;
  late SkillInstallService svc;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill_install_test_');
    final paths = AppPaths(tmp.path);
    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
    manifest = SkillManifestService(rootDir: tmp.path);
    svc = SkillInstallService(manifest: manifest);
  });

  tearDown(() {
    RuntimeStorageContext.resetForTesting();
    AppPathsBootstrapper.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Map<String, Uint8List> fooPayload() => {
    'SKILL.md': Uint8List.fromList(
      '---\nname: foo\ndescription: d\n---\nbody'.codeUnits,
    ),
    'extras/x.txt': Uint8List.fromList('hello'.codeUnits),
  };

  test('installLocal writes files and inserts manifest entry', () async {
    final s = await svc.installLocal(
      basename: 'foo',
      files: fooPayload(),
      repoOwner: null,
      repoName: null,
      repoBranch: null,
      readmeUrl: null,
      name: 'foo',
      description: 'd',
    );
    expect(s.id, 'local:foo');
    expect(
      File(p.join(tmp.path, 'skills/installed/foo/SKILL.md')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(tmp.path, 'skills/installed/foo/extras/x.txt')).existsSync(),
      isTrue,
    );
    final installed = await manifest.loadSkills();
    expect(installed.single.id, 'local:foo');
  });

  test('installLocal without overwrite throws when target exists', () async {
    await svc.installLocal(
      basename: 'foo',
      files: fooPayload(),
      repoOwner: null,
      repoName: null,
      repoBranch: null,
      readmeUrl: null,
      name: 'foo',
      description: 'd',
    );
    expect(
      () => svc.installLocal(
        basename: 'foo',
        files: fooPayload(),
        repoOwner: null,
        repoName: null,
        repoBranch: null,
        readmeUrl: null,
        name: 'foo',
        description: 'd',
      ),
      throwsA(isA<SkillInstallException>()),
    );
  });

  test('uninstall moves files to backups and removes manifest row', () async {
    final s = await svc.installLocal(
      basename: 'foo',
      files: fooPayload(),
      repoOwner: null,
      repoName: null,
      repoBranch: null,
      readmeUrl: null,
      name: 'foo',
      description: 'd',
    );
    final backup = await svc.uninstall(s);
    expect(Directory(p.join(tmp.path, 'skills/installed/foo')).existsSync(), isFalse);
    expect(Directory(backup.backupPath).existsSync(), isTrue);
    expect((await manifest.loadSkills()), isEmpty);
    expect((await manifest.loadBackups()).single.backupId, backup.backupId);
  });

  test('restoreBackup moves payload back and reinserts manifest', () async {
    final s = await svc.installLocal(
      basename: 'foo',
      files: fooPayload(),
      repoOwner: null,
      repoName: null,
      repoBranch: null,
      readmeUrl: null,
      name: 'foo',
      description: 'd',
    );
    final backup = await svc.uninstall(s);
    final restored = await svc.restoreBackup(backup);
    expect(restored.id, s.id);
    expect(Directory(p.join(tmp.path, 'skills/installed/foo')).existsSync(), isTrue);
    expect(Directory(backup.backupPath).existsSync(), isFalse);
    expect((await manifest.loadBackups()), isEmpty);
    expect((await manifest.loadSkills()).single.id, s.id);
  });

  test('scanUnmanaged finds skill dirs not in manifest', () async {
    Directory(p.join(tmp.path, 'skills/installed/orphan')).createSync(recursive: true);
    File(p.join(tmp.path, 'skills/installed/orphan/SKILL.md')).writeAsStringSync(
      '---\nname: orphan\ndescription: yes\n---\n',
    );
    final scanned = await svc.scanUnmanaged();
    expect(scanned.single.directory, 'orphan');
    expect(scanned.single.name, 'orphan');
  });

  test('importUnmanaged inserts manifest rows', () async {
    Directory(p.join(tmp.path, 'skills/installed/orphan')).createSync(recursive: true);
    File(p.join(tmp.path, 'skills/installed/orphan/SKILL.md')).writeAsStringSync(
      '---\nname: orphan\ndescription: yes\n---\n',
    );
    final scanned = await svc.scanUnmanaged();
    final added = await svc.importUnmanaged(scanned);
    expect(added.single.id, 'local:orphan');
    expect((await manifest.loadSkills()).single.id, 'local:orphan');
  });
}
