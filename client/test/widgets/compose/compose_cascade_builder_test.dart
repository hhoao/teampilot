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
      expect(p.config.id, 'official');
    });

    test('skips CLIs without providers or capability', () {
      final groups = resolveComposeCascadeCliGroups(
        registry: registry,
        providersByCli: {CliTool.codex: []},
        cliItems: [CliTool.codex, CliTool.claude],
      );
      expect(groups.where((g) => g.cli == CliTool.codex), isEmpty);
    });

    test('sorts providers by category then lowercase name', () {
      final zebra = AppProviderConfig(
        id: 'z', cli: CliTool.claude, name: 'Zebra',
        category: AppProviderCategory.custom);
      final alpha = AppProviderConfig(
        id: 'a', cli: CliTool.claude, name: 'alpha',
        category: AppProviderCategory.custom);
      official() => AppProviderConfig(
        id: 'o', cli: CliTool.claude, name: 'mid',
        category: AppProviderCategory.official);
      final groups = resolveComposeCascadeCliGroups(
        registry: registry,
        providersByCli: {
          CliTool.claude: [zebra, official(), alpha],
        },
        cliItems: [CliTool.claude],
      );
      expect(
        groups.single.providers.map((p) => p.id).toList(),
        ['a', 'z', 'o'],
      );
    });
  });

  group('buildComposeModelCascadeMenuSpecs', () {
    ComposeCascadeProvider cascadeProvider({
      String id = 'p1',
      String name = 'X',
      bool supportsCustomModelEntry = false,
      List<String> models = const ['plain-model'],
      Map<String, List<String>> efforts = const {'plain-model': []},
    }) =>
        ComposeCascadeProvider(
          id: id,
          name: name,
          supportsCustomModelEntry: supportsCustomModelEntry,
          models: models,
          config: provider(id, name: name),
          effortByModel: efforts,
        );

    test('presets group, provider drill-down, effort leaves, bottom actions',
        () {
      final groups = [
        ComposeCascadeCliGroup(cli: CliTool.claude, providers: [
          cascadeProvider(
            id: 'p1',
            name: 'DeepSeek',
            supportsCustomModelEntry: true,
            models: ['deepseek-chat'],
            efforts: {'deepseek-chat': ['low', 'high']},
          ),
        ]),
      ];
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: [preset('preset-1', 'Work')],
        selectedPresetId: 'preset-1',
        emptyHintLabel: 'No presets',
        emptyProvidersLabel: 'No providers',
        presetsLabel: 'Presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom model ID…',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save as preset…',
        managePresetsLabel: 'Manage',
        cliGroups: groups,
        groupByCli: true,
      );

      // Presets are a submenu whose sole child is a fixed-height scroll block.
      expect(specs.first.isSubmenu, isTrue);
      expect(specs.first.label, 'Presets');
      final presetBlock = specs.first.children!.single;
      expect(presetBlock.isScrollBlock, isTrue);
      final presetRows = presetBlock.scrollChildren!;
      expect(presetRows, hasLength(1));
      final presetRow = presetRows.first;
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

    test('onModelsOpened fires from provider submenu onOpen', () {
      final config = provider('prov-1', name: 'Prov');
      Object? captured;
      final groups = [
        ComposeCascadeCliGroup(cli: CliTool.claude, providers: [
          ComposeCascadeProvider(
            id: 'prov-1',
            name: 'Prov',
            supportsCustomModelEntry: false,
            models: ['m1'],
            config: config,
            effortByModel: {'m1': ['low']},
          ),
        ]),
      ];
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'x',
        emptyProvidersLabel: 'y',
        presetsLabel: 'Presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom…',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save',
        managePresetsLabel: 'Manage',
        cliGroups: groups,
        groupByCli: false,
        onModelsOpened: (cli, providerId, cfg) {
          captured = (cli, providerId, cfg);
        },
      );
      // Refresh-on-open is wired to the provider submenu (model list), not
      // the nested effort submenu under a model row.
      final providerSpec = specs.firstWhere((s) => s.isSubmenu);
      expect(providerSpec.label, 'Prov');
      providerSpec.onOpen?.call();
      final tuple = captured! as (CliTool, String, AppProviderConfig);
      expect(tuple.$1, CliTool.claude);
      expect(tuple.$2, 'prov-1');
      expect(identical(tuple.$3, config), isTrue);

      final modelSpec = providerSpec.children!.first;
      expect(modelSpec.onOpen, isNull);
    });

    test('zero providers renders hint row and a single divider', () {
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'No presets',
        emptyProvidersLabel: 'No providers',
        presetsLabel: 'Presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom…',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save',
        managePresetsLabel: 'Manage',
        cliGroups: [
          ComposeCascadeCliGroup(cli: CliTool.claude, providers: []),
          ComposeCascadeCliGroup(cli: CliTool.codex, providers: []),
        ],
        groupByCli: true,
      );
      expect(specs.where((s) => s.isDivider), hasLength(1));
      expect(
        specs.any(
          (s) =>
              !s.isDivider &&
              !s.isSubmenu &&
              s.enabled == false &&
              s.label == 'No providers',
        ),
        isTrue,
      );
      expect(
        specs.any((s) => s.value == ComposeModelPresetChipAction.savePreset),
        isTrue,
      );
    });

    test('model without effort candidates is a direct leaf', () {
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'No presets',
        emptyProvidersLabel: 'No providers',
        presetsLabel: 'Presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom…',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save',
        managePresetsLabel: 'Manage',
        cliGroups: [
          ComposeCascadeCliGroup(cli: CliTool.claude, providers: [
            cascadeProvider(
              id: 'p1',
              name: 'X',
              models: ['plain-model'],
              efforts: {'plain-model': []},
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

    test('omits save preset when showSavePreset is false', () {
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'empty',
        emptyProvidersLabel: 'none',
        presetsLabel: 'Presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save',
        managePresetsLabel: 'Manage',
        cliGroups: const [],
        groupByCli: true,
        showSavePreset: false,
        showManagePresets: true,
      );
      final labels = specs.map((s) => s.label).whereType<String>().toList();
      expect(labels, isNot(contains('Save')));
      expect(labels, contains('Manage'));
    });

    test('omits manage presets when showManagePresets is false', () {
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'empty',
        emptyProvidersLabel: 'none',
        presetsLabel: 'Presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save',
        managePresetsLabel: 'Manage',
        cliGroups: const [],
        groupByCli: true,
        showSavePreset: true,
        showManagePresets: false,
      );
      expect(
        specs.any((s) => s.value == ComposeModelPresetChipAction.savePreset),
        isTrue,
      );
      expect(
        specs.any((s) => s.value == ComposeModelPresetChipAction.manage),
        isFalse,
      );
    });

    test('empty model catalog shows disabled row but keeps custom entry', () {
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'x',
        emptyProvidersLabel: 'No providers',
        presetsLabel: 'Presets',
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
              config: provider('p1'),
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

  group('decodeComposeCascadeValue', () {
    test('decodeComposeCascadeValue maps picks and ignores actions', () {
      final effort = decodeComposeCascadeValue(CascadeEffortPick(
        cli: CliTool.claude, providerId: 'p', modelId: 'm', effort: 'high'))!;
      expect(effort.effort, 'high');
      final model = decodeComposeCascadeValue(
        CascadeModelPick(cli: CliTool.claude, providerId: 'p', modelId: 'm'))!;
      expect(model.effort, isEmpty);
      expect(decodeComposeCascadeValue(ComposeModelPresetChipAction.manage), isNull);
      expect(decodeComposeCascadeValue(CascadeCustomModelRequest(
        cli: CliTool.claude, providerId: 'p')), isNull);
    });
  });
}
