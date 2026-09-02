import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('fromJson migrates legacy presetId into unresolved row', () {
    final entry = GenerateModelPoolEntry.fromJson({
      'presetId': 'claude-strong',
      'description': 'lead',
      'tags': ['strong'],
    });
    expect(entry.legacyPresetId, 'claude-strong');
    expect(entry.id, 'claude-strong');
    expect(entry.isInline, isFalse);
  });

  test('hydrate snapshots preset into inline four-tuple', () {
    final hydrated = hydrateTeamGenerationSettings(
      settings: TeamGenerationSettings(
        modelPool: [
          GenerateModelPoolEntry.fromJson({'presetId': 'claude-strong'}),
        ],
      ),
      presets: [
        CliPreset(
          id: 'claude-strong',
          name: 'Strong',
          cli: CliTool.claude,
          provider: 'anthropic',
          model: 'opus',
          effort: 'high',
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
    );
    final entry = hydrated.modelPool.single;
    expect(entry.isInline, isTrue);
    expect(entry.id, 'claude-strong');
    expect(entry.cli, CliTool.claude);
    expect(entry.provider, 'anthropic');
    expect(entry.model, 'opus');
    expect(entry.effort, 'high');
    expect(entry.toJson().containsKey('presetId'), isFalse);
    expect(entry.toJson()['id'], 'claude-strong');
  });

  test('native snapshot filters by native cli using inline entries', () {
    final snapshot = resolveTeamGenerationSettingsSnapshot(
      settings: TeamGenerationSettings(
        teamMode: TeamMode.native,
        nativeCli: CliTool.claude,
        modelPool: [
          GenerateModelPoolEntry(
            id: 'codex-row',
            cli: CliTool.codex,
            provider: 'o',
            model: 'm',
          ),
          GenerateModelPoolEntry(
            id: 'claude-row',
            cli: CliTool.claude,
            provider: 'p',
            model: 'm',
            description: 'lead',
            tags: ['strong'],
          ),
        ],
      ),
      presets: const [],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );
    expect(snapshot.modelPool.single.rank, 1);
    expect(snapshot.modelPool.single.preset.id, 'claude-row');
    expect(snapshot.modelPool.single.preset.cli, CliTool.claude);
  });

  test('hydrate drops unknown legacy preset from effective pool', () {
    final snapshot = resolveTeamGenerationSettingsSnapshot(
      settings: TeamGenerationSettings(
        modelPool: [
          GenerateModelPoolEntry.fromJson({'presetId': 'missing'}),
        ],
      ),
      presets: const [],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 1,
    );
    expect(snapshot.modelPool, isEmpty);
  });

  test('native snapshot excludes launchable but non-native-team clis', () {
    final snapshot = resolveTeamGenerationSettingsSnapshot(
      settings: TeamGenerationSettings(
        teamMode: TeamMode.native,
        nativeCli: CliTool.codex,
        modelPool: [
          GenerateModelPoolEntry(
            id: 'codex-strong',
            cli: CliTool.codex,
            provider: 'codex-provider',
            model: 'codex-strong-model',
            description: 'looks launchable',
            tags: ['reasoning'],
          ),
        ],
      ),
      presets: const [],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );

    expect(snapshot.modelPool, isEmpty);
  });

  test('caller tag mutations do not alter entry or snapshot revision', () {
    final sourceTags = ['reasoning'];
    final entry = GenerateModelPoolEntry(
      id: 'claude-strong',
      cli: CliTool.claude,
      provider: 'claude-provider',
      model: 'claude-strong-model',
      description: 'lead',
      tags: sourceTags,
    );
    final settings = TeamGenerationSettings(modelPool: [entry]);

    final firstSnapshot = resolveTeamGenerationSettingsSnapshot(
      settings: settings,
      presets: const [],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );

    sourceTags.add('mutated');

    final secondSnapshot = resolveTeamGenerationSettingsSnapshot(
      settings: settings,
      presets: const [],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );

    expect(entry.tags, ['reasoning']);
    expect(firstSnapshot.modelPool.single.source.tags, ['reasoning']);
    expect(secondSnapshot.modelPool.single.source.tags, ['reasoning']);
    expect(secondSnapshot.revision, firstSnapshot.revision);
  });

  test('settings snapshot round-trip keeps nested preset ids', () {
    final snapshot = resolveTeamGenerationSettingsSnapshot(
      settings: TeamGenerationSettings(
        teamMode: TeamMode.mixed,
        modelPool: [
          GenerateModelPoolEntry(
            id: 'claude-strong',
            cli: CliTool.claude,
            provider: 'claude-provider',
            model: 'claude-strong-model',
            description: 'lead',
            tags: ['strong'],
          ),
        ],
      ),
      presets: const [],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );

    final reloaded = TeamGenerationSettingsSnapshot.fromJson(snapshot.toJson());
    expect(reloaded.modelPool.single.preset.id, 'claude-strong');
    expect(reloaded.modelPool.single.source.id, 'claude-strong');
    expect(reloaded.teamMode, TeamMode.mixed);
  });

  test(
    'settings snapshot recovers preset id from source when nested id empty',
    () {
      final reloaded = TeamGenerationSettingsSnapshot.fromJson({
        'revision': 'r1',
        'capturedAt': 1,
        'teamMode': 'mixed',
        'nativeCli': 'claude',
        'modelPool': [
          {
            'rank': 1,
            'source': {
              'presetId': 'claude-strong',
              'description': 'lead',
              'tags': <String>[],
            },
            'preset': {
              'id': '',
              'name': 'claude-strong',
              'cli': 'claude',
              'provider': 'p',
              'model': 'm',
              'effort': '',
            },
          },
        ],
      });

      expect(reloaded.modelPool.single.preset.id, 'claude-strong');
    },
  );
}
