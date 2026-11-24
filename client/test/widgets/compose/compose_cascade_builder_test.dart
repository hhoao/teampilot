import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/utils/ui/format_tokens.dart';
import 'package:teampilot/widgets/compose/compose_model_preset_chip.dart';

AppProviderConfig provider(
  String id, {
  String? name,
  Map<String, Object?> config = const {},
}) => AppProviderConfig(
  id: id,
  cli: CliTool.claude,
  name: name ?? id,
  config: config,
);

CliPreset preset(String id, String name) => CliPreset(
  id: id,
  name: name,
  cli: CliTool.claude,
  provider: 'p1',
  model: 'm1',
  effort: '',
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  final registry = CliToolRegistry.builtIn();

  group('resolveComposeCascadeCliGroups', () {
    test('builds providers with models and custom-entry flag', () {
      final groups = resolveComposeCascadeCliGroups(
        registry: registry,
        providersByCli: {
          CliTool.claude: [
            provider(
              'official',
              name: 'Claude Official',
              config: {
                'models': {
                  'm-a': {'model': 'm-a'},
                  'm-b': {'model': 'm-b'},
                },
              },
            ),
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

    test('live agent models replace the catalog groups', () {
      const bound = AppProviderConfig(
        id: 'opencode',
        cli: CliTool.opencode,
        name: 'OpenCode',
        config: {'opencodeSubscription': 'opencode-go'},
      );

      final groups = resolveComposeCascadeCliGroups(
        registry: registry,
        providersByCli: {
          CliTool.opencode: [bound],
        },
        cliItems: [CliTool.opencode],
        liveModelsByNamespace: const {
          'opencode-go': ['hy3'],
          'opencode': ['big-pickle'],
        },
      );

      final p = groups.single.providers.single;
      expect(p.groups.map((g) => g.namespace), ['opencode-go', 'opencode']);
      expect(p.groups[0].models, ['hy3']);
      expect(p.groups[1].models, ['big-pickle']);
    });

    test('drops a namespace the running agent does not advertise', () {
      const bound = AppProviderConfig(
        id: 'opencode',
        cli: CliTool.opencode,
        name: 'OpenCode',
        config: {'opencodeSubscription': 'opencode-go'},
      );

      final groups = resolveComposeCascadeCliGroups(
        registry: registry,
        providersByCli: {
          CliTool.opencode: [bound],
        },
        cliItems: [CliTool.opencode],
        liveModelsByNamespace: const {
          'opencode-go': ['hy3'],
        },
      );

      final p = groups.single.providers.single;
      expect(p.groups.map((g) => g.namespace), ['opencode-go']);
    });

    test('sorts providers by category then lowercase name', () {
      final zebra = AppProviderConfig(
        id: 'z',
        cli: CliTool.claude,
        name: 'Zebra',
        category: AppProviderCategory.custom,
      );
      final alpha = AppProviderConfig(
        id: 'a',
        cli: CliTool.claude,
        name: 'alpha',
        category: AppProviderCategory.custom,
      );
      official() => AppProviderConfig(
        id: 'o',
        cli: CliTool.claude,
        name: 'mid',
        category: AppProviderCategory.official,
      );
      final groups = resolveComposeCascadeCliGroups(
        registry: registry,
        providersByCli: {
          CliTool.claude: [zebra, official(), alpha],
        },
        cliItems: [CliTool.claude],
      );
      expect(groups.single.providers.map((p) => p.id).toList(), [
        'a',
        'z',
        'o',
      ]);
    });
  });

  group('buildComposeModelCascadeMenuSpecs', () {
    ComposeCascadeProvider cascadeProvider({
      String id = 'p1',
      String name = 'X',
      bool supportsCustomModelEntry = false,
      List<String> models = const ['plain-model'],
      Map<String, List<String>> efforts = const {'plain-model': []},
    }) => ComposeCascadeProvider(
      id: id,
      name: name,
      supportsCustomModelEntry: supportsCustomModelEntry,
      models: models,
      config: provider(id, name: name),
      effortByModel: efforts,
    );

    test(
      'presets group, provider drill-down, effort leaves, bottom actions',
      () {
        final groups = [
          ComposeCascadeCliGroup(
            cli: CliTool.claude,
            providers: [
              cascadeProvider(
                id: 'p1',
                name: 'DeepSeek',
                supportsCustomModelEntry: true,
                models: ['deepseek-chat'],
                efforts: {
                  'deepseek-chat': ['low', 'high'],
                },
              ),
            ],
          ),
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
      },
    );

    test('onModelsOpened fires from provider submenu onOpen', () {
      final config = provider('prov-1', name: 'Prov');
      Object? captured;
      final groups = [
        ComposeCascadeCliGroup(
          cli: CliTool.claude,
          providers: [
            ComposeCascadeProvider(
              id: 'prov-1',
              name: 'Prov',
              supportsCustomModelEntry: false,
              models: ['m1'],
              config: config,
              effortByModel: {
                'm1': ['low'],
              },
            ),
          ],
        ),
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
          ComposeCascadeCliGroup(
            cli: CliTool.claude,
            providers: [
              cascadeProvider(
                id: 'p1',
                name: 'X',
                models: ['plain-model'],
                efforts: {'plain-model': []},
              ),
            ],
          ),
        ],
        groupByCli: false,
      );
      // top level (no CLI wrapper): divider, provider submenu, divider, save, manage
      final providerSpec = specs.firstWhere((s) => s.isSubmenu);
      final modelRows = providerSpec.children!;
      final leaf = modelRows.firstWhere((s) => s.value is CascadeModelPick);
      expect(leaf.isSubmenu, isFalse);
      expect((leaf.value as CascadeModelPick).modelId, 'plain-model');
      expect(
        modelRows.any((s) => s.value is CascadeCustomModelRequest),
        isFalse,
      );
    });

    test('model rows show the per-model context window', () {
      final groups = [
        ComposeCascadeCliGroup(
          cli: CliTool.qoder,
          providers: [
            ComposeCascadeProvider(
              id: 'p1',
              name: 'Qoder',
              supportsCustomModelEntry: false,
              models: const ['m1', 'm2'],
              config: provider(
                'p1',
                config: {
                  'models': {
                    'm1': {'model': 'm1', 'contextWindow': 200000},
                  },
                },
              ),
              effortByModel: const {'m1': [], 'm2': []},
            ),
          ],
        ),
      ];
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'x',
        emptyProvidersLabel: 'y',
        presetsLabel: 'Presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save',
        managePresetsLabel: 'Manage',
        cliGroups: groups,
        groupByCli: false,
        modelTooltip: (cli, providerId, model) => 'desc-$model',
        contextWindowLabel: (tokens) => '${compactTokenCount(tokens)} ctx',
      );
      final providerSpec = specs.firstWhere((s) => s.isSubmenu);
      final rows = providerSpec.children!;
      expect(rows[0].subtitleSuffix, '200K ctx · desc-m1');
      expect(rows[1].subtitleSuffix, 'desc-m2');
    });

    test('context window is absent when no formatter is supplied', () {
      final groups = [
        ComposeCascadeCliGroup(
          cli: CliTool.qoder,
          providers: [
            ComposeCascadeProvider(
              id: 'p1',
              name: 'Qoder',
              supportsCustomModelEntry: false,
              models: const ['m1'],
              config: provider(
                'p1',
                config: {
                  'models': {
                    'm1': {'model': 'm1', 'contextWindow': 200000},
                  },
                },
              ),
              effortByModel: const {'m1': []},
            ),
          ],
        ),
      ];
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'x',
        emptyProvidersLabel: 'y',
        presetsLabel: 'Presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save',
        managePresetsLabel: 'Manage',
        cliGroups: groups,
        groupByCli: false,
      );
      final providerSpec = specs.firstWhere((s) => s.isSubmenu);
      expect(providerSpec.children!.first.subtitleSuffix, isNull);
    });

    test('showEffortLevels=false keeps model rows as direct leaves', () {
      final groups = [
        ComposeCascadeCliGroup(
          cli: CliTool.qoder,
          providers: [
            cascadeProvider(
              id: 'p1',
              name: 'Qoder',
              models: ['m1'],
              efforts: {
                'm1': ['low', 'high'],
              },
            ),
          ],
        ),
      ];
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'x',
        emptyProvidersLabel: 'y',
        presetsLabel: 'Presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save',
        managePresetsLabel: 'Manage',
        cliGroups: groups,
        groupByCli: false,
        showEffortLevels: false,
      );
      final providerSpec = specs.firstWhere((s) => s.isSubmenu);
      final modelSpec = providerSpec.children!.first;
      expect(modelSpec.isSubmenu, isFalse);
      expect(modelSpec.value, isA<CascadeModelPick>());
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
          ComposeCascadeCliGroup(
            cli: CliTool.claude,
            providers: [
              ComposeCascadeProvider(
                id: 'p1',
                name: 'X',
                supportsCustomModelEntry: true,
                models: [],
                config: provider('p1'),
                effortByModel: {},
              ),
            ],
          ),
        ],
        groupByCli: false,
      );
      final providerSpec = specs.firstWhere((s) => s.isSubmenu);
      expect(
        providerSpec.children!.any(
          (s) => !s.isDivider && s.enabled == false && s.label == 'No models',
        ),
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
      final effort = decodeComposeCascadeValue(
        CascadeEffortPick(
          cli: CliTool.claude,
          providerId: 'p',
          modelId: 'm',
          effort: 'high',
        ),
      )!;
      expect(effort.effort, 'high');
      final model = decodeComposeCascadeValue(
        CascadeModelPick(cli: CliTool.claude, providerId: 'p', modelId: 'm'),
      )!;
      expect(model.effort, isEmpty);
      expect(
        decodeComposeCascadeValue(ComposeModelPresetChipAction.manage),
        isNull,
      );
      expect(
        decodeComposeCascadeValue(
          CascadeCustomModelRequest(cli: CliTool.claude, providerId: 'p'),
        ),
        isNull,
      );
    });

    test('grouped provider renders one submenu per upstream namespace', () {
      final groups = [
        ComposeCascadeCliGroup(
          cli: CliTool.opencode,
          providers: [
            ComposeCascadeProvider(
              id: 'opencode',
              name: 'OpenCode',
              supportsCustomModelEntry: true,
              models: const ['deepseek-v4.1-flash', 'deepseek-v4.1-flash-free'],
              config: provider('opencode'),
              effortByModel: const {},
              groups: const [
                ComposeCascadeModelGroup(
                  namespace: 'opencode-go',
                  models: ['deepseek-v4.1-flash'],
                ),
                ComposeCascadeModelGroup(
                  namespace: 'opencode',
                  models: ['deepseek-v4.1-flash-free'],
                ),
              ],
            ),
          ],
        ),
      ];

      final specs = buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'No presets',
        emptyProvidersLabel: 'No providers',
        presetsLabel: 'Presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom model ID…',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save as preset…',
        managePresetsLabel: 'Manage',
        cliGroups: groups,
        groupByCli: false,
      );

      final providerSpec = specs.firstWhere(
        (s) => s.isSubmenu && s.label == 'OpenCode',
      );
      final levelTwo = providerSpec.children!;
      // The extra level is labeled with the namespace itself, because that is
      // exactly the prefix written into `model: "<namespace>/<model>"`.
      expect(levelTwo, hasLength(2));
      expect(levelTwo[0].label, 'opencode-go');
      expect(levelTwo[1].label, 'opencode');

      // Each layer offers its own custom-id entry, so unrestricted ids still
      // land in the namespace the user chose.
      expect(levelTwo[0].children!.last.label, 'Custom model ID…');
      final goCustom =
          levelTwo[0].children!.last.value as CascadeCustomModelRequest;
      expect(goCustom.providerId, 'opencode');
      expect(goCustom.namespace, 'opencode-go');

      final freeCustom =
          levelTwo[1].children!.last.value as CascadeCustomModelRequest;
      expect(freeCustom.providerId, 'opencode');
      expect(freeCustom.namespace, 'opencode');

      // The pick keeps the catalog row id (what a preset stores) and carries
      // the upstream namespace separately.
      final goPick = levelTwo[0].children!.first.value as CascadeModelPick;
      expect(goPick.providerId, 'opencode');
      expect(goPick.namespace, 'opencode-go');
      expect(goPick.modelId, 'deepseek-v4.1-flash');

      final freePick = levelTwo[1].children!.first.value as CascadeModelPick;
      expect(freePick.providerId, 'opencode');
      expect(freePick.namespace, 'opencode');
      expect(freePick.modelId, 'deepseek-v4.1-flash-free');
    });
  });

  group('configWithModelContextWindow', () {
    test('sets the window on a row keyed by the model id', () {
      final config = <String, Object?>{
        'keep': true,
        'models': {
          'm1': {'name': 'M1', 'model': 'm1', 'enabled': true},
          'm2': {'name': 'M2', 'model': 'm2', 'enabled': true},
        },
      };
      final next = configWithModelContextWindow(config, 'm1', 200000);
      expect(next['keep'], isTrue);
      final models = next['models'] as Map;
      expect((models['m1'] as Map)['contextWindow'], 200000);
      expect((models['m2'] as Map).containsKey('contextWindow'), isFalse);
      // Pure: the input config is not mutated.
      expect(
        ((config['models'] as Map)['m1'] as Map).containsKey('contextWindow'),
        isFalse,
      );
    });

    test('matches a row whose key differs from the served model id', () {
      final config = <String, Object?>{
        'models': {
          'alias': {'name': 'Alias', 'model': 'served-model', 'enabled': true},
        },
      };
      final next = configWithModelContextWindow(config, 'served-model', 128000);
      expect(
        ((next['models'] as Map)['alias'] as Map)['contextWindow'],
        128000,
      );
      expect((next['models'] as Map).containsKey('served-model'), isFalse);
    });

    test('creates a row for a model with none', () {
      final next = configWithModelContextWindow(const {}, 'new-model', 300000);
      final row = (next['models'] as Map)['new-model'] as Map;
      expect(row['model'], 'new-model');
      expect(row['enabled'], isTrue);
      expect(row['contextWindow'], 300000);
    });

    test('clearing removes the key and keeps the rest of the row', () {
      final config = <String, Object?>{
        'models': {
          'm1': {
            'name': 'M1',
            'model': 'm1',
            'enabled': true,
            'contextWindow': 200000,
            'provider': 'X',
          },
        },
      };
      final next = configWithModelContextWindow(config, 'm1', null);
      final row = (next['models'] as Map)['m1'] as Map;
      expect(row.containsKey('contextWindow'), isFalse);
      expect(row['provider'], 'X');
    });
  });

  group('context window editor submenu', () {
    List<TpActionMenuSpec> buildSpecs({
      List<ComposeCascadeModelGroup> groups = const [],
      bool withEditLabel = true,
    }) {
      return buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'x',
        emptyProvidersLabel: 'y',
        presetsLabel: 'Presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save',
        managePresetsLabel: 'Manage',
        cliGroups: [
          ComposeCascadeCliGroup(
            cli: CliTool.qoder,
            providers: [
              ComposeCascadeProvider(
                id: 'p1',
                name: 'Qoder',
                supportsCustomModelEntry: false,
                models: groups.isEmpty ? const ['m1', 'm2'] : const [],
                config: provider(
                  'p1',
                  config: {
                    'models': {
                      'm1': {'model': 'm1', 'contextWindow': 200000},
                    },
                  },
                ),
                effortByModel: const {'m1': [], 'm2': []},
                groups: groups,
              ),
            ],
          ),
        ],
        groupByCli: false,
        contextWindowLabel: (t) => '${compactTokenCount(t)} ctx',
        contextWindowEditLabel: withEditLabel ? 'Context window' : null,
        contextWindowDefaultLabel: 'Model default',
      );
    }

    test('lists models with their current value and routes edit requests', () {
      final specs = buildSpecs();
      final providerSpec = specs.firstWhere((s) => s.isSubmenu);
      final editSubmenu = providerSpec.children!
          .where((s) => s.isSubmenu && s.label == 'Context window')
          .single;
      final rows = editSubmenu.children!;
      expect(rows, hasLength(2));
      final pick = rows[0].value as CascadeContextWindowEditRequest;
      expect(pick.cli, CliTool.qoder);
      expect(pick.providerId, 'p1');
      expect(pick.modelId, 'm1');
      expect(rows[0].subtitleSuffix, '200K ctx');
      expect(rows[1].subtitleSuffix, 'Model default');
    });

    test('hidden when the surface does not opt into the editor', () {
      final specs = buildSpecs(withEditLabel: false);
      final providerSpec = specs.firstWhere((s) => s.isSubmenu);
      expect(
        providerSpec.children!.where((s) => s.label == 'Context window'),
        isEmpty,
      );
    });

    test('grouped provider nests the editor under each namespace', () {
      final specs = buildSpecs(
        groups: const [
          ComposeCascadeModelGroup(namespace: 'ns-a', models: ['m1']),
          ComposeCascadeModelGroup(namespace: 'ns-b', models: ['m2']),
        ],
      );
      final providerSpec = specs.firstWhere((s) => s.isSubmenu);
      final namespaceSubmenus = providerSpec.children!
          .where((s) => s.isSubmenu && s.label != 'Context window')
          .toList();
      expect(namespaceSubmenus, hasLength(2));
      for (final submenu in namespaceSubmenus) {
        final editor = submenu.children!
            .where((s) => s.isSubmenu && s.label == 'Context window')
            .single;
        final request =
            editor.children!.single.value as CascadeContextWindowEditRequest;
        expect(request.namespace, submenu.label);
      }
    });
  });

  group('standalone effort and window selectors', () {
    test('effort specs mark the current level', () {
      final specs = buildComposeEffortSpecs(
        cli: CliTool.qoder,
        providerId: 'p1',
        modelId: 'm1',
        efforts: const ['low', 'high'],
        selectedEffort: 'high',
        defaultLabel: 'Default',
      );
      expect(specs.map((s) => s.label), ['Default', 'low', 'high']);
      expect(specs.first.selected, isFalse);
      expect(specs.last.selected, isTrue);
      expect(specs.first.value, isA<CascadeModelPick>());
      expect(specs.last.value, isA<CascadeEffortPick>());
    });

    test('window specs include default, presets and a custom entry', () {
      final specs = buildComposeContextWindowSpecs(
        cli: CliTool.qoder,
        providerId: 'p1',
        modelId: 'm1',
        currentWindow: 200000,
        defaultLabel: 'Model default',
        customLabel: 'Custom…',
        formatTokens: compactTokenCount,
      );
      expect(specs.first.label, 'Model default');
      expect(specs.where((s) => s.selected).single.label, '200K');
      expect(specs.last.label, 'Custom…');
      expect(specs.last.value, isA<CascadeContextWindowEditRequest>());
      final picks = specs
          .where((s) => s.value is CascadeContextWindowPick)
          .map((s) => (s.value as CascadeContextWindowPick).tokens);
      expect(picks, containsAll([null, 128000, 200000, 300000, 1000000]));
    });
  });
}
