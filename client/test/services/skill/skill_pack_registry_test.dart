import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill_pack.dart';
import 'package:teampilot/models/skill_pack_instruction.dart';
import 'package:teampilot/services/skill/skill_pack_registry.dart';

void main() {
  test('builtin gstack pack matches skill-packs/gstack/pack.json', () {
    final packJsonPath = File(
      '${Directory.current.path}/../skill-packs/gstack/pack.json',
    );
    expect(packJsonPath.existsSync(), isTrue, reason: packJsonPath.path);
    final disk = SkillPack.fromJson(
      (jsonDecode(packJsonPath.readAsStringSync()) as Map)
          .cast<String, Object?>(),
    );
    final builtin = kGstackSkillPack;
    expect(builtin.id, disk.id);
    expect(builtin.name, disk.name);
    expect(builtin.install, disk.install);
  });

  test('SkillPackRegistry resolves garrytan/gstack install shape', () {
    final pack = SkillPackRegistry().byId('garrytan/gstack');
    expect(pack, isNotNull);
    expect(pack!.install, isNotEmpty);
    expect(pack.install.first, isA<FromInstruction>());
    expect(
      pack.install.whereType<SkillsInstruction>(),
      isNotEmpty,
    );
    expect(pack.install.whereType<PathInstruction>(), isNotEmpty);
  });
}
