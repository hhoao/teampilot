import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/widgets/compose/compose_model_preset_chip.dart';

AppProviderConfig provider(String id, {String? name, Map<String, Object?> config = const {}}) =>
    AppProviderConfig(id: id, cli: CliTool.claude, name: name ?? id, config: config);

CliPreset preset(String id, String name) => CliPreset(
      id: id, name: name, cli: CliTool.claude,
      provider: 'p1', model: 'm1', effort: '',
      createdAt: 0, updatedAt: 0,
    );

void main() {
  final registry = CliToolRegistry.builtIn();

  group('resolveComposeCascadeCliGroups', () {
    test('builds providers with models and custom-entry flag', () {
      final groups = resolveComposeCascadeCliGroups(
        registry: registry,
        providersByCli: {
          CliTool.claude: [
            provider('official', name: 'Claude Official',
              config: {'models': {'m-a': {'model': 'm-a'}, 'm-b': {'model': 'm-b'}}}),
          ],
        },
        cliItems: [CliTool.claude],
      );
      expect(groups, hasLength(1));
      final p = groups.single.providers.single;
      expect(p.supportsCustomModelEntry, isTrue); // claude picker mode
      expect(p.models, containsAll(['m-a', 'm-b']));
    });

    test('skips CLIs without providers or capability', () {
      final groups = resolveComposeCascadeCliGroups(
        registry: registry,
        providersByCli: {CliTool.codex: []},
        cliItems: [CliTool.codex, CliTool.claude],
      );
      expect(groups.where((g) => g.cli == CliTool.codex), isEmpty);
    });
  });

  group('buildComposeModelCascadeMenuSpecs', () {
    test('presets group, provider drill-down, effort leaves, bottom actions', () {
      final groups = [
        ComposeCascadeCliGroup(cli: CliTool.claude, providers: [
          ComposeCascadeProvider(
            id: 'p1', name: 'DeepSeek',
            supportsCustomModelEntry: true,
            models: ['deepseek-chat'],
            effortByModel: {'deepseek-chat': ['low', 'high']},
          ),
        ]),
      ];
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: [preset('preset-1', 'Work')],
        selectedPresetId: 'preset-1',
        emptyHintLabel: 'No presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom model ID…',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save as preset…',
        managePresetsLabel: 'Manage',
        cliGroups: groups,
        groupByCli: true,
      );

      final presetRow = specs.first;
      expect(presetRow.selected, isTrue);
      expect(presetRow.value, 'preset-1');

      final cliSubmenu = specs.where((s) => s.isSubmenu).toList();
      final providerLevel = cliSubmenu.last.children!;
      final providerSpec = providerLevel.first;
      expect(providerSpec.isSubmenu, isTrue);

      final modelLevel = providerSpec.children!;
      final modelSpec = modelLevel.first;
      expect(modelSpec.isSubmenu, isTrue); // has effort candidates ⇒ submenu

      final effortLevel = modelSpec.children!;
      expect(effortLevel.first.value, isA<CascadeModelPick>()); // 默认 entry
      expect(effortLevel[1].value, isA<CascadeEffortPick>());
      expect(modelLevel.last.value, isA<CascadeCustomModelRequest>());

      expect(
        specs.any((s) => s.value == ComposeModelPresetChipAction.savePreset),
        isTrue,
      );
      expect(
        specs.any((s) => s.value == ComposeModelPresetChipAction.manage),
        isTrue,
      );
    });

    test('model without effort candidates is a direct leaf', () {
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'No presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom…',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save',
        managePresetsLabel: 'Manage',
        cliGroups: [
          ComposeCascadeCliGroup(cli: CliTool.claude, providers: [
            ComposeCascadeProvider(
              id: 'p1', name: 'X',
              supportsCustomModelEntry: false,
              models: ['plain-model'],
              effortByModel: {'plain-model': []},
            ),
          ]),
        ],
        groupByCli: false,
      );
      // top level (no CLI wrapper): divider, provider submenu, divider, save, manage
      final providerSpec = specs.firstWhere((s) => s.isSubmenu);
      final modelRows = providerSpec.children!;
      final leaf = modelRows.firstWhere((s) => s.value is CascadeModelPick);
      expect(leaf.isSubmenu, isFalse);
      expect((leaf.value as CascadeModelPick).modelId, 'plain-model');
      expect(modelRows.any((s) => s.value is CascadeCustomModelRequest), isFalse);
    });

    test('empty model catalog shows disabled row but keeps custom entry', () {
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'x',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom…',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save',
        managePresetsLabel: 'Manage',
        cliGroups: [
          ComposeCascadeCliGroup(cli: CliTool.claude, providers: [
            ComposeCascadeProvider(
              id: 'p1', name: 'X',
              supportsCustomModelEntry: true,
              models: [],
              effortByModel: {},
            ),
          ]),
        ],
        groupByCli: false,
      );
      final providerSpec = specs.firstWhere((s) => s.isSubmenu);
      expect(
        providerSpec.children!.any((s) => !s.isDivider && s.enabled == false && s.label == 'No models'),
        isTrue,
      );
      expect(
        providerSpec.children!.any((s) => s.value is CascadeCustomModelRequest),
        isTrue,
      );
    });
  });
}
