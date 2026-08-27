import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill_pack.dart';
import 'package:teampilot/models/skill_pack_instruction.dart';
import 'package:teampilot/services/skill/skill_pack_registry.dart';
import 'package:teampilot/services/skill/skill_pack_source.dart';

final remoteGstackPack = SkillPack(
  id: 'garrytan/gstack',
  name: 'remote-gstack',
  install: [FromInstruction.parseRef('garrytan/gstack@main')],
);

class _FakeSkillPackSource implements SkillPackSource {
  _FakeSkillPackSource(this.loader);

  final Future<List<SkillPack>> Function() loader;

  @override
  Future<List<SkillPack>> fetchPacks({bool forceRefresh = false}) => loader();
}

void main() {
  test(
    'builtin gstack pack matches resources/skill-packs/gstack/pack.json',
    () {
      final packJsonPath = File(
        '${Directory.current.path}/../resources/skill-packs/gstack/pack.json',
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
    },
  );

  test('SkillPackRegistry resolves garrytan/gstack install shape', () {
    final pack = SkillPackRegistry().byId('garrytan/gstack');
    expect(pack, isNotNull);
    expect(pack!.install, isNotEmpty);
    expect(pack.install.first, isA<FromInstruction>());
    expect(pack.install.whereType<SkillsInstruction>(), isNotEmpty);
    expect(pack.install.whereType<PathInstruction>(), isNotEmpty);
  });

  test('loads a remote pack once after a lookup miss', () async {
    var loads = 0;
    final registry = SkillPackRegistry(
      packs: const [],
      remote: _FakeSkillPackSource(() async {
        loads++;
        return [remoteGstackPack];
      }),
    );

    expect(registry.byId('garrytan/gstack'), isNull);
    await registry.ensureLoaded();
    await registry.ensureLoaded();
    expect(loads, 1);
    expect(registry.byId('garrytan/gstack'), remoteGstackPack);
  });

  test('built-in pack wins over remote same id', () async {
    final registry = SkillPackRegistry(
      remote: _FakeSkillPackSource(() async => [remoteGstackPack]),
    );
    await registry.ensureLoaded();
    expect(registry.byId('garrytan/gstack'), kGstackSkillPack);
  });
}
