import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  group('CliPresetsRepository', () {
    late InMemoryFilesystem fs;
    late CliPresetsRepository repo;
    late String presetsPath;

    setUp(() {
      fs = InMemoryFilesystem();
      presetsPath = '/teampilot/cli-presets.json';
      repo = CliPresetsRepository(fs: fs, presetsPath: presetsPath);
    });

    test('load returns empty list when file does not exist', () async {
      final presets = await repo.load();
      expect(presets, isEmpty);
    });

    test('load returns presets from valid JSON', () async {
      await fs.writeString(presetsPath, '''
[
  {"id":"1","name":"Claude Work","cli":"claude","provider":"p1","model":"m1","effort":"high","createdAt":1000,"updatedAt":1000}
]
''');

      final presets = await repo.load();
      expect(presets.length, 1);
      expect(presets.first.id, '1');
      expect(presets.first.name, 'Claude Work');
      expect(presets.first.cli, CliTool.claude);
      expect(presets.first.effort, 'high');
    });

    test('load returns empty list for malformed JSON', () async {
      await fs.writeString(presetsPath, '{not valid');
      final presets = await repo.load();
      expect(presets, isEmpty);
    });

    test('save writes presets to file and returns them', () async {
      final presets = [
        CliPreset(
          id: '1', name: 'Test', cli: CliTool.claude,
          provider: 'p', model: 'm', effort: '',
          createdAt: 1000, updatedAt: 1000,
        ),
      ];

      await repo.save(presets);

      final raw = await fs.readString(presetsPath);
      expect(raw, contains('"id":"1"'));
      expect(raw, contains('"name":"Test"'));
    });

    test('save then load round-trips', () async {
      final presets = [
        CliPreset(
          id: 'a', name: 'A', cli: CliTool.claude,
          provider: 'p', model: 'm1', effort: '',
          createdAt: 1, updatedAt: 1,
        ),
        CliPreset(
          id: 'b', name: 'B', cli: CliTool.flashskyai,
          provider: 'p2', model: 'm2', effort: 'low',
          createdAt: 2, updatedAt: 2,
        ),
      ];

      await repo.save(presets);
      final loaded = await repo.load();

      expect(loaded.length, 2);
      expect(loaded[0], presets[0]);
      expect(loaded[1], presets[1]);
    });
  });
}
