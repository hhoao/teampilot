import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/team_generation/team_generation_settings_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test(
    'load preserves order and broken refs while first duplicate wins',
    () async {
      final fs = InMemoryFilesystem();
      final store = TeamGenerationSettingsStore(
        fs: fs,
        pathOverride: '/tp/ui/team-generation-settings.json',
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
