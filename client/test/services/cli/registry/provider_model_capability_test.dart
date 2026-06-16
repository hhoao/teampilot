import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_model_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/provider/claude/claude_provider_model_capability.dart';

void main() {
  test('backgroundModelFromProvider returns the role-flagged model id', () {
    const provider = AppProviderConfig(
      id: 'tiered',
      cli: CliTool.claude,
      name: 'Tiered',
      defaultModel: 'main',
      config: {
        'models': {
          'main': {'name': 'Main', 'model': 'main', 'enabled': true},
          'cheap': {
            'name': 'Cheap',
            'model': 'cheap-model',
            'enabled': true,
            'role': 'background',
          },
        },
      },
    );
    expect(backgroundModelFromProvider(provider), 'cheap-model');
    expect(const ClaudeProviderModelCapability().supportsModelTiers, isTrue);
  });

  test('backgroundModelFromProvider is empty without a background role', () {
    const provider = AppProviderConfig(
      id: 'flat',
      cli: CliTool.claude,
      name: 'Flat',
      config: {
        'models': {
          'main': {'name': 'Main', 'model': 'main', 'enabled': true},
        },
      },
    );
    expect(backgroundModelFromProvider(provider), '');
  });

  test('mergeProviderModelCandidates merges catalog, record, and current', () {
    const provider = AppProviderConfig(
      id: 'deepseek',
      cli: CliTool.claude,
      name: 'DeepSeek',
      defaultModel: 'deepseek-v4-pro',
      config: {
        'models': {
          'alt-model': {
            'name': 'Alt Name',
            'model': 'deepseek-chat',
          },
        },
      },
    );

    expect(
      mergeProviderModelCandidates(
        builtInCatalog: const ['built-in-model'],
        provider: provider,
        currentModel: 'imported-model',
      ),
      [
        'Alt Name',
        'built-in-model',
        'deepseek-chat',
        'deepseek-v4-pro',
        'imported-model',
      ],
    );
  });

  test('claude official provider exposes catalog with aliases and full ids', () {
    const capability = ClaudeProviderModelCapability();
    const official = AppProviderConfig(
      id: 'claude-official',
      cli: CliTool.claude,
      name: 'Claude Official',
      category: AppProviderCategory.official,
      isOfficial: true,
      config: {'env': {}},
    );

    expect(
      capability.pickerMode(official),
      ProviderModelPickerMode.catalogWithCustomEntry,
    );
    final models = capability.modelCandidates(
      provider: official,
      providerId: 'claude-official',
      currentModel: '',
    );
    expect(models, contains('sonnet'));
    expect(models, contains('claude-sonnet-4-6'));
    expect(capability.defaultModel(provider: official, providerId: 'claude-official'), 'sonnet');
  });

  test('claude proxy provider supports custom model entry', () {
    const capability = ClaudeProviderModelCapability();
    expect(
      capability.pickerMode(
        const AppProviderConfig(
          id: 'custom',
          cli: CliTool.claude,
          name: 'Custom',
          defaultModel: 'preset-model',
        ),
      ),
      ProviderModelPickerMode.catalogWithCustomEntry,
    );
  });

  test('opencode capability exposes zen catalog and custom entry', () {
    const capability = OpencodeProviderModelCapability();
    const provider = AppProviderConfig(
      id: 'opencode',
      cli: CliTool.opencode,
      name: 'OpenCode',
      defaultModel: 'claude-sonnet-4-5',
    );

    expect(
      capability.pickerMode(provider),
      ProviderModelPickerMode.catalogWithCustomEntry,
    );
    final models = capability.modelCandidates(
      provider: provider,
      providerId: 'opencode',
      currentModel: '',
    );
    expect(models, contains('big-pickle'));
    expect(models, contains('claude-sonnet-4-5'));
  });

  test('opencode catalog resolves from providerId without provider row', () {
    const capability = OpencodeProviderModelCapability();
    final models = capability.modelCandidates(
      provider: null,
      providerId: 'opencode',
      currentModel: '',
    );
    expect(models, contains('big-pickle'));
  });

  test('built-in registry registers ProviderModelCapability for every cli', () {
    final registry = CliToolRegistry.builtIn();
    for (final cli in CliTool.values) {
      expect(
        registry.capability<ProviderModelCapability>(cli),
        isNotNull,
        reason: cli.value,
      );
    }
  });
}
