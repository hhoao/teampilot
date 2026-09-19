import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/chat/team_generation/team_generation_settings_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('save and load preserve the minimum member count', () async {
    final fs = InMemoryFilesystem();
    final store = TeamGenerationSettingsStore(
      fs: fs,
      pathOverride: '/tp/ui/team-generation-settings.json',
      storage: fakeHomeStorage(filesystem: fs),
    );

    await store.save(TeamGenerationSettings(minimumMemberCount: 9));

    expect((await store.load()).minimumMemberCount, 9);
  });

  test('legacy settings without a minimum use the shared default', () async {
    final fs = InMemoryFilesystem();
    final store = TeamGenerationSettingsStore(
      fs: fs,
      pathOverride: '/tp/ui/team-generation-settings.json',
      storage: fakeHomeStorage(filesystem: fs),
    );
    await fs.ensureDir('/tp/ui');
    await fs.writeString(
      '/tp/ui/team-generation-settings.json',
      jsonEncode({'schemaVersion': 1, 'modelPool': []}),
    );

    expect((await store.load()).minimumMemberCount, 3);
  });

  test('save and load preserve Builder retention setting', () async {
    final fs = InMemoryFilesystem();
    final store = TeamGenerationSettingsStore(
      fs: fs,
      pathOverride: '/tp/ui/team-generation-settings.json',
      storage: fakeHomeStorage(filesystem: fs),
    );

    await store.save(TeamGenerationSettings(retainBuilderSession: true));

    expect((await store.load()).retainBuilderSession, isTrue);
  });

  test(
    'load preserves order and broken refs while first duplicate wins',
    () async {
      final fs = InMemoryFilesystem();
      final store = TeamGenerationSettingsStore(
        fs: fs,
        pathOverride: '/tp/ui/team-generation-settings.json',
        storage: fakeHomeStorage(filesystem: fs),
      );
      await fs.ensureDir('/tp/ui');
      await fs.writeString(
        '/tp/ui/team-generation-settings.json',
        jsonEncode({
          'schemaVersion': 1,
          'teamMode': 'mixed',
          'nativeCli': 'claude',
          'modelPool': [
            {
              'presetId': 'strong',
              'description': 'lead',
              'tags': ['reasoning'],
            },
            {'presetId': 'missing', 'description': 'keep visible', 'tags': []},
            {
              'presetId': 'strong',
              'description': 'duplicate',
              'tags': ['drop'],
            },
          ],
        }),
      );

      final loaded = await store.load();

      expect(loaded.modelPool.map((entry) => entry.id), ['strong', 'missing']);
      expect(loaded.modelPool.first.legacyPresetId, 'strong');
      expect(loaded.modelPool.first.description, 'lead');

      final hydrated = hydrateTeamGenerationSettings(
        settings: loaded,
        presets: const [
          CliPreset(
            id: 'strong',
            name: 'Strong',
            cli: CliTool.claude,
            provider: 'anthropic',
            model: 'opus',
            effort: 'high',
            createdAt: 0,
            updatedAt: 0,
          ),
        ],
      );
      expect(hydrated.modelPool.first.model, isNotEmpty);
    },
  );
}
