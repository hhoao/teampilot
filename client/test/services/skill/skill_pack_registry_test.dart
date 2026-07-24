import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill_pack.dart';
import 'package:teampilot/services/skill/skill_pack_registry.dart';

void main() {
  test('builtin gstack pack matches skill-packs/gstack/pack.json', () {
    final packJsonPath = File(
      '${Directory.current.path}/../skill-packs/gstack/pack.json',
    );
    // tests run from client/; repo root is parent.
    expect(packJsonPath.existsSync(), isTrue, reason: packJsonPath.path);
    final disk = SkillPack.fromJson(
      (jsonDecode(packJsonPath.readAsStringSync()) as Map).cast<String, Object?>(),
    );
    final builtin = kGstackSkillPack;
    expect(builtin.id, disk.id);
    expect(builtin.name, disk.name);
    expect(builtin.repoOwner, disk.repoOwner);
    expect(builtin.repoName, disk.repoName);
    expect(builtin.repoBranch, disk.repoBranch);
    expect(builtin.recipe.steps.map((s) => s.uses).toList(),
        disk.recipe.steps.map((s) => s.uses).toList());
    expect(builtin.recipe.exports.path, disk.recipe.exports.path);
    expect(builtin.skills.length, disk.skills.length);
    for (var i = 0; i < builtin.skills.length; i++) {
      expect(builtin.skills[i].id, disk.skills[i].id);
      expect(builtin.skills[i].directory, disk.skills[i].directory);
      expect(builtin.skills[i].name, disk.skills[i].name);
    }
  });

  test('SkillPackRegistry resolves garrytan/gstack', () {
    final pack = SkillPackRegistry().byId('garrytan/gstack');
    expect(pack, isNotNull);
    expect(pack!.skills, hasLength(9));
    expect(
      pack.entryById('garrytan/gstack:ship')?.directory,
      'ship',
    );
  });
}
