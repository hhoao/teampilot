import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/skill/git_registry_skill_pack_source.dart';
import 'package:teampilot/services/skill/skill_pack_source.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('default registry points to resources repo', () {
    expect(kDefaultSkillPackRegistry.fullName, 'hhoao/teampilot-resources');
    expect(
      kDefaultSkillPackRegistry.rawUri('index.json').toString(),
      'https://raw.githubusercontent.com/hhoao/teampilot-resources/main/skill-packs/index.json',
    );
  });

  test('loads only indexed pack manifests and caches parsed packs', () async {
    final calls = <Uri>[];
    final fs = InMemoryFilesystem();
    final source = GitRegistrySkillPackSource(
      fs: fs,
      cacheDirOverride: '/cache',
      fetch: (uri) async {
        calls.add(uri);
        if (uri.path.endsWith('/index.json')) {
          return '{"packs":["gstack"]}';
        }
        return '{"id":"garrytan/gstack","name":"gstack","install":[{"FROM":"garrytan/gstack@main"}]}';
      },
    );

    final packs = await source.fetchPacks();
    expect(packs.single.id, 'garrytan/gstack');
    expect(
      calls.any((uri) => uri.path.endsWith('/skill-packs/gstack/pack.json')),
      isTrue,
    );
    expect(await source.fetchPacks(), packs);
    expect(
      await fs.readString('/cache/hhoao-teampilot-resources/packs.json'),
      jsonEncode(packs.map((pack) => pack.toJson()).toList()),
    );
  });

  test(
    'returns and caches an empty list when the registry index is unavailable',
    () async {
      final fs = InMemoryFilesystem();
      final source = GitRegistrySkillPackSource(
        fs: fs,
        cacheDirOverride: '/cache',
        fetch: (_) async => null,
      );

      expect(await source.fetchPacks(), isEmpty);
      expect(source.lastFailure?.sourceId, 'skill-pack-registry');
      expect(source.lastFailure?.message, 'Registry index unavailable');
      expect(
        await fs.readString('/cache/hhoao-teampilot-resources/packs.json'),
        '[]',
      );
    },
  );

  test('skips malformed manifests while keeping valid indexed packs', () async {
    final source = GitRegistrySkillPackSource(
      fs: InMemoryFilesystem(),
      cacheDirOverride: '/cache',
      fetch: (uri) async {
        if (uri.path.endsWith('/index.json')) {
          return '{"packs":["bad","valid"]}';
        }
        if (uri.path.endsWith('/bad/pack.json')) {
          return '{"id":"bad","name":"bad","install":[]}';
        }
        return '{"id":"valid","name":"valid","install":[{"FROM":"org/repo@main"}]}';
      },
    );

    final packs = await source.fetchPacks();
    expect(packs.map((pack) => pack.id), ['valid']);
  });
}
