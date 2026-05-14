import 'dart:io';

import 'package:teampilot/models/skill.dart';
import 'package:teampilot/services/skill_manifest_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late SkillManifestService svc;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill_manifest_test_');
    svc = SkillManifestService(rootDir: tmp.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Skill mkSkill(String id, {String? hash}) => Skill(
    id: id,
    name: id,
    description: '',
    directory: id,
    installedAt: 1,
    updatedAt: 1,
    contentHash: hash,
  );

  SkillBackup mkBackup(String id, int createdAt) => SkillBackup(
    backupId: id,
    backupPath: '/tmp/$id',
    createdAt: createdAt,
    skill: mkSkill(id),
  );

  test('empty manifest returns empty lists', () async {
    expect(await svc.loadSkills(), isEmpty);
    expect(await svc.loadBackups(), isEmpty);
  });

  test('upsert then load round-trips', () async {
    await svc.upsertSkill(mkSkill('a'));
    await svc.upsertSkill(mkSkill('b'));
    final loaded = await svc.loadSkills();
    expect(loaded.map((s) => s.id), unorderedEquals(['a', 'b']));
  });

  test('upsert replaces existing id', () async {
    await svc.upsertSkill(mkSkill('a', hash: 'h1'));
    await svc.upsertSkill(mkSkill('a', hash: 'h2'));
    final loaded = await svc.loadSkills();
    expect(loaded, hasLength(1));
    expect(loaded.single.contentHash, 'h2');
  });

  test('removeSkill removes by id', () async {
    await svc.upsertSkill(mkSkill('a'));
    await svc.upsertSkill(mkSkill('b'));
    await svc.removeSkill('a');
    expect((await svc.loadSkills()).map((s) => s.id), ['b']);
  });

  test('backup round-trips', () async {
    await svc.addBackup(mkBackup('b1', 100));
    expect((await svc.loadBackups()).single.backupId, 'b1');
  });

  test('removeBackup removes by id', () async {
    await svc.addBackup(mkBackup('b1', 100));
    await svc.addBackup(mkBackup('b2', 200));
    await svc.removeBackup('b1');
    expect((await svc.loadBackups()).single.backupId, 'b2');
  });

  test('pruneBackups keeps newest and returns dropped', () async {
    for (var i = 0; i < 5; i++) {
      await svc.addBackup(mkBackup('b$i', i));
    }
    final dropped = await svc.pruneBackups(keep: 2);
    final kept = await svc.loadBackups();
    expect(kept.map((b) => b.backupId), unorderedEquals(['b3', 'b4']));
    expect(dropped.map((b) => b.backupId), unorderedEquals(['b0', 'b1', 'b2']));
  });
}
